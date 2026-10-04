#lang racket/base
;; Unified factory, not a replacement for either existing concrete class.
;; This explicit GUI module imports only the selected raster/GPU implementation.
(require racket/class racket/future racket/promise racket/runtime-path
         (prefix-in gui: racket/gui/base)
         "private/render-canvas-policy.rkt" "private/render-canvas-state.rkt")
(provide make-skia-render-canvas skia-render-canvas<%> skia-render-canvas?
         skia-render-window%)

(define-runtime-path raster-module "canvas.rkt")
(define-runtime-path gpu-module "gpu-canvas.rkt")
(define skia-render-canvas<%>
  (interface () get-renderer get-backend get-render-capabilities get-render-info
                get-dc get-raster-dc set-paint-callback refresh refresh-now
                present close-skia close closed?))
(define (skia-render-canvas? value) (is-a? value skia-render-canvas<%>))

(define (handler! who)
  (unless (and (eq? (current-thread) (gui:eventspace-handler-thread (gui:current-eventspace)))
               (not (current-future)))
    (error who "create render canvases on their eventspace handler thread (queue-callback)")))

(define (callback-canvas-class base% raster?)
  (class* base% (skia-render-canvas<%>)
    (inherit/super closed? get-skia-info)
    (init parent policy [paint-callback void] [on-error raise]
          [background "white"] [smoothing 'smoothed] [min-width 1] [min-height 1])
    (define selection policy)
    (define capabilities (render-canvas-capabilities selection))
    (define session (make-render-session paint-callback))
    (define error-proc on-error)
    (define facade-ready? #f)
    (define close-status 'open)
    (define last-size #f)
    (define toolkit-dc-permitted? #f)
    (define/private (with-toolkit-access thunk)
      ;; canvas%'s refresh-now calls virtual get-dc before invoking its paint
      ;; procedure. Permit that ONE synchronous handoff, not persistent public
      ;; access. GPU refresh-now does not call the toolkit implementation.
      (if raster?
          (dynamic-wind
           (lambda () (set! toolkit-dc-permitted? #t))
           thunk
           (lambda () (set! toolkit-dc-permitted? #f)))
          (thunk)))
    (check-render-callback 'make-skia-render-canvas error-proc 1)
    (define/private (live! who)
      (render-session-check! who session)
      (when (super closed?) (error who "render canvas is closed")))
    (define/private (idle! who)
      (live! who) (render-session-idle! who session))
    (define/private (deliver dc [one-shot #f])
      (define-values (w h) (send dc get-size))
      (define-values (pw ph) (send dc get-pixel-size))
      (set! last-size (hasheq 'logical_width w 'logical_height h 'pixel_width pw 'pixel_height ph))
      (render-session-deliver! session this dc one-shot))

    ;; Both superclass constructors take a two-argument paint callback. Raster
    ;; has no on-error option; its scheduled paint exceptions are routed below.
    (if raster?
        (super-new [parent parent] [paint-callback (lambda (_canvas dc) (deliver dc))]
                   [background background] [smoothing smoothing]
                   [min-width min-width] [min-height min-height])
        (super-new [parent parent] [paint-callback (lambda (_canvas dc) (deliver dc))]
                   [on-error error-proc] [background background] [smoothing smoothing]
                   [min-width min-width] [min-height min-height]
                   [backend (hash-ref selection 'backend)] [adapter (hash-ref selection 'adapter)]
                   [adapter-index (hash-ref selection 'adapter_index)]
                   [sync-interval (hash-ref selection 'sync_interval)]))

    (define/public (get-renderer)
      (render-session-check! 'get-renderer session) (hash-ref selection 'renderer))
    (define/public (get-backend)
      (render-session-check! 'get-backend session) (hash-ref selection 'backend))
    (define/public (get-render-capabilities)
      (render-session-check! 'get-render-capabilities session) capabilities)
    (define/public (get-render-info)
      (render-session-check! 'get-render-info session)
      (hasheq 'stage "0.61" 'selection selection 'capabilities capabilities
              'callback (render-session-info session) 'last_callback_size last-size
              'close_status close-status 'implementation (super get-skia-info)
              'physical_display_verified #f 'performance_measured #f))
    (define/override (get-dc)
      (cond [(not facade-ready?) (super get-dc)] ; native toolkit construction
            [else
             (live! 'get-dc)
             (or (render-session-current-dc session)
                 (and raster? toolkit-dc-permitted?
                      (begin (set! toolkit-dc-permitted? #f) (super get-dc)))
                 (error 'get-dc "DC is available only during the paint callback; use get-raster-dc for explicit persistent raster access"))]))
    (define/public (get-raster-dc)
      (live! 'get-raster-dc)
      (unless raster? (error 'get-raster-dc "persistent raster DC access is unavailable for a GPU canvas"))
      (super get-dc))
    (define/public (set-paint-callback callback)
      (idle! 'set-paint-callback)
      (render-session-set-callback! session callback))
    (define/override (refresh)
      (when facade-ready? (render-session-check! 'refresh session))
      ;; Preserve the native coalescing and the historical post-close no-op.
      (super refresh))
    (define/override (refresh-now [proc #f] #:flush? [flush? #t])
      (idle! 'refresh-now)
      (when proc (check-render-callback 'refresh-now proc 1))
      (unless (eq? flush? #t)
        (raise-argument-error 'refresh-now "#t for portable render-canvas presentation" flush?))
      (with-toolkit-access
       (lambda () (super refresh-now (and proc (lambda (dc) (deliver dc proc))) #:flush? #t))))
    (define/override (on-paint)
      (if (and raster? facade-ready?)
          (with-handlers ([(lambda (_) #t) error-proc]) (super on-paint))
          (super on-paint)))
    (define/override (present)
      (idle! 'present)
      (unless raster? (error 'present "cached pixel presentation is raster-only; request a GPU frame with refresh"))
      (with-toolkit-access (lambda () (super present))))
    (define/override (close-skia)
      (render-session-idle! 'close-skia session)
      ;; Do not skip a retry just because the underlying GPU widget has marked
      ;; itself closed. Retained resources can make its first close fail.
      (set! close-status 'closing)
      (with-handlers ([(lambda (_) #t)
                       (lambda (e) (set! close-status 'close-failed) (raise e))])
        (super close-skia)
        (set! close-status 'closed))
      (void))
    (define/override (close) (send this close-skia))
    (set! facade-ready? #t)))

(define raster-class
  (delay/sync (callback-canvas-class (dynamic-require raster-module 'skia-canvas%) #t)))
(define gpu-class
  (delay/sync
    (let ([gpu% (dynamic-require gpu-module 'skia-gpu-canvas%)])
      ;; Add the one query missing from the raw GPU class so the shared mixin
      ;; can use an actual superclass method in both modes.
      (callback-canvas-class
       (class gpu%
         (define/override (close-gpu)
           (when (hash-ref (hash-ref (send this get-render-info) 'callback) 'painting)
             (error 'close-gpu "cannot close a unified render canvas during a paint callback"))
           (super close-gpu))
         (define/public (closed?) (send this skia-closed?))
         (super-new))
       #f))))

(define (make-skia-render-canvas parent
          #:renderer [renderer 'auto] #:backend [backend 'auto]
          #:adapter [adapter #f] #:adapter-index [adapter-index #f] #:sync-interval [sync-interval #f]
          #:paint-callback [paint-callback void] #:on-error [on-error raise]
          #:background [background "white"] #:smoothing [smoothing 'smoothed]
          #:min-width [min-width 1] #:min-height [min-height 1])
  (handler! 'make-skia-render-canvas)
  ;; Validate selection before a child is added or an implementation loaded.
  (define policy (resolve-render-canvas-policy renderer backend adapter adapter-index sync-interval))
  (check-render-callback 'make-skia-render-canvas paint-callback 2)
  (check-render-callback 'make-skia-render-canvas on-error 1)
  (unless (memq smoothing '(unsmoothed smoothed aligned))
    (raise-argument-error 'make-skia-render-canvas "'unsmoothed, 'smoothed, or 'aligned" smoothing))
  (unless (exact-nonnegative-integer? min-width)
    (raise-argument-error 'make-skia-render-canvas "exact-nonnegative-integer? minimum width" min-width))
  (unless (exact-nonnegative-integer? min-height)
    (raise-argument-error 'make-skia-render-canvas "exact-nonnegative-integer? minimum height" min-height))
  (new (force (if (eq? (hash-ref policy 'renderer) 'raster) raster-class gpu-class))
       [parent parent] [policy policy] [paint-callback paint-callback] [on-error on-error]
       [background background] [smoothing smoothing] [min-width min-width] [min-height min-height]))

(define skia-render-window%
  (class gui:frame%
    (init [label "Skia render canvas"] [width 640] [height 480]
          [renderer 'auto] [backend 'auto]
          [adapter #f] [adapter-index #f] [sync-interval #f]
          [paint-callback void] [on-error raise] [background "white"] [smoothing 'smoothed])
    (handler! 'skia-render-window%)
    ;; Reject invalid choices even before creating the frame itself.
    (resolve-render-canvas-policy renderer backend adapter adapter-index sync-interval)
    (check-render-callback 'skia-render-window% paint-callback 2)
    (check-render-callback 'skia-render-window% on-error 1)
    (super-new [label label] [width width] [height height])
    (define canvas
      (make-skia-render-canvas this #:renderer renderer #:backend backend
        #:adapter adapter #:adapter-index adapter-index #:sync-interval sync-interval
        #:paint-callback paint-callback #:on-error on-error
        #:background background #:smoothing smoothing))
    (define/public (get-render-canvas) canvas)
    (define/public (close-render)
      ;; A rejected close (e.g. from its paint callback) must not hide the frame.
      (send canvas close-skia) (send this show #f))
    (define/augment (on-close) (send this close-render))))
