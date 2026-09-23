#lang racket/base
(require racket/cmdline "../main.rkt")

;; Visual smoke test for the 0.4 encoded-image layer. Everything is generated
;; in memory: render -> encode PNG/JPEG/WebP -> decode -> crop/subset -> render.
(define (render-codec-gallery filename)
  (with-skia ([source (make-surface 240 180 #:background 'white)]
              [gradient (make-linear-gradient-shader
                         0 0 240 180
                         '("#326DE6" "#16A598" "#F38C42")
                         #:positions '(0 1/2 1))]
              [gradient-paint (make-paint #:shader gradient)]
              [white (make-paint #:color (rgba 255 255 255 205))]
              [navy (make-paint #:color "#20304A")])
    (define sc (surface-canvas source))
    (draw-rect sc 0 0 240 180 gradient-paint)
    (draw-circle sc 65 70 34 white)
    (draw-rounded-rect sc 115 42 88 58 14 14 navy)
    (draw-circle sc 174 132 25 white)

    (with-skia ([original (surface-snapshot source)])
      (define png (image->png-bytes original))
      (define jpeg (image->jpeg-bytes original #:quality 88 #:downsample 'yuv-444))
      (define webp (image->webp-bytes original #:quality 82))

      (with-skia ([png-image (image-from-bytes png)]
                  [jpeg-image (image-from-bytes jpeg)]
                  [webp-image (image-from-bytes webp)]
                  [subset (image-subset original 55 30 130 110)]
                  [out (make-surface 1040 650 #:background "#F3F5F9")]
                  [card (make-paint #:color 'white)]
                  [ink (make-paint #:color "#223149")]
                  [font (make-font #:size 22)])
        (define c (surface-canvas out))
        (define (card-image x label im)
          (draw-rounded-rect c x 30 230 245 18 18 card)
          (draw-image-rect c im (+ x 10) 40 210 158 #:sampling 'linear)
          (draw-simple-text c label (+ x 14) 238 font ink))

        (card-image 30  "Original" original)
        (card-image 285 "PNG decode" png-image)
        (card-image 540 "JPEG decode" jpeg-image)
        (card-image 795 "WebP decode" webp-image)

        ;; Exact raster subset from the original image.
        (draw-rounded-rect c 30 305 480 315 18 18 card)
        (draw-simple-text c "image-subset" 50 345 font ink)
        (draw-image-rect c subset 50 370 440 220 #:sampling 'linear)

        ;; Source-rectangle drawing without allocating a subset image.
        (draw-rounded-rect c 530 305 480 315 18 18 card)
        (draw-simple-text c "draw-image-subrect" 550 345 font ink)
        (draw-image-subrect c original 55 30 130 110
                            550 370 440 220 #:sampling 'linear)

        (save-png out filename)
        (printf "encoded sizes: PNG ~a bytes; JPEG ~a bytes; WebP ~a bytes\n"
                (bytes-length png) (bytes-length jpeg) (bytes-length webp))))))

(module+ main
  (define filename
    (command-line #:program "codecs.rkt" #:args ([output "codecs.png"]) output))
  (render-codec-gallery filename)
  (printf "Wrote ~a\n" filename))
