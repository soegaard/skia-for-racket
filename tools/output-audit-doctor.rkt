#lang racket/base
(require "../main.rkt")
(provide output-audit-doctor!)
(define (output-audit-doctor!)
  (define source "half4 main(float2 p) { return half4(.2,.4,.8,1); }")
  (with-skia ([effect (make-runtime-effect source)]
              [shader (runtime-effect->shader effect)]
              [paint (make-paint #:shader shader)])
    ;; Keep facts after the caller closes its shader/effect aliases.
    (skia-close! shader)
    (skia-close! effect)
    (define (draw c) (draw-rect c 0 0 32 20 paint))
    (define unsafe (make-output-page 80 60 draw))
    (define preflight (analyze-output-page unsafe 'svg))
    (unless (and (output-audit-report-blocking? preflight)
                 (for/or ([e (in-list (output-audit-report-events preflight))])
                   (eq? (output-audit-event-feature e) 'runtime-shader)))
      (error 'doctor "output audit did not detect retained runtime shader"))
    (define safe
      (make-output-page 80 60
        (lambda (c)
          (with-output-label "bounded-runtime"
            (draw-rasterized c 4 4 32 20 draw #:scale 2)))))
    (define-values (xml report) (output->bytes/audit safe 'svg #:policy 'error))
    (unless (and (regexp-match? #rx#"<image" xml)
                 (not (output-audit-report-blocking? report))
                 (for/or ([e (in-list (output-audit-report-events report))])
                   (and (eq? (output-audit-event-feature e) 'raster-group)
                        (= (hash-ref (output-audit-event-details e) 'pixel_width) 64)
                        (= (hash-ref (output-audit-event-details e) 'pixel_height) 40))))
      (error 'doctor "explicit rasterization did not resolve the audit"))
    (printf "Output audit passed: retained provenance, SVG preflight, strict export, 64x40 explicit raster group; no new native symbols\n")))
