#lang racket/base
;; Pure argument/result arithmetic. No native image or GPU is created here.
(require racket/list racket/vector "check.rkt")
(provide operation-rectangle operation-subset operation-budget
         operation-result-geometry operation-precision-compatible?)

(define (operation-rectangle who value)
  (define xs (cond [(list? value) value] [(vector? value) (vector->list value)]
                  [else (raise-argument-error who "(list x y width height) or vector of four integers" value)]))
  (unless (and (= (length xs) 4) (andmap exact-integer? xs))
    (raise-argument-error who "four exact integers (x y width height)" value))
  (define x (car xs)) (define y (cadr xs))
  (define w (caddr xs)) (define h (cadddr xs))
  (unless (and (<= 1 w 32768) (<= 1 h 32768)
               (<= (- (expt 2 31)) x (+ x w) (sub1 (expt 2 31)))
               (<= (- (expt 2 31)) y (+ y h) (sub1 (expt 2 31))))
    (raise-arguments-error who "nonempty rectangle exceeds supported dimensions or signed 32-bit edges"
                           "rectangle" value))
  (vector-immutable x y w h))

(define (operation-subset who value width height)
  (define r (operation-rectangle who (or value (vector 0 0 width height))))
  (unless (and (>= (vector-ref r 0) 0) (>= (vector-ref r 1) 0)
               (<= (+ (vector-ref r 0) (vector-ref r 2)) width)
               (<= (+ (vector-ref r 1) (vector-ref r 3)) height))
    (raise-arguments-error who "subset must be contained in the image"
                           "subset" value "image dimensions" (list width height)))
  r)

(define (operation-budget who width height [bytes-per-pixel 16])
  (unless (and (exact-integer? width) (<= 1 width 32768)
               (exact-integer? height) (<= 1 height 32768)
               (exact-integer? bytes-per-pixel) (<= 1 bytes-per-pixel 16))
    (raise-arguments-error who "invalid image dimensions or sample size"
                           "dimensions" (list width height) "bytes per pixel" bytes-per-pixel))
  (define size (* width height bytes-per-pixel))
  (unless (and (<= size #x7fffffff) (<= size (current-skia-byte-limit)))
    (error who "image/clip extent exceeds the byte limit or native signed allocation range"))
  size)

(define (operation-result-geometry who width height subset offset clip)
  (define r (operation-subset who subset width height))
  (unless (and (vector? offset) (= (vector-length offset) 2)
               (for/and ([v (in-vector offset)])
                 (and (exact-integer? v) (<= (- (expt 2 31)) v (sub1 (expt 2 31))))))
    (error who "invalid native filter offset"))
  (define c (operation-rectangle who clip))
  (define x (vector-ref offset 0)) (define y (vector-ref offset 1))
  (unless (and (<= (vector-ref c 0) x)
               (<= (vector-ref c 1) y)
               (<= (+ x (vector-ref r 2)) (+ (vector-ref c 0) (vector-ref c 2)))
               (<= (+ y (vector-ref r 3)) (+ (vector-ref c 1) (vector-ref c 3))))
    (error who "native filter result lies outside the requested clip"))
  (values r (vector-immutable x y)))

;; m119 color-type enum values. An explicit destination format authorizes
;; conversion; implicit materialization/filtering does not authorize narrowing.
(define (operation-precision-compatible? source result)
  (cond [(= source 16) (= result 16)]
        [(memv source '(14 15)) (and (memv result '(14 15 16)) #t)]
        [else #t]))
