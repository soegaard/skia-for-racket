#lang racket/base

;;;
;;; Text Run Validation
;;;

;; Checks glyph arrays, positions, transforms, UTF-8 metadata, and run budgets.
;; Prepares text-blob builder inputs with explicit ordering and allocation limits.

(require racket/list racket/match racket/vector "check.rkt" "text-run-data.rkt")
(provide text-run-budget text-run-sequence text-run-glyphs text-run-points
         text-run-scalars text-run-transforms text-run-metadata text-run-cost
         text-run-index text-run-band text-run-path-placement text-run-point)

;;;
;;; Bounded Glyph and Position Sequences
;;;

; text-run-budget : symbol? exact-nonnegative-integer? -> exact-nonnegative-integer?
;;   Checks text payload and snapshot bookkeeping against the current byte limit.
(define (text-run-budget who bytes)
  (unless (and (exact-nonnegative-integer? bytes) (<= bytes (current-skia-byte-limit)))
    (raise-arguments-error who "text data exceeds current-skia-byte-limit"
                           "required bytes" bytes "limit" (current-skia-byte-limit)))
  bytes)
; text-run-sequence : symbol? (or/c list? vector?) [exact-nonnegative-integer?] -> list?
;;   Checks the native signed-int count and conservative per-element allocation before normalizing a
;;   sequence to a list.
(define (text-run-sequence who value [stride 16])
  (define n
    (cond [(list? value) (length value)] [(vector? value) (vector-length value)]
          [else (raise-argument-error who "list? or vector?" value)]))
  (unless (<= n #x7fffffff)
    (raise-arguments-error who "count exceeds the native signed-int range" "count" n))
  (text-run-budget who (* n stride))
  (if (vector? value) (vector->list value) value))
; text-run-glyphs : symbol? (or/c list? vector?) -> (listof exact-nonnegative-integer?)
;;   Copies and validates unsigned 16-bit glyph IDs while retaining their drawing order.
(define (text-run-glyphs who value)
  (for/list ([g (in-list (text-run-sequence who value))]) (glyph-id who g)))
; text-run-point : symbol? (or/c list? vector?) -> (list/c real? real?)
;;   Checks one x/y position and converts both coordinates to native scalars.
(define (text-run-point who value)
  (match value
    [(list x y) (list (scalar who x) (scalar who y))]
    [(vector x y) (list (scalar who x) (scalar who y))]
    [_ (raise-argument-error who "two-element point list or vector" value)]))
; text-run-points : symbol? (or/c list? vector?) exact-nonnegative-integer? -> list?
;;   Checks one x/y position per glyph, preserving positional correspondence.
(define (text-run-points who value count)
  (define xs (text-run-sequence who value))
  (unless (= (length xs) count)
    (raise-arguments-error who "glyph and position counts differ"
                           "glyph count" count "position count" (length xs)))
  (map (lambda (p) (text-run-point who p)) xs))
; text-run-scalars : symbol? (or/c list? vector?) exact-nonnegative-integer? -> (listof real?)
;;   Checks one horizontal position per glyph and converts each to a native scalar.
(define (text-run-scalars who value count)
  (define xs (text-run-sequence who value))
  (unless (= (length xs) count)
    (raise-arguments-error who "glyph and position counts differ"
                           "glyph count" count "position count" (length xs)))
  (map (lambda (x) (scalar who x)) xs))
; text-run-transforms : symbol? (or/c list? vector?) exact-nonnegative-integer? -> list?
;;   Checks one four-component transform per glyph in scos, ssin, tx, ty order.
(define (text-run-transforms who value count)
  (define xs (text-run-sequence who value 32))
  (unless (= (length xs) count)
    (raise-arguments-error who "glyph and transform counts differ"
                           "glyph count" count "transform count" (length xs)))
  (for/list ([x (in-list xs)])
    (define cs (if (vector? x) (vector->list x) x))
    (unless (and (list? cs) (= (length cs) 4))
      (raise-argument-error who "(scos ssin tx ty) transform list or vector" x))
    (map (lambda (v) (scalar who v)) cs)))

;;;
;;; UTF-8 Text and Cluster Correspondence
;;;

; text-run-metadata : symbol? any/c any/c exact-nonnegative-integer? -> (values (or/c #f bytes?)
;   (or/c #f list?))
;;   Checks paired UTF-8 text and per-glyph scalar-start byte offsets; repeated or descending
;;   cluster offsets remain valid for ligatures and RTL runs.
(define (text-run-metadata who text clusters count)
  (cond
    [(and (not text) (not clusters)) (values #f #f)]
    [(or (not text) (not clusters))
     (raise-arguments-error who "#:text and #:clusters must be supplied together"
                            "text" text "clusters" clusters)]
    [else
     (unless (or (string? text) (bytes? text))
       (raise-argument-error who "string? or valid UTF-8 bytes?" text))
     ;; Charge input before allocating either UTF-8 bytes or the immutable copy.
     (define size (if (bytes? text) (bytes-length text) (string-utf-8-length text)))
     (unless (<= size #x7fffffff)
       (raise-arguments-error who "text exceeds native signed-int byte count" "bytes" size))
     (text-run-budget who (+ (* size 2) (* count 20)))
     (define bs
       (bytes->immutable-bytes (if (string? text) (string->bytes/utf-8 text) (bytes-copy text))))
     ;; #f error-char means malformed sequences are rejected, never repaired.
     (bytes->string/utf-8 bs #f)
     (define cs (text-run-sequence who clusters))
     (unless (= count (length cs))
       (raise-arguments-error who "glyph and cluster counts differ"
                              "glyph count" count "cluster count" (length cs)))
     (when (and (zero? count) (positive? size))
       (raise-arguments-error who "text for an empty glyph run would be discarded" "text bytes" size))
     (when (and (positive? count) (zero? size))
       (raise-arguments-error who "nonempty glyphs need nonempty text when clusters are supplied"
                              "glyph count" count))
     (define copied
       (for/list ([c (in-list cs)])
         (unless (and (exact-nonnegative-integer? c) (< c size)
                      (not (= (bitwise-and (bytes-ref bs c) #xc0) #x80)))
           (raise-arguments-error
            who "cluster must be a UTF-8 scalar-start byte offset inside the supplied text"
                                  "cluster" c "text bytes" size))
         c))
     ;; Repeated and descending offsets are legal: marks/ligatures and RTL.
     (values bs copied)]))

;;;
;;; Snapshot Accounting and Path Placement
;;;

; text-run-cost : exact-nonnegative-integer? symbol? (or/c #f bytes?) -> exact-nonnegative-integer?
;;   Estimates logical run payload and conservative snapshot bookkeeping, not native cache usage.
(define (text-run-cost count positioning text)
  ;; Logical payload + conservative snapshot bookkeeping, not a Skia cache quota.
  (+ 256 (* count (+ 2 16 (case positioning [(default) 0] [(horizontal) 4]
                                      [(positioned) 8] [(transformed) 16])
                         (if text 8 0)))
     (if text (* 2 (bytes-length text)) 0)))
; text-run-index : symbol? exact-nonnegative-integer? exact-nonnegative-integer? ->
;   exact-nonnegative-integer?
;;   Checks a zero-based run index against the run count.
(define (text-run-index who value count)
  (unless (and (exact-nonnegative-integer? value) (< value count))
    (raise-arguments-error who "run index out of range" "index" value "count" count))
  value)
; text-run-band : symbol? real? real? -> (list/c real? real?)
;;   Checks a nonempty top-to-bottom intercept band in downward-positive drawing coordinates.
(define (text-run-band who top bottom)
  (define a (scalar who top)) (define b (scalar who bottom))
  (unless (< a b)
    (raise-arguments-error who "intercept band must have top < bottom" "top" top "bottom" bottom))
  (list a b))
; text-run-path-placement : symbol? real? real? real? real? real? -> (list/c real? real? real? real?)
;;   Builds a native scos/ssin/tx/ty transform from a path tangent and normal offset, using the
;;   downward-positive normal (-ty, tx).
(define (text-run-path-placement who x y tangent-x tangent-y normal)
  ;; In downward-positive drawing coordinates, the normal is (-ty, tx).
  (list (scalar who tangent-x) (scalar who tangent-y)
        (scalar who (- x (* tangent-y normal)))
        (scalar who (+ y (* tangent-x normal)))))
