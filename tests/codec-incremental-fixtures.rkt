#lang racket/base

;;;
;;; Codec Incremental Fixtures
;;;

;; Provides shared inputs and drawing fixtures for incremental PNG feeding, decode progress, and
;; detached snapshots.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
;; Original procedural PNG fixtures: no external images, fonts, zlib library or
;; native encoder is needed. Each IDAT ends at a DEFLATE stored-block boundary.
(require racket/list)
(provide incremental-fixture-parts incremental-fixture-bytes incremental-fixture-pixels
         incremental-fixture-width incremental-fixture-height png-chunk)

;;;
;;; Fixtures and Assertions
;;;

; incremental-fixture-width : exact-positive-integer?
;   Sets the noninterlaced incremental PNG width in pixels.
(define incremental-fixture-width 8)

; incremental-fixture-height : exact-positive-integer?
;   Sets the noninterlaced incremental PNG height in pixels.
(define incremental-fixture-height 6)

; be32 : exact-nonnegative-integer? -> bytes?
;   Encodes an unsigned 32-bit PNG field in network byte order.
(define (be32 n) (integer->integer-bytes n 4 #f #t))

; le16 : exact-nonnegative-integer? -> bytes?
;   Encodes an unsigned 16-bit stored-DEFLATE field in little-endian order.
(define (le16 n) (integer->integer-bytes n 2 #f #f))

; crc32 : bytes? -> exact-nonnegative-integer?
;   Computes the PNG CRC over a chunk type and payload.
(define (crc32 bytes)
  (bitwise-xor #xffffffff
    (for/fold ([crc #xffffffff]) ([b (in-bytes bytes)])
      (for/fold ([c (bitwise-xor crc b)]) ([_ (in-range 8)])
        (bitwise-xor (arithmetic-shift c -1) (if (odd? c) #xedb88320 0))))))

; png-chunk : bytes? bytes? -> bytes?
;   Frames a four-byte PNG chunk tag and payload with length and CRC.
(define (png-chunk tag payload)
  (bytes-append (be32 (bytes-length payload)) tag payload (be32 (crc32 (bytes-append tag payload)))))

; pixel : exact-nonnegative-integer? exact-nonnegative-integer? -> bytes?
;   Generates a coordinate-dependent opaque RGBA pixel to expose row-placement errors.
(define (pixel x y)
  (bytes (modulo (+ (* x 37) (* y 17)) 256)
         (modulo (+ (* x 13) (* y 53)) 256)
         (modulo (+ (* x 71) (* y 7)) 256) 255))

; incremental-fixture-pixels : [exact-positive-integer? exact-positive-integer?] -> bytes?
;   Produces tightly packed expected RGBA pixels in top-to-bottom row order.
(define (incremental-fixture-pixels [width 8] [height 6])
  (apply bytes-append (for*/list ([y (in-range height)] [x (in-range width)]) (pixel x y))))

; passes : (listof (listof exact-nonnegative-integer?))
;   Lists Adam7 passes as x-start, y-start, x-step, y-step in decoding order.
(define passes '((0 0 8 8) (4 0 8 8) (0 4 4 8) (2 0 4 4) (0 2 2 4) (1 0 2 2) (0 1 1 2)))

; adler : bytes? -> exact-nonnegative-integer?
;   Computes the Adler-32 checksum used by the fixture's zlib stream.
(define (adler bytes)
  (define-values (a b)
    (for/fold ([a 1] [b 0]) ([x (in-bytes bytes)])
      (define next (modulo (+ a x) 65521))
      (values next (modulo (+ b next) 65521))))
  (+ (arithmetic-shift b 16) a))

; incremental-fixture-parts : [#:interlaced? boolean?] -> (listof bytes?)
;   Splits a complete PNG into a header and independently feedable row or Adam7-pass chunks.
(define (incremental-fixture-parts #:interlaced? [interlaced? #f])
  (define width 8)
  (define height (if interlaced? 8 6))
  (define (row y [x0 0] [dx 1])
    (bytes-append #"\0" (apply bytes-append (for/list ([x (in-range x0 width dx)]) (pixel x y)))))
  (define raw
    (if interlaced?
        (for/list ([p (in-list passes)])
          (apply bytes-append (for/list ([y (in-range (cadr p) height (cadddr p))])
                                (row y (car p) (caddr p)))))
        (for/list ([y (in-range height)]) (row y))))
  (define count (length raw))
  (define checksum (be32 (adler (apply bytes-append raw))))
  (define header
    (bytes-append #"\211PNG\r\n\32\n"
      (png-chunk #"IHDR"
        (bytes-append (be32 width) (be32 height) (bytes 8 6 0 0 (if interlaced? 1 0))))))
  (cons header
    (for/list ([data (in-list raw)] [i (in-naturals)])
      (define n (bytes-length data))
      (define last? (= i (sub1 count)))
      (define zlib
        (bytes-append (if (zero? i) #"\170\1" #"")
          (bytes (if last? 1 0)) (le16 n) (le16 (- #xffff n)) data
          (if last? checksum #"")))
      (bytes-append (png-chunk #"IDAT" zlib) (if last? (png-chunk #"IEND" #"") #"")))))

; incremental-fixture-bytes : [#:interlaced? boolean?] -> bytes?
;   Concatenates the incremental pieces into one complete deterministic PNG.
(define (incremental-fixture-bytes #:interlaced? [interlaced? #f])
  (apply bytes-append (incremental-fixture-parts #:interlaced? interlaced?)))
