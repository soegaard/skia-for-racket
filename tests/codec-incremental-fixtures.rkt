#lang racket/base
;; Original procedural PNG fixtures: no external images, fonts, zlib library or
;; native encoder is needed. Each IDAT ends at a DEFLATE stored-block boundary.
(require racket/list)
(provide incremental-fixture-parts incremental-fixture-bytes incremental-fixture-pixels
         incremental-fixture-width incremental-fixture-height png-chunk)
(define incremental-fixture-width 8)
(define incremental-fixture-height 6)
(define (be32 n) (integer->integer-bytes n 4 #f #t))
(define (le16 n) (integer->integer-bytes n 2 #f #f))
(define (crc32 bytes)
  (bitwise-xor #xffffffff
    (for/fold ([crc #xffffffff]) ([b (in-bytes bytes)])
      (for/fold ([c (bitwise-xor crc b)]) ([_ (in-range 8)])
        (bitwise-xor (arithmetic-shift c -1) (if (odd? c) #xedb88320 0))))))
(define (png-chunk tag payload)
  (bytes-append (be32 (bytes-length payload)) tag payload (be32 (crc32 (bytes-append tag payload)))))
(define (pixel x y)
  (bytes (modulo (+ (* x 37) (* y 17)) 256)
         (modulo (+ (* x 13) (* y 53)) 256)
         (modulo (+ (* x 71) (* y 7)) 256) 255))
(define (incremental-fixture-pixels [width 8] [height 6])
  (apply bytes-append (for*/list ([y (in-range height)] [x (in-range width)]) (pixel x y))))
(define passes '((0 0 8 8) (4 0 8 8) (0 4 4 8) (2 0 4 4) (0 2 2 4) (1 0 2 2) (0 1 1 2)))
(define (adler bytes)
  (define-values (a b)
    (for/fold ([a 1] [b 0]) ([x (in-bytes bytes)])
      (define next (modulo (+ a x) 65521))
      (values next (modulo (+ b next) 65521))))
  (+ (arithmetic-shift b 16) a))
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
      (png-chunk #"IHDR" (bytes-append (be32 width) (be32 height) (bytes 8 6 0 0 (if interlaced? 1 0))))))
  (cons header
    (for/list ([data (in-list raw)] [i (in-naturals)])
      (define n (bytes-length data))
      (define last? (= i (sub1 count)))
      (define zlib
        (bytes-append (if (zero? i) #"\170\1" #"")
          (bytes (if last? 1 0)) (le16 n) (le16 (- #xffff n)) data
          (if last? checksum #"")))
      (bytes-append (png-chunk #"IDAT" zlib) (if last? (png-chunk #"IEND" #"") #"")))))
(define (incremental-fixture-bytes #:interlaced? [interlaced? #f])
  (apply bytes-append (incremental-fixture-parts #:interlaced? interlaced?)))
