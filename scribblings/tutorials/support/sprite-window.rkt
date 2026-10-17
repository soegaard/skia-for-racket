#lang racket

;;;
;;; Sprite Window
;;;

;; Hosts the sprite tutorials in a lazily loaded GUI submodule with explicit renderer choice.
;; This module supports documentation assembly and shared examples rather than the public Skia
;; API.


;; Loading this file is headless. Only the explicitly selected gui submodule
;; initializes the toolkit, so source-package test traversal need not open it.
(module gui racket
  ;; Small shared host, not a new public Skia widget or a general game engine.
  (require racket/class
           (only-in racket/gui/base
                    canvas% frame% vertical-panel% horizontal-panel% button% message%
                    timer% queue-callback current-eventspace eventspace-handler-thread)
           skia skia/bitmap skia/gpu skia/gpu-gui
           "sprite-assets.rkt" "sprite-math.rkt")
  (provide open-sprite-window)

  ;;;
  ;;; Backend Selection and Shared Window
  ;;;

  ; preferred-backend : -> (or/c symbol? #f)
  ;   Returns the supported platform GPU choice, or #f when no choice is defined.
  (define (preferred-backend)
    (case (system-type 'os)
      [(macosx) 'metal]
      [(windows) (and (eq? (system-type 'arch) 'x86_64) 'direct3d)]
      [(unix) 'opengl]
      [else #f]))

  ; open-sprite-window : string? real? real? any/c any/c any/c any/c #:renderer [symbol?]
  ; #:instructions [any/c] #:smoke? [boolean?] -> (is-a?/c frame%)
  ;   Creates the shared sprite host with fixed-step updates and scoped renderer cleanup.
  (define (open-sprite-window title scene-width scene-height
                              make-atlas make-world step-world! draw-world
                              #:renderer [renderer 'gpu]
                              #:instructions [instructions "P: pause   R: restart"]
                              #:smoke? [smoke? #f])
    (unless (memq renderer '(gpu raster))
      (raise-argument-error 'open-sprite-window "'gpu or 'raster" renderer))
    (unless (eq? (current-thread) (eventspace-handler-thread (current-eventspace)))
      (error 'open-sprite-window "call on the GUI handler thread using queue-callback"))
    (define backend (and (eq? renderer 'gpu) (preferred-backend)))
    (when (and (eq? renderer 'gpu) (not backend))
      (error 'open-sprite-window "no GPU backend; choose --renderer raster"))

    ;;;
    ;;; Owned Assets and Simulation State
    ;;;

    (define texture (make-sprite-texture (make-atlas)))
    (define world (make-world))
    (define held (make-hasheq))
    (define paused? #f)
    (define closed? #f)
    (define failed? #f)
    (define pending-arm? #f)
    (define ticker #f)
    (define view #f)
    (define window #f)
    (define pause-button #f)
    (define status #f)
    (define previous-ms (current-inexact-monotonic-milliseconds))
    (define remainder 0.0)
    (define frames 0)
    (define smoke-stage 0)

    ;;;
    ;;; Controls and Cleanup
    ;;;

    (define (refresh-status)
      (when status
        (send status set-label
              (format "~a / ~a   atlas uploads: ~a~a"
                      renderer (or backend 'cpu) (sprite-texture-uploads texture)
                      (cond [failed? "   rendering failed"] [paused? "   paused"] [else ""])))))
    (define (request-frame)
      (when (and view (not closed?) (not failed?))
        (if (eq? renderer 'gpu) (send view request-gpu-render) (send view refresh))))
    (define (reset-clock!)
      (set! remainder 0.0)
      (set! previous-ms (current-inexact-monotonic-milliseconds)))
    (define (toggle-pause!)
      (unless (or closed? failed?)
        (set! paused? (not paused?))
        (hash-clear! held)
        (when ticker (send ticker stop))
        (reset-clock!)
        (send pause-button set-label (if paused? "Resume" "Pause"))
        (refresh-status)
        (request-frame)))
    (define (restart!)
      (unless (or closed? failed?)
        ;; Restart only the simulation. Do not rebuild or upload the atlas.
        (set! world (make-world))
        (hash-clear! held)
        (reset-clock!)
        (request-frame)))
    (define (close-window!)
      (unless closed?
        (when ticker (send ticker stop))
        (close-sprite-texture! texture)
        (when (and view (eq? renderer 'gpu)) (send view close-gpu))
        (set! closed? #t)
        (send window show #f)))
    (define (render-error error)
      (set! failed? #t)
      (when ticker (send ticker stop))
      (refresh-status)
      (eprintf "~a: ~a\n" title (if (exn? error) (exn-message error) error))
      (when smoke? (close-window!) (exit 1)))

    ;;;
    ;;; Frame Scheduling and Smoke Checks
    ;;;

    (define (schedule-next-tick)
      ;; Only one low-priority rearm can be queued. Input runs before rearming.
      (unless (or pending-arm? paused? closed? failed?)
        (set! pending-arm? #t)
        (queue-callback
         (lambda ()
           (set! pending-arm? #f)
           (when (and ticker (not paused?) (not closed?) (not failed?))
             (send ticker start 16 #t)))
         #f)))

    (define (after-frame)
      (set! frames (add1 frames))
      (refresh-status)
      (when smoke?
        ;; Exercise the same pause/restart/close functions as the controls.
        ;; These actions run outside the borrowed frame scope.
        (cond
          [(and (= smoke-stage 0) (>= frames 3))
           (set! smoke-stage 1)
           (queue-callback
            (lambda ()
              (toggle-pause!)
              (unless paused? (error 'sprite-smoke "pause did not take effect"))
              (queue-callback (lambda () (toggle-pause!)) #f)) #f)]
          [(and (= smoke-stage 1) (>= frames 6))
           (set! smoke-stage 2)
           (queue-callback restart! #f)]
          [(and (= smoke-stage 2) (>= frames 10))
           (set! smoke-stage 3)
           (queue-callback
            (lambda ()
              (define uploads (sprite-texture-uploads texture))
              (unless (= uploads (if (eq? renderer 'gpu) 1 0))
                (error 'sprite-smoke "unexpected atlas upload count: ~a" uploads))
              (close-window!)
              (printf "sprite-window-smoke: ~a / ~a frames / ~a uploads / closed\n"
                      renderer frames uploads)) #f)]))
      (schedule-next-tick))

    ;;;
    ;;; Raster and GPU Drawing
    ;;;

    (define (paint-scene canvas atlas width height)
      (define-values (scale x y) (fit-viewport width height scene-width scene-height))
      (canvas-clear! canvas "#050B18")
      (with-canvas-state canvas
        (canvas-translate! canvas x y)
        (canvas-scale! canvas scale scale)
        (canvas-clip-rect! canvas 0 0 scene-width scene-height)
        (draw-world canvas atlas world)))
    (define (paint-gpu-frame frame)
      (define atlas (sprite-texture-for-frame! texture frame))
      (define canvas (gpu-frame-canvas frame))
      (when (and smoke? (zero? frames))
        (define info (gpu-image-info atlas))
        (unless (and (hash-ref info 'texture_backed #f) (hash-ref info 'context_matches #f))
          (error 'sprite-smoke "atlas has no valid texture in this context")))
      (with-canvas-state canvas
        (canvas-scale! canvas (gpu-frame-scale-x frame) (gpu-frame-scale-y frame))
        (paint-scene canvas atlas
                     (gpu-frame-logical-width frame) (gpu-frame-logical-height frame)))
      (after-frame))

    ;;;
    ;;; Input Classes and Widget Construction
    ;;;

    (define (input-canvas% base%)
      (class base%
        (super-new)
        (define/override (on-event event)
          (when (send event button-down? 'left) (send this focus)))
        (define/override (on-focus focused?)
          (unless focused? (hash-clear! held)))
        (define/override (on-char event)
          (define released? (eq? (send event get-key-code) 'release))
          (define raw (if released? (send event get-key-release-code) (send event get-key-code)))
          (define key (if (char? raw) (char-downcase raw) raw))
          (cond
            [released? (hash-remove! held key)]
            [(not (hash-ref held key #f))
             (hash-set! held key #t)
             (case key
               [(#\p) (toggle-pause!) (hash-set! held key #t)]
               [(#\r) (restart!) (hash-set! held key #t)]
               [else (void)])]))))
    (define window%
      (class frame%
        (super-new)
        (define/augment (on-close) (close-window!))))

    ;; If construction fails after the atlas was made, retire it on this thread.
    (with-handlers ([exn:fail? (lambda (error)
                               (close-sprite-texture! texture)
                               (when (and view (eq? renderer 'gpu)) (send view close-gpu))
                               (when window (send window show #f))
                               (raise error))])
      (set! window (new window% [label title]
                       [width (+ scene-width 40)] [height (min 780 (+ scene-height 110))]))
      (define panel (new vertical-panel% [parent window]))
      (define controls (new horizontal-panel% [parent panel] [stretchable-height #f]))
      (set! pause-button
        (new button% [parent controls] [label "Pause"]
             [callback (lambda (_button _event) (toggle-pause!) (send view focus))]))
      (new button% [parent controls] [label "Restart"]
           [callback (lambda (_button _event) (restart!) (send view focus))])
      (new button% [parent controls] [label "Close"]
           [callback (lambda (_button _event) (close-window!))])
      (set! status (new message% [parent controls] [label "Preparing atlas"] [auto-resize #t]))
      (new message% [parent panel] [label instructions])
      (set! view
        (if (eq? renderer 'gpu)
            (new (input-canvas% gpu-canvas%) [parent panel] [backend backend]
                 [min-width 320] [min-height 240]
                 [render paint-gpu-frame] [on-error render-error])
            (new (input-canvas% canvas%) [parent panel] [style '(no-autoclear)]
                 [min-width 320] [min-height 240]
                 [paint-callback
                  (lambda (widget dc)
                    (with-handlers ([exn:fail? render-error])
                      (define-values (width height) (send widget get-client-size))
                      (when (and (positive? width) (positive? height) (not closed?) (not failed?))
                        (with-skia ([surface (make-surface width height)])
                          (paint-scene (surface-canvas surface) (sprite-texture-cpu texture)
                                       width height)
                          ;; The GUI DC displays pixels; all artwork was drawn by Skia.
                          (send dc draw-bitmap (surface->bitmap surface) 0 0))
                        (after-frame))))])))
      (set! ticker
        (new timer%
             [notify-callback
              (lambda ()
                (unless (or closed? paused? failed?)
                  (with-handlers ([exn:fail? render-error])
                    (define now (current-inexact-monotonic-milliseconds))
                    (define-values (steps rest)
                      (advance-clock remainder (/ (- now previous-ms) 1000.0)))
                    (set! previous-ms now)
                    (set! remainder rest)
                    (for ([_ (in-range steps)])
                      (step-world! world fixed-step (lambda (key) (hash-ref held key #f))))
                    (request-frame))))]))
      (refresh-status)
      (send window show #t)
      (send view focus)
      (reset-clock!)
      (schedule-next-tick)
      window))
)
