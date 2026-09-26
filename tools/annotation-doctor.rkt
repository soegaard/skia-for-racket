#lang racket/base
(require "../main.rkt")
(provide annotation-doctor!)

(define (annotation-doctor!)
  (define pdf
    (call-with-pdf-bytes
     (lambda (doc)
       (call-with-document-page doc 100 80
         (lambda (c)
           (unless (eq? (canvas-annotation-backend c) 'pdf)
             (error 'doctor "incorrect PDF annotation backend"))
           (canvas-annotate-url! c 5 5 20 10 "https://example.invalid/")
           (canvas-link-destination! c 5 25 20 10 "later")))
       (call-with-document-page doc 120 90
         (lambda (c) (canvas-define-destination! c "later" 5 10))))))
  (unless (and (regexp-match? #rx#"/Annots" pdf)
               (regexp-match? #rx#"/URI" pdf)
               (regexp-match? #rx#"/Dests" pdf))
    (error 'doctor "PDF link/destination structures missing"))
  (define svg
    (call-with-svg-bytes
     100 80
     (lambda (c)
       (unless (eq? (canvas-annotation-backend c) 'svg)
         (error 'doctor "incorrect SVG annotation backend"))
       (canvas-annotate-url! c 5 5 20 10 "https://example.invalid/?a=1&b=2")
       (canvas-link-destination! c 5 25 20 10 "later")
       (canvas-translate! c 3 7)
       (canvas-define-destination! c "later" 5 10))
     #:id-prefix "doctor"))
  (unless (and (= (length (regexp-match* #rx#"<a " svg)) 2)
               (regexp-match? #rx#"<view " svg)
               (regexp-match? #rx#"viewBox=\"8.0 17.0 100.0 80.0\"" svg)
               (regexp-match? #rx#"a=1&amp;b=2" svg)
               (not (regexp-match? #rx#"urn:racket-skia" svg)))
    (error 'doctor "SVG links, destination view, or escaping failed"))
  (with-skia ([surface (make-surface 10 10 #:background 'white)])
    (define c (surface-canvas surface))
    (define original (surface->rgba-bytes surface))
    (canvas-link-destination! c 0 0 5 5 "ignored-on-raster")
    (unless (equal? original (surface->rgba-bytes surface))
      (error 'doctor "raster annotation changed pixels")))
  (printf "Annotations passed: PDF URLs/cross-page destinations, SVG root links/views, URI escaping, raster no-op\n"))
