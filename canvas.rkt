#lang racket/base
;; Explicit GUI entry point. The drawing context and its CPU Skia surface
;; belong to the widget; racket/gui only presents the completed bitmap.
(require racket/class racket/future racket/list
         (prefix-in gui: racket/gui/base)
         (prefix-in rd: racket/draw)
         "dc.rkt" "private/canvas-backing.rkt")
(provide skia-canvas% skia-canvas?)

(define (handler! who space)
  (unless (and (eq? (current-thread) (gui:eventspace-handler-thread space))
               (not (current-future)))
    (error who "use skia-canvas% on its eventspace handler thread (queue-callback)")))

(define (callback! who proc arity)
  (unless (and (procedure? proc) (procedure-arity-includes? proc arity))
    (raise-argument-error who (format "procedure accepting ~a arguments" arity) proc)))

(define (canvas-color value)
  (cond [(is-a? value rd:color%)
         (make-object rd:color% (send value red) (send value green)
                      (send value blue) (send value alpha))]
        [(string? value)
         (or (send rd:the-color-database find-color value)
             (raise-argument-error 'skia-canvas% "known color name" value))]
        [else (raise-argument-error 'skia-canvas% "color% object or color name" value)]))

(define (opaque-window-color color)
  (make-object rd:color% (send color red) (send color green) (send color blue)))

;; A monitor is necessary for a backing-scale change that does not also
;; deliver on-size. It never retains an otherwise discarded canvas.
(define (make-geometry-monitor weak-canvas)
  (define monitor #f)
  (set! monitor
    (new gui:timer% [interval 150]
         [notify-callback
          (lambda ()
            (define canvas (weak-box-value weak-canvas))
            (if canvas
                (send canvas check-skia-geometry)
                (send monitor stop)))]))
  monitor)

(define skia-canvas%
  (class gui:canvas%
    (inherit/super make-bitmap)
    (init parent [style '()] [paint-callback void]
          [background "white"] [smoothing 'unsmoothed]
          [label #f] [enabled #t] [vert-margin 0] [horiz-margin 0]
          [min-width 1] [min-height 1]
          [stretchable-width #t] [stretchable-height #t])
    (define space (gui:current-eventspace))
    (handler! 'skia-canvas% space)
    (callback! 'skia-canvas% paint-callback 2)
    (unless (and (list? style)
                 (andmap (lambda (v) (memq v '(border control-border no-focus deleted no-autoclear)))
                         style))
      (raise-argument-error 'skia-canvas%
        "list of 'border, 'control-border, 'no-focus, 'deleted, or 'no-autoclear styles" style))
    (unless (memq smoothing '(unsmoothed smoothed aligned))
      (raise-argument-error 'skia-canvas% "'unsmoothed, 'smoothed, or 'aligned" smoothing))
    (define background-value (canvas-color background))
    (define window-background (opaque-window-color background-value))
    (define smoothing-value smoothing)
    (define paint-proc paint-callback)
    (define clear? (not (memq 'no-autoclear style)))
    (define backing #f)
    (define geometry #f)
    (define observed-geometry #f)
    (define ready? #f)
    (define closed-value? #f)
    (define painting? #f)
    (define deferred-refresh? #f)
    (define monitor #f)
    (define paint-count 0)
    (define presentation-count 0)

    ;; Native automatic clearing must not operate on the overridden get-dc.
    ;; Root clearing and alpha cleanup are performed by the backing manager.
    (super-new [parent parent]
               [style (cons 'no-autoclear (remq 'no-autoclear style))]
               [paint-callback void] [label label] [enabled enabled]
               [vert-margin vert-margin] [horiz-margin horiz-margin]
               [min-width min-width] [min-height min-height]
               [stretchable-width stretchable-width]
               [stretchable-height stretchable-height])

    (define/private (live! who)
      (handler! who space)
      (when closed-value? (error who "Skia canvas is closed")))
    (define/private (idle! who)
      (live! who)
      (when painting? (error who "a Skia canvas paint/presentation is already active")))
    (define/private (measure)
      (define-values (w h) (send this get-client-size))
      ;; Canvas DCs can report 1.0 before their native backing is acquired.
      ;; A public compatible bitmap reports the actual monitor/text scale,
      ;; without estimating a ratio from rounded client dimensions.
      (define probe (super make-bitmap 1 1))
      (define scale (send probe get-backing-scale))
      (list w h scale))
    (define/private (sync-backing! [allow-minimal? #f])
      (define current (measure))
      (define w (car current))
      (define h (cadr current))
      (define scale (caddr current))
      (cond
        [(and (positive? w) (positive? h))
         (cond [backing (send backing resize! w h scale)]
               [else
                (set! backing
                  (new canvas-backing% [width w] [height h] [backing-scale scale]
                       [background background-value] [smoothing smoothing-value]))])
         (set! geometry current)
         (set! observed-geometry current)
         #t]
        [else
         ;; Keep the most recent backing while the client is zero-sized.
         ;; Only get-dc before a first usable size needs a minimal surface.
         (when (and allow-minimal? (not backing))
           (set! backing
             (new canvas-backing% [width 1] [height 1] [backing-scale scale]
                  [background background-value] [smoothing smoothing-value])))
         (set! geometry current)
         (set! observed-geometry current)
         #f]))
    (define/private (present-backing!)
      (define bitmap (send backing get-bitmap))
      (define native (super get-dc))
      ;; This DC never escapes. The toolkit performs only the final bitmap
      ;; copy. Clear its destination each time so partial alpha cannot build
      ;; up across repeated exposures/presentations.
      (send native set-transformation '#(#(1.0 0.0 0.0 1.0 0.0 0.0) 0.0 0.0 1.0 1.0 0.0))
      (send native set-clipping-region #f)
      (send native set-alpha 1.0)
      ;; The widget is an opaque window. Its underlay uses the configured
      ;; background's RGB; intrinsic alpha belongs only to the Skia root and
      ;; remains available in readbacks/snapshots.
      (send native set-background window-background)
      (send native erase)
      (send native clear)
      (send native set-smoothing 'unsmoothed)
      (unless (send native draw-bitmap bitmap 0 0)
        (error 'skia-canvas% "could not present the raster backing"))
      (set! presentation-count (add1 presentation-count))
      (void))
    (define/private (with-presentation thunk)
      (idle! 'skia-canvas%)
      (call-with-continuation-barrier
       (lambda ()
         (dynamic-wind
          (lambda ()
            (idle! 'skia-canvas%)
            (set! painting? #t))
          thunk
          (lambda ()
            (set! painting? #f)
            (when (and deferred-refresh? (not closed-value?))
              (set! deferred-refresh? #f)
              (super refresh)))))))
    (define/private (render-and-present! proc)
      ;; Resize before entering the callback: user-held DC references keep
      ;; their identity while their logical/physical geometry becomes current.
      (idle! 'refresh-now)
      (when (sync-backing!)
        (with-presentation
         (lambda ()
           (send backing paint! (lambda () (proc (send backing get-dc))) clear?)
           (set! paint-count (add1 paint-count))
           (present-backing!))))
      (void))

    (define/override (get-dc)
      (live! 'get-dc)
      (cond
        [ready?
         (unless painting? (sync-backing! #t))
         (send backing get-dc)]
        [else (super get-dc)]))

    (define/override (refresh)
      (handler! 'refresh space)
      (unless closed-value?
        (if painting? (set! deferred-refresh? #t) (super refresh)))
      (void))
    (define/override (refresh-now [proc #f] #:flush? [flush? #t])
      (idle! 'refresh-now)
      (when proc (callback! 'refresh-now proc 1))
      (super refresh-now
        (lambda (_dc)
          (render-and-present! (or proc (lambda (dc) (paint-proc this dc)))))
        #:flush? flush?))
    (define/override (on-paint)
      (when (and ready? (not closed-value?))
        (handler! 'on-paint space)
        (if painting?
            (set! deferred-refresh? #t)
            (render-and-present! (lambda (dc) (paint-proc this dc)))))
      (void))
    (define/override (on-size w h)
      (when (and ready? (not closed-value?))
        (handler! 'on-size space)
        (if painting?
            (set! deferred-refresh? #t)
            (begin (sync-backing!) (super refresh))))
      (void))
    (define/override (on-superwindow-show shown?)
      (when (and ready? shown? (not closed-value?)) (send this refresh)))
    (define/override (on-superwindow-activate active?)
      (when (and ready? active? (not closed-value?)) (send this check-skia-geometry)))
    (define/override (set-canvas-background value)
      (live! 'set-canvas-background)
      (unless (is-a? value rd:color%)
        (raise-argument-error 'set-canvas-background "color% object" value))
      (define next (canvas-color value))
      (define underlay (opaque-window-color next))
      (super set-canvas-background underlay)
      (set! background-value next)
      (set! window-background underlay)
      (when backing (send (send backing get-dc) set-background next))
      (when ready? (send this refresh))
      (void))
    (define/override (get-canvas-background)
      (live! 'get-canvas-background)
      (canvas-color background-value))

    (define/public (present)
      (idle! 'present)
      (when (sync-backing!)
        (super refresh-now
          (lambda (_dc) (with-presentation (lambda () (present-backing!))))))
      (void))
    (define/public (check-skia-geometry)
      (handler! 'check-skia-geometry space)
      (when (and ready? (not closed-value?) (send this is-shown?))
        (define next (measure))
        (unless (equal? next observed-geometry)
          ;; Schedule only; allocation and drawing belong to the paint event.
          ;; Record the observation before scheduling so a failed allocation
          ;; does not turn into a 150 ms retry/error loop.
          (set! observed-geometry next)
          (if painting?
              (set! deferred-refresh? #t)
              (super refresh))))
      (void))
    (define/public (get-skia-info)
      (handler! 'get-skia-info space)
      (hasheq 'stage "0.58" 'storage 'raster 'backend 'cpu
              'closed closed-value? 'painting painting?
              'geometry geometry 'dc_created (and backing #t)
              'pixel_size (and backing (not closed-value?)
                               (call-with-values
                                (lambda () (send (send backing get-dc) get-pixel-size)) list))
              'paint_count paint-count 'presentation_count presentation-count
              'gpu_execution #f))
    (define/public (closed?)
      (handler! 'closed? space)
      closed-value?)
    (define/public (close-skia)
      (handler! 'close-skia space)
      (when painting? (error 'close-skia "cannot close a canvas during painting/presentation"))
      (unless closed-value?
        (set! closed-value? #t)
        (set! deferred-refresh? #f)
        (when monitor (send monitor stop))
        (when backing (send backing close)))
      (void))
    (define/public (close) (send this close-skia))

    (super set-canvas-background window-background)
    (set! ready? #t)
    (set! monitor (make-geometry-monitor (make-weak-box this)))))

(define (skia-canvas? value) (is-a? value skia-canvas%))
