#lang racket/base
(require racket/list "../main.rkt")
(provide geometry-width geometry-height geometry-scene-names geometry-scene-probes
         draw-geometry-scene capture-geometry-scene current-geometry-renderer check-geometry-pixels)
(define geometry-width 64)
(define geometry-height 48)
(define geometry-scene-names '(arc tangent boolean outline region rrect polygon))
(define blue '(0 64 220 255))
(define red '(220 32 16 255))
(define green '(0 160 80 255))
(define white '(255 255 255 255))
(define (geometry-scene-probes name)
  (case name
    [(arc) (list (list 32 32 blue) (list 12 12 white) (list 50 40 white))]
    [(tangent) (list (list 24 8 red) (list 40 28 red) (list 12 32 white))]
    [(boolean) (list (list 12 12 blue) (list 24 24 white) (list 44 36 blue))]
    [(outline) (list (list 32 24 red) (list 8 24 red) (list 32 10 white))]
    [(region) (list (list 18 16 blue) (list 34 16 white) (list 44 16 blue))]
    [(rrect) (list (list 32 24 green) (list 13 9 white) (list 58 24 white))]
    [(polygon) (list (list 32 16 red) (list 8 32 white) (list 56 40 white))]
    [else (raise-argument-error 'geometry-scene-probes "known geometry scene" name)]))
(define (pixel b x y)
  (define offset (* 4 (+ x (* geometry-width y))))
  (bytes->list (subbytes b offset (+ offset 4))))
(define (check-geometry-pixels name data)
  (unless (= (bytes-length data) (* geometry-width geometry-height 4))
    (error 'geometry-pixels "wrong byte count"))
  (for ([probe (in-list (geometry-scene-probes name))])
    (define actual (pixel data (car probe) (cadr probe)))
    (unless (for/and ([a (in-list actual)] [b (in-list (caddr probe))]) (<= (abs (- a b)) 2))
      (error 'geometry-pixels "~a @ ~a,~a expected ~a got ~a"
             name (car probe) (cadr probe) (caddr probe) actual))))
(define current-geometry-renderer
  (make-parameter
   (lambda (draw)
     (with-skia ([surface (make-surface geometry-width geometry-height #:background 'white)])
       (draw (surface-canvas surface))
       (surface->rgba-bytes surface #:premultiplied? #t)))))
(define (capture-geometry-scene name)
  ((current-geometry-renderer) (lambda (c) (draw-geometry-scene name c))))
(define (draw-geometry-scene name c)
  (with-skia ([blue-p (make-paint #:color (rgb 0 64 220) #:antialias? #f)]
              [red-p (make-paint #:color (rgb 220 32 16) #:antialias? #f)]
              [green-p (make-paint #:color (rgb 0 160 80) #:antialias? #f)])
    (case name
      [(arc)
       (with-skia ([p (make-path)])
         (path-arc-to-oval! p 8 8 32 32 0 90 #:force-move? #t)
         (path-line-to! p 24 24) (path-close! p) (draw-path c p blue-p))]
      [(tangent)
       (with-skia ([p (make-path '((move 8 8)))])
         (path-tangent-arc-to! p 40 8 40 40 8) (path-line-to! p 40 40)
         (paint-set-style! red-p 'stroke) (paint-set-stroke-width! red-p 4)
         (draw-path c p red-p))]
      [(boolean)
       (with-skia ([a (make-path)] [b (make-path)])
         (path-add-rect-start! a 8 8 40 32 2)
         (path-add-rect-start! b 20 16 12 16 1 #:direction 'ccw)
         (with-skia ([result (path-combine (list (list 'union a) (list 'difference b)))])
           (skia-close! a) (skia-close! b) (draw-path c result blue-p)))]
      [(outline)
       (with-skia ([line (make-path '((move 8 24) (line 56 24)))]
                   [stroke (make-paint #:style 'stroke #:stroke-width 8)])
         (paint-set-cap! stroke 'round)
         (define-values (path fillable?) (paint->fill-path stroke line))
         (call-with-skia-resource path
           (lambda (p)
             (unless fillable? (error 'draw-geometry-scene "expected a fillable outline"))
             (skia-close! stroke) (skia-close! line) (draw-path c p red-p))))]
      [(region)
       (with-skia ([region (make-region '((8 8 24 24) (40 8 16 24)))])
         (with-skia ([cropped (region-op-rect region '(16 12 32 20) 'intersect)]
                     [path (region->path cropped)])
           (skia-close! region) (skia-close! cropped) (draw-path c path blue-p)))]
      [(rrect)
       (define rr (rounded-rect-offset (make-nine-patch-rounded-rect 8 8 40 32 6 6 6 6) 4 0))
       (with-skia ([p (make-path)])
         (path-add-rrect! p rr #:start-index 3) (draw-path c p green-p))]
      [(polygon)
       (with-skia ([p (make-path)])
         (path-add-polygon! p '((8 8) (56 8) (32 40))) (draw-path c p red-p))]
      [else (raise-argument-error 'draw-geometry-scene "known geometry scene" name)])))
