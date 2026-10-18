#lang racket

;;;
;;; Bezier Editor
;;;

;; Connects pointer events to a draggable cubic-curve editor with explicit renderer choice.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require racket/class
         racket/cmdline
         (only-in racket/gui/base
                  canvas% frame% vertical-panel% horizontal-panel%
                  button% queue-callback)
         (except-in skia draw-points)
         skia/bitmap
         skia/gpu
         skia/gpu-gui
         "scene.rkt")

(provide open-bezier-editor)

;;;
;;; Backend Selection and Editor Window
;;;

; preferred-gpu-backend : -> symbol?
;   Chooses the platform's preferred explicitly requested GPU backend.
(define (preferred-gpu-backend)
  (case (system-type 'os)
    [(macosx) 'metal]
    [(windows)
     (and (eq? (system-type 'arch) 'x86_64) 'direct3d)]
    [(unix) 'opengl]
    [else #f]))

; clamp : real? real? real? -> real?
;   Restricts a real value to the closed interval between the two bounds.
(define (clamp value low high)
  (max low (min high value)))

; open-bezier-editor : symbol? -> #f
;   Opens the draggable control-point editor with the selected rendering backend.
(define (open-bezier-editor renderer)
  (unless (memq renderer '(raster gpu))
    (raise-argument-error 'open-bezier-editor "'raster or 'gpu" renderer))
  (define gpu-backend
    (and (eq? renderer 'gpu) (preferred-gpu-backend)))
  (when (and (eq? renderer 'gpu) (not gpu-backend))
    (error 'open-bezier-editor "no supported GPU backend; use --renderer raster"))

  ;;;
  ;;; Control-Point State and Pointer Input
  ;;;

  (define points initial-control-points)
  (define selected-index #f)
  (define window #f)
  (define view #f)
  (define closed? #f)

  (define (request-frame)
    (when (and view (not closed?))
      (if (eq? renderer 'gpu)
          (send view request-gpu-render)
          (send view refresh))))

  (define (move-selected! widget x y)
    (when selected-index
      (let-values ([(width height) (send widget get-client-size)])
        (set! points
              (move-control-point
               points selected-index
               (clamp x 16 (- width 16))
               (clamp y 16 (- height 16))))
        (request-frame))))

  (define (handle-pointer-event widget event)
    (define x (send event get-x))
    (define y (send event get-y))
    (unless closed?
      (cond
        [(send event button-down? 'left)
         (set! selected-index (hit-control-point points x y))
         (request-frame)]
        [(send event button-up? 'left)
         (move-selected! widget x y)
         (set! selected-index #f)
         (request-frame)]
        [(and selected-index (send event dragging?))
         (move-selected! widget x y)])))

  ;; Both GUI classes extend canvas%, so one override handles mouse events.
  (define (with-mouse-events base%)
    (class base%
      (define/override (on-event event)
        (handle-pointer-event this event))
      (super-new)))

  ;;;
  ;;; Raster and GPU Drawing
  ;;;

  (define (paint-cpu-frame widget dc)
    (define-values (width height) (send widget get-client-size))
    (when (and (positive? width) (positive? height))
      (with-skia ([surface (make-surface width height)])
        (draw-editor (surface-canvas surface)
                     points width height selected-index)
        ;; The Racket GUI DC only presents the bitmap, not the curve geometry.
        (send dc draw-bitmap (surface->bitmap surface) 0 0))))

  (define (paint-gpu-frame frame)
    (define canvas (gpu-frame-canvas frame))
    ;; Mouse positions are logical; GPU targets are physical pixels.
    (with-canvas-state canvas
      (canvas-scale! canvas
                     (gpu-frame-scale-x frame)
                     (gpu-frame-scale-y frame))
      (draw-editor canvas points
                   (gpu-frame-logical-width frame)
                   (gpu-frame-logical-height frame)
                   selected-index)))

  ;;;
  ;;; Window Controls and Cleanup
  ;;;

  (define (close-editor)
    (unless closed?
      (when (and view (eq? renderer 'gpu))
        (send view close-gpu))
      (set! closed? #t)
      (send window show #f)))

  (define window%
    (class frame%
      (define/augment (on-close)
        (close-editor))
      (super-new)))

  (set! window
        (new window% [label (format "Bézier Workshop / ~a" renderer)]
             [width 800] [height 590]))
  (define panel (new vertical-panel% [parent window]))
  (define controls
    (new horizontal-panel% [parent panel] [stretchable-height #f]))

  (set! view
        (if (eq? renderer 'gpu)
            (new (with-mouse-events gpu-canvas%)
                 [parent panel]
                 [backend gpu-backend]
                 [min-width 740] [min-height 430]
                 [render paint-gpu-frame])
            (new (with-mouse-events canvas%)
                 [parent panel]
                 [style '(no-autoclear)]
                 [min-width 740] [min-height 430]
                 [paint-callback paint-cpu-frame])))

  (new button%
       [parent controls] [label "Reset"]
       [callback
        (lambda (_button _event)
          (set! points initial-control-points)
          (set! selected-index #f)
          (request-frame))])
  (new button%
       [parent controls] [label "Close"]
       [callback (lambda (_button _event) (close-editor))])

  (send window show #t)
  (send view focus)
  window)

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; renderer : symbol?
  ;   Selects renderer for the example.
  (define renderer 'raster)
  (command-line
   #:program "bezier-editor.rkt"
   #:once-each
   [("--renderer") name "raster or gpu"
    (set! renderer (string->symbol name))]
   #:args () (void))
  (unless (memq renderer '(raster gpu))
    (raise-argument-error 'bezier-editor "'raster or 'gpu" renderer))
  ;; GUI creation, mouse events, and GPU presentation use the handler thread.
  (queue-callback (lambda () (open-bezier-editor renderer))))
