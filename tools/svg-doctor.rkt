#lang racket/base
(require "../main.rkt")
(provide svg-doctor!)

(define (svg-doctor!)
  (define stale #f)
  (define (render)
    (with-skia ([d (make-svg-document 64.5 40.25 #:title "SVG & vector")]
                [gradient (make-linear-gradient-shader 0 0 64 0 '(blue red))]
                [p (make-paint #:shader gradient)])
      (define c (svg-document-canvas d))
      (set! stale c)
      (with-canvas-state c
        (canvas-clip-rect! c 2 2 50 30)
        (draw-rect c 0 0 64 40 p))
      (svg-document-finish! d)
      (unless (skia-closed? c) (error 'doctor "finished SVG canvas is still live"))
      (svg-document->bytes d)))
  (define a (render))
  (unless (and (equal? a (render))
               (skia-closed? stale)
               (regexp-match? #rx#"viewBox=\"0 0 64.5 40.25\"" a)
               (regexp-match? #rx#"<linearGradient" a)
               (regexp-match? #rx#"<clipPath" a)
               (regexp-match? #rx#"<title>SVG &amp; vector</title>" a)
               (regexp-match? #rx#"</svg>" a))
    (error 'doctor "SVG vector/root/lifetime/ID probe failed"))
  (define raster
    (call-with-svg-bytes 16 16
      (lambda (c)
        (draw-rasterized c 0 0 16 16
          (lambda (rc)
            (with-skia ([p (make-paint #:color 'red)])
              (draw-circle rc 8 8 4 p))) #:scale 2))))
  (unless (regexp-match? #rx#"data:image/png;base64," raster)
    (error 'doctor "SVG explicit raster embedding failed"))
  (printf "SVG output passed; vector XML, stable IDs, embedded PNG, and canvas invalidation\n"))
