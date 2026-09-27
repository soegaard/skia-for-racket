#lang racket/base
(provide renderer-class verify-smoke-pixels)
;; Classification is an explicit string heuristic, not a hardware attestation.
(define (renderer-class vendor renderer)
  (define name (string-append vendor " " renderer))
  (cond
    [(regexp-match? #px"(?i:llvmpipe|softpipe|swrast|swiftshader|software|gdi generic|lavapipe)" name)
     "software"]
    [(regexp-match? #px"(?i:apple [ma][0-9]|nvidia|geforce|quadro|radeon|intel.*(?:iris|graphics|arc)|amd.*graphics)" name)
     "hardware-reported"]
    [else "unclassified"]))
(define (verify-smoke-pixels data)
  (unless (and (bytes? data) (= (bytes-length data) (* 8 8 4)))
    (error 'gpu-smoke-test "expected 8x8 tightly packed RGBA readback"))
  ;; Full-image comparison catches origin flips, channel swaps, a missing draw,
  ;; and a missing clear. Alpha is tested in the untouched center column.
  (for* ([y (in-range 8)] [x (in-range 8)])
    (define expected
      (cond [(= x 3) '(0 0 0 0)]
            [(< y 4) (if (< x 3) '(255 0 0 255) '(0 255 0 255))]
            [else (if (< x 3) '(0 0 255 255) '(255 255 0 255))]))
    (define offset (* 4 (+ x (* y 8))))
    (unless (equal? expected (bytes->list (subbytes data offset (+ offset 4))))
      (error 'gpu-smoke-test "RGBA/origin mismatch at (~a, ~a): expected ~a; got ~a"
             x y expected (bytes->list (subbytes data offset (+ offset 4))))))
  #t)
