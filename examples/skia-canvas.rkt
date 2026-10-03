#lang racket/base
;; Explicit GUI example. Resize, cover/uncover, minimize/restore, and move the
;; window between monitors. Use New window to check independent lifetimes.
(require racket/class racket/gui/base
         (prefix-in rd: racket/draw)
         "../canvas.rkt")

(define next-window 0)

(define (make-window)
  (set! next-window (add1 next-window))
  (define index next-window)
  (define canvas #f)
  (define window%
    (class frame%
      (define/augment (on-close)
        (when canvas (send canvas close-skia))
        (send this show #f))
      (super-new)))
  (define window
    (new window% [label (format "Skia raster canvas ~a" index)]
         [width 640] [height 450]))
  (define panel (new vertical-panel% [parent window]))
  (define controls
    (new horizontal-panel% [parent panel] [stretchable-height #f]
         [horiz-margin 12] [vert-margin 8]))
  (new button% [parent controls] [label "Refresh"]
       [callback (lambda (_button _event)
                   ;; Several invalidations may become one paint callback.
                   (send canvas refresh)
                   (send canvas refresh)
                   (send canvas refresh))])
  (new button% [parent controls] [label "Present pixels"]
       [callback (lambda (_button _event) (send canvas present))])
  (new button% [parent controls] [label "New window"]
       [callback (lambda (_button _event) (make-window))])
  (new button% [parent controls] [label "Close"]
       [callback (lambda (_button _event)
                   (send canvas close-skia)
                   (send window show #f))])
  (set! canvas
    (new skia-canvas% [parent panel] [style '(border)]
         [min-width 360] [min-height 290] [smoothing 'smoothed]
         [paint-callback
          (lambda (_canvas dc)
            (define-values (width height) (send dc get-size))
            (send dc set-pen "black" 1 'transparent)
            (send dc set-brush "navy" 'solid)
            (send dc draw-rounded-rectangle 20 20 (- width 40) 88 12)
            (send dc set-font (rd:make-font #:family 'swiss #:size 22 #:weight 'bold))
            (send dc set-text-foreground "white")
            (send dc draw-text "Skia raster canvas" 36 34)
            (send dc set-font (rd:make-font #:family 'swiss #:size 12))
            (send dc draw-text
                  (format "~a x ~a logical pixels; backing scale ~a"
                          width height (send dc get-backing-scale))
                  36 73)

            (define left 30)
            (define top 134)
            (define box-width (max 100 (/ (- width 90) 2)))
            (send dc set-pen "navy" 2 'solid)
            (send dc set-brush "lightblue" 'solid)
            (send dc draw-rounded-rectangle left top box-width 86 14)
            (send dc set-brush "gold" 'solid)
            (send dc draw-ellipse (+ left box-width 30) top box-width 86)
            (send dc set-pen "black" 1 'transparent)
            (send dc start-alpha 0.6)
            (send dc set-brush "firebrick" 'solid)
            (send dc draw-ellipse 46 158 68 68)
            (send dc set-brush "seagreen" 'solid)
            (send dc draw-ellipse 88 158 68 68)
            (send dc end-alpha)
            (send dc set-text-foreground "navy")
            (send dc draw-text "Resize or move this window between displays." 30 (- height 43))
            (send dc draw-text "New window creates an independently owned canvas." 30 (- height 24)))]))
  ;; The handler keeps one DC identity even as resize replaces its storage.
  (define retained-dc (send canvas get-dc))
  (unless (eq? retained-dc (send canvas get-dc))
    (error 'skia-canvas-example "canvas did not preserve its DC identity"))
  (send window show #t)
  (void))

(module+ main
  (queue-callback make-window))
