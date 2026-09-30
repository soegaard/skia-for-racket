#lang racket/base
;; Public Racket path access only. No private racket/draw or Cairo entry points.
(require racket/class racket/list racket/vector (prefix-in rd: racket/draw) "dc-support.rkt")
(provide dc-path-commands dc-polyline dc-rectangle dc-clip-points make-dc-clip dc-clip-data)
(define (dc-path-commands who path [dx 0] [dy 0])
  (unless (is-a? path rd:dc-path%) (raise-argument-error who "dc-path% object" path))
  (dc-real who dx) (dc-real who dy)
  (define-values (closed open) (send path get-datum))
  (define (subpath points close?)
    (append
     (for/list ([p (in-list points)] [i (in-naturals)])
       (unless (and (vector? p) (if (= i 0) (= (vector-length p) 2) (memq (vector-length p) '(2 6))))
         (raise-arguments-error who "invalid dc-path% datum" "segment" p))
       (vector->immutable-vector
        (list->vector
         (cons (cond [(= i 0) 'move] [(= (vector-length p) 2) 'line] [else 'cubic])
               (for/list ([n (in-vector p)] [j (in-naturals)])
                 (dc-real who (+ (dc-real who n) (if (even? j) dx dy))))))))
     (if (and close? (pair? points)) (list '#(close)) '())))
  (append (append* (for/list ([p (in-list closed)]) (subpath p #t))) (subpath open #f)))
(define (dc-polyline who points dx dy close?)
  (dc-real who dx) (dc-real who dy)
  (unless (and (list? points)
               (or (andmap pair? points) (andmap (lambda (p) (is-a? p rd:point%)) points)))
    (raise-argument-error who "list of real pairs or list of point% objects" points))
  (define converted
    (for/list ([p (in-list points)])
      (define x (if (pair? p) (car p) (send p get-x)))
      (define y (if (pair? p) (cdr p) (send p get-y)))
      (cons (dc-real who (+ (dc-real who x) dx)) (dc-real who (+ (dc-real who y) dy)))))
  (if (< (length converted) 2) '()
      (append
       (for/list ([p (in-list converted)] [i (in-naturals)])
         (vector-immutable (if (= i 0) 'move 'line) (car p) (cdr p)))
       (if close? (list '#(close)) '()))))
(define (dc-rectangle x y w h)
  (list (vector-immutable 'move x y) (vector-immutable 'line (+ x w) y)
        (vector-immutable 'line (+ x w) (+ y h)) (vector-immutable 'line x (+ y h)) '#(close)))
(define (dc-clip-points matrix x y w h)
  (dc-path-map (dc-rectangle x y w h) (lambda (x y) (dc-point matrix x y))))
;; get-clipping-region must return an actual region%, not an invented hash.
;; Rectangle tickets are immutable through its documented mutators. Their
;; snapshots can be saved/restored without implementing arbitrary region import.
(define tickets (make-weak-hasheq))
(define (read-only who) (dc-unsupported who 'immutable-skia-rectangle-snapshot "0.54"))
(define rectangle-region%
  (class rd:region%
    (init path)
    (super-new)
    (super set-path path 0 0 'winding)
    (define/override (set-arc . xs) (read-only 'set-arc))
    (define/override (set-ellipse . xs) (read-only 'set-ellipse))
    (define/override (set-path . xs) (read-only 'set-path))
    (define/override (set-polygon . xs) (read-only 'set-polygon))
    (define/override (set-rectangle . xs) (read-only 'set-rectangle))
    (define/override (set-rounded-rectangle . xs) (read-only 'set-rounded-rectangle))
    (define/override (intersect . xs) (read-only 'intersect))
    (define/override (subtract . xs) (read-only 'subtract))
    (define/override (union . xs) (read-only 'union))
    (define/override (xor . xs) (read-only 'xor))))
(define (make-dc-clip owner commands)
  (define p (new rd:dc-path%))
  (for ([v (in-list commands)])
    (case (vector-ref v 0)
      [(move) (send p move-to (vector-ref v 1) (vector-ref v 2))]
      [(line) (send p line-to (vector-ref v 1) (vector-ref v 2))]
      [(close) (send p close)]))
  (define r (new rectangle-region% [path p]))
  (hash-set! tickets r (cons owner commands))
  r)
(define (dc-clip-data who owner region)
  (cond [(not region) #f]
        [(not (is-a? region rd:region%)) (raise-argument-error who "region% or #f" region)]
        [else
         (define data (hash-ref tickets region #f))
         (unless (and data (eq? (car data) owner))
           (dc-unsupported who 'arbitrary-or-foreign-region "0.54"))
         (cdr data)]))
