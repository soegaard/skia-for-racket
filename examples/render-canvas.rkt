#lang racket/base
;; The same callback can run on raster, Metal, OpenGL, or Direct3D.
;; Run from the checkout, or require skia/render-canvas when installed.
(require racket/class racket/cmdline (prefix-in gui: racket/gui/base)
         "../render-canvas.rkt" "../tests/gpu-dc-consumer-fixtures.rkt")

(define (open-review renderer backend adapter)
  (define workloads (make-consumer-workloads))
  (define selected 0)
  (define canvas #f)
  (define review-frame%
    (class gui:frame%
      (super-new)
      (define/augment (on-close)
        (when canvas (send canvas close))
        (send this show #f))))
  (define frame (new review-frame% [label "Skia 0.61: unified render canvas"] [width 720] [height 560]))
  (define panel (new gui:vertical-panel% [parent frame]))
  (new gui:choice% [parent panel] [label "Consumer / execution"]
       [choices (for/list ([w (in-list workloads)])
                  (string-append (consumer-workload-scene w) " / " (consumer-workload-mode w)))]
       [callback (lambda (choice _event)
                   (set! selected (send choice get-selection))
                   (when canvas (send canvas refresh)))])
  (set! canvas
    (make-skia-render-canvas panel #:renderer renderer #:backend backend #:adapter adapter
      #:min-width 320 #:min-height 240
      #:paint-callback
      (lambda (_canvas dc)
        ;; Portable callbacks establish all state they depend on; only raster
        ;; preserves DC state between frames. Never retain the callback's DC.
        (send dc set-transformation '#(#(1 0 0 1 0 0) 0 0 1 1 0))
        (send dc set-clipping-region #f) (send dc set-alpha 1)
        (send dc set-background "white") (send dc clear)
        (exercise-consumer! (list-ref workloads selected) dc))))
  (send frame set-label
        (format "Skia 0.61: ~a / ~a" (send canvas get-renderer) (send canvas get-backend)))
  (send frame show #t)
  (void))

(module+ main
  ;; Mutable options belong to this submodule, not to its enclosing module.
  (define renderer 'auto)
  (define backend 'auto)
  (define adapter #f)
  (command-line #:once-each
    [("--renderer") name "auto, raster or gpu" (set! renderer (string->symbol name))]
    [("--backend") name "auto, opengl, metal or direct3d" (set! backend (string->symbol name))]
    [("--adapter") name "hardware or warp (Direct3D)" (set! adapter (string->symbol name))]
    #:args () (void))
  ;; Capture options lexically; queue-callback does not transfer the caller's
  ;; dynamic parameterization into the eventspace's existing handler thread.
  (gui:queue-callback (lambda () (open-review renderer backend adapter))))
