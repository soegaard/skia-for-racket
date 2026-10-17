#lang racket/base

;;;
;;; Color Filter Validation
;;;

;; Validates color matrices, lookup tables, interpolation weights, and contrast options.
;; Prepares bounded inputs for public color-filter constructors.

(require racket/list "check.rkt")
(provide checked-filter-matrix checked-filter-table checked-filter-tables
         checked-filter-weight checked-high-contrast filter-buffer-limit!)

;; Validators do not load Skia. Numeric ranges are checked before conversion so
;; an exact value just outside a closed interval is not rounded into that range.

; filter-buffer-limit! : symbol? exact-nonnegative-integer? -> void?
;   Bounds copied filter arrays by the current byte limit.
(define (filter-buffer-limit! who size)
  (unless (<= size (current-skia-byte-limit))
    (raise-arguments-error who "filter input exceeds current-skia-byte-limit"
                           "required bytes" size "limit" (current-skia-byte-limit))))

; closed-range : symbol? real? real? real? string? -> inexact-real?
;   Checks an inclusive parameter interval and native scalar representability.
(define (closed-range who value lo hi description)
  (unless (and (real? value) (<= lo value hi))
    (raise-argument-error who description value))
  (scalar who value))

; checked-filter-weight : symbol? real? -> inexact-real?
;   Checks a filter interpolation weight between zero and one.
(define (checked-filter-weight who weight)
  (closed-range who weight 0 1 "finite real from 0 through 1"))

; checked-high-contrast : symbol? boolean? symbol? real? -> (values boolean? integer? real?)
;   Checks grayscale, inversion mode, contrast, and the native configuration's byte budget.
(define (checked-high-contrast who grayscale? invert-style contrast)
  (boolean who grayscale?)
  (define invert
    (choice who invert-style (hasheq 'none 0 'brightness 1 'lightness 2)))
  (define c (closed-range who contrast -1 1 "finite real from -1 through 1"))
  (filter-buffer-limit! who 12)
  (values grayscale? invert c))

; checked-filter-matrix : symbol? (or/c list? vector?) -> vector?
;   Copies exactly twenty checked RGBA matrix coefficients in row-major 4-by-5 order.
(define (checked-filter-matrix who input)
  (define xs
    (cond [(list? input) input] [(vector? input) (vector->list input)]
          [else (raise-argument-error who "list or vector of 20 finite real values" input)]))
  (unless (= (length xs) 20)
    (raise-arguments-error who "matrix must have 20 row-major entries"
                           "entries" (length xs)))
  (filter-buffer-limit! who 80)
  ;; A fresh immutable vector, independent of the caller's vector.
  (apply vector-immutable (map (lambda (x) (scalar who x)) xs)))

; checked-filter-table : symbol? (or/c bytes? list? vector?) -> bytes?
;   Copies exactly 256 byte entries into an immutable channel lookup table.
(define (checked-filter-table who input)
  (filter-buffer-limit! who 256)
  (define out
    (cond
      [(bytes? input)
       (unless (= (bytes-length input) 256)
         (raise-arguments-error who "table must have exactly 256 bytes"
                                "entries" (bytes-length input)))
       (bytes-copy input)]
      [else
       (define xs
         (cond [(list? input) input] [(vector? input) (vector->list input)]
               [else (raise-argument-error who "256-byte bytes, list, or vector" input)]))
       (unless (= (length xs) 256)
         (raise-arguments-error who "table must have exactly 256 byte entries"
                                "entries" (length xs)))
       (for ([x (in-list xs)])
         (unless (byte? x) (raise-argument-error who "exact byte from 0 through 255" x)))
       (apply bytes xs)]))
  (bytes->immutable-bytes out))

; checked-filter-tables : symbol? any/c any/c any/c any/c -> list?
;   Checks the aggregate table budget and copies alpha/red/green/blue tables, retaining #f
;   identities.
(define (checked-filter-tables who alpha red green blue)
  ;; Check the aggregate table payload, not only each individual table.
  (define inputs (list alpha red green blue))
  (filter-buffer-limit! who (* 256 (count (lambda (x) (not (eq? x #f))) inputs)))
  (for/list ([input (in-list inputs)])
    (and input (checked-filter-table who input))))
