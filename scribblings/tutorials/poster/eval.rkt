#lang racket/base

(require scribble/eval)

(provide poster-interaction
         poster-interaction-eval
         poster-racketmod+eval
         poster-racketblock+eval
         poster-def+int
         poster-image)

(define poster-eval (make-base-eval))

(void
 (interaction-eval
  #:eval poster-eval
  (require racket
           skia
           (prefix-in draw: racket/draw)
           (prefix-in pict: pict))))

(void
 (interaction-eval
  #:eval poster-eval
  (define (poster-render-pict draw)
    (define width 720)
    (define height 900)
    (with-skia ([surface (make-surface width height
                                      #:background "#F4F1EA")])
      (draw (surface-canvas surface))
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.55)))))

(void
 (interaction-eval
  #:eval poster-eval
  (define (poster-gradient-domain-pict)
    (define width 760)
    (define height 210)
    (with-skia ([surface (make-surface width height
                                      #:background "#F4F1EA")]
                [shader
                 (make-linear-gradient-shader
                  120 0 640 0
                  '("#0B1026" "#45C2C7" "#F35B74")
                  #:positions '(0 3/5 1))]
                [paint (make-paint #:shader shader)]
                [guide (make-paint #:color "#8A94A3"
                                   #:style 'stroke
                                   #:stroke-width 2)]
                [marker (make-paint #:color "#26333D")]
                [font (make-font #:size 16)]
                [text (make-paint #:color "#26333D")])
      (define canvas (surface-canvas surface))
      (draw-rounded-rect canvas 40 48 680 88 12 12 paint)
      (for ([x '(120 432 640)]
            [label '("0" "3/5" "1")])
        (draw-line canvas x 35 x 150 guide)
        (draw-circle canvas x 154 4 marker)
        (draw-simple-text canvas label (- x 11) 184 font text))
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.72)))))

(void
 (interaction-eval
  #:eval poster-eval
  (define (poster-tile-modes-pict)
    (define width 760)
    (define height 230)
    (with-skia ([surface (make-surface width height
                                      #:background "#F4F1EA")]
                [font (make-font #:size 17)]
                [label-paint (make-paint #:color "#26333D")]
                [frame (make-paint #:color "#CBD0D4"
                                   #:style 'stroke
                                   #:stroke-width 2)]
                [guide (make-paint #:color "#8A94A3"
                                   #:style 'stroke
                                   #:stroke-width 1)])
      (define canvas (surface-canvas surface))
      (for ([x '(20 205 390 575)]
            [mode '(clamp repeat mirror decal)]
            [label '("'clamp" "'repeat" "'mirror" "'decal")])
        (draw-rounded-rect canvas x 42 165 112 12 12 frame)
        (with-skia ([shader
                     (make-linear-gradient-shader
                      (+ x 55) 0 (+ x 105) 0
                      '("#45C2C7" "#F35B74")
                      #:tile-mode mode)]
                    [paint (make-paint #:shader shader)])
          (draw-rounded-rect canvas
                             (+ x 10) 58
                             145 80
                             8 8
                             paint))
        (draw-line canvas (+ x 55) 50 (+ x 55) 146 guide)
        (draw-line canvas (+ x 105) 50 (+ x 105) 146 guide)
        (draw-simple-text canvas
                          label
                          (+ x 48) 190
                          font label-paint))
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.72)))))


(void
 (interaction-eval
  #:eval poster-eval
  (define (poster-checker-pict image)
    (with-skia ([surface (make-surface 128 128
                                      #:background 'transparent)])
      (draw-image-rect (surface-canvas surface)
                       image
                       0 0 128 128
                       #:sampling 'nearest)
      (pict:bitmap
       (draw:read-bitmap
        (open-input-bytes (surface->png-bytes surface))
        'png/alpha))))))

(define-syntax-rule (poster-interaction expression ...)
  (interaction #:eval poster-eval expression ...))

(define-syntax-rule (poster-interaction-eval expression ...)
  (interaction-eval #:eval poster-eval expression ...))

(define-syntax-rule (poster-racketmod+eval expression ...)
  (racketmod+eval #:eval poster-eval expression ...))

(define-syntax-rule (poster-racketblock+eval expression ...)
  (racketblock+eval #:eval poster-eval expression ...))

(define-syntax-rule (poster-def+int expression ...)
  (def+int #:eval poster-eval expression ...))

(define-syntax-rule (poster-image expression)
  (interaction-eval-show #:eval poster-eval expression))
