#lang racket/base
(require racket/cmdline "../main.rkt" "../tests/codec-fixtures.rkt")

;; A deterministic contact sheet: animation disposal/blending above, all eight
;; normalized EXIF orientations below. All input images are local/in-memory.
(define (render-advanced-codecs filename)
  (with-skia ([out (make-surface 1120 740 #:background "#F0F2F5")]
              [ink (make-paint #:color "#182330")]
              [card (make-paint #:color 'white)]
              [checker (make-paint #:color "#D5D9DE")]
              [font (make-font #:size 18)]
              [title (make-font #:size 25)])
    (define canvas (surface-canvas out))
    (define (label text x y) (draw-simple-text canvas text x y font ink))
    (define (panel im x y w h)
      (draw-rect canvas x y w h card)
      (for* ([row (in-range 0 h 12)] [col (in-range 0 w 12)]
             #:when (even? (+ (quotient row 12) (quotient col 12))))
        (draw-rect canvas (+ x col) (+ y row) (min 12 (- w col)) (min 12 (- h row)) checker))
      (define scale (min (/ w (image-width im)) (/ h (image-height im))))
      (define iw (* scale (image-width im)))
      (define ih (* scale (image-height im)))
      (draw-image-rect canvas im (+ x (/ (- w iw) 2)) (+ y (/ (- h ih) 2)) iw ih
                       #:sampling 'nearest))
    (draw-simple-text canvas "Advanced codecs: animation and orientation" 25 35 title ink)
    (label "GIF: keep / restore previous / restore background / transparent blending" 25 67)
    (with-skia ([gif (codec-from-bytes animated-gif)])
      (for ([i (in-range (codec-frame-count gif))])
        (define x (+ 25 (* i 215)))
        (with-skia ([im (codec->image gif #:frame-index i)]) (panel im x 82 195 104))
        (label (format "Frame ~a  |  ~a ms" i (codec-frame-info-duration (codec-frame-info gif i))) x 210)))
    (label "Lossless animated WebP (decoded in reverse order)" 25 250)
    (with-skia ([webp (codec-from-bytes animated-webp)])
      (for ([i (in-range 2 -1 -1)])
        (define x (+ 25 (* i 215)))
        (with-skia ([im (codec->image webp #:frame-index i)]) (panel im x 267 195 104))
        (label (format "Frame ~a  |  ~a ms" i (codec-frame-info-duration (codec-frame-info webp i))) x 395)))
    (label "EXIF 1-8: normalized output (top row 1-4, bottom row 5-8)" 25 434)
    (with-skia ([source (make-surface 96 64)])
      (for ([color (in-list '("#FF0000" "#00FF00" "#0000FF" "#FFFF00" "#00FFFF" "#FF00FF"))] [i (in-naturals)])
        (with-skia ([p (make-paint #:color color)])
          (draw-rect (surface-canvas source) (* 32 (remainder i 3)) (* 32 (quotient i 3)) 32 32 p)))
      (with-skia ([snapshot (surface-snapshot source)])
        (define jpeg (image->jpeg-bytes snapshot #:quality 100 #:downsample 'yuv-444))
        (for ([origin (in-range 1 9)])
          (define x (+ 25 (* 270 (remainder (sub1 origin) 4))))
          (define y (+ 449 (* 139 (quotient (sub1 origin) 4))))
          (with-skia ([im (image-frame-from-bytes (jpeg-with-origin jpeg origin))])
            (panel im x y 235 99)
            (label (format "Origin ~a: ~a x ~a" origin (image-width im) (image-height im))
                   x (+ y 123))))))
    (save-png out filename)))

(module+ main
  (define filename
    (command-line #:program "advanced-codecs.rkt"
                  #:args ([output "advanced-codecs.png"]) output))
  (render-advanced-codecs filename)
  (printf "Wrote ~a\n" filename))
