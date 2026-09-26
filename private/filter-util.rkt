#lang racket/base
(require racket/list racket/match "check.rkt" "types.rkt")
(provide filter-rectangle optional-filter-crop filter-kernel filter-channel
         filter-tile-mode filter-point3 filter-light-parameters filter-spot-parameters
         filter-input-list filter-float)

;; These checks do not load Skia. Round before validating geometry so a positive
;; extent that disappears at the native float precision cannot pass unnoticed.
(define (filter-float who value)
  (scalar who value)
  (floating-point-bytes->real (real->floating-point-bytes value 4 #f) #f))

(define (filter-rectangle who value #:positive? [positive? #f])
  (define parts
    (cond [(vector? value) (vector->list value)]
          [(list? value) value]
          [else (raise-argument-error who "(list x y width height) or four-element vector" value)]))
  (match parts
    [(list x y width height)
     (define fx (filter-float who x))
     (define fy (filter-float who y))
     (define w (nonnegative-scalar who width))
     (define h (nonnegative-scalar who height))
     (define right (filter-float who (+ fx w)))
     (define bottom (filter-float who (+ fy h)))
     (when (or (and (> w 0) (<= right fx)) (and (> h 0) (<= bottom fy))
               (and positive? (or (= right fx) (= bottom fy))))
       (raise-arguments-error who "rectangle must have representable positive extents"
                              "rectangle" value))
     (make-sk-rect fx fy right bottom)]
    [_ (raise-argument-error who "(list x y width height) or four-element vector" value)]))

(define (optional-filter-crop who value)
  (and value (filter-rectangle who value)))

(define (filter-channel who v)
  (choice who v (hasheq 'red 0 'green 1 'blue 2 'alpha 3)))

(define (filter-tile-mode who mode crop #:require-crop? [require-crop? #f])
  (define result (choice who mode tile-mode-values))
  (when (eq? mode 'mirror)
    (raise-arguments-error who "'mirror is not supported for this filter by pinned m119 Skia"
                           "tile-mode" mode))
  ;; Unlike blur's legacy no-crop branch, m119 convolution silently ignores a
  ;; non-decal tile mode without a crop. Refuse that ambiguous request.
  (when (and require-crop? (not crop) (not (eq? mode 'decal)))
    (raise-arguments-error who "non-decal convolution tiling requires #:crop"
                           "tile-mode" mode))
  result)

(define (filter-input-list who inputs)
  (define count
    (cond [(list? inputs) (length inputs)] [(vector? inputs) (vector-length inputs)]
          [else (raise-argument-error who "nonempty list or vector of filter inputs" inputs)]))
  (unless (<= 1 count 2147483647)
    (raise-argument-error who "nonempty list or vector with an int32-sized count" inputs))
  ;; Bound the pointer array before copying vectors or constructing native data.
  (unless (<= (* count 8) (current-skia-byte-limit))
    (error who "filter input array exceeds current-skia-byte-limit"))
  (if (vector? inputs) (vector->list inputs) inputs))

(define (filter-kernel who width height kernel offset)
  (for ([n (in-list (list width height))])
    (unless (and (exact-integer? n) (<= 1 n 2048))
      (raise-argument-error who "exact kernel dimension from 1 through 2048" n)))
  (define count (* width height))
  (unless (<= (* count 4) (current-skia-byte-limit))
    (error who "convolution kernel exceeds current-skia-byte-limit"))
  (define size
    (cond [(list? kernel) (length kernel)] [(vector? kernel) (vector-length kernel)]
          [else (raise-argument-error who "flat row-major list or vector of kernel coefficients" kernel)]))
  (unless (= count size)
    (raise-arguments-error who "kernel coefficient count does not equal width * height"
                           "required" count "given" size))
  (define xy
    (cond [(not offset) (list (quotient width 2) (quotient height 2))]
          [(vector? offset) (vector->list offset)] [else offset]))
  (match-define (list ox oy)
    (match xy
      [(list (? exact-nonnegative-integer? x) (? exact-nonnegative-integer? y))
       (unless (and (< x width) (< y height))
         (raise-arguments-error who "kernel offset lies outside the kernel" "offset" offset))
       (list x y)]
      [_ (raise-argument-error who "#f or a pair of exact nonnegative kernel indices" offset)]))
  (values (make-sk-isize width height) (make-sk-ipoint ox oy)
          (for/list ([v (if (vector? kernel) (in-vector kernel) (in-list kernel))])
            (filter-float who v))))

(define (filter-point3 who value #:direction? [direction? #f])
  (define parts (if (vector? value) (vector->list value) value))
  (match parts
    [(list x y z)
     (define xyz (map (lambda (v) (filter-float who v)) (list x y z)))
     (when (and direction? (andmap zero? xyz))
       (raise-arguments-error who "light direction must be nonzero" "direction" value))
     (apply make-sk-point3 xyz)]
    [_ (raise-argument-error who "(list x y z) or three-element vector" value)]))

(define (filter-light-parameters who surface-scale coefficient shininess)
  (define s (filter-float who surface-scale))
  (define k (filter-float who (nonnegative-scalar who coefficient)))
  (define shine
    (and shininess
         (let ([v (filter-float who shininess)])
           (unless (<= 1 v 128)
             (raise-argument-error who "shininess from 1 through 128" shininess))
           v)))
  (values s k shine))

(define (filter-spot-parameters who location target exponent cutoff)
  (define loc (filter-point3 who location))
  (define dst (filter-point3 who target))
  (when (and (= (sk-point3-x loc) (sk-point3-x dst))
             (= (sk-point3-y loc) (sk-point3-y dst))
             (= (sk-point3-z loc) (sk-point3-z dst)))
    (raise-arguments-error who "spotlight location and target must differ"
                           "location" location "target" target))
  (define e (filter-float who exponent))
  (define c (filter-float who cutoff))
  (unless (<= 0 e 128) (raise-argument-error who "spot exponent from 0 through 128" exponent))
  (unless (<= 0 c 90) (raise-argument-error who "cutoff angle from 0 through 90 degrees" cutoff))
  (values loc dst e c))
