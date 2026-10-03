#lang racket/base
;; All actual style rasterization goes through the existing Skia API.
(require racket/list (prefix-in sk: "../main.rkt")
         "dc-support.rkt" "dc-native-util.rkt" "dc-style-math.rkt" "dc-bitmap.rkt")
(provide call-with-dc-paint)
(define (with-source-shader source antialias? proc)
  (define data (dc-paint-source-data source))
  (case (dc-paint-source-kind source)
    [(gradient)
     (define stops (vector-ref data 2))
     (define colors (map (lambda (s) (native-color (cadr s))) stops))
     (define positions (map car stops))
     (define maker (if (eq? (vector-ref data 0) 'linear)
                       sk:make-linear-gradient-shader sk:make-two-point-conical-gradient-shader))
     (sk:with-skia ([shader (keyword-apply maker '(#:positions #:tile-mode) (list positions 'clamp)
                                         (append (vector-ref data 1) (list colors)))])
       (proc shader))]
    [(stipple)
     (sk:with-skia ([image (sk:rgba-bytes->image (dc-bitmap-data-width data) (dc-bitmap-data-height data)
                                               (dc-bitmap-data-pixels data) #:premultiplied? #t)]
                   [shader (sk:make-image-shader image #:tile-x 'repeat #:tile-y 'repeat
                                                 #:sampling (if antialias? 'linear 'nearest))])
       (proc shader))]
    [(hatch)
     (sk:with-skia ([surface (sk:make-surface 12 12 #:background 'transparent)]
                   [path (sk:make-path)]
                   [paint (sk:make-paint #:color (native-color (vector-ref data 1))
                                          #:style 'stroke #:stroke-width 1 #:antialias? antialias?)])
       (sk:paint-set-cap! paint 'butt)
       (for ([v (in-list (dc-hatch-lines (vector-ref data 0)))])
         (sk:path-move-to! path (vector-ref v 0) (vector-ref v 1))
         (sk:path-line-to! path (vector-ref v 2) (vector-ref v 3)))
       (sk:draw-path (sk:surface-canvas surface) path paint)
       (sk:with-skia ([image (sk:surface-snapshot surface)]
                     [shader (sk:make-image-shader image #:tile-x 'repeat #:tile-y 'repeat
                                                   #:sampling (if antialias? 'linear 'nearest))])
         (proc shader)))]
    [else (error 'skia-dc-style "invalid private paint source")]))
(define (call-with-dc-paint ink antialias? proc)
  (define source (and (dc-ink/style? ink) (dc-ink/style-source ink)))
  (define (paint shader [rgba (dc-ink-rgba ink)])
    (sk:with-skia ([p (sk:make-paint #:color (native-color rgba)
                                    #:shader shader
                                    #:style (if (dc-ink-stroke? ink) 'stroke 'fill)
                                    #:stroke-width (dc-ink-width ink) #:antialias? antialias?)])
      (sk:paint-set-cap! p (dc-ink-cap ink))
      (sk:paint-set-join! p (dc-ink-join ink))
      (sk:paint-set-miter-limit! p 10)
      (if (pair? (dc-ink-dashes ink))
          (sk:with-skia ([effect (sk:make-dash-path-effect (dc-ink-dashes ink)
                                                           (if (dc-ink/style? ink) (dc-ink/style-phase ink) 0.0))])
            (sk:paint-set-path-effect! p effect) (proc p))
          (proc p))))
  (cond
    [(not source) (paint #f)]
    [(and (eq? (dc-paint-source-kind source) 'gradient)
          (< (length (vector-ref (dc-paint-source-data source) 2)) 2))
     ;; Cairo permits zero/one stop. Skia's native constructors need at least
     ;; two, so reduce these cases to a transparent/constant paint.
     (define stops (vector-ref (dc-paint-source-data source) 2))
     (define c (if (null? stops) '#(0 0 0 0.0) (cadar stops)))
     (paint #f (vector (vector-ref c 0) (vector-ref c 1) (vector-ref c 2)
                       (* (vector-ref c 3) (vector-ref (dc-ink-rgba ink) 3))))]
    [else
     (with-source-shader source antialias?
       (lambda (shader)
         (sk:with-skia ([mapped (sk:shader-with-local-matrix shader
                                 (apply sk:make-matrix (vector->list (dc-paint-source-matrix source))))])
           (paint mapped))))]))
