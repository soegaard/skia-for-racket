#lang racket/base
(require ffi/unsafe "../main.rkt" "../private/types.rkt")
(provide color-output-doctor!)
(define (color-output-doctor!)
  (unless (and (= (ctype-sizeof _sk-transfer) 28) (= (ctype-sizeof _sk-xyz) 36)
               (= (ctype-sizeof _sk-primaries) 32)) (error 'doctor "color ABI mismatch"))
  (with-skia ([linear (make-linear-srgb-color-space)] [srgb (make-srgb-color-space)]
              [p3 (make-rgb-color-space 'srgb 'display-p3)]
              [im (rgba-bytes->image 1 1 (bytes 128 128 128 255) #:color-space linear)]
              [converted (image-convert-color-space im srgb)])
    (unless (<= 187 (bytes-ref (image->rgba-bytes converted) 0) 189)
      (error 'doctor "linear-to-sRGB conversion did not change midpoint correctly"))
    (define profile (color-space->icc-bytes srgb))
    (for ([format '(png jpeg webp)])
      (define bs (image->encoded-bytes converted format #:icc-profile profile
                                      #:icc-description "Doctor RGB" #:webp-lossless? #t))
      (unless (regexp-match? (case format [(png) #rx#"iCCP"] [(jpeg) #rx#"ICC_PROFILE"] [(webp) #rx#"ICCP"]) bs)
        (error 'doctor "missing explicit ICC data in ~a" format))
      (with-skia ([c (codec-from-bytes bs)] [cs (codec-color-space c)])
        (unless (color-space? cs) (error 'doctor "codec lost color space"))))
    (unless (> (vector-ref (color-space-xyz-d50 p3) 0) 0.5)
      (error 'doctor "unexpected Display-P3 primary matrix")))
  (define pdf
    (call-with-pdf-bytes (lambda (d) (with-document-page (c d 100 80) (void))) #:pdfa? #t))
  (unless (regexp-match? #rx#"/OutputIntents" pdf) (error 'doctor "missing PDF sRGB output intent"))
  (displayln "Color output passed: custom RGB, sample conversion, PNG/JPEG/WebP ICC, PDF output intent; transfer=28 XYZ=36 primaries=32"))
