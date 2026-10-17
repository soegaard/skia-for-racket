#lang racket/base

;;;
;;; GPU Drawing-Context Canvas
;;;

;; Presents frame-scoped Skia drawing contexts in Racket GUI canvases and windows.
;; This opt-in GUI bridge connects GPU presenters to drawing-context callbacks without making a
;; frame context persistent.

;;;
;;; Imports and Exports
;;;

;; DC-oriented facade over the existing backend-neutral GPU presenters.
;; Import explicitly: unlike gpu-dc.rkt, this module initializes racket/gui.
(require racket/class racket/future
         (prefix-in gui: racket/gui/base) (prefix-in rd: racket/draw)
         "gpu-gui.rkt" "gpu-dc.rkt"
         (only-in "gpu.rkt" gpu-frame-info)
         (only-in "private/dc-support.rkt" dc-unsupported))
(provide skia-gpu-canvas% skia-gpu-canvas? skia-gpu-window%)

; handler! : symbol? gui:eventspace? -> void?
;   Requires the canvas's eventspace handler thread and excludes future execution.
(define (handler! who space)
  (unless (and (eq? (current-thread) (gui:eventspace-handler-thread space))
               (not (current-future)))
    (error who "use GPU canvases on their eventspace handler thread")))

; callback! : symbol? procedure? exact-nonnegative-integer? -> void?
;   Checks that a supplied callback accepts the arguments used by the canvas.
(define (callback! who callback arity)
  (unless (and (procedure? callback) (procedure-arity-includes? callback arity))
    (raise-argument-error who (format "procedure accepting ~a arguments" arity) callback)))

; canvas-color : (or/c string? (is-a?/c rd:color%)) -> (is-a?/c rd:color%)
;   Resolves a background color name or copies a supplied color object.
(define (canvas-color value)
  (cond
    [(is-a? value rd:color%)
     (make-object rd:color% (send value red) (send value green) (send value blue) (send value alpha))]
    [(string? value)
     (or (send rd:the-color-database find-color value)
         (raise-argument-error 'skia-gpu-canvas% "known color name" value))]
    [else (raise-argument-error 'skia-gpu-canvas% "color% object or color name" value)]))

; skia-gpu-canvas% : class?
;   Adapts GPU presentation frames to short-lived Skia drawing contexts for GUI paint callbacks.
(define skia-gpu-canvas%
  (class gpu-canvas%
    (init parent [backend 'auto] [adapter #f] [adapter-index #f] [sync-interval #f]
          [paint-callback void] [on-error raise] [background "white"]
          [smoothing 'smoothed] [automatic? #t] [min-width 1] [min-height 1])
    (define space (gui:current-eventspace))
    (handler! 'skia-gpu-canvas% space)
    (callback! 'skia-gpu-canvas% paint-callback 2)
    (unless (memq smoothing '(unsmoothed smoothed aligned))
      (raise-argument-error 'skia-gpu-canvas% "'unsmoothed, 'smoothed, or 'aligned" smoothing))
    (define paint-proc paint-callback)
    (define background-value (canvas-color background))
    (define smoothing-value smoothing)
    (define active-dc #f)
    (define one-shot #f)
    (define synchronous? #f)
    (define closed-value? #f)
    (define ready? #f)
    (define frame-count 0)
    (define last-frame #f)
    (super-new
     [parent parent] [backend backend] [adapter adapter] [adapter-index adapter-index]
     [sync-interval sync-interval] [automatic? automatic?] [on-error on-error]
     [background 'transparent] [min-width min-width] [min-height min-height]
     [render
      (lambda (frame)
        (set! frame-count (add1 frame-count))
        (set! last-frame (gpu-frame-info frame))
        (call-with-gpu-frame-dc frame
          (lambda (dc)
            (dynamic-wind
             (lambda () (set! active-dc dc))
             (lambda () (if one-shot (one-shot dc) (paint-proc this dc)))
             (lambda () (set! active-dc #f))))
          #:background background-value #:smoothing smoothing-value))])
    (define/private (live! who)
      (handler! who space)
      (when closed-value? (error who "Skia GPU canvas is closed")))
    (define/override (get-dc)
      (live! 'get-dc)
      (cond [active-dc active-dc]
            [(not ready?) (super get-dc)] ; toolkit initialization only
            [else
             (error 'get-dc
                    "GPU DC is available only during the paint callback; request a refresh instead")]))
    (define/override (refresh)
      (handler! 'refresh space)
      (when (and ready? (not closed-value?)) (send this request-gpu-render))
      (void))
    (define/override (refresh-now [proc #f] #:flush? [flush? #t])
      (live! 'refresh-now)
      (when (or active-dc synchronous?)
        (error 'refresh-now "nested GPU rendering is not allowed; use refresh"))
      (when proc (callback! 'refresh-now proc 1))
      (unless flush?
        (dc-unsupported 'refresh-now 'gpu-frame-without-presentation "0.59 GPU canvas"))
      (dynamic-wind
       (lambda () (set! synchronous? #t) (set! one-shot proc))
       (lambda () (send this render-gpu-now) (void))
       (lambda () (set! one-shot #f) (set! synchronous? #f))))
    (define/public (present)
      (live! 'present)
      (dc-unsupported 'present 'persistent-gpu-pixels "0.59: use refresh or refresh-now"))
    (define/override (close-gpu)
      (handler! 'close-gpu space)
      ;; The presenter cancels an active frame and defers native destruction
      ;; until it unwinds. The active DC is closed by its own scope cleanup.
      (set! closed-value? #t)
      (super close-gpu))
    (define/public (close-skia) (send this close-gpu))
    (define/public (close) (send this close-gpu))
    (define/public (skia-closed?)
      (handler! 'skia-closed? space)
      closed-value?)
    (define/public (get-skia-info)
      (handler! 'get-skia-info space)
      (hasheq 'stage "0.59" 'storage 'gpu-offscreen 'dc_lifetime 'frame-scoped
              'backend (send this get-gpu-backend) 'closed closed-value?
              'painting (and active-dc #t) 'frames_started frame-count 'last_frame last-frame
              'implicit_cpu_readback #f 'visible_pixels_verified #f 'performance_measured #f))
    (set! ready? #t)))

; skia-gpu-canvas? : any/c -> boolean?
;   Returns whether v is an instance of skia-gpu-canvas%.
(define (skia-gpu-canvas? value) (is-a? value skia-gpu-canvas%))

; skia-gpu-window% : class?
;   Hosts a Skia GPU canvas and closes its native presentation resources with the window.
(define skia-gpu-window%
  (class gui:frame%
    (init [label "Skia GPU DC"] [width 640] [height 480]
          [backend 'auto] [adapter #f] [adapter-index #f] [sync-interval #f]
          [paint-callback void] [on-error raise] [background "white"]
          [smoothing 'smoothed] [automatic? #t])
    (super-new [label label] [width width] [height height])
    (define canvas
      (new skia-gpu-canvas% [parent this] [backend backend] [adapter adapter]
           [adapter-index adapter-index] [sync-interval sync-interval]
           [paint-callback paint-callback] [on-error on-error] [background background]
           [smoothing smoothing] [automatic? automatic?]))
    (define/public (get-skia-canvas) canvas)
    (define/public (get-gpu-presenter) (send canvas get-gpu-presenter))
    (define/public (close-skia)
      (dynamic-wind void (lambda () (send canvas close-skia)) (lambda () (send this show #f))))
    (define/augment (on-close) (send this close-skia))))
