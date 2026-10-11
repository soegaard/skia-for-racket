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
