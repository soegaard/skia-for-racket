#lang racket/base
(require rackunit rackunit/text-ui racket/file racket/vector "../main.rkt")
(provide color-output-native-tests)
(define sample (bytes 128 96 64 255 64 128 96 128))
(define (close-color a b [eps 3e-4])
  (define x (color-space-xyz-d50 a))
  (define y (color-space-xyz-d50 b))
  (for ([u (in-vector x)] [v (in-vector y)]) (check-= u v eps))
  (define ta (color-space-transfer-function a))
  (define tb (color-space-transfer-function b))
  (check-true (transfer-function? ta))
  (check-true (transfer-function? tb))
  (for ([n '(0 0.01 0.04 0.25 0.5 0.75 1)])
    (check-= (transfer-function-evaluate ta n) (transfer-function-evaluate tb n) 1e-3)))
(define (with-temp proc)
  (define dir (make-temporary-file "skia-color-test-~a" 'directory))
  (dynamic-wind void (lambda () (proc dir)) (lambda () (delete-directory/files dir))))
(define (encode-check format)
  (with-skia ([cs (make-rgb-color-space 'srgb 'display-p3)]
              [im (rgba-bytes->image 2 1 sample #:color-space cs)])
    (define bs (image->encoded-bytes im format #:icc-profile (color-space->icc-bytes cs)
                                    #:icc-description "P3 regression" #:webp-lossless? #t))
    (check-true
     (regexp-match? (case format [(png) #rx#"iCCP"] [(jpeg) #rx#"ICC_PROFILE"] [(webp) #rx#"ICCP"]) bs))
    (with-skia ([codec (codec-from-bytes bs)] [decoded (codec->image codec)]
                [dcs (image-color-space decoded)])
      (close-color dcs cs)
      (check-equal? (image-width decoded) 2)
      (unless (eq? format 'jpeg)
        (define result (image->rgba-bytes decoded))
        (for ([a (in-bytes result)] [b (in-bytes sample)]) (check-= a b 1))))))

(define color-output-native-tests
  (test-suite
   "Color output native regression"
   (test-case "named sRGB constructor agrees with existing singleton"
     (with-skia ([a (make-rgb-color-space 'srgb 'srgb)] [b (make-srgb-color-space)])
       (check-true (color-space=? a b))))
   (test-case "named linear constructor agrees with existing singleton"
     (with-skia ([a (make-rgb-color-space 'linear 'srgb)] [b (make-linear-srgb-color-space)])
       (check-true (color-space=? a b))))
   (test-case "all named SDR transfer functions have expected endpoints"
     (for ([name '(srgb linear gamma-2.2 rec2020)])
       (define tf (named-transfer-function name))
       (check-= (transfer-function-evaluate tf 0) 0 1e-5)
       (check-= (transfer-function-evaluate tf 1) 1 1e-5)))
   (test-case "inverse transfer round trip"
     (define tf (named-transfer-function 'srgb))
     (define inv (transfer-function-invert tf))
     (check-true (transfer-function? inv))
     (for ([x '(0 0.01 0.04 0.2 0.5 1)])
       (check-= (transfer-function-evaluate inv (transfer-function-evaluate tf x)) x 1e-4)))
   (test-case "Display P3 differs from sRGB"
     (with-skia ([p3 (make-rgb-color-space 'srgb 'display-p3)] [s (make-srgb-color-space)])
       (check-false (color-space=? p3 s))
       (check-false (color-space-srgb? p3))))
   (test-case "named gamut queries produce immutable matrices"
     (for ([name '(srgb adobe-rgb display-p3 rec2020 xyz)])
       (define m (named-xyz-d50 name))
       (check-true (immutable? m))
       (check-equal? (vector-length m) 9)))
   (test-case "XYZ identity gamut is row-major"
     (check-equal? (named-xyz-d50 'xyz) '#(1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 1.0)))
   (test-case "sRGB chromaticities are adapted to D50"
     (define actual (primaries->xyz-d50 '(0.64 0.33) '(0.30 0.60) '(0.15 0.06) '(0.3127 0.3290)))
     (for ([a (in-vector actual)] [b (in-vector (named-xyz-d50 'srgb))]) (check-= a b 3e-4)))
   (test-case "degenerate primaries fail cleanly"
     (check-exn exn:fail? (lambda () (primaries->xyz-d50 '(0.64 0.33) '(0.64 0.33) '(0.64 0.33) '(0.3127 0.3290)))))
   (test-case "custom transfer and gamut snapshots"
     (define xyz (vector-copy (named-xyz-d50 'display-p3)))
     (with-skia ([cs (make-rgb-color-space (make-transfer-function 2 1 0 0 0 0 0) xyz)])
       (vector-set! xyz 0 99)
       (check-true (< (vector-ref (color-space-xyz-d50 cs) 0) 1))
       (check-= (transfer-function-evaluate (color-space-transfer-function cs) 0.5) 0.25 1e-5)))
   (test-case "inspection values survive native close"
     (define cs (make-srgb-color-space))
     (define tf (color-space-transfer-function cs))
     (define xyz (color-space-xyz-d50 cs))
     (skia-close! cs)
     (check-= (transfer-function-evaluate tf 0.5) 0.214041 1e-5)
     (check-equal? (vector-length xyz) 9)
     (check-exn exn:fail? (lambda () (color-space-xyz-d50 cs))))
   (test-case "custom RGB ICC export and import preserve gamut"
     (with-skia ([cs (make-rgb-color-space 'gamma-2.2 'adobe-rgb)]
                 [again (color-space-from-icc-bytes (color-space->icc-bytes cs))])
       (close-color cs again)))
   (test-case "linear 128 converts to sRGB about 188"
     (with-skia ([lin (make-linear-srgb-color-space)] [srgb (make-srgb-color-space)]
                 [im (rgba-bytes->image 1 1 (bytes 128 128 128 255) #:color-space lin)]
                 [converted (image-convert-color-space im srgb)])
       (check-= (bytes-ref (image->rgba-bytes converted) 0) 188 1)))
   (test-case "untagged conversion requires explicit source"
     (with-skia ([srgb (make-srgb-color-space)] [im (rgba-bytes->image 1 1 (bytes 128 128 128 255))])
       (check-exn #rx"untagged" (lambda () (image-convert-color-space im srgb)))))
   (test-case "untagged source declaration enables conversion"
     (with-skia ([lin (make-linear-srgb-color-space)] [srgb (make-srgb-color-space)]
                 [im (rgba-bytes->image 1 1 (bytes 128 128 128 255))]
                 [converted (image-convert-color-space im srgb #:source-color-space lin)])
       (check-= (bytes-ref (image->rgba-bytes converted) 0) 188 1)))
   (test-case "explicit source cannot override already-tagged input"
     (with-skia ([cs (make-srgb-color-space)] [im (rgba-bytes->image 2 1 sample #:color-space cs)])
       (check-exn exn:fail? (lambda () (image-convert-color-space im cs #:source-color-space cs)))))
   (test-case "conversion preserves original samples"
     (with-skia ([lin (make-linear-srgb-color-space)] [srgb (make-srgb-color-space)]
                 [im (rgba-bytes->image 2 1 sample #:color-space lin)]
                 [converted (image-convert-color-space im srgb)])
       (check-equal? (image->rgba-bytes im) sample)
       (define result (image->rgba-bytes converted))
       (check-not-equal? result sample)
       (skia-close! im) (skia-close! lin) (skia-close! srgb)
       (check-equal? (image->rgba-bytes converted) result)))
   (test-case "alpha is not gamma corrected"
     (with-skia ([lin (make-linear-srgb-color-space)] [srgb (make-srgb-color-space)]
                 [im (rgba-bytes->image 2 1 sample #:color-space lin)]
                 [converted (image-convert-color-space im srgb)])
       (define bs (image->rgba-bytes converted))
       (check-equal? (bytes-ref bs 3) 255)
       (check-equal? (bytes-ref bs 7) 128)))
   (test-case "closed conversion destination is rejected"
     (with-skia ([cs (make-srgb-color-space)] [im (rgba-bytes->image 2 1 sample #:color-space cs)])
       (skia-close! cs)
       (check-exn exn:fail? (lambda () (image-convert-color-space im cs)))))
   (test-case "PNG explicit ICC round trip" (encode-check 'png))
   (test-case "JPEG explicit ICC round trip" (encode-check 'jpeg))
   (test-case "WebP explicit ICC round trip" (encode-check 'webp))
   (test-case "encoder color-space keyword converts before PNG encoding"
     (with-skia ([lin (make-linear-srgb-color-space)] [s (make-srgb-color-space)]
                 [im (rgba-bytes->image 1 1 (bytes 128 128 128 255) #:color-space lin)]
                 [decoded (image-from-bytes (image->png-bytes im #:color-space s))])
       (check-= (bytes-ref (image->rgba-bytes decoded) 0) 188 1)))
   (test-case "ICC metadata alone does not convert untagged samples"
     (with-skia ([cs (make-linear-srgb-color-space)] [im (rgba-bytes->image 2 1 sample)]
                 [dec (image-from-bytes (image->png-bytes im #:icc-profile (color-space->icc-bytes cs)))]
                 [tag (image-color-space dec)])
       (check-true (color-space-linear-gamma? tag))
       (define bs (image->rgba-bytes dec))
       (for ([a (in-bytes bs)] [b (in-bytes sample)]) (check-= a b 1))))
   (test-case "existing automatic P3 embedding remains available"
     (with-skia ([cs (make-rgb-color-space 'srgb 'display-p3)]
                 [im (rgba-bytes->image 2 1 sample #:color-space cs)]
                 [dec (image-from-bytes (image->png-bytes im))]
                 [tag (image-color-space dec)])
       (close-color cs tag)))
   (test-case "existing untagged encoding works without new keywords"
     (with-skia ([im (rgba-bytes->image 2 1 sample)])
       (for ([f '(png jpeg webp)]) (check-true (bytes? (image->encoded-bytes im f))))))
   (test-case "surface PNG forwards explicit profile"
     (with-skia ([cs (make-srgb-color-space)] [s (make-surface 3 2 #:color-space cs #:background 'red)])
       (check-true (regexp-match? #rx#"iCCP" (surface->png-bytes s #:icc-profile (color-space->icc-bytes cs))))))
   (test-case "save-image forwards ICC settings for all formats"
     (with-temp
      (lambda (dir)
        (with-skia ([cs (make-srgb-color-space)] [im (rgba-bytes->image 2 1 sample #:color-space cs)])
          (for ([format '(png jpeg webp)])
            (define name (build-path dir (symbol->string format)))
            (save-image im name format #:icc-profile (color-space->icc-bytes cs))
            (check-true (> (file-size name) 32)))))))
   (test-case "save-png forwards profile description"
     (with-temp
      (lambda (dir)
        (with-skia ([cs (make-srgb-color-space)] [s (make-surface 3 2 #:color-space cs)])
          (define name (build-path dir "image.png"))
          (save-png s name #:icc-profile (color-space->icc-bytes cs) #:icc-description "Surface RGB")
          (check-true (regexp-match? #rx#"iCCP" (file->bytes name)))))))
   (test-case "invalid profile leaves existing output unchanged"
     (with-temp
      (lambda (dir)
        (define name (build-path dir "keep.png"))
        (call-with-output-file name (lambda (out) (write-bytes #"keep" out)))
        (with-skia ([s (make-surface 1 1)])
          (check-exn exn:fail? (lambda () (save-png s name #:exists 'replace #:icc-profile #"bad"))))
        (check-equal? (file->bytes name) #"keep"))))
   (test-case "profile scope can be used repeatedly without retaining caller buffers"
     (with-skia ([cs (make-rgb-color-space 'srgb 'display-p3)] [im (rgba-bytes->image 2 1 sample #:color-space cs)])
       (define profile (color-space->icc-bytes cs))
       (skia-close! cs)
       (for ([i (in-range 8)]) (check-true (bytes? (image->png-bytes im #:icc-profile profile))))))
   (test-case "PDF-A request adds an output intent and metadata"
     (define bs (call-with-pdf-bytes (lambda (d) (with-document-page (c d 100 80) (void))) #:pdfa? #t))
     (check-true (regexp-match? #rx#"/OutputIntents" bs))
     (check-true (regexp-match? #rx#"/Metadata" bs)))
   (test-case "default PDF mode retains its previous no-output-intent behavior"
     (define bs (call-with-pdf-bytes (lambda (d) (with-document-page (c d 100 80) (void)))))
     (check-false (regexp-match? #rx#"/OutputIntents" bs)))
   (test-case "shared PDF export forwards PDF-A mode"
     (define p (make-output-page 120 80 (lambda (c) (with-skia ([ink (make-paint #:color 'blue)]) (draw-circle c 30 30 10 ink)))))
     (check-true (regexp-match? #rx#"/OutputIntents" (output->bytes p 'pdf #:pdfa? #t))))
   (test-case "file PDF helper forwards PDF-A mode"
     (with-temp
      (lambda (dir)
        (define name (build-path dir "pdfa.pdf"))
        (call-with-pdf-file name (lambda (d) (with-document-page (c d 100 80) (void))) #:pdfa? #t)
        (check-true (regexp-match? #rx#"/OutputIntents" (file->bytes name))))))))
(module+ test (run-tests color-output-native-tests))
