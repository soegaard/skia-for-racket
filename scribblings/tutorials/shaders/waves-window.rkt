#lang racket

(require racket/class racket/cmdline
         (only-in racket/gui/base
                  canvas% frame% vertical-panel% horizontal-panel%
                  button% slider% timer% queue-callback)
         skia skia/bitmap skia/gpu skia/gpu-gui
         "waves.rkt")

(provide open-waves-window)

(define (preferred-gpu-backend)
  (case (system-type 'os)
    [(macosx) 'metal]
    [(windows) (and (eq? (system-type 'arch) 'x86_64) 'direct3d)]
    [(unix) 'opengl]
    [else #f]))

(define (open-waves-window renderer)
  (unless (memq renderer '(raster gpu))
    (raise-argument-error 'open-waves-window "'raster or 'gpu" renderer))
  (define backend (and (eq? renderer 'gpu) (preferred-gpu-backend)))
  (when (and (eq? renderer 'gpu) (not backend))
    (error 'open-waves-window "no GPU backend for this platform; use --renderer raster"))

  ;; Compile once on the GUI handler thread; create shader instances per frame.
  (define effect (make-runtime-effect wave-source))
  (define frequency 5)
  (define bend 0.30)
  (define hue 0.08)
  (define seconds 0.0)
  (define previous-ms (current-inexact-monotonic-milliseconds))
  (define paused? #f)
  (define closed? #f)
  (define view #f)
  (define ticker #f)
  (define window #f)
  (define frame-interval-ms 50)

  (define (request-frame)
    (when (and view (not closed?))
      (if (eq? renderer 'gpu)
          (send view request-gpu-render)
          (send view refresh))))

  (define (schedule-next-tick)
    (queue-callback
     (lambda ()
       (when (and ticker (not paused?) (not closed?))
         (send ticker start frame-interval-ms #t)))
     #f))

  (define (paint-frame canvas width height)
    (draw-wave-scene canvas effect seconds width height
                     #:frequency frequency #:bend bend #:hue hue)
    (schedule-next-tick))

  (define (paint-gpu-frame frame)
    (define canvas (gpu-frame-canvas frame))
    (with-canvas-state canvas
      (canvas-scale! canvas
                     (gpu-frame-scale-x frame)
                     (gpu-frame-scale-y frame))
      (paint-frame canvas
                   (gpu-frame-logical-width frame)
                   (gpu-frame-logical-height frame))))

  (define (close-waves)
    (unless closed?
      (when ticker (send ticker stop))
      (when (and view (eq? renderer 'gpu)) (send view close-gpu))
      (skia-close! effect)
      (set! closed? #t)
      (send window show #f)))

  (define window%
    (class frame%
      (define/augment (on-close) (close-waves))
      (super-new)))
  (set! window
    (new window% [label (format "Prismatic Waves / ~a" renderer)]
         [width 950] [height 620]))
  (define panel (new vertical-panel% [parent window]))
  (define controls
    (new horizontal-panel% [parent panel] [stretchable-height #f]))

  (new slider%
       [parent controls] [label "Frequency"]
       [min-value 1] [max-value 10] [init-value 5]
       [callback (lambda (slider _event)
                   (set! frequency (send slider get-value))
                   (request-frame))])
  (new slider%
       [parent controls] [label "Bend"]
       [min-value 0] [max-value 60] [init-value 30]
       [callback (lambda (slider _event)
                   (set! bend (/ (send slider get-value) 100.0))
                   (request-frame))])
  (new slider%
       [parent controls] [label "Hue"]
       [min-value 0] [max-value 100] [init-value 8]
       [callback (lambda (slider _event)
                   (set! hue (/ (send slider get-value) 100.0))
                   (request-frame))])
  (new button%
       [parent controls] [label "Pause"]
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
       [parent controls] [label "Close"]
       [callback (lambda (_button _event) (close-waves))])

  (set! view
    (if (eq? renderer 'gpu)
        (new gpu-canvas% [parent panel] [backend backend]
             [render paint-gpu-frame])
        (new canvas%
             [parent panel] [style '(no-autoclear)]
             [paint-callback
              (lambda (widget dc)
                (define-values (width height) (send widget get-client-size))
                (when (and (positive? width) (positive? height))
                  (with-skia ([surface (make-surface width height)])
                    (paint-frame (surface-canvas surface) width height)
                    (send dc draw-bitmap (surface->bitmap surface) 0 0))))])))

  (set! ticker
    (new timer%
         [notify-callback
          (lambda ()
            (unless (or paused? closed?)
              (let ([now (current-inexact-monotonic-milliseconds)])
                (set! seconds (+ seconds (/ (- now previous-ms) 1000.0)))
                (set! previous-ms now)
                (request-frame))))]))

  (send window show #t)
  (set! previous-ms (current-inexact-monotonic-milliseconds))
  (send ticker start frame-interval-ms #t)
  window)

(module+ main
  (define renderer 'gpu)
  (command-line
   #:program "waves-window.rkt" #:once-each
   [("--renderer") name "gpu or raster"
    (set! renderer (string->symbol name))]
   #:args () (void))
  (unless (memq renderer '(raster gpu))
    (raise-argument-error 'waves-window.rkt "'raster or 'gpu" renderer))
  (queue-callback (lambda () (open-waves-window renderer))))
