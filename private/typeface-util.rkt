#lang racket/base
;; Pure values and bounds checks. No font lookup, native initialization, or I/O.
(require racket/list "check.rkt")
(provide font-style? make-font-style font-style-weight font-style-width font-style-slant
         font-style-entry? font-style-entry-index font-style-entry-name font-style-entry-style
         make-font-style-entry-record font-table-tag font-table-tag->bytes
         typeface-index typeface-budget typeface-count typeface-input-bytes
         typeface-glyphs typeface-family-bytes typeface-slice check-font-style
         ttc-font-collection? ttc-member->sfnt)

(struct font-style (weight width slant) #:transparent #:constructor-name make-style)
(struct font-style-entry (index name style) #:transparent
  #:constructor-name make-font-style-entry-record)
(define (make-font-style #:weight [weight 'normal] #:width [width 'normal]
                         #:slant [slant 'upright])
  (define who 'make-font-style)
  (define w (font-weight who weight))
  (define d (font-width who width))
  (choice who slant font-slant-values)
  (make-style w d slant))
(define (check-font-style who value)
  (unless (font-style? value) (raise-argument-error who "font-style?" value))
  value)

(define (typeface-index who index)
  (unless (and (exact-integer? index) (<= 0 index #x7fffffff))
    (raise-argument-error who "nonnegative signed 32-bit integer" index))
  index)
(define (typeface-budget who bytes)
  (unless (and (exact-nonnegative-integer? bytes) (<= bytes (current-skia-byte-limit)))
    (raise-arguments-error who "data exceeds current-skia-byte-limit"
                           "required bytes" bytes "limit" (current-skia-byte-limit)))
  bytes)
(define (typeface-count who count [element-size 0])
  (unless (and (exact-integer? count) (<= 0 count #x7fffffff))
    (error who "invalid native count: ~a" count))
  (typeface-budget who (* count element-size))
  count)
(define (typeface-input-bytes who data)
  (unless (bytes? data) (raise-argument-error who "bytes?" data))
  (when (zero? (bytes-length data))
    (raise-arguments-error who "font data is empty"))
  (typeface-budget who (bytes-length data))
  ;; The eventual SkData owns another copy; no pointer into caller-owned bytes
  ;; is installed in a typeface, even if the caller later mutates its bytes.
  (bytes-copy data))
(define (typeface-family-bytes who name)
  (nul-free-string who name "font family string")
  ;; Bound the input before allocating its UTF-8 representation as well.
  (typeface-budget who (string-length name))
  (define utf8 (string->bytes/utf-8 name))
  (typeface-budget who (add1 (bytes-length utf8)))
  (nul-terminated-bytes utf8))
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


;; Pinned m119's CoreText backend rejects nonzero TTC indices, while index zero
;; goes through a singular-descriptor API that rejected the valid generated TTC
;; during host acceptance. Keep the public byte+index contract portable by
;; extracting the selected member into an ordinary standalone SFNT. This is
;; exact table re-wrapping, not font fallback.
(define (ttc-font-collection? data)
  (and (bytes? data) (>= (bytes-length data) 4)
       (bytes=? (subbytes data 0 4) #"ttcf")))
(define (align4 n) (* 4 (quotient (+ n 3) 4)))
(define (bytes-u16 who data offset)
  (unless (<= (+ offset 2) (bytes-length data))
    (error who "truncated font data at byte ~a" offset))
  (integer-bytes->integer data #f #t offset (+ offset 2)))
(define (bytes-u32 who data offset)
  (unless (<= (+ offset 4) (bytes-length data))
    (error who "truncated font data at byte ~a" offset))
  (integer-bytes->integer data #f #t offset (+ offset 4)))
(define (put-u32! out offset value)
  (bytes-copy! out offset (integer->integer-bytes (bitwise-and value #xffffffff) 4 #f #t)))
(define (sfnt-checksum data)
  ;; OpenType checksums pad the final 32-bit word with zeros without extending
  ;; the table itself.
  (for/fold ([sum 0]) ([i (in-range 0 (align4 (bytes-length data)) 4)])
    (define word
      (for/fold ([n 0]) ([j (in-range 4)])
        (+ (arithmetic-shift n 8)
           (if (< (+ i j) (bytes-length data)) (bytes-ref data (+ i j)) 0))))
    (bitwise-and #xffffffff (+ sum word))))
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

;; Table tags are four bytes in big-endian order, NOT native-endian strings.
;; Integers preserve every uint32 tag; strings are the convenient Latin-1 form.
(define (font-table-tag value)
  (cond
    [(exact-integer? value) (uint32 'font-table-tag value)]
    [else
     (define bs
       (cond [(bytes? value) value]
             [(and (string? value) (= 4 (string-length value))
                   (for/and ([c (in-string value)]) (<= (char->integer c) 255)))
              (string->bytes/latin-1 value)]
             [else (raise-argument-error 'font-table-tag "uint32, four bytes, or four Latin-1 characters" value)]))
     (unless (= (bytes-length bs) 4)
       (raise-argument-error 'font-table-tag "exactly four tag bytes" value))
     (integer-bytes->integer bs #f #t)]))
(define (font-table-tag->bytes tag)
  (bytes->immutable-bytes (integer->integer-bytes (uint32 'font-table-tag->bytes tag) 4 #f #t)))
