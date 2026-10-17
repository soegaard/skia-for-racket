#lang racket/base

;;;
;;; Typeface Fixtures
;;;

;; Provides shared inputs and drawing fixtures for deterministic font fixtures, font tables, and
;; typeface ownership.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
;; Original, procedural test fixtures, not copies of installed or third-party
;; fonts. No font binaries are checked in. Four glyphs: .notdef, space, A, V.
(require racket/list)
(provide fixture-font-bytes fixture-collection-bytes fixture-table-bytes fixture-checksum
         fixture-family fixture-postscript fixture-text)

;;;
;;; Fixtures and Assertions
;;;

; fixture-family : string?
;;   Names the original generated test family, independent of installed host fonts.
(define fixture-family "Skia Racket Fixture")

; fixture-text : string?
;;   Uses AV to expose the fixture's advance widths and kerning pair.
(define fixture-text "AV")

; fixture-postscript : [boolean?] -> string?
;;   Returns distinct regular/bold PostScript names for the generated family.
(define (fixture-postscript [bold? #f])
  (if bold? "SkiaRacketFixture-Bold" "SkiaRacketFixture-Regular"))

; u16 : exact-nonnegative-integer? -> bytes?
;;   Encodes an unsigned 16-bit OpenType field in big-endian byte order.
(define (u16 n) (integer->integer-bytes n 2 #f #t))

; s16 : exact-integer? -> bytes?
;;   Encodes a signed 16-bit OpenType metric in big-endian byte order.
(define (s16 n) (integer->integer-bytes n 2 #t #t))

; u32 : exact-nonnegative-integer? -> bytes?
;;   Encodes an unsigned 32-bit OpenType field in big-endian byte order.
(define (u32 n) (integer->integer-bytes n 4 #f #t))

; us : (listof exact-nonnegative-integer?) -> bytes?
;;   Concatenates unsigned 16-bit OpenType fields in their declared order.
(define (us xs) (apply bytes-append (map u16 xs)))

; ss : (listof exact-integer?) -> bytes?
;;   Concatenates signed 16-bit metrics or coordinate deltas in declaration order.
(define (ss xs) (apply bytes-append (map s16 xs)))

; pad : bytes? -> bytes?
;;   Appends zero bytes to align a font table to the next four-byte boundary.
(define (pad bs) (bytes-append bs (make-bytes (modulo (- (bytes-length bs)) 4))))

; fixture-checksum : bytes? -> exact-nonnegative-integer?
;;   Sums padded big-endian 32-bit words modulo 2^32 as required by OpenType.
(define (fixture-checksum bs)
  (define b (pad bs))
  (for/fold ([sum 0]) ([i (in-range 0 (bytes-length b) 4)])
    (bitwise-and #xffffffff (+ sum (integer-bytes->integer b #f #t i (+ i 4))))))

; glyph : (listof (listof exact-integer?)) -> bytes?
;;   Encodes a single-contour on-curve TrueType glyph with delta-coded coordinates.
(define (glyph points)
  (define xs (map car points))
  (define ys (map cadr points))
  (define (deltas ns)
    (for/list ([x (in-list ns)] [p (in-list (cons 0 ns))]) (- x p)))
  (pad (bytes-append (ss (list 1 (apply min xs) (apply min ys) (apply max xs) (apply max ys)))
                     (u16 (sub1 (length points))) (u16 0)
                     (make-bytes (length points) 1)
                     (ss (deltas xs)) (ss (deltas ys)))))

; name-table : boolean? -> bytes?
;;   Builds Windows Unicode name records and strings for the regular or bold face.
(define (name-table bold?)
  (define subfamily (if bold? "Bold" "Regular"))
  (define fields
    (list (cons 1 fixture-family) (cons 2 subfamily)
          (cons 3 (string-append "SkiaRacketFixture-1-" subfamily))
          (cons 4 (string-append fixture-family " " subfamily))
          (cons 5 "Version 1.0") (cons 6 (fixture-postscript bold?))
          (cons 16 fixture-family) (cons 17 subfamily)))
  (define offset 0)
  (define strings '())
  (define records
    (for/list ([field (in-list fields)])
      (define text
        (apply bytes-append (for/list ([c (in-string (cdr field))]) (u16 (char->integer c)))))
      (define record (us (list 3 1 #x409 (car field) (bytes-length text) offset)))
      (set! offset (+ offset (bytes-length text)))
      (set! strings (cons text strings))
      record))
  (bytes-append (us (list 0 (length fields) (+ 6 (* 12 (length fields)))))
                (apply bytes-append records) (apply bytes-append (reverse strings))))

; tables : boolean? -> hash?
;;   Builds original outline, metric, cmap, kerning, and identity tables for a four-glyph font.
(define (tables bold?)
  (define width (if bold? 800 600))
  (define right (- width 200))
  (define block (glyph (list '(0 0) (list right 0) (list right 700) '(0 700))))
  (define vee (glyph (list '(0 700) (list (quotient right 2) 0) (list right 700))))
  (define glyphs (list block #"" block vee))
  (define offsets
    (let loop ([gs glyphs] [n 0])
      (if (null? gs) (list n) (cons n (loop (cdr gs) (+ n (bytes-length (car gs))))))))
  (define cmap4
    (bytes-append (us '(4 48 0 8 8 2 0)) (us '(32 65 86 65535)) (u16 0)
                  (us '(32 65 86 65535)) (ss '(-31 -63 -83 1)) (us '(0 0 0 0))))
  (define head
    (bytes-append (u32 #x10000) (u32 #x10000) (u32 0) (u32 #x5f0f3cf5)
                  (us '(3 1000))
                  (u32 0) (u32 2082844800) (u32 0) (u32 2082844800)
                  (ss (list 0 0 right 700)) (us (list (if bold? 1 0) 8)) (ss '(2 1 0))))
  (define hhea
    (bytes-append (u32 #x10000) (ss '(800 -200 0)) (u16 width)
                  (ss (list 0 200 right 1 0 0)) (make-bytes 8) (ss '(0)) (u16 4)))
  (define os2
    (bytes-append (u16 0) (s16 width) (us (list (if bold? 700 400) 5 0))
                  (ss '(650 600 0 75 650 600 0 350 50 300 0))
                  (bytes 2 0 5 9 0 0 0 0 0 0) (u32 1) (make-bytes 12) #"SKRF"
                  (us (list (if bold? #x20 #x40) 32 86)) (ss '(800 -200 0)) (us '(800 200))))
  (define pairs (bytes-append (us '(0 1 0 20 1 1 6 0 0 2 3)) (s16 -80)))
  (unless (and (= (bytes-length head) 54) (= (bytes-length hhea) 36)
               (= (bytes-length os2) 78) (= (bytes-length cmap4) 48))
    (error 'typeface-fixture "invalid fixture table layout"))
  (hash "OS/2" os2 "cmap" (bytes-append (us '(0 1 3 1)) (u32 12) cmap4)
        "glyf" (apply bytes-append glyphs) "head" head "hhea" hhea
        "hmtx" (apply bytes-append (make-list 4 (bytes-append (u16 width) (s16 0))))
        "kern" pairs "loca" (apply bytes-append (map u32 offsets))
        "maxp" (bytes-append (u32 #x10000) (us '(4 4 1 0 0 2 0 0 0 0 0 0 0 0)))
        "name" (name-table bold?)
        "post" (bytes-append (u32 #x30000) (u32 0) (ss '(-75 50)) (u32 1) (make-bytes 16))))

; build-font : boolean? exact-nonnegative-integer? boolean? -> bytes?
;;   Assembles sorted font tables using absolute base offsets and optional whole-font checksum
;;   adjustment.
(define (build-font bold? base checksum?)
  (define ts (tables bold?))
  (define tags (sort (hash-keys ts) string<?))
  (define count (length tags))
  (define power (sub1 (integer-length count)))
  (define search (* 16 (arithmetic-shift 1 power)))
  (define pos (+ 12 (* 16 count)))
  (define head-pos #f)
  (define payload '())
  (define directory
    (for/list ([tag (in-list tags)])
      (define b (hash-ref ts tag))
      (when (equal? tag "head") (set! head-pos pos))
      (define entry (bytes-append (string->bytes/latin-1 tag) (u32 (fixture-checksum b))
                                  (u32 (+ base pos)) (u32 (bytes-length b))))
      (set! pos (+ pos (bytes-length (pad b))))
      (set! payload (cons (pad b) payload))
      entry))
  (define out
    (bytes-append (u32 #x10000) (us (list count search power (- (* 16 count) search)))
                  (apply bytes-append directory) (apply bytes-append (reverse payload))))
  (when checksum?
    (bytes-copy! out (+ head-pos 8)
      (u32 (bitwise-and #xffffffff (- #xb1b0afba (fixture-checksum out))))))
  out)

; fixture-font-bytes : [#:bold? boolean?] -> bytes?
;;   Builds a complete standalone regular or bold TrueType fixture.
(define (fixture-font-bytes #:bold? [bold? #f]) (build-font bold? 0 #t))

; fixture-collection-bytes : -> bytes?
;;   Packs regular and bold faces into a TTC with collection-relative table offsets.
(define (fixture-collection-bytes)
  ;; TTC table offsets are absolute from the start of the collection. The
  ;; per-face checkSumAdjustment is zero, as required for collection members.
  (define a (build-font #f 20 #f))
  (define b (build-font #t (+ 20 (bytes-length a)) #f))
  (bytes-append #"ttcf" (u32 #x10000) (u32 2) (u32 20) (u32 (+ 20 (bytes-length a))) a b))

; fixture-table-bytes : string? [#:bold? boolean?] -> bytes?
;;   Returns a fresh copy of the requested generated font table.
(define (fixture-table-bytes tag #:bold? [bold? #f])
  (bytes-copy (hash-ref (tables bold?) tag)))
