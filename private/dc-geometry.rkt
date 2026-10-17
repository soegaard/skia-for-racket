#lang racket/base

;;;
;;; Drawing Context Geometry
;;;

;; Builds detached path commands for shapes and clipping geometry.
;; Translates dc<%> geometry into the common Skia rendering representation.

;; Public Racket path access only. No private racket/draw or Cairo entry points.

;;;
;;; Imports and Exports
;;;

(require racket/class racket/list racket/vector (prefix-in rd: racket/draw) "dc-support.rkt")
(provide dc-path-commands dc-polyline dc-rectangle dc-clip-points)

;;;
;;; Detached Shape Commands
;;;

; dc-path-commands : symbol? (is-a?/c dc-path%) [real? real?] -> (listof vector?)
;;   Copies closed then open Racket contours into immutable move/line/cubic/close commands with
;;   optional xy translation.
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

; dc-polyline : symbol? list? real? real? boolean? -> (listof vector?)
;;   Copies a homogeneous list of coordinate pairs or point% objects into translated commands,
;;   optionally closing the contour.
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

; dc-rectangle : real? real? real? real? -> (listof vector?)
;;   Builds a closed rectangular contour in corner order from x, y, width, and height.
(define (dc-rectangle x y w h)
  (list (vector-immutable 'move x y) (vector-immutable 'line (+ x w) y)
        (vector-immutable 'line (+ x w) (+ y h)) (vector-immutable 'line x (+ y h)) '#(close)))

; dc-clip-points : vector? real? real? real? real? -> (listof vector?)
;;   Transforms a rectangle into device-coordinate path commands for clipping or pixel copies.
(define (dc-clip-points matrix x y w h)
  (dc-path-map (dc-rectangle x y w h) (lambda (x y) (dc-point matrix x y))))
