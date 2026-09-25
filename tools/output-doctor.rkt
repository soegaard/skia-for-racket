#lang racket/base
(require "../main.rkt")
(provide output-doctor!)

(define (output-doctor!)
  (define page
    (make-output-page
     3 2
     (lambda (c)
       (with-skia ([f (make-font #:size 1/4 #:linear-metrics? #t #:subpixel? #t #:hinting 'none)] [paint (make-paint #:color 'black)])
         (draw-simple-text c "PDF and SVG" 1/8 1/2 f paint)))
     #:unit 'in #:margins 1/8))
  (define svg (output->bytes page 'svg))
  (define pdf (output->bytes (list page page) 'pdf))
  (unless (and (regexp-match? #rx#"width=\"216.0pt\" height=\"144.0pt\"" svg)
               (regexp-match? #rx#"<path[ >]" svg)
               (not (regexp-match? #rx#"<text[ >]" svg))
               (regexp-match? #rx#"^%PDF-" pdf)
               (= 2 (length (regexp-match* #rx#"/Type /Page([^s]|$)" pdf))))
    (error 'doctor "shared vector output or physical sizing failed"))
  (with-skia ([f (make-font #:size 18)]
              [blob (make-positioned-text-blob f (list (font-char->glyph f #\A)) '((0 0)))])
    (font-set-size! f 60)
    (skia-close! f)
    (with-skia ([outline (text-blob->path blob)])
      (unless (positive? (path-point-count outline))
        (error 'doctor "detached text-blob outline failed"))))
  (printf "Vector output passed: shared physical sizing, 2 PDF pages, outlined SVG, independent blob snapshot; PDF ~a bytes, SVG ~a bytes\n"
          (bytes-length pdf) (bytes-length svg)))
