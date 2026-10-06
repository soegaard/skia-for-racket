#lang racket/base
(require racket/file "../main.rkt")
(module+ main
  (make-directory* "output")
  (with-skia ([font (make-font #:size 30 #:hinting 'none)] [sh (make-shaper font)]
              [builder (make-text-blob-builder)]
              [curve (make-path '((move 30 200) (cubic 100 100 260 100 350 200)))])
    (define text "Retained text")
    (text-blob-builder-add-shaped-run! builder sh (shape-text sh text) #:origin '(30 65) #:text text)
    (with-skia ([blob (text-blob-builder-finish! builder)]
                [curved (shaped-run->text-blob/on-path sh (shape-text sh "Along a curve") curve)])
      (skia-close! sh) (skia-close! font) (skia-close! curve)
      (define page
        (make-output-page 400 250
          (lambda (c)
            (with-skia ([paint (make-paint #:color 'black)])
              (draw-text-blob c blob 0 0 paint)
              (draw-text-blob c curved 0 0 paint))) #:background 'white))
      (call-with-output-file "output/text-blobs-advanced.svg"
        (lambda (out) (write-bytes (output->bytes page 'svg #:text-mode 'outline) out)) #:exists 'truncate/replace)
      (call-with-output-file "output/text-blobs-advanced.pdf"
        (lambda (out) (write-bytes (output->bytes page 'pdf #:text-mode 'outline) out)) #:exists 'truncate/replace))))
