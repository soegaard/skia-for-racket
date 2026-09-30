#lang racket/base
;; Import explicitly: this is the only public module that starts racket/gui.
(require racket/class racket/gui/base racket/runtime-path racket/future
         (only-in racket/draw gl-config%)
         "gpu.rkt" "private/gpu-provider.rkt"
         "private/gpu-dxgi-util.rkt"
         (only-in "private/gpu-d3d12-util.rkt" d3d12-selection!)
         (submod "private/gpu-presenter.rkt" adapter-internals))
(provide gpu-canvas% gpu-window%)
(define-runtime-path gl-adapter "private/gpu-presenter-gl.rkt")
(define-runtime-path metal-adapter "private/gpu-presenter-metal.rkt")
(define-runtime-path d3d12-adapter "private/gpu-presenter-d3d12.rkt")
(define (backend-choice requested)
  (case requested
    [(auto) (if (eq? (system-type 'os) 'macosx) 'metal 'opengl)]
    [(opengl metal direct3d) requested]
    [else (raise-argument-error 'gpu-canvas% "'auto, 'opengl, 'metal, or 'direct3d" requested)]))
(define (handler! who space)
  (unless (and (eq? (current-thread) (eventspace-handler-thread space)) (not (current-future)))
    (error who "create/use GPU widgets on their eventspace handler thread (queue-callback)")))
(define (visible-to-root? window)
  (and (or (not (is-a? window window<%>)) (send window is-shown?))
       (or (not (is-a? window subarea<%>))
           (visible-to-root? (send window get-parent)))))
;; Poll only geometry/visibility. A weak reference prevents this timer from
;; retaining a discarded canvas indefinitely. No draw/readback is done here.
(define (make-geometry-monitor weak-canvas)
  (define timer #f)
  (set! timer
    (new timer% [interval 150]
         [notify-callback
          (lambda ()
            (define canvas (weak-box-value weak-canvas))
            (if canvas (send canvas check-gpu-geometry) (send timer stop)))]))
  timer)
(define gpu-canvas%
  (class canvas%
    (init parent [backend 'auto] [adapter #f] [adapter-index #f] [sync-interval #f] [render void] [on-error raise] [background 'white] [automatic? #t]
          [min-width 1] [min-height 1])
    (define space (current-eventspace))
    (handler! 'gpu-canvas% space)
    (define chosen (backend-choice backend))
    (when (and (eq? chosen 'direct3d) (not (and (eq? (system-type 'os) 'windows)
                                                          (eq? (system-type 'arch) 'x86_64))))
      (gpu-unavailable 'd3d12-presentation-platform "DXGI GPU windows require Windows x64"))
    (when (and (or adapter adapter-index sync-interval) (not (eq? chosen 'direct3d)))
      (raise-arguments-error 'gpu-canvas% "adapter/index/sync-interval options require explicit 'direct3d"))
    (define adapter-value (or adapter 'hardware))
    (define adapter-index-value (or adapter-index 0))
    (define sync-value (or sync-interval 1))
    (when (eq? chosen 'direct3d)
      (d3d12-selection! adapter-value adapter-index-value)
      (dxgi-sync-interval! sync-value))
    (when (and (eq? chosen 'metal) (not (eq? (system-type 'os) 'macosx)))
      (gpu-unavailable 'metal-presentation-platform "Metal GPU windows require macOS"))
    (unless (and (procedure? render) (procedure-arity-includes? render 1))
      (raise-argument-error 'gpu-canvas% "one-argument render callback" render))
    (unless (and (procedure? on-error) (procedure-arity-includes? on-error 1))
      (raise-argument-error 'gpu-canvas% "one-argument error callback" on-error))
    (unless (boolean? automatic?) (raise-argument-error 'gpu-canvas% "boolean?" automatic?))
    (define automatic-value automatic?)
    (define render-value render)
    (define error-value on-error)
    (define background-value background)
    (define presenter #f)
    (define initialized? #f)
    (define closed? #f)
    (define start-queued? #f)
    (define initialization-failed? #f)
    (define geometry #f)
    (define monitor #f)
    (define config
      (and (eq? chosen 'opengl)
           (let ([c (new gl-config%)])
             (send c set-legacy? (eq? (system-type 'os) 'windows))
             (send c set-double-buffered #t) (send c set-stencil-size 8)
             (send c set-hires-mode #t) c)))
    (super-new [parent parent] [style (if config '(gl no-autoclear) '(no-autoclear))]
               [gl-config config] [min-width min-width] [min-height min-height])
    (define weak-self (make-weak-box this))
    (define (post thunk)
      (when (eventspace-shutdown? space) (error 'gpu-presenter "eventspace has shut down"))
      (parameterize ([current-eventspace space]) (queue-callback thunk #f)))
    (define (live-canvas)
      (or (weak-box-value weak-self) (error 'gpu-presenter "GUI canvas is no longer reachable")))
    (define (measure-gl)
      (define canvas (live-canvas))
      (define-values (pw ph) (send canvas get-gl-client-size))
      (define-values (lw lh) (send canvas get-client-size))
      (define top (send canvas get-top-level-window))
      (presentation-metrics pw ph lw lh
        #:visible? (and (visible-to-root? canvas)
                        (or (not (is-a? top frame%)) (not (send top is-iconized?))))))
    (define (measure-client)
      (define canvas (live-canvas))
      (define-values (pw ph) (send canvas get-scaled-client-size))
      (define-values (lw lh) (send canvas get-client-size))
      (define top (send canvas get-top-level-window))
      (presentation-metrics pw ph lw lh
        #:visible? (and (visible-to-root? canvas)
                        (or (not (is-a? top frame%)) (not (send top is-iconized?))))))
    (define/public (get-gpu-presenter)
      (handler! 'get-gpu-presenter space)
      (when closed? (error 'get-gpu-presenter "GPU canvas is closed"))
      (unless presenter
        (when (presentation-active?)
          (error 'get-gpu-presenter "do not initialize widgets inside another GPU/presentation callback"))
        (set! initialization-failed? #f)
        (define adapter
          (with-handlers ([(lambda (_) #t)
                           (lambda (e) (set! initialization-failed? #t) (raise e))])
          (case chosen
            [(opengl)
             ((dynamic-require gl-adapter 'make-gl-presentation-adapter)
              (send (send this get-dc) get-gl-context) measure-gl post background-value)]
            [(direct3d)
             ((dynamic-require d3d12-adapter 'make-d3d12-presentation-adapter)
              (send this get-client-handle) measure-client post background-value
              adapter-value adapter-index-value sync-value)]
            [(metal)
             ((dynamic-require metal-adapter 'make-metal-presentation-adapter)
              (send this get-client-handle) post background-value)])))
        (with-handlers ([(lambda (_) #t)
                         (lambda (e) ((presentation-adapter-close adapter)) (raise e))])
          (set! presenter (make-presenter adapter render-value error-value))))
      presenter)
    (define/public (get-gpu-backend) chosen)
    (define/public (request-gpu-render)
      (handler! 'request-gpu-render space)
      (unless closed?
        (cond
          [presenter
           (when (memq (gpu-presenter-state presenter) '(ready rendering))
             (gpu-presenter-request-render! presenter))]
          [(and (not start-queued?) (not initialization-failed?))
           (set! start-queued? #t)
           (post
            (lambda ()
              (set! start-queued? #f)
              (unless (or closed? (presentation-active?) (not (visible-to-root? this)))
                (with-handlers ([(lambda (_) #t) error-value])
                  (gpu-presenter-request-render! (send this get-gpu-presenter))))))]))
      (void))
    (define/public (render-gpu-now)
      (handler! 'render-gpu-now space)
      (gpu-presenter-render! (send this get-gpu-presenter)))
    (define/public (close-gpu)
      (handler! 'close-gpu space)
      ;; This method is retryable when application GPU resources still prevent
      ;; context closure. Do not clear presenter on an unsuccessful close.
      (set! closed? #t)
      (when monitor (send monitor stop))
      (when presenter (gpu-presenter-close! presenter))
      (void))
    (define/public (check-gpu-geometry)
      (handler! 'check-gpu-geometry space)
      (unless closed?
        (define-values (lw lh) (send this get-client-size))
        (define-values (pw ph) (send this get-scaled-client-size))
        (define top (send this get-top-level-window))
        (define current (list lw lh pw ph (visible-to-root? this)
                              (and (is-a? top frame%) (send top is-iconized?))))
        (when (or (not (equal? current geometry))
                  ;; A deferred first initialization during a user yield gets
                  ;; another chance without an immediate requeue/spin loop.
                  (and (not presenter) (not start-queued?) (not initialization-failed?)
                       (visible-to-root? this))
                  ;; A nil nextDrawable is transient. Retry at this bounded
                  ;; geometry-poll rate, not an immediate event-queue loop.
                  (and presenter (eq? (gpu-presenter-state presenter) 'ready)
                       (visible-to-root? this)
                       (let ([last (hash-ref (gpu-presenter-info presenter) 'last_frame)])
                         (and (hash? last) (hash-ref last 'drawable #f)
                              (equal? (hash-ref last 'result #f) "skipped")))))
          (set! geometry current)
          (send this request-gpu-render))))
    (define/override (on-paint)
      (when (and initialized? automatic-value) (send this request-gpu-render)))
    (define/override (on-size w h)
      (when (and initialized? automatic-value) (send this request-gpu-render)))
    (define/override (on-superwindow-show shown?)
      (when (and initialized? automatic-value) (send this request-gpu-render)))
    (define/override (on-superwindow-activate active?)
      (when (and initialized? automatic-value) (send this request-gpu-render)))
    (set! initialized? #t)
    (when automatic-value (set! monitor (make-geometry-monitor weak-self)))))
(define gpu-window%
  (class frame%
    (init [label "Skia GPU"] [width 640] [height 480]
          [backend 'auto] [adapter #f] [adapter-index #f] [sync-interval #f]
          [render void] [on-error raise] [background 'white] [automatic? #t])
    (super-new [label label] [width width] [height height])
    (define canvas
      (new gpu-canvas% [parent this] [backend backend] [adapter adapter]
           [adapter-index adapter-index] [sync-interval sync-interval] [render render]
           [on-error on-error] [background background] [automatic? automatic?]))
    (define/public (get-gpu-canvas) canvas)
    (define/public (get-gpu-presenter) (send canvas get-gpu-presenter))
    (define/public (request-gpu-render) (send canvas request-gpu-render))
    (define/public (close-gpu)
      (dynamic-wind void (lambda () (send canvas close-gpu))
        (lambda () (send this show #f))))
    (define/augment (on-close) (send this close-gpu))))
