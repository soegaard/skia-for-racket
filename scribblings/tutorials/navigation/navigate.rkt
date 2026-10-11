#lang racket

(require racket/class racket/cmdline
         (only-in racket/gui/base canvas% frame% vertical-panel% horizontal-panel%
                  button% queue-callback)
         skia skia/bitmap skia/gpu skia/gpu-gui
         "model.rkt" "scene.rkt")

(provide open-navigation-window)

(define (preferred-gpu-backend)
  (case (system-type 'os)
    [(macosx) 'metal]
    [(windows) (and (eq? (system-type 'arch) 'x86_64) 'direct3d)]
    [(unix) 'opengl]
    [else #f]))

(define (open-navigation-window renderer)
  (unless (memq renderer '(raster gpu))
    (raise-argument-error 'open-navigation-window "'raster or 'gpu" renderer))
  (define backend (and (eq? renderer 'gpu) (preferred-gpu-backend)))
  (when (and (eq? renderer 'gpu) (not backend))
    (error 'open-navigation-window "no GPU backend for this platform; use --renderer raster"))
  (define points initial-points)
  (define view home-view)
  (define selected #f)
  (define drag-offset #f)
  (define pan-anchor #f)
  (define widget #f)
  (define window #f)
  (define closed? #f)

  (define (request-frame)
    (when (and widget (not closed?))
      (if (eq? renderer 'gpu)
          (send widget request-gpu-render)
          (send widget refresh))))

  (define (end-drag!)
    (set! selected #f)
    (set! drag-offset #f)
    (set! pan-anchor #f))

  (define (drag-to! x y)
    (cond
      [pan-anchor
       (set! view (pan-view view (- x (car pan-anchor)) (- y (cdr pan-anchor))))
       (set! pan-anchor (cons x y))]
      [selected
       (define-values (mx my) (screen->model view x y))
       (set! points
             (move-point points selected
                         (+ mx (car drag-offset)) (+ my (cdr drag-offset))))]))

  (define (handle-pointer-event target event)
    (define x (send event get-x))
    (define y (send event get-y))
    (define-values (width height) (send target get-client-size))
    (unless closed?
      (cond
        [(send event button-down? 'left)
         (end-drag!)
         (send target focus)
         (when (<= header-height y (- height footer-height))
           (cond
             [(send event get-shift-down) (set! pan-anchor (cons x y))]
             [else
              (set! selected (hit-point points view x y))
              (when selected
                (define point (list-ref points selected))
                (define-values (mx my) (screen->model view x y))
                ;; Preserve the grab offset instead of snapping to the pointer.
                (set! drag-offset (cons (- (control-point-x point) mx)
                                        (- (control-point-y point) my))))]))
         (request-frame)]
        [(send event button-up? 'left)
         (drag-to! x y)
         (end-drag!)
         (request-frame)]
        [(and (or selected pan-anchor) (send event get-left-down))
         (drag-to! x y)
         (request-frame)]
        [(or selected pan-anchor)
         ;; A button-up event can be lost; do not keep a stale drag alive.
         (end-drag!)
         (request-frame)])))

  (define (zoom! x y factor)
    (end-drag!)
    (set! view (zoom-at view x y factor))
    (request-frame))

  (define (handle-key-event target event)
    (define code (send event get-key-code))
    (unless closed?
      (case code
        [(wheel-up wheel-down)
         (define exponent (min 8 (max 0 (send event get-wheel-steps))))
         (define factor (expt 1.15 (if (eq? code 'wheel-up) exponent (- exponent))))
         (zoom! (send event get-x) (send event get-y) factor)]
        [(escape) (end-drag!) (request-frame)]
        [else (void)])))

  (define (interactive-class base%)
    (class base%
      (define/override (on-event event) (handle-pointer-event this event))
      (define/override (on-char event) (handle-key-event this event))
      (super-new)))

  (define (paint-cpu target dc)
    (define-values (width height) (send target get-client-size))
    (when (and (positive? width) (positive? height))
      (with-skia ([surface (make-surface width height)])
        (draw-editor (surface-canvas surface) points view width height selected)
        ;; The toolkit DC presents pixels only. All geometry is drawn by Skia.
        (send dc draw-bitmap (surface->bitmap surface) 0 0))))

  (define (paint-gpu frame)
    (define canvas (gpu-frame-canvas frame))
    (with-canvas-state canvas
      (canvas-scale! canvas (gpu-frame-scale-x frame) (gpu-frame-scale-y frame))
      (draw-editor canvas points view
                   (gpu-frame-logical-width frame) (gpu-frame-logical-height frame) selected)))

  (define (close-window)
    (unless closed?
      (end-drag!)
      (when (and widget (eq? renderer 'gpu)) (send widget close-gpu))
      (set! closed? #t)
      (send window show #f)))

  (define window%
    (class frame%
      (define/augment (on-close) (close-window))
      (super-new)))
  (set! window (new window% [label (format "Navigate the Curve / ~a" renderer)]
                     [width 820] [height 590]))
  (define panel (new vertical-panel% [parent window]))
  (define controls (new horizontal-panel% [parent panel] [stretchable-height #f]))
  (set! widget
        (if (eq? renderer 'gpu)
            (new (interactive-class gpu-canvas%) [parent panel] [backend backend]
                 [min-width 620] [min-height 400] [render paint-gpu])
            (new (interactive-class canvas%) [parent panel] [style '(no-autoclear)]
                 [min-width 620] [min-height 400] [paint-callback paint-cpu])))
  (define (zoom-center factor)
    (define-values (width height) (send widget get-client-size))
    (zoom! (/ width 2) (/ (+ header-height (- height footer-height)) 2) factor))
  (new button% [parent controls] [label "Zoom in"]
       [callback (lambda (_button _event) (zoom-center 1.25))])
  (new button% [parent controls] [label "Zoom out"]
       [callback (lambda (_button _event) (zoom-center 0.8))])
  (new button% [parent controls] [label "Reset view"]
       [callback (lambda (_button _event)
                   (end-drag!) (set! view home-view) (request-frame))])
  (new button% [parent controls] [label "Reset curve"]
       [callback (lambda (_button _event)
                   (end-drag!) (set! points initial-points) (request-frame))])
  (new button% [parent controls] [label "Close"]
       [callback (lambda (_button _event) (close-window))])
  (send window show #t)
  (send widget focus)
  window)

(module+ main
  (define renderer 'raster)
  (command-line #:once-each
                [("--renderer") name "raster or gpu" (set! renderer (string->symbol name))]
                #:args () (void))
  (queue-callback (lambda () (open-navigation-window renderer))))
