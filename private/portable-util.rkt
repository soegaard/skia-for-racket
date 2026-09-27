#lang racket/base
(require racket/list racket/vector
         "check.rkt" "geometry-util.rkt" "../color.rkt")
(provide image-grid-cell? image-grid-cell-row image-grid-cell-column
         image-grid-cell-kind image-grid-cell-source image-grid-cell-destination
         image-grid-cell-color image-nine-plan image-grid-plan->jsexpr
         portable-lattice-plan portable-filter portable-alpha portable-marker-boxes)

;; These cells are detached values, not native resources or editable commands.
;; Construction is private so source rectangles and shared edges stay checked.
(struct image-grid-cell (row column kind source destination color)
  #:transparent #:constructor-name make-cell)

(define (source-size who width height)
  (for ([v (in-list (list width height))])
    (geometry-int who v)
    (unless (positive? v) (raise-argument-error who "positive exact image dimensions" v))))
(define (portable-filter who filter)
  (unless (memq filter '(nearest linear))
    (raise-argument-error who "'nearest or 'linear" filter))
  filter)
(define (portable-alpha who alpha)
  (unless (byte? alpha) (raise-argument-error who "byte? (0 through 255)" alpha))
  alpha)
(define (float who x)
  ;; Store finite single-precision edge values, just as the native rects do.
  (define checked (scalar who x))
  (floating-point-bytes->real (real->floating-point-bytes checked 4 #f) #f))
(define (snapshot xs) (vector->immutable-vector (list->vector xs)))

(define (portable-marker-boxes who points size shape)
  (unless (memq shape '(circle square))
    (raise-argument-error who "'circle or 'square" shape))
  (define side (positive-scalar who size))
  (define ps (geometry-points who points))
  (geometry-budget who (vector-length ps) (* 24 (vector-length ps)))
  ;; Validate the complete batch, including arithmetic overflow, before drawing.
  (for/list ([p (in-vector ps)])
    (geometry-rectangle who
      (list (- (vector-ref p 0) (/ side 2))
            (- (vector-ref p 1) (/ side 2)) side side))))

(define (axis-edges who start end divisions d0 d1)
  ;; Alternating fixed / stretch spans. An undivided axis maps in its entirety.
  ;; This is the pinned SkLatticeIter set_points rule, not equal-size tiling.
  (define source (append (list start) (vector->list divisions) (list end)))
  (define spans (for/list ([a (in-list source)] [b (in-list (cdr source))]) (- b a)))
  (define fixed (for/sum ([s (in-list spans)] [i (in-naturals)] #:when (even? i)) s))
  (define stretch (- (- end start) fixed))
  (define length (- d1 d0))
  (define normal? (>= length fixed))
  (define factor (cond [(not normal?) (/ length fixed)]
                       [(positive? stretch) (/ (- length fixed) stretch)]
                       [else 0]))
  (define position d0)
  (define middle
    (for/list ([s (in-list (drop-right spans 1))] [i (in-naturals)])
      (define delta (cond [normal? (if (odd? i) (* factor s) s)]
                          [else (if (odd? i) 0 (* factor s))]))
      ;; Share rounded edges. Never independently round adjacent cell widths.
      (set! position (min d1 (max d0 (float who (+ position delta)))))
      position))
  (values (snapshot source) (snapshot (append (list d0) middle (list d1)))))

(define (nine-axis who length first last d0 d1)
  (define fixed (+ first (- length last)))
  (define available (- d1 d0))
  (define a (if (< available fixed)
                (+ d0 (* available (/ first fixed)))
                (+ d0 first)))
  (define b (if (< available fixed) a (- d1 (- length last))))
  (values (vector-immutable 0 first last length)
          (vector-immutable d0 (float who a) (float who b) d1)))

(define (make-grid who sx sy dx dy types colors)
  (define columns (sub1 (vector-length sx)))
  (define rows (sub1 (vector-length sy)))
  (define count (* columns rows))
  (geometry-budget who count (* 64 count))
  (for*/list ([row (in-range rows)] [column (in-range columns)])
    (define index (+ column (* row columns)))
    (define kind (if types (vector-ref types index) 'default))
    (make-cell
     row column kind
     (vector-immutable (vector-ref sx column) (vector-ref sy row)
                       (- (vector-ref sx (add1 column)) (vector-ref sx column))
                       (- (vector-ref sy (add1 row)) (vector-ref sy row)))
     (vector-immutable (vector-ref dx column) (vector-ref dy row)
                       (- (vector-ref dx (add1 column)) (vector-ref dx column))
                       (- (vector-ref dy (add1 row)) (vector-ref dy row)))
     (and (eq? kind 'fixed-color) (color->rgba (vector-ref colors index))))))

(define (image-nine-plan image-width image-height center x y width height)
  (define who 'image-nine-plan)
  (source-size who image-width image-height)
  (define c (geometry-source-bounds who (geometry-irect who center) image-width image-height))
  (define dst (geometry-rectangle who (list x y width height)))
  (define-values (sx dx)
    (nine-axis who image-width (vector-ref c 0) (+ (vector-ref c 0) (vector-ref c 2))
               (vector-ref dst 0) (+ (vector-ref dst 0) (vector-ref dst 2))))
  (define-values (sy dy)
    (nine-axis who image-height (vector-ref c 1) (+ (vector-ref c 1) (vector-ref c 3))
               (vector-ref dst 1) (+ (vector-ref dst 1) (vector-ref dst 3))))
  (make-grid who sx sy dx dy #f #f))

(define (portable-lattice-plan who image-width image-height xs ys bounds types colors dst)
  (source-size who image-width image-height)
  (define box (geometry-source-bounds who (geometry-irect who bounds) image-width image-height))
  (define xdivs (geometry-divisions who xs))
  (define ydivs (geometry-divisions who ys))
  (unless (positive? (+ (vector-length xdivs) (vector-length ydivs)))
    (raise-arguments-error who "at least one axis needs a division"))
  (for ([divs (in-list (list xdivs ydivs))] [axis '(0 1)] [extent '(2 3)])
    (for ([v (in-vector divs)])
      (unless (< (vector-ref box axis) v (+ (vector-ref box axis) (vector-ref box extent)))
        (raise-arguments-error who "divisions must lie strictly inside source bounds" "division" v))))
  (define count (* (add1 (vector-length xdivs)) (add1 (vector-length ydivs))))
  (geometry-budget who count (* 64 count))
  (define ts
    (and types
         (let ([ls (geometry-list who types)])
           (unless (= (length ls) count)
             (raise-arguments-error who "wrong cell-type count" "expected" count "given" (length ls)))
           (for ([t (in-list ls)])
             (unless (memq t '(default transparent fixed-color))
               (raise-argument-error who "default, transparent, or fixed-color cell" t)))
           (snapshot ls))))
  (define cs (geometry-colors who colors count))
  (when (and cs (not ts)) (raise-arguments-error who "colors require explicit cell types"))
  (when (and ts (for/or ([t (in-vector ts)]) (eq? t 'fixed-color)) (not cs))
    (raise-arguments-error who "fixed-color cells require colors"))
  (define d (geometry-rectangle who dst))
  (define-values (sx dx)
    (axis-edges who (vector-ref box 0) (+ (vector-ref box 0) (vector-ref box 2)) xdivs
                (vector-ref d 0) (+ (vector-ref d 0) (vector-ref d 2))))
  (define-values (sy dy)
    (axis-edges who (vector-ref box 1) (+ (vector-ref box 1) (vector-ref box 3)) ydivs
                (vector-ref d 1) (+ (vector-ref d 1) (vector-ref d 3))))
  (make-grid who sx sy dx dy ts cs))

(define (image-grid-plan->jsexpr plan)
  (unless (and (list? plan) (andmap image-grid-cell? plan))
    (raise-argument-error 'image-grid-plan->jsexpr "list of image-grid-cell? values" plan))
  (for/list ([cell (in-list plan)])
    (hasheq 'row (image-grid-cell-row cell) 'column (image-grid-cell-column cell)
            'kind (symbol->string (image-grid-cell-kind cell))
            'source (vector->list (image-grid-cell-source cell))
            'destination (vector->list (image-grid-cell-destination cell))
            'color (and (image-grid-cell-color cell) (color->argb (image-grid-cell-color cell))))))
