#lang racket/base

;;;
;;; Typeface Metadata and Font Tables
;;;

;; Validates font styles, collection indices, table tags, and font data slices.
;; Supplies detached font metadata and safe table access for typeface operations.

;; Pure values and bounds checks. No font lookup, native initialization, or I/O.
(require racket/list "check.rkt")
(provide font-style? make-font-style font-style-weight font-style-width font-style-slant
         font-style-entry? font-style-entry-index font-style-entry-name font-style-entry-style
         make-font-style-entry-record font-table-tag font-table-tag->bytes
         typeface-index typeface-budget typeface-count typeface-input-bytes
         typeface-glyphs typeface-family-bytes typeface-slice check-font-style
         ttc-font-collection? ttc-member->sfnt)

;;;
;;; Detached Font Styles
;;;

(struct font-style (weight width slant) #:transparent #:constructor-name make-style)
;; Fields:
;;   weight: exact integer 0..1000, with 400 normal and 700 bold. width: exact width class 1..9,
;;   from ultra-condensed to ultra-expanded, with 5 normal. slant: 'upright, 'italic, or 'oblique.
;;   Named input weights and widths are normalized to these numeric classes. Field order matches
;;   the weight/width/slant tuple used by matching and metadata APIs.

(struct font-style-entry (index name style) #:transparent
  #:constructor-name make-font-style-entry-record)
;; Fields:
;;   index: exact nonnegative, zero-based position in the originating style set. name: copied
;;   style-name string. style: font-style snapshot. The entry remains meaningful as metadata after
;;   the native style set is closed; the index is not a global typeface identifier.

; make-font-style : [#:weight (or/c (integer-in 0 1000) 'invisible 'thin 'extra-light 'light 'normal
;   'medium 'semi-bold 'bold 'extra-bold 'black 'extra-black)] [#:width (or/c (integer-in 1 9)
;   'ultra-condensed 'extra-condensed 'condensed 'semi-condensed 'normal 'semi-expanded 'expanded
;   'extra-expanded 'ultra-expanded)] [#:slant (or/c 'upright 'italic 'oblique)] -> font-style?
;   Returns a font-style value, normalizing named weights and widths to their numeric classes.
(define (make-font-style #:weight [weight 'normal] #:width [width 'normal]
                         #:slant [slant 'upright])
  (define who 'make-font-style)
  (define w (font-weight who weight))
  (define d (font-width who width))
  (choice who slant font-slant-values)
  (make-style w d slant))

; check-font-style : symbol? any/c -> font-style?
;   Requires the checked font-style value used by typeface matching.
(define (check-font-style who value)
  (unless (font-style? value) (raise-argument-error who "font-style?" value))
  value)

;;;
;;; Input Bounds and Native Counts
;;;

; typeface-index : symbol? exact-nonnegative-integer? -> exact-nonnegative-integer?
;   Checks a collection index representable by a native signed 32-bit integer.
(define (typeface-index who index)
  (unless (and (exact-integer? index) (<= 0 index #x7fffffff))
    (raise-argument-error who "nonnegative signed 32-bit integer" index))
  index)

; typeface-budget : symbol? exact-nonnegative-integer? -> exact-nonnegative-integer?
;   Checks font input, output, or temporary allocation against the current byte limit.
(define (typeface-budget who bytes)
  (unless (and (exact-nonnegative-integer? bytes) (<= bytes (current-skia-byte-limit)))
    (raise-arguments-error who "data exceeds current-skia-byte-limit"
                           "required bytes" bytes "limit" (current-skia-byte-limit)))
  bytes)

; typeface-count : symbol? exact-nonnegative-integer? [exact-nonnegative-integer?] ->
;   exact-nonnegative-integer?
;   Checks a native signed-int count and its optional per-element allocation cost.
(define (typeface-count who count [element-size 0])
  (unless (and (exact-integer? count) (<= 0 count #x7fffffff))
    (error who "invalid native count: ~a" count))
  (typeface-budget who (* count element-size))
  count)

; typeface-input-bytes : symbol? bytes? -> bytes?
;   Copies nonempty bounded font data so later caller mutation cannot affect native typeface
;   construction.
(define (typeface-input-bytes who data)
  (unless (bytes? data) (raise-argument-error who "bytes?" data))
  (when (zero? (bytes-length data))
    (raise-arguments-error who "font data is empty"))
  (typeface-budget who (bytes-length data))
  ;; The eventual SkData owns another copy; no pointer into caller-owned bytes
  ;; is installed in a typeface, even if the caller later mutates its bytes.
  (bytes-copy data))

; typeface-family-bytes : symbol? string? -> bytes?
;   Encodes a NUL-free family name as budgeted, NUL-terminated UTF-8 for native matching.
(define (typeface-family-bytes who name)
  (nul-free-string who name "font family string")
  ;; Bound the input before allocating its UTF-8 representation as well.
  (typeface-budget who (string-length name))
  (define utf8 (string->bytes/utf-8 name))
  (typeface-budget who (add1 (bytes-length utf8)))
  (nul-terminated-bytes utf8))

; typeface-glyphs : symbol? (or/c list? vector?) -> (listof exact-nonnegative-integer?)
;   Checks unsigned 16-bit glyph IDs and the storage needed for glyphs and adjacent-pair kerning
;   results.
(define (typeface-glyphs who glyphs)
  (define n
    (cond [(vector? glyphs) (vector-length glyphs)]
          [(list? glyphs) (length glyphs)]
          [else (raise-argument-error who "list or vector of glyph IDs" glyphs)]))
  (typeface-count who n)
  (typeface-budget who (+ (* n 2) (* (max 0 (sub1 n)) 4)))
  (for/list ([g (if (vector? glyphs) (in-vector glyphs) (in-list glyphs))])
    (unless (and (exact-integer? g) (<= 0 g #xffff))
      (raise-argument-error who "unsigned 16-bit glyph ID" g))
    g))

; typeface-slice : symbol? exact-nonnegative-integer? exact-nonnegative-integer? (or/c #f
;   exact-nonnegative-integer?) -> (values exact-nonnegative-integer? exact-nonnegative-integer?)
;   Returns the checked start and exclusive end of a font-table byte slice; false end means the
;   table size.
(define (typeface-slice who size start end)
  (unless (exact-nonnegative-integer? start)
    (raise-argument-error who "exact-nonnegative-integer? for #:start" start))
  (unless (or (not end) (exact-nonnegative-integer? end))
    (raise-argument-error who "#f or exact-nonnegative-integer? for #:end" end))
  (define stop (or end size))
  (unless (<= start stop size)
    (raise-arguments-error who "slice must lie within the table (end is exclusive)"
                           "table size" size "start" start "end" stop))
  (typeface-budget who (- stop start))
  (values start stop))


;;;
;;; Standalone TTC Member Extraction
;;;

;; Pinned m119's CoreText backend rejects nonzero TTC indices, while index zero
;; goes through a singular-descriptor API that rejected the valid generated TTC
;; during host acceptance. Keep the public byte+index contract portable by
;; extracting the selected member into an ordinary standalone SFNT. This is
;; exact table re-wrapping, not font fallback.

; ttc-font-collection? : any/c -> boolean?
;   Recognizes the TTC header before attempting collection-member extraction.
(define (ttc-font-collection? data)
  (and (bytes? data) (>= (bytes-length data) 4)
       (bytes=? (subbytes data 0 4) #"ttcf")))

; align4 : exact-nonnegative-integer? -> exact-nonnegative-integer?
;   Rounds a font-table byte count up to its four-byte storage boundary.
(define (align4 n) (* 4 (quotient (+ n 3) 4)))

; bytes-u16 : symbol? bytes? exact-nonnegative-integer? -> exact-nonnegative-integer?
;   Reads a bounded big-endian unsigned 16-bit field from font data.
(define (bytes-u16 who data offset)
  (unless (<= (+ offset 2) (bytes-length data))
    (error who "truncated font data at byte ~a" offset))
  (integer-bytes->integer data #f #t offset (+ offset 2)))

; bytes-u32 : symbol? bytes? exact-nonnegative-integer? -> exact-nonnegative-integer?
;   Reads a bounded big-endian unsigned 32-bit field from font data.
(define (bytes-u32 who data offset)
  (unless (<= (+ offset 4) (bytes-length data))
    (error who "truncated font data at byte ~a" offset))
  (integer-bytes->integer data #f #t offset (+ offset 4)))

; put-u32! : bytes? exact-nonnegative-integer? exact-integer? -> void?
;   Writes the low 32 bits in big-endian order for SFNT directory and checksum fields.
(define (put-u32! out offset value)
  (bytes-copy! out offset (integer->integer-bytes (bitwise-and value #xffffffff) 4 #f #t)))

; sfnt-checksum : bytes? -> exact-nonnegative-integer?
;   Sums big-endian 32-bit words modulo 2^32, treating the last partial word as zero-padded.
(define (sfnt-checksum data)
  ;; OpenType checksums pad the final 32-bit word with zeros without extending
  ;; the table itself.
  (for/fold ([sum 0]) ([i (in-range 0 (align4 (bytes-length data)) 4)])
    (define word
      (for/fold ([n 0]) ([j (in-range 4)])
        (+ (arithmetic-shift n 8)
           (if (< (+ i j) (bytes-length data)) (bytes-ref data (+ i j)) 0))))
    (bitwise-and #xffffffff (+ sum word))))

; ttc-member->sfnt : symbol? bytes? exact-nonnegative-integer? -> bytes?
;   Extracts one validated TTC member as an immutable standalone font, rebasing aligned table
;   offsets and recomputing table and whole-font checksums.
(define (ttc-member->sfnt who data index)
  (unless (bytes? data) (raise-argument-error who "bytes?" data))
  (typeface-budget who (bytes-length data))
  (define i (typeface-index who index))
  (unless (ttc-font-collection? data)
    (raise-arguments-error who "TTC member extraction requires TrueType Collection data"
                           "index" i))
  (define version (bytes-u32 who data 4))
  (unless (memv version '(#x00010000 #x00020000))
    (error who "unsupported TTC version: #x~x" version))
  (define faces (bytes-u32 who data 8))
  (unless (and (positive? faces) (<= faces #x7fffffff))
    (error who "invalid TTC face count: ~a" faces))
  (define offsets-end (+ 12 (* faces 4)))
  (define header-end (+ offsets-end (if (= version #x00020000) 12 0)))
  (unless (<= header-end (bytes-length data))
    (error who "truncated TTC header"))
  (unless (< i faces)
    (raise-arguments-error who "collection index out of range"
                           "index" i "count" faces))
  (define face-offset (bytes-u32 who data (+ 12 (* i 4))))
  (unless (and (zero? (modulo face-offset 4))
               (<= (+ face-offset 12) (bytes-length data)))
    (error who "invalid TTC member offset: ~a" face-offset))
  (define sfnt-version (subbytes data face-offset (+ face-offset 4)))
  (unless (member sfnt-version (list #"\0\1\0\0" #"OTTO" #"true" #"typ1") bytes=?)
    (error who "unsupported SFNT flavor in TTC member"))
  (define table-count (bytes-u16 who data (+ face-offset 4)))
  (unless (and (positive? table-count) (<= table-count 4095))
    (error who "invalid SFNT table count in TTC member: ~a" table-count))
  (typeface-count who table-count 16)
  (define directory-end (+ face-offset 12 (* table-count 16)))
  (unless (<= directory-end (bytes-length data))
    (error who "truncated TTC member table directory"))
  (define seen (make-hash))
  (define tables
    (for/list ([n (in-range table-count)])
      (define entry (+ face-offset 12 (* n 16)))
      (define tag (subbytes data entry (+ entry 4)))
      (when (hash-ref seen tag #f)
        (error who "duplicate SFNT table tag in TTC member: ~s" tag))
      (hash-set! seen tag #t)
      (define source (bytes-u32 who data (+ entry 8)))
      (define length (bytes-u32 who data (+ entry 12)))
      (unless (<= source (+ source length) (bytes-length data))
        (error who "SFNT table lies outside TTC data: ~s" tag))
      (define payload (subbytes data source (+ source length)))
      ;; head.checkSumAdjustment is zero while computing both the table and full
      ;; standalone-font checksums.
      (define normalized
        (if (bytes=? tag #"head")
            (let ([copy (bytes-copy payload)])
              (unless (>= length 12) (error who "truncated head table"))
              (bytes-copy! copy 8 #"\0\0\0\0")
              copy)
            payload))
      (cons tag normalized)))
  (define first-table (+ 12 (* table-count 16)))
  (define total-size
    (for/fold ([pos first-table]) ([table (in-list tables)])
      (+ pos (align4 (bytes-length (cdr table))))))
  (typeface-budget who total-size)
  (define out (make-bytes total-size 0))
  (bytes-copy! out 0 sfnt-version)
  (bytes-copy! out 4 (integer->integer-bytes table-count 2 #f #t))
  (define power (sub1 (integer-length table-count)))
  (define search-range (* 16 (arithmetic-shift 1 power)))
  (bytes-copy! out 6 (integer->integer-bytes search-range 2 #f #t))
  (bytes-copy! out 8 (integer->integer-bytes power 2 #f #t))
  (bytes-copy! out 10 (integer->integer-bytes (- (* 16 table-count) search-range) 2 #f #t))
  (define head-offset #f)
  (for/fold ([pos first-table]) ([table (in-list tables)] [n (in-naturals)])
    (define tag (car table))
    (define payload (cdr table))
    (define entry (+ 12 (* n 16)))
    (bytes-copy! out entry tag)
    (put-u32! out (+ entry 4) (sfnt-checksum payload))
    (put-u32! out (+ entry 8) pos)
    (put-u32! out (+ entry 12) (bytes-length payload))
    (bytes-copy! out pos payload)
    (when (bytes=? tag #"head") (set! head-offset pos))
    (+ pos (align4 (bytes-length payload))))
  (unless head-offset (error who "TTC member has no head table"))
  (put-u32! out (+ head-offset 8)
            (- #xb1b0afba (sfnt-checksum out)))
  (bytes->immutable-bytes out))

;;;
;;; Font Table Tags
;;;

;; Table tags are four bytes in big-endian order, NOT native-endian strings.
;; Integers preserve every uint32 tag; strings are the convenient Latin-1 form.

; font-table-tag : (or/c (integer-in 0 4294967295) bytes? string?) -> (integer-in 0 4294967295)
;   Returns a packed four-byte table tag.
(define (font-table-tag value)
  (cond
    [(exact-integer? value) (uint32 'font-table-tag value)]
    [else
     (define bs
       (cond [(bytes? value) value]
             [(and (string? value) (= 4 (string-length value))
                   (for/and ([c (in-string value)]) (<= (char->integer c) 255)))
              (string->bytes/latin-1 value)]
             [else
              (raise-argument-error 'font-table-tag
                                    "uint32, four bytes, or four Latin-1 characters" value)]))
     (unless (= (bytes-length bs) 4)
       (raise-argument-error 'font-table-tag "exactly four tag bytes" value))
     (integer-bytes->integer bs #f #t)]))

; font-table-tag->bytes : (integer-in 0 4294967295) -> (and/c bytes? immutable?)
;   Returns the immutable four-byte representation of the packed integer tag.
(define (font-table-tag->bytes tag)
  (bytes->immutable-bytes (integer->integer-bytes (uint32 'font-table-tag->bytes tag) 4 #f #t)))
