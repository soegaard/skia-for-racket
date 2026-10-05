#lang racket/base
(require racket/file "../main.rkt")
;; Public APIs only. Labels and other surrounding drawing can remain vector.
(module+ main
  (make-directory* "output/effects-example")
  (define page
    (make-output-page 300 180
      (lambda (c)
        (with-skia ([stamp (make-path '((move 0 -4) (line 8 0) (line 0 4) (close)))]
                    [effect (make-1d-path-effect stamp 20 #:style 'rotate)]
                    [p (make-paint #:color 'navy #:path-effect effect)]
                    [path (make-path '((move 12 24) (cubic 60 0 150 80 270 24)))])
          (draw-output-group c 0 0 300 70 (lambda (g) (draw-path g path p)) #:scale 2))
        (draw-output-group c 10 80 280 80
          (lambda (g)
            (with-skia ([noise (make-fractal-noise-shader 0.04 0.07 4 42)]
                        [p (make-paint #:shader noise)])
              (draw-rect g 0 0 280 80 p)))
          #:scale 2))
      #:background 'white))
  (for ([fmt (in-list '(pdf svg))])
    (save-output/audit page (build-path "output/effects-example" (format "effects.~a" fmt))
                       fmt #:policy 'error #:exists 'replace))
  (with-skia ([image (output-page->image page)])
    (save-image image "output/effects-example/effects.png" 'png #:exists 'replace)))
