#lang racket/base

;;;
;;; Structured Geometry Validation
;;;

;; Checks points, colors, rectangles, vertex arrays, and lattice divisions.
;; Prepares bounded, ordered inputs for Skia's structured geometry operations.

(require racket/list racket/vector "check.rkt" "types.rkt" "../color.rkt")
(provide geometry-list geometry-budget geometry-points geometry-colors
         geometry-rectangle geometry-irect geometry-int geometry-vertices
         geometry-divisions geometry-source-bounds)

; geometry-list : symbol? (or/c list? vector?) -> list?
;   Normalizes ordered geometry input without changing element order.
(define (geometry-list who v)
  (cond [(list? v) v] [(vector? v) (vector->list v)]
        [else (raise-argument-error who "list? or vector?" v)]))

; geometry-budget : symbol? exact-nonnegative-integer? exact-nonnegative-integer? -> void?
;   Checks native signed-count bounds and explicit geometry-buffer byte cost.
(define (geometry-budget who count bytes)
  (unless (and (exact-nonnegative-integer? count) (<= count #x7fffffff)
               (exact-nonnegative-integer? bytes) (<= bytes (current-skia-byte-limit)))
    (raise-arguments-error who "buffer exceeds native count or current-skia-byte-limit"
                           "count" count "bytes" bytes))
  (void))

; snapshot : list? -> vector?
;   Copies ordered entries into a detached immutable vector.
(define (snapshot xs) (vector->immutable-vector (list->vector xs)))

; geometry-points : symbol? any/c [any/c] -> vector?
;   Copies budgeted x/y pairs into immutable vectors, optionally requiring an exact point count.
(define (geometry-points who v [expected #f])
  (define xs (geometry-list who v))
  (define n (length xs))
  (geometry-budget who n (* n 8))
  (when (and expected (not (= n expected)))
    (raise-arguments-error who "wrong number of points" "expected" expected "given" n))
  (snapshot
   (for/list ([p (in-list xs)])
     (define xy (geometry-list who p))
     (unless (= (length xy) 2) (raise-argument-error who "two-element point" p))
     (vector-immutable (scalar who (car xy)) (scalar who (cadr xy))))))

; geometry-colors : symbol? any/c exact-nonnegative-integer? -> (or/c #f vector?)
;   Copies optional packed ARGB colors with one entry per required vertex or cell.
(define (geometry-colors who v n)
  (and v
       (let ([xs (geometry-list who v)])
         (geometry-budget who (length xs) (* (length xs) 4))
         (unless (= (length xs) n)
           (raise-arguments-error who "wrong number of colors" "expected" n "given" (length xs)))
         (snapshot (map color->argb xs)))))

; geometry-rectangle : symbol? any/c -> vector?
;   Checks and snapshots x/y/width/height bounds while validating native edge coordinates.
(define (geometry-rectangle who v)
  (define xs (geometry-list who v))
  (unless (= (length xs) 4) (raise-argument-error who "(x y width height) list/vector" v))
  (define r (apply rect who xs))
  (vector-immutable (sk-rect-left r) (sk-rect-top r)
                    (- (sk-rect-right r) (sk-rect-left r))
                    (- (sk-rect-bottom r) (sk-rect-top r))))
;; Reserve SkRegion's INT_MAX sentinel and keep widths/differences in int32.
;; This is deliberately narrower than all int32 coordinates.

; region-coordinate-limit : exact-positive-integer?
;   Uses a conservative signed region-coordinate bound to keep native endpoint arithmetic in range.
(define region-coordinate-limit #x3fffffff)

; geometry-int : symbol? exact-integer? -> exact-integer?
;   Checks a region coordinate against the conservative symmetric integer limit.
(define (geometry-int who v)
  (unless (and (exact-integer? v) (<= (- region-coordinate-limit) v region-coordinate-limit))
    (raise-argument-error who "exact integer in [-1073741823, 1073741823]" v))
  v)

; geometry-irect : symbol? any/c -> vector?
;   Checks integer x/y/width/height and derived endpoints, allowing empty extents.
(define (geometry-irect who v)
  (define xs (geometry-list who v))
  (unless (= (length xs) 4) (raise-argument-error who "integer (x y width height) list/vector" v))
  (define x (geometry-int who (car xs)))
  (define y (geometry-int who (cadr xs)))
  (define w (caddr xs))
  (define h (cadddr xs))
  (unless (and (exact-nonnegative-integer? w) (exact-nonnegative-integer? h))
    (raise-argument-error who "nonnegative exact rectangle sizes" v))
  (geometry-int who (+ x w)) (geometry-int who (+ y h))
  (vector-immutable x y w h))

; geometry-source-bounds : symbol? vector? integer? integer? -> vector?
;   Requires a nonempty source rectangle entirely inside the image.
(define (geometry-source-bounds who box width height)
  (unless (and (> (vector-ref box 2) 0) (> (vector-ref box 3) 0)
               (<= 0 (vector-ref box 0)) (<= 0 (vector-ref box 1))
               (<= (+ (vector-ref box 0) (vector-ref box 2)) width)
               (<= (+ (vector-ref box 1) (vector-ref box 3)) height))
    (raise-arguments-error who "source rectangle must be nonempty and inside the image"
                           "rectangle" box "image width" width "image height" height))
  box)

; geometry-vertices : symbol? symbol? any/c any/c any/c any/c -> (values vector? any/c any/c any/c)
;   Checks mesh topology, matching attribute arrays, uint16 indices, and aggregate native buffer
;   cost.
(define (geometry-vertices who mode positions tex colors indices)
  (unless (memq mode '(triangles triangle-strip triangle-fan))
    (raise-argument-error who "'triangles, 'triangle-strip, or 'triangle-fan" mode))
  (define ps (geometry-points who positions))
  (define n (vector-length ps))
  (define ts (and tex (geometry-points who tex n)))
  (define cs (geometry-colors who colors n))
  (define is
    (and indices
         (let ([xs (geometry-list who indices)])
           (geometry-budget who (length xs) (* 2 (length xs)))
           (snapshot
            (for/list ([i (in-list xs)])
              (unless (and (exact-nonnegative-integer? i) (< i n) (<= i #xffff))
                (raise-argument-error who "uint16 index within the vertex array" i))
              i)))))
  (define count (if is (vector-length is) n))
  (unless (and (<= 3 n 65536) (>= count 3) (or (not (eq? mode 'triangles)) (zero? (modulo count 3))))
    (raise-arguments-error
     who "3..65536 vertices and at least three indices; triangle count must be divisible by three"
                           "vertices" n "submitted count" count))
  (geometry-budget who n (+ (* n (+ 8 (if ts 8 0) (if cs 4 0))) (if is (* count 2) 0)))
  (values ps ts cs is))

; geometry-divisions : symbol? any/c -> vector?
;   Copies strictly increasing checked integer lattice divisions in source order.
(define (geometry-divisions who divs)
  (define xs (geometry-list who divs))
  (geometry-budget who (length xs) (* (length xs) 4))
  (for ([x (in-list xs)]) (geometry-int who x))
  (for ([a (in-list xs)] [b (in-list (if (null? xs) '() (cdr xs)))])
    (unless (< a b) (raise-argument-error who "strictly increasing integer divisions" divs)))
  (snapshot xs))
