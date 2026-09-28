#lang racket/base
;; Backend-independent drawing used by the image-workflow doctor. Sources are
;; ordinary image? values: the doctor supplies independent CPU or GPU images.
(require racket/list "../main.rkt")
(provide image-workflow-names image-workflow-width image-workflow-height
         image-workflow-pixels make-image-workflow-source draw-image-workflow-source
         make-image-workflow-picture)
(define image-workflow-names '(upload-reuse snapshot-graph))
(define image-workflow-width 420)
(define image-workflow-height 260)
(define image-workflow-pixels
  (apply bytes
    (append* (for*/list ([y (in-range 8)] [x (in-range 8)])
               (cond [(= x 3) '(0 0 0 0)]
                     [(< y 4) (if (< x 3) '(255 0 0 255) '(0 255 0 255))]
                     [else (if (< x 3) '(0 0 255 255) '(255 255 0 255))])))))
(define (make-image-workflow-source)
  (rgba-bytes->image 8 8 image-workflow-pixels #:premultiplied? #t))
(define (rectangle c x y w h color)
  (with-skia ([p (make-paint #:color color #:antialias? #f)]) (draw-rect c x y w h p)))
(define (draw-image-workflow-source c)
  (canvas-clear! c 'transparent)
  (rectangle c 0 0 3 4 (rgb 255 0 0))
  (rectangle c 4 0 4 4 (rgb 0 255 0))
  (rectangle c 0 4 3 4 (rgb 0 0 255))
  (rectangle c 4 4 4 4 (rgb 255 255 0)))
(define (label c text x y size)
  (with-skia ([font (make-font #:size size #:hinting 'none #:linear-metrics? #t #:subpixel? #t)]
              [paint (make-paint #:color "#17354B")])
    (draw-simple-text c text x y font paint)))
(define (make-image-workflow-picture name source subset)
  (unless (memq name image-workflow-names)
    (raise-argument-error 'make-image-workflow-picture "image-workflow name" name))
  ;; All these intermediate wrappers are closed before the resulting picture
  ;; is used. Native retains, not reachability of the original Racket wrappers,
  ;; must preserve the source texture and the associated execution domain.
  (with-skia ([shader (make-image-shader source #:tile-x 'repeat #:tile-y 'repeat)]
              [local (shader-with-local-matrix shader (matrix-scale 6))]
              [effect (make-runtime-effect
                        "uniform shader tex; half4 main(float2 p) { return tex.eval(p); }")]
              [runtime (runtime-effect->shader effect #:children (hash "tex" local))]
              [paint (make-paint #:shader runtime)]
              [copy (paint-copy paint)]
              [filter (make-image-source-filter source #:destination '(196 166 192 60)
                                                #:sampling 'nearest)]
              [filtered (make-paint #:image-filter filter)]
              [inner
               (call-with-picture image-workflow-width image-workflow-height
                 (lambda (c)
                   (rectangle c 16 16 388 228 'white)
                   (rectangle c 0 0 8 8 (rgb 255 0 0))
                   (rectangle c 412 0 8 8 (rgb 0 255 0))
                   (rectangle c 0 252 8 8 (rgb 0 0 255))
                   (rectangle c 412 252 8 8 (rgb 255 255 0))
                   (label c (string-append "GPU image / CPU   " (symbol->string name)) 28 42 16)
                   (draw-image-rect c source 28 64 144 144 #:sampling 'nearest)
                   (draw-image-rect c subset 196 64 82 76 #:sampling 'nearest)
                   (draw-rounded-rect c 298 64 90 76 10 10 copy)
                   (draw-rect c 196 166 192 60 filtered)
                   (label c "image" 28 228 12)
                   (label c "subset" 196 154 12)
                   (label c "retained SkSL" 298 154 12)))])
    ;; A second recorder adds a picture -> picture dependency.
    (call-with-picture image-workflow-width image-workflow-height
      (lambda (c) (draw-picture c inner)))))
