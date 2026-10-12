#lang racket

(require rackunit "color-study.rkt" skia)

(module+ test
  (test-case "tagging preserves the supplied samples"
    (with-skia ([srgb (make-srgb-color-space)] [linear (make-linear-srgb-color-space)]
                [a (make-gray-sample srgb)] [b (make-gray-sample linear)])
      (check-equal? (image->rgba-bytes a) (bytes 128 128 128 255))
      (check-equal? (image->rgba-bytes b) (bytes 128 128 128 255))))
  (test-case "linear midpoint conversion changes RGB but not alpha"
    (with-skia ([srgb (make-srgb-color-space)] [linear (make-linear-srgb-color-space)]
                [source (make-gray-sample linear)]
                [converted (image-convert-color-space source srgb)])
      (define pixels (image->rgba-bytes converted))
      (for ([i '(0 1 2)]) (check-true (<= 187 (bytes-ref pixels i) 189)))
      (check-equal? (bytes-ref pixels 3) 255)
      (check-equal? (image->rgba-bytes source) (bytes 128 128 128 255))))
  (test-case "untagged conversion requires a source declaration"
    (with-skia ([srgb (make-srgb-color-space)] [linear (make-linear-srgb-color-space)]
                [source (rgba-bytes->image 1 1 (bytes 128 128 128 255))])
      (check-exn exn:fail? (lambda () (image-convert-color-space source srgb)))
      (with-skia ([result (image-convert-color-space source srgb #:source-color-space linear)])
        (check-true (<= 187 (bytes-ref (image->rgba-bytes result) 0) 189)))))
  (test-case "an existing tag cannot be overridden accidentally"
    (with-skia ([srgb (make-srgb-color-space)] [source (make-gray-sample srgb)])
      (check-exn exn:fail?
                 (lambda () (image-convert-color-space source srgb #:source-color-space srgb)))))
  (test-case "an ICC profile can describe the source again"
    (with-skia ([srgb (make-srgb-color-space)]
                [restored (color-space-from-icc-bytes (color-space->icc-bytes srgb))])
      (check-true (color-space? restored))
      (with-skia ([source (make-gray-sample restored)]
                  [result (image-convert-color-space source srgb)])
        (check-= (bytes-ref (image->rgba-bytes result) 0) 128 1))))
  (test-case "automatic drawing conversion agrees with explicit conversion, not retagging"
    (with-skia ([srgb (make-srgb-color-space)] [linear (make-linear-srgb-color-space)]
                [source (make-gray-sample linear)]
                [converted (image-convert-color-space source srgb)]
                [wrong (rgba-bytes->image 1 1 (image->rgba-bytes source) #:color-space srgb)])
      (define (display-sample image)
        (with-skia ([surface (make-surface 2 2 #:color-space srgb)])
          (draw-image-rect (surface-canvas surface) image 0 0 2 2 #:sampling 'nearest)
          (bytes-ref (surface->rgba-bytes surface) 0)))
      (check-= (display-sample source) (display-sample converted) 2)
      (check-true (> (- (display-sample converted) (display-sample wrong)) 50))))
  (test-case "the gray sample is configurable instead of fixed in figure captions"
    (with-skia ([srgb (make-srgb-color-space)] [linear (make-linear-srgb-color-space)]
                [source (make-gray-sample linear 64)]
                [converted (image-convert-color-space source srgb)])
      (check-equal? (image->rgba-bytes source) (bytes 64 64 64 255))
      (check-true (<= 136 (bytes-ref (image->rgba-bytes converted) 0) 138))))
  (test-case "ramp ticks refer to the actual input-128 output sample"
    (define images (make-color-study))
    (define encoded (image->rgba-bytes (third images)))
    (define converted (image->rgba-bytes (fourth images)))
    (check-equal? (bytes-ref encoded (* 4 128)) 128)
    (check-true (<= 187 (bytes-ref converted (* 4 128)) 189)))
  (test-case "sRGB 128 decodes to about 55 in eight-bit linear storage"
    (with-skia ([srgb (make-srgb-color-space)] [linear (make-linear-srgb-color-space)]
                [source (make-gray-sample srgb)]
                [decoded (image-convert-color-space source linear)]
                [encoded (image-convert-color-space decoded srgb)])
      (define pixels (image->rgba-bytes decoded))
      (for ([i '(0 1 2)]) (check-true (<= 54 (bytes-ref pixels i) 56)))
      (check-equal? (bytes-ref pixels 3) 255)
      (check-= (bytes-ref (image->rgba-bytes encoded) 0) 128 1)
      (check-equal? (image->rgba-bytes source) (bytes 128 128 128 255))))
  (test-case "the matching PNG profile survives encode and decode"
    (with-skia ([srgb (make-srgb-color-space)] [linear (make-linear-srgb-color-space)]
                [source (make-gray-sample linear)]
                [converted (image-convert-color-space source srgb)]
                [decoded (image-from-bytes
                          (image->png-bytes converted #:icc-profile (color-space->icc-bytes srgb)
                                            #:icc-description "Tutorial sRGB"))])
      (check-true (<= 187 (bytes-ref (image->rgba-bytes decoded) 0) 189))
      (with-skia ([space (image-color-space decoded)])
        (check-true (color-space? space))))))
