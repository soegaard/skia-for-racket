#lang racket

;;;
;;; Orbiting Lights
;;;

;; Runs an animated window whose scene is shared by raster and GPU renderers.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require racket/class
         racket/cmdline
         (only-in racket/gui/base
                  canvas% frame% vertical-panel% horizontal-panel%
                  button% timer% queue-callback)
         skia
         skia/bitmap
         skia/gpu
         skia/gpu-gui
         "scene.rkt")

(provide open-animation-window)

;;;
;;; Renderer Selection and Animation Window
;;;

; preferred-gpu-backend : -> symbol?
;   Chooses the platform's preferred explicitly requested GPU backend.
(define (preferred-gpu-backend)
  (case (system-type 'os)
    [(macosx) 'metal]
    [(windows)
     (and (eq? (system-type 'arch) 'x86_64)
          'direct3d)]
    [(unix) 'opengl]
    [else #f]))

; open-animation-window : symbol? -> #f
;   Opens the orbiting-light animation with the explicitly requested renderer.
(define (open-animation-window renderer)
  (unless (memq renderer '(raster gpu))
    (raise-argument-error 'open-animation-window "'raster or 'gpu" renderer))
  (define frame-interval-ms 50)
  (define gpu-backend
    (and (eq? renderer 'gpu) (preferred-gpu-backend)))
  (when (and (eq? renderer 'gpu) (not gpu-backend))
    (error 'open-animation-window
           "no supported GPU backend; use --renderer raster"))

  ;;;
  ;;; Window State and Cleanup
  ;;;

  (define view #f)
  (define ticker #f)
  (define window #f)
  (define closed? #f)
  (define (request-frame)
    (when (and view (not closed?))
      (if (eq? renderer 'gpu)
          (send view request-gpu-render)
          (send view refresh))))
  (define (close-animation)
    (unless closed?
      (when ticker (send ticker stop))
      (when (and view (eq? renderer 'gpu))
        (send view close-gpu))
      (set! closed? #t)
      (send window show #f)))
  (define window%
    (class frame%
      (define/augment (on-close)
        (close-animation))
      (super-new)))
  (set! window
    (new window% [label (format "Orbiting Lights / ~a" renderer)]
         [width 800] [height 550]))
  (define panel (new vertical-panel% [parent window]))
  (define controls
    (new horizontal-panel% [parent panel]
         [stretchable-height #f]))

  ;;;
  ;;; Animation Clock and Frame Drawing
  ;;;

  (define elapsed-seconds 0.0)
  (define previous-ms (current-inexact-monotonic-milliseconds))
  (define paused? #f)
  (define (schedule-next-tick)
    ;; Use a low-priority callback so user input is handled before rearming.
    (queue-callback
     (lambda ()
       (when (and ticker (not paused?) (not closed?))
         (send ticker start frame-interval-ms #t)))
     #f))
  (define (paint-frame canvas width height)
    (draw-scene canvas elapsed-seconds width height)
    (schedule-next-tick))
  (define (paint-gpu-frame frame)
    (define canvas (gpu-frame-canvas frame))
    ;; GPU framebuffer dimensions are physical pixels. Draw our scene in
    ;; logical window coordinates, as on the CPU canvas.
    (with-canvas-state canvas
      (canvas-scale! canvas (gpu-frame-scale-x frame) (gpu-frame-scale-y frame))
      (paint-frame canvas
                   (gpu-frame-logical-width frame)
                   (gpu-frame-logical-height frame))))

  (set! view
    (if (eq? renderer 'gpu)
        (new gpu-canvas%
             [parent panel]
             [backend gpu-backend]
             [render paint-gpu-frame])
        (new canvas%
             [parent panel]
             [style '(no-autoclear)]
             [paint-callback
              (lambda (widget dc)
                (define-values (width height) (send widget get-client-size))
                (when (and (positive? width) (positive? height))
                  (with-skia ([surface (make-surface width height)])
                    (paint-frame (surface-canvas surface) width height)
                    ;; This drawing context only presents the completed bitmap.
                    (send dc draw-bitmap (surface->bitmap surface) 0 0))))])))

  (set! ticker
    (new timer%
         [notify-callback
          (lambda ()
            (unless (or paused? closed?)
              (let ([now (current-inexact-monotonic-milliseconds)])
                (set! elapsed-seconds
                      (+ elapsed-seconds (/ (- now previous-ms) 1000.0)))
                (set! previous-ms now)
                (request-frame))))]))

  (new button%
       [parent controls]
       [label "Pause"]
       [callback
        (lambda (button _event)
          (if paused?
              (begin
                (set! paused? #f)
                (set! previous-ms (current-inexact-monotonic-milliseconds))
                (send ticker start frame-interval-ms #t)
                (send button set-label "Pause"))
              (begin
                (set! paused? #t)
                (send ticker stop)
                (send button set-label "Resume"))))])
  (new button%
       [parent controls]
       [label "Close"]
       [callback (lambda (_button _event) (close-animation))])

  (send window show #t)
  (set! previous-ms (current-inexact-monotonic-milliseconds))
  (send ticker start frame-interval-ms #t)
  window)

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; renderer : symbol?
  ;   Selects renderer for the example.
  (define renderer 'raster)
  (command-line
   #:program "orbiting-lights.rkt"
   #:once-each
   [("--renderer") name "raster or gpu"
    (set! renderer (string->symbol name))]
   #:args () (void))
  (unless (memq renderer '(raster gpu))
    (raise-argument-error 'orbiting-lights "'raster or 'gpu" renderer))
  ;; The eventspace handler thread owns the window, timer, and GPU presenter.
  (queue-callback (lambda () (open-animation-window renderer))))
