#lang racket/base
(require racket/list "check.rkt")
(provide (all-defined-out))

;; Copy and round at the boundary: native structures contain IEEE binary32.
(define (color-float who x)
  (define f (scalar who x))
  (floating-point-bytes->real (real->floating-point-bytes f 4 #f) #f))

(define (color-sequence who xs count what)
  (define entries
    (cond [(vector? xs) (vector->list xs)] [(list? xs) xs]
          [else (raise-argument-error who what xs)]))
  (unless (= (length entries) count) (raise-argument-error who what xs))
  (vector->immutable-vector
   (list->vector (map (lambda (x) (color-float who x)) entries))))

(define (checked-xyz-d50 who xs)
  (define v (color-sequence who xs 9 "nine row-major XYZ-D50 coefficients"))
  (define (at i) (vector-ref v i))
  (define det
    (+ (* (at 0) (- (* (at 4) (at 8)) (* (at 5) (at 7))))
       (- (* (at 1) (- (* (at 3) (at 8)) (* (at 5) (at 6)))))
       (* (at 2) (- (* (at 3) (at 7)) (* (at 4) (at 6))))))
  (when (zero? det)
    (raise-arguments-error who "XYZ-D50 matrix is singular after float conversion" "matrix" xs))
  v)

(define (checked-chromaticity who xy)
  (define v (color-sequence who xy 2 "two chromaticity coordinates (x y)"))
  (define x (vector-ref v 0))
  (define y (vector-ref v 1))
  (unless (and (<= 0 x 1) (< 0 y) (<= y 1) (<= (+ x y) 1.000001))
    (raise-arguments-error who "invalid chromaticity (requires x >= 0, y > 0, x+y <= 1)"
                           "chromaticity" xy))
  v)

(define (icc-description-bytes who profile description)
  (when (and description (not profile))
    (raise-arguments-error who "#:icc-description requires #:icc-profile" "description" description))
  (cond
    [(not description) #f]
    [else
     ;; Skia's ICC description writer consumes a char*, not a UTF-8 string.
     ;; Printable ASCII avoids pretending that arbitrary UTF-8 becomes UTF-16.
     (unless (and (string? description) (<= 1 (string-length description) 4096)
                  (for/and ([c (in-string description)]) (<= 32 (char->integer c) 126)))
       (raise-argument-error who "1 through 4096 printable ASCII characters" description))
     (define bs (string->bytes/utf-8 description))
     (unless (<= (add1 (bytes-length bs)) (current-skia-byte-limit))
       (error who "ICC description exceeds current-skia-byte-limit"))
     (bytes-append bs #"\0")]))

(define (icc-u32 bs at) (integer-bytes->integer bs #f #t at (+ at 4)))

;; This gate protects the native profile *writer*, whose LUT paths assert on
;; unsupported mAB/mBA forms. Import through color-space-from-icc-bytes remains
;; unchanged. Encoding overrides deliberately accept only SDR RGB matrix/TRC.
(define (checked-encoding-profile who value)
  (cond
    [(not value) #f]
    [else
     (unless (bytes? value) (raise-argument-error who "#f or RGB matrix/TRC ICC bytes" value))
     (define n (bytes-length value))
     (unless (<= 132 n (current-skia-byte-limit))
       (raise-arguments-error who "ICC input is too short or exceeds current-skia-byte-limit"
                              "bytes" n "limit" (current-skia-byte-limit)))
     (define bs (bytes->immutable-bytes value))
     (unless (and (= (icc-u32 bs 0) n)
                  (bytes=? (subbytes bs 36 40) #"acsp")
                  (bytes=? (subbytes bs 16 20) #"RGB ")
                  (bytes=? (subbytes bs 20 24) #"XYZ "))
       (error who "encoding ICC must have an exact length, acsp signature, RGB data, and XYZ PCS"))
     (define count (icc-u32 bs 128))
     (define table-end (+ 132 (* 12 count)))
     (unless (<= table-end n) (error who "truncated ICC tag table"))
     (define tags (make-hash))
     (for ([i (in-range count)])
       (define at (+ 132 (* 12 i)))
       (define tag (subbytes bs at (+ at 4)))
       (define pos (icc-u32 bs (+ at 4)))
       (define len (icc-u32 bs (+ at 8)))
       (when (hash-has-key? tags tag) (error who "duplicate ICC tag: ~s" tag))
       (unless (and (>= pos table-end) (zero? (modulo pos 4))
                    (>= len 8) (<= (+ pos len) n))
         (error who "ICC tag range lies outside the profile: ~s" tag))
       (when (or (regexp-match? #rx#"^(A2B|B2A|D2B|B2D)" tag) (bytes=? tag #"cicp"))
         (error who "LUT/HDR ICC encoding overrides are not supported: ~s" tag))
       (hash-set! tags tag (cons pos len)))
     (for ([tag (in-list '(#"rXYZ" #"gXYZ" #"bXYZ" #"rTRC" #"gTRC" #"bTRC"))])
       (define loc (hash-ref tags tag (lambda () (error who "missing matrix/TRC ICC tag: ~s" tag))))
       (define type (subbytes bs (car loc) (+ (car loc) 4)))
       (unless (if (bytes=? (subbytes tag 1) #"XYZ")
                   (and (bytes=? type #"XYZ ") (>= (cdr loc) 20))
                   (or (bytes=? type #"para") (bytes=? type #"curv")))
         (error who "invalid matrix/TRC ICC tag type: ~s" tag)))
     bs]))
