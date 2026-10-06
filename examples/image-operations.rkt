#lang racket/base
(require "../main.rkt")
(module+ main
  ;; A returned backing image can contain pixels outside its valid subset.
  ;; Crop first, then place the cropped result at the geometric offset.
  (with-skia ([surface (make-surface 80 48 #:background 'transparent)]
              [ink (make-paint #:color (rgb 32 96 192))]
              [filter (make-drop-shadow-image-filter 6 4 2 2 (rgba 0 0 0 160))])
    (draw-rect (surface-canvas surface) 8 8 48 24 ink)
    (with-skia ([source (surface-snapshot surface)])
      (define-values (image subset offset)
        (image-apply-filter source filter #:clip '(-12 -12 112 80)))
      (with-skia ([filtered image] [visible (apply image-subset filtered (vector->list subset))])
        (printf "Backing: ~ax~a; valid subset ~a; placement ~a\n"
                (image-width filtered) (image-height filtered) subset offset)
        (define page
          (make-output-page 160 100
            (lambda (c)
              (draw-image c visible (+ 24 (vector-ref offset 0)) (+ 24 (vector-ref offset 1))))
            #:background 'white))
        ;; Existing pixel images are intentionally embedded, not mislabeled as
        ;; vector geometry. 'error rejects unexpected blocking fallbacks.
        (save-output/audit page "image-operations.pdf" 'pdf #:exists 'replace #:policy 'error)
        (save-output/audit page "image-operations.svg" 'svg #:exists 'replace #:policy 'error)))))
