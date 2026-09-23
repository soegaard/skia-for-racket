#lang racket/base
(require racket/cmdline racket/math "../main.rkt")

;; A visual smoke test: curves, compositing, fills, clipping, transforms,
;; and image snapshots. No fonts, external images, or text renderer needed.
(define (render-gallery filename)
  (with-skia ([s (make-surface 1000 720 #:background "#F3F5F9")]
              [card (make-paint #:color 'white)]
              [ink (make-paint #:color "#223149" #:style 'stroke
                               #:stroke-width 3 #:cap 'round #:join 'round)]
              [blue (make-paint #:color "#326DE6")]
              [teal (make-paint #:color "#16A598")]
              [orange (make-paint #:color "#F38C42")]
              [faint (make-paint #:color "#E0E6F0" #:style 'stroke #:stroke-width 1)])
    (define c (surface-canvas s))
    (for* ([x '(30 355 680)] [y '(30 375)])
      (draw-rounded-rect c x y 290 315 18 18 card))

    ;; 1: A cubic curve, its control polygon, and a quadratic arch.
    (with-canvas-state c
      (canvas-translate! c 50 75)
      (draw-polygon c '((10 180) (45 0) (185 270) (245 55)) faint #:closed? #f)
      (with-skia ([curve (make-path '((move 10 180) (cubic 45 0 185 270 245 55)))])
        (draw-path c curve ink))
      (for ([p '((10 180) (45 0) (185 270) (245 55))])
        (draw-circle c (car p) (cadr p) 5 blue))
      (with-skia ([arch (make-path '((move 20 235) (quad 125 155 235 235)))])
        (draw-path c arch ink)))

    ;; 2: Straight-alpha color input composed over white.
    (with-skia ([r (make-paint #:color (rgba 241 70 90 150))]
                [g (make-paint #:color (rgba 30 170 120 150))]
                [b (make-paint #:color (rgba 45 105 225 150))])
      (draw-circle c 465 163 76 r)
      (draw-circle c 535 163 76 g)
      (draw-circle c 500 220 76 b))

    ;; 3: A clipped lattice. The border is drawn after restoring the clip.
    (with-skia ([clip (make-path)])
      (path-add-circle! clip 825 187 107)
      (with-canvas-state c
        (canvas-clip-path! c clip #:antialias? #t)
        (draw-rect c 700 55 250 265 teal)
        (for ([x (in-range 630 1000 20)])
          (draw-line c x 45 (+ x 160) 340 ink)))
      (draw-path c clip ink))

    ;; 4: An even-odd ring and a triangle.
    (with-skia ([ring (make-path #:fill-rule 'even-odd)])
      (path-add-circle! ring 175 530 92)
      (path-add-circle! ring 175 530 52)
      (draw-path c ring blue))
    (draw-polygon c '((175 490) (211 552) (139 552)) orange)

    ;; 5: Scoped transformations around a common center.
    (for ([angle (in-range 0 360 30)])
      (with-canvas-state c
        (canvas-translate! c 500 530)
        (canvas-rotate! c angle)
        (draw-rounded-rect c 42 -10 62 20 10 10 teal)))
    (draw-circle c 500 530 26 orange)

    ;; 6: An immutable snapshot, scaled using nearest and linear sampling.
    (with-skia ([tile (make-surface 8 8 #:background "#DEE7F9")])
      (define tc (surface-canvas tile))
      (draw-rect tc 0 0 4 4 blue)
      (draw-rect tc 4 4 4 4 blue)
      (with-skia ([im (surface-snapshot tile)])
        (draw-image-rect c im 711 422 98 98 #:sampling 'nearest)
        (draw-image-rect c im 841 422 98 98 #:sampling 'linear)
        (with-canvas-state c
          (canvas-translate! c 825 607)
          (canvas-rotate! c -15)
          (draw-image-rect c im -55 -55 110 110 #:sampling 'linear))))
    (save-png s filename)))

(module+ main
  (define filename
    (command-line #:program "gallery.rkt" #:args ([output "gallery.png"]) output))
  (render-gallery filename)
  (printf "Wrote ~a\n" filename))
