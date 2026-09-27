#lang racket/base
(require racket/list "../main.rkt")
(provide portable-drawing-doctor!)
(define (portable-drawing-doctor!)
  (define plan (image-nine-plan 9 9 '(3 3 3 3) 0 0 30 24))
  (unless (and (= (length plan) 9)
               (equal? (image-grid-cell-destination (list-ref plan 4)) '#(3.0 3.0 24.0 18.0)))
    (error 'portable-drawing-doctor "fixed/stretch plan mismatch"))
  (with-skia ([s (make-surface 24 24)] [p (make-paint #:color 'blue)]
              [im (rgba-bytes->image 9 9 (make-bytes (* 9 9 4) 255))])
    (draw-markers (surface-canvas s) '((10 10)) 8 p)
    (unless (equal? (surface-pixel s 10 10) (rgba 0 0 255 255))
      (error 'portable-drawing-doctor "marker pixel mismatch"))
    (define decision #f)
    (define-values (svg report)
      (output->bytes/audit
       (make-output-page 40 32
         (lambda (c)
           (set! decision
             (draw-output-group c 0 0 40 32
               (lambda (local) (draw-image-nine/portable local im '(3 3 3 3) 0 0 30 24))))))
       'svg #:policy 'error))
    (unless (and (eq? (output-group-report-strategy decision) 'native)
                 (regexp-match? #rx#"<image" svg)
                 (not (output-audit-report-vector-only? report))
                 (not (output-audit-report-blocking? report))
                 (not (for/or ([e (in-list (output-audit-report-events report))])
                        (eq? (output-audit-event-feature e) 'raster-group))))
      (error 'portable-drawing-doctor "cropped images were rasterized again or lost their image classification")))
  (displayln "Portable drawing passed: marker geometry, fixed/stretch plans, cropped images in native groups; no new native symbols"))
(module+ main (portable-drawing-doctor!))
