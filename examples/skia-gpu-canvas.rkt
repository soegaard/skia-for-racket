#lang racket/base
;; Run on the desktop: auto selects Metal on macOS, OpenGL elsewhere.
;; This example never retains a frame DC and performs no CPU pixel readback.
(require racket/class racket/gui/base (prefix-in rd: racket/draw)
         "../gpu-canvas.rkt")
(define (make-window)
  (define canvas #f) (define frames 0)
  (define window%
    (class frame%
      (super-new)
      (define/augment (on-close)
        (when canvas (send canvas close-skia)) (send this show #f))))
  (define window (new window% [label "Skia GPU DC — frame scoped"] [width 660] [height 440]))
  (define panel (new vertical-panel% [parent window]))
  (define controls (new horizontal-panel% [parent panel] [stretchable-height #f]))
  (new button% [parent controls] [label "Refresh"]
       [callback (lambda (_b _e) (send canvas refresh))])
  (new button% [parent controls] [label "New window"]
       [callback (lambda (_b _e) (make-window))])
  (new button% [parent controls] [label "Close"]
       [callback (lambda (_b _e) (send canvas close-skia) (send window show #f))])
  (set! canvas
    (new skia-gpu-canvas% [parent panel] [min-width 360] [min-height 280]
         [paint-callback
          (lambda (c dc)
            (set! frames (add1 frames))
            (define-values (w h) (send dc get-size))
            (define-values (sx sy) (send dc get-device-scale))
            (send dc set-pen "black" 1 'transparent)
            (send dc set-brush "navy" 'solid)
            (send dc draw-rounded-rectangle 18 16 (- w 36) 94 12)
            (send dc set-font (rd:make-font #:size 23 #:family 'swiss #:weight 'bold))
            (send dc set-text-foreground "white")
            (send dc draw-text "Skia GPU drawing context" 32 30 #t)
            (send dc set-font (rd:make-font #:size 12 #:family 'swiss))
            (send dc draw-text
              (format "~a — frame ~a — device scales ~a × ~a"
                      (send c get-gpu-backend) frames sx sy) 32 76 #t)
            (send dc start-alpha 0.65)
            (send dc set-brush "firebrick" 'solid) (send dc draw-ellipse 38 140 130 110)
            (send dc set-brush "seagreen" 'solid) (send dc draw-ellipse 116 140 130 110)
            (send dc end-alpha)
            (send dc set-pen "navy" 2 'solid)
            (send dc set-brush "gold" 'solid)
            (send dc draw-rounded-rectangle 284 142 (max 40 (- w 322)) 106 16)
            (send dc set-text-foreground "navy")
            (send dc draw-text "Resize or move between displays; every frame gets a fresh DC." 24 (- h 38) #t)
            (send dc draw-text "Ordinary drawing and presentation stay on GPU surfaces." 24 (- h 20) #t))]))
  (send window show #t) (void))
(module+ main (queue-callback make-window))
