#lang racket/base

;;;
;;; Path and Shape Operations
;;;

;; Extends path construction, geometric inspection, paint queries, and region and rounded-rectangle
;; operations.
;; This public layer supplies higher-level geometry operations while preserving the core resource
;; and native-coordinate checks.

;;;
;;; Imports and Exports
;;;

;; Geometry completion. Owned paths/regions use the existing lifetime system;
;; returned coordinates and rounded rectangles contain no borrowed pointers.
(require ffi/unsafe racket/list racket/vector
         "private/core.rkt" "private/native.rkt" "private/types.rkt"
         "private/check.rkt" "private/filter-util.rkt" "private/geometry-util.rkt"
         "private/geometry-completion-util.rkt" "private/lifetime.rkt"
         "private/path-matrix.rkt" "geometry-primitives.rkt" "canvas-primitives.rkt"
         "matrix.rkt"
         (only-in (submod "private/core.rkt" geometry-internals)
                  path-h paint-h region-resource-handle call-with-native-temporary))
(provide path-arc-to! path-rarc-to! path-arc-to-oval! path-tangent-arc-to! path-add-arc!
         path-add-rect-start! path-add-rounded-rect! path-add-polygon! path-add-transformed!
         path-rewind! path-verbs path-segment-kinds path-fill-bounds
         path-as-line path-as-oval path-as-rectangle path-as-rounded-rect
         path-rectangle? path-rectangle-bounds path-rectangle-closed? path-rectangle-direction
         conic->quadratics path-combine current-path-operation-limit
         paint-style paint-stroke-width paint-cap paint-join paint-miter-limit
         paint-antialias? paint-dither? paint-set-dither! paint-reset!
         paint-blend-mode-or-src-over paint->fill-path
         region-intersects-rect? region-quick-contains-rect? region-quick-reject-rect?
         region-quick-reject? region-clear! region-set-rect! region-op-rect
         region-clipped-rectangles in-region-clipped-rectangles region-spans in-region-spans
         make-nine-patch-rounded-rect make-empty-rounded-rect rounded-rect-normalize
         rounded-rect-type rounded-rect-offset rounded-rect-inset rounded-rect-outset
         rounded-rect-transform)

;;;
;;; Coordinate Conversion and Path Mutation Helpers
;;;

; float-point : symbol? sk-point? -> vector?
;   Copies a native point into a checked immutable x/y vector.
(define (float-point who p)
  (vector-immutable (geometry-float who (sk-point-x p)) (geometry-float who (sk-point-y p))))

; float-rect : symbol? sk-rect? -> vector?
;   Copies finite native rectangle edges into an immutable x/y/width/height vector.
(define (float-rect who r)
  (define x (geometry-float who (sk-rect-left r)))
  (define y (geometry-float who (sk-rect-top r)))
  (define right (geometry-float who (sk-rect-right r)))
  (define bottom (geometry-float who (sk-rect-bottom r)))
  (vector-immutable x y (- right x) (- bottom y)))

; integer-rect : sk-irect? -> vector?
;   Copies native integer edges into an immutable x/y/width/height vector.
(define (integer-rect r)
  (vector-immutable (sk-irect-left r) (sk-irect-top r)
                    (- (sk-irect-right r) (sk-irect-left r))
                    (- (sk-irect-bottom r) (sk-irect-top r))))

; native-irect : symbol? any/c -> sk-irect?
;   Validates integer rectangle coordinates and converts extents to native edges.
(define (native-irect who value)
  (define b (geometry-irect who value))
  (make-sk-irect (vector-ref b 0) (vector-ref b 1)
                (+ (vector-ref b 0) (vector-ref b 2))
                (+ (vector-ref b 1) (vector-ref b 3))))

; native-point : (list/c real? real?) -> sk-point?
;   Converts an already checked x/y pair to a native point.
(define (native-point xy) (apply make-sk-point xy))

; with-result-path : symbol? (listof (or/c owned? domain-resource?)) procedure? -> path?
;   Keeps source handles locked while constructing an owned result path, closing it on failure.
(define (with-result-path who handles proc)
  ;; Keep all source handles locked through allocation, execution and adoption.
  (call-with-owned who handles
    (lambda pointers
      (define out (make-path))
      (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! out) (raise e))])
        (call-with-owned who (list (path-h who out))
          (lambda (dst)
            (apply proc dst pointers)
            ;; Reconcile inverse-fill provenance from the actual result, without
            ;; retaining unrelated source paint/shader/effect features.
            (sk_path_set_filltype dst (sk_path_get_filltype dst))))
        out))))

; mutate-path : symbol? path? procedure? -> void?
;   Runs a native path mutation while holding the managed path handle.
(define (mutate-path who p proc)
  (call-with-owned who (list (path-h who p)) proc)
  (void))

; endpoint-arc : symbol? procedure? path? real? real? real? real? real? boolean? symbol? boolean? ->
;   void?
;   Validates endpoint-arc parameters and relative endpoints before applying the native operation.
(define (endpoint-arc who native p rx ry rotation x y large? direction relative?)
  (define a (geometry-nonnegative who rx))
  (define b (geometry-nonnegative who ry))
  (define angle (geometry-float who rotation))
  (define fx (geometry-float who x))
  (define fy (geometry-float who y))
  (boolean who large?)
  (define dir (choice who direction direction-values))
  (mutate-path who p
    (lambda (pp)
      (when relative?
        (define last (make-sk-point 0.0 0.0))
        (sk_path_get_last_point pp last)
        (geometry-float who (+ (sk-point-x last) fx))
        (geometry-float who (+ (sk-point-y last) fy)))
      (native pp a b angle (if large? 1 0) dir fx fy))))

;;;
;;; Path Construction
;;;

; path-arc-to! : path? real? real? real? real? real? [#:large? boolean?] [#:direction (or/c 'cw
;   'ccw)] -> void?
;   Appends an elliptical arc from the current point to coordinates x and y.
(define (path-arc-to! p rx ry rotation x y #:large? [large? #f] #:direction [direction 'cw])
  (endpoint-arc 'path-arc-to! sk_path_arc_to p rx ry rotation x y large? direction #f))

; path-rarc-to! : path? real? real? real? real? real? [#:large? boolean?] [#:direction (or/c 'cw
;   'ccw)] -> void?
;   Appends an elliptical arc from the current point to the point displaced by dx and dy.
(define (path-rarc-to! p rx ry rotation dx dy #:large? [large? #f] #:direction [direction 'cw])
  (endpoint-arc 'path-rarc-to! sk_path_rarc_to p rx ry rotation dx dy large? direction #t))

; path-arc-to-oval! : path? real? real? (and/c real? (>=/c 0)) (and/c real? (>=/c 0)) real? real?
;   [#:force-move? boolean?] -> void?
;   Appends an arc of the specified oval, starting at start and sweeping through sweep degrees.
(define (path-arc-to-oval! p x y width height start sweep #:force-move? [move? #f])
  (define who 'path-arc-to-oval!)
  (define oval (filter-rectangle who (list x y width height)))
  (define a (geometry-float who start)) (define b (geometry-float who sweep))
  (boolean who move?)
  (mutate-path who p (lambda (pp) (sk_path_arc_to_with_oval pp oval a b move?))))

; path-tangent-arc-to! : path? real? real? real? real? real? -> void?
;   Appends a circular arc tangent to the line from the current point toward the first point and
;   the line from the first point toward the second.
(define (path-tangent-arc-to! p x1 y1 x2 y2 radius)
  (define who 'path-tangent-arc-to!)
  (define xy (map (lambda (v) (geometry-float who v)) (list x1 y1 x2 y2)))
  (define r (geometry-nonnegative who radius))
  (mutate-path who p (lambda (pp) (apply sk_path_arc_to_with_points pp (append xy (list r))))))

; path-add-arc! : path? real? real? (and/c real? (>=/c 0)) (and/c real? (>=/c 0)) real? real? ->
;   void?
;   Adds an oval arc as a new contour, rather than connecting it to the preceding contour.
(define (path-add-arc! p x y width height start sweep)
  (define who 'path-add-arc!)
  (define oval (filter-rectangle who (list x y width height)))
  (define a (geometry-float who start)) (define b (geometry-float who sweep))
  (mutate-path who p (lambda (pp) (sk_path_add_arc pp oval a b))))

; path-add-rect-start! : path? real? real? (and/c real? (>=/c 0)) (and/c real? (>=/c 0)) (integer-in
;   0 3) [#:direction (or/c 'cw 'ccw)] -> void?
;   Adds a rectangle contour with an explicit starting corner.
(define (path-add-rect-start! p x y width height start #:direction [direction 'cw])
  (define who 'path-add-rect-start!)
  (define b (filter-rectangle who (list x y width height)))
  (define index (geometry-start-index who start 4))
  (define dir (choice who direction direction-values))
  (mutate-path who p (lambda (pp) (sk_path_add_rect_start pp b dir index))))

; path-add-polygon! : path? (or/c list? vector?) [#:closed? boolean?] -> void?
;   Adds a contour from a list or vector of two-element point lists or vectors.
(define (path-add-polygon! p points #:closed? [closed? #t])
  (define who 'path-add-polygon!)
  (boolean who closed?)
  (define xy (geometry-point-list who points))
  (mutate-path who p
    (lambda (pp)
      (unless (null? xy)
        (define data (malloc (* 8 (length xy)) 'atomic))
        (for ([v (in-list (append* xy))] [i (in-naturals)]) (ptr-set! data _float i v))
        (sk_path_add_poly pp data (length xy) closed?)
        (void/reference-sink data)))))

; path-add-transformed! : path? path? matrix? [#:mode (or/c 'append 'extend)] -> void?
;   Adds the source geometry after applying the affine transform.
(define (path-add-transformed! p other m #:mode [mode 'append])
  (define who 'path-add-transformed!)
  (define matrix (geometry-matrix who m))
  (define md (choice who mode path-add-mode-values))
  (call-with-owned who (list (path-h who p) (path-h who other))
    (lambda (pp src) (sk_path_add_path_matrix pp src matrix md)))
  (void))

; path-rewind! : path? -> void?
;   Clears the path's contours for reuse while retaining native storage where possible.
(define (path-rewind! p)
  (mutate-path 'path-rewind! p
    (lambda (pp) (sk_path_rewind pp) (sk_path_set_filltype pp (sk_path_get_filltype pp)))))

;;;
;;; Path Inspection and Conversion
;;;

; path-verbs : path? -> (listof (or/c 'move 'line 'quad 'conic 'cubic 'close))
;   Returns the verbs from raw path iteration, in stored order.
(define (path-verbs p)
  ;; Existing raw snapshots already provide a replayable, peekable sequence.
  (map path-segment-verb (path-segments p #:mode 'raw)))

; path-segment-kinds : path? -> (listof (or/c 'line 'quad 'conic 'cubic))
;   Returns the distinct drawing-segment kinds present, in the order line, quad, conic, cubic.
(define (path-segment-kinds p)
  (define bits (call-with-owned 'path-segment-kinds (list (path-h 'path-segment-kinds p))
                               sk_path_get_segment_masks))
  (for/list ([name (in-list '(line quad conic cubic))] [bit (in-list '(1 2 4 8))]
             #:when (not (zero? (bitwise-and bits bit)))) name))

; path-fill-bounds : path? -> (and/c (vector/c real? real? real? real?) immutable?)
;   Returns the tight rectangle reported by native path operations.
(define (path-fill-bounds p)
  (define who 'path-fill-bounds)
  (define b (make-sk-rect 0.0 0.0 0.0 0.0))
  (call-with-owned who (list (path-h who p))
    (lambda (pp)
      (unless (sk_pathop_tight_bounds pp b) (error who "native path-ops bounds failed"))
      (float-rect who b))))
(struct path-rectangle (bounds closed? direction) #:transparent
  #:constructor-name make-path-rectangle-record)
;; A path-rectangle is a detached result of native rectangular-path recognition.
;;  - bounds     immutable vector  Local x, y, width, and height, in that order.
;;  - closed?    boolean?          Whether the recognized contour closes explicitly.
;;  - direction  symbol?           Native traversal direction, 'cw or 'ccw.
;; Bounds describe the recognized geometry, not a stroke or paint effect. The
;; record preserves closure and traversal information rather than normalizing it.

; path-as-line : path? -> (or/c #f (and/c (vector/c (and/c (vector/c real? real?) immutable?) (and/c
;   (vector/c real? real?) immutable?)) immutable?))
;   Returns the two endpoints when native recognition identifies a line, or #f otherwise.
(define (path-as-line p)
  (define who 'path-as-line)
  (call-with-owned who (list (path-h who p))
    (lambda (pp)
      (define data (malloc (* 2 (ctype-sizeof _sk-point)) 'atomic))
      (and (sk_path_is_line pp data)
           (vector-immutable (float-point who (ptr-ref data _sk-point 0))
                             (float-point who (ptr-ref data _sk-point 1)))))))

; path-as-oval : path? -> (or/c #f (and/c (vector/c real? real? real? real?) immutable?))
;   Returns the oval's bounds when native recognition succeeds, or #f otherwise.
(define (path-as-oval p)
  (define who 'path-as-oval)
  (define b (make-sk-rect 0.0 0.0 0.0 0.0))
  (call-with-owned who (list (path-h who p))
    (lambda (pp) (and (sk_path_is_oval pp b) (float-rect who b)))))

; path-as-rectangle : path? -> (or/c path-rectangle? #f)
;   Returns a detached rectangle description when native recognition succeeds, or #f otherwise.
(define (path-as-rectangle p)
  (define who 'path-as-rectangle)
  (call-with-owned who (list (path-h who p))
    (lambda (pp)
      (define b (make-sk-rect 0.0 0.0 0.0 0.0))
      (define closed (malloc _stdbool 'atomic))
      (define direction (malloc _int 'atomic))
      (and (sk_path_is_rect pp b closed direction)
           (make-path-rectangle-record (float-rect who b) (ptr-ref closed _stdbool)
             (enum-name who (ptr-ref direction _int) direction-values "path direction"))))))

; conic->quadratics : (or/c (list/c real? real?) (vector/c real? real?)) (or/c (list/c real? real?)
;   (vector/c real? real?)) (or/c (list/c real? real?) (vector/c real? real?)) (and/c real? (>/c 0))
;   [#:subdivisions (integer-in 0 5)] -> (listof (and/c vector? immutable?))
;   Approximates a rational quadratic with ordinary quadratic segments.
(define (conic->quadratics p0 p1 p2 weight #:subdivisions [power 2])
  (define who 'conic->quadratics)
  (define-values (ps w capacity) (geometry-conic-parameters who p0 p1 p2 weight power))
  (skia-check!)
  (define data (malloc (* capacity (ctype-sizeof _sk-point)) 'atomic))
  (define count
    (sk_path_convert_conic_to_quads (native-point (car ps)) (native-point (cadr ps))
                                   (native-point (caddr ps)) w data power))
  (unless (<= 1 count (arithmetic-shift 1 power))
    (error who "invalid native quadratic count: ~a" count))
  ;; Consecutive triples share endpoints; callers get copied immutable points.
  (for/list ([i (in-range count)])
    (vector-immutable (float-point who (ptr-ref data _sk-point (* 2 i)))
                      (float-point who (ptr-ref data _sk-point (add1 (* 2 i))))
                      (float-point who (ptr-ref data _sk-point (+ 2 (* 2 i)))))))

; path-combine : (or/c list? vector?) -> path?
;   Combines a list or vector of two-element operation/path pairs, starting with an empty
;   accumulator.
(define (path-combine operations)
  (define who 'path-combine)
  (define entries (geometry-operation-list who operations))
  (define handles (map (lambda (e) (path-h who (cadr e))) entries))
  (define ops (map (lambda (e) (choice who (car e) path-op-values)) entries))
  (call-with-owned who handles
    (lambda ptrs
      (define bytes
        (for/sum ([p (in-list ptrs)])
          (+ 16 (* 8 (sk_path_count_points p)) (sk_path_count_verbs p))))
      (geometry-budget who (length entries) bytes)
      (with-result-path who '()
        (lambda (out)
          (unless (null? entries)
            (call-with-native-temporary who 'path-op-builder sk_opbuilder_new sk_opbuilder_destroy
              (lambda (builder)
                (for ([p (in-list ptrs)] [op (in-list ops)]) (sk_opbuilder_add builder p op))
                (unless (sk_opbuilder_resolve builder out)
                  (error who "native path operation failed; no result was published"))))))))))

;; Paint scalar getters do not initialize a context or read pixels. The native
;; blend-mode getter deliberately substitutes SrcOver for arbitrary blenders.

;;;
;;; Paint Queries and Stroke Expansion
;;;

; paint-query : symbol? paint? procedure? -> any/c
;   Runs a native paint query while holding its managed handle.
(define (paint-query who paint native)
  (call-with-owned who (list (paint-h who paint)) native))

; paint-style : paint? -> (or/c 'fill 'stroke 'stroke-and-fill)
;   Returns the paint's current geometry style.
(define (paint-style p)
  (enum-name 'paint-style (paint-query 'paint-style p sk_paint_get_style) style-values "style"))

; paint-stroke-width : paint? -> real?
;   Returns the current stroke width.
(define (paint-stroke-width p) (paint-query 'paint-stroke-width p sk_paint_get_stroke_width))

; paint-miter-limit : paint? -> real?
;   Returns the current dimensionless miter limit.
(define (paint-miter-limit p) (paint-query 'paint-miter-limit p sk_paint_get_stroke_miter))

; paint-cap : paint? -> (or/c 'butt 'round 'square)
;   Returns the current stroke-cap setting.
(define (paint-cap p)
  (enum-name 'paint-cap (paint-query 'paint-cap p sk_paint_get_stroke_cap) cap-values "cap"))

; paint-join : paint? -> (or/c 'miter 'round 'bevel)
;   Returns the current stroke-join setting.
(define (paint-join p)
  (enum-name 'paint-join (paint-query 'paint-join p sk_paint_get_stroke_join) join-values "join"))

; paint-antialias? : paint? -> boolean?
;   Reports whether the paint requests antialiased shape edges.
(define (paint-antialias? p) (paint-query 'paint-antialias? p sk_paint_is_antialias))

; paint-dither? : paint? -> boolean?
;   Reports whether the paint requests dithering when reducing color precision.
(define (paint-dither? p) (paint-query 'paint-dither? p sk_paint_is_dither))

; paint-blend-mode-or-src-over : paint? -> symbol?
;   Returns the ordinary blend mode when the paint has one.
(define (paint-blend-mode-or-src-over p)
  (enum-name 'paint-blend-mode-or-src-over
    (paint-query 'paint-blend-mode-or-src-over p sk_paint_get_blendmode) blend-values "blend mode"))

; paint-set-dither! : paint? boolean? -> void?
;   Sets the dithering request.
(define (paint-set-dither! p enabled?)
  (boolean 'paint-set-dither! enabled?)
  (paint-query 'paint-set-dither! p (lambda (pp) (sk_paint_set_dither pp enabled?)))
  (void))

; paint-reset! : paint? -> void?
;   Resets the paint to native Skia defaults and removes attached shader, effect, filter, and
;   blender references.
(define (paint-reset! p)
  ;; The lifetime/audit hooks clear retained child slots after native success.
  (paint-query 'paint-reset! p sk_paint_reset) (void))

; paint->fill-path : paint? skia-path? [#:cull (or/c list? vector? #f)] [#:matrix matrix?] ->
;   (values skia-path? boolean?)
;   Returns a new owned path for the geometry produced by the paint's style, stroke settings, and
;   path effect, together with a boolean indicating whether the result is fillable.
(define (paint->fill-path paint path #:cull [cull #f] #:matrix [matrix matrix-identity])
  (define who 'paint->fill-path)
  (define cr (optional-filter-crop who cull))
  (define m (geometry-matrix who matrix))
  (define fillable? #f)
  (define result
    (with-result-path who (list (paint-h who paint) (path-h who path))
      (lambda (out pp src) (set! fillable? (sk_paint_get_fill_path pp src out cr m)))))
  ;; False denotes a hairline result, not an allocation failure. The path is
  ;; still returned and owned. Color/shader/filter/blend state is not baked in.
  (values result fillable?))

;; Region quick predicates are sufficient tests, not exact converses.

;;;
;;; Region Queries and Mutation
;;;

; region-h : symbol? region? -> (or/c owned? domain-resource?)
;   Checks a region wrapper and retrieves its managed native handle.
(define (region-h who r)
  (unless (region? r) (raise-argument-error who "region?" r))
  (region-resource-handle r))

; region-rect-query : symbol? region? any/c procedure? -> any/c
;   Validates an integer rectangle and queries the locked native region.
(define (region-rect-query who r b native)
  (define rect (native-irect who b))
  (call-with-owned who (list (region-h who r)) (lambda (rp) (native rp rect))))

; region-intersects-rect? : region? (or/c (list/c exact-integer? exact-integer? exact-integer?
;   exact-integer?) (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)) ->
;   boolean?
;   Reports whether the region shares any pixels with the rectangle.
(define (region-intersects-rect? r b)
  (region-rect-query 'region-intersects-rect? r b sk_region_intersects_rect))

; region-quick-contains-rect? : region? (or/c (list/c exact-integer? exact-integer? exact-integer?
;   exact-integer?) (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)) ->
;   boolean?
;   Returns #t only when containment is established by the inexpensive native test.
(define (region-quick-contains-rect? r b)
  (region-rect-query 'region-quick-contains-rect? r b sk_region_quick_contains))

; region-quick-reject-rect? : region? (or/c (list/c exact-integer? exact-integer? exact-integer?
;   exact-integer?) (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)) ->
;   boolean?
;   Returns #t when disjointness is established cheaply.
(define (region-quick-reject-rect? r b)
  (region-rect-query 'region-quick-reject-rect? r b sk_region_quick_reject_rect))

; region-quick-reject? : region? region? -> boolean?
;   Returns #t when the regions are cheaply proved disjoint.
(define (region-quick-reject? a b)
  (call-with-owned 'region-quick-reject?
    (list (region-h 'region-quick-reject? a) (region-h 'region-quick-reject? b))
                   sk_region_quick_reject))

; region-clear! : region? -> void?
;   Mutates the region to the empty set.
(define (region-clear! r)
  (call-with-owned 'region-clear! (list (region-h 'region-clear! r)) sk_region_set_empty) (void))

; region-set-rect! : region? (or/c (list/c exact-integer? exact-integer? exact-integer?
;   exact-integer?) (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)) -> void?
;   Replaces the region with the supplied rectangle.
(define (region-set-rect! r b) (region-rect-query 'region-set-rect! r b sk_region_set_rect) (void))

; region-op-rect : region? (or/c (list/c exact-integer? exact-integer? exact-integer?
;   exact-integer?) (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)) (or/c
;   'difference 'intersect 'union 'xor 'reverse-difference 'replace) -> region?
;   Returns the selected operation between the region and rectangle, using the operand order and
;   operations of region-op.
(define (region-op-rect r b operation)
  (define who 'region-op-rect)
  (define rect (native-irect who b))
  (define op
    (choice who operation
            (hasheq 'difference 0 'intersect 1 'union 2 'xor 3 'reverse-difference 4 'replace 5)))
  (define out (region-copy r))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! out) (raise e))])
    (call-with-owned who (list (region-h who out)) (lambda (rp) (sk_region_op_rect rp rect op)))
    out))

; region-clipped-rectangles : region? (or/c (list/c exact-integer? exact-integer? exact-integer?
;   exact-integer?) (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)) ->
;   (listof (and/c (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)
;   immutable?))
;   Returns immutable rectangles describing the intersection with the clipping rectangle, without
;   mutating the region.
(define (region-clipped-rectangles r clip)
  (define who 'region-clipped-rectangles)
  (define rect (native-irect who clip))
  (call-with-owned who (list (region-h who r))
    (lambda (rp)
      (call-with-native-temporary who 'region-clip-iterator
        (lambda () (sk_region_cliperator_new rp rect)) sk_region_cliperator_delete
        (lambda (it)
          (define b (make-sk-irect 0 0 0 0))
          (let loop ([n 0] [out '()])
            (cond [(sk_region_cliperator_done it) (reverse out)]
                  [else
                   (geometry-budget who (add1 n) (* 16 (add1 n)))
                   (sk_region_cliperator_rect it b)
                   (define v (integer-rect b))
                   (sk_region_cliperator_next it)
                   (loop (add1 n) (cons v out))])))))))

; in-region-clipped-rectangles : region? (or/c (list/c exact-integer? exact-integer? exact-integer?
;   exact-integer?) (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)) ->
;   sequence?
;   Returns a sequence over a newly created region-clipped-rectangles snapshot.
(define (in-region-clipped-rectangles r clip) (in-list (region-clipped-rectangles r clip)))

; region-spans : region? (integer-in -1073741823 1073741823) (integer-in -1073741823 1073741823)
;   (integer-in -1073741823 1073741823) -> (listof (and/c (vector/c exact-integer? exact-integer?)
;   immutable?))
;   Returns horizontal intervals at row y, clipped to the half-open interval from left to right.
(define (region-spans r y left right)
  (define who 'region-spans)
  (define-values (iy il ir) (geometry-span-range who y left right))
  (call-with-owned who (list (region-h who r))
    (lambda (rp)
      ;; [left,right) is public half-open geometry. m119's simple-rectangle
      ;; Spanerator can report the degenerate interval [x,x) when left=right,
      ;; so normalize the empty range before constructing the native iterator.
      (if (= il ir)
          '()
          (call-with-native-temporary who 'region-span-iterator
            (lambda () (sk_region_spanerator_new rp iy il ir)) sk_region_spanerator_delete
            (lambda (it)
              (define l (malloc _int 'atomic)) (define r (malloc _int 'atomic))
              (let loop ([n 0] [out '()])
                (if (sk_region_spanerator_next it l r)
                    (begin
                      (geometry-budget who (add1 n) (* 8 (add1 n)))
                      (loop (add1 n) (cons (vector-immutable (ptr-ref l _int) (ptr-ref r _int)) out)))
                    (reverse out)))))))))

; in-region-spans : region? (integer-in -1073741823 1073741823) (integer-in -1073741823 1073741823)
;   (integer-in -1073741823 1073741823) -> sequence?
;   Returns a sequence over a newly created region-spans snapshot, with the same half-open interval
;   and validation rules.
(define (in-region-spans r y left right) (in-list (region-spans r y left right)))

;; Round-rectangle values stay immutable. Native normalization is copied back
;; from a synchronous temporary; no heap layout for SkRRect is assumed.

;;;
;;; Rounded-Rectangle Operations
;;;

; with-rrect : symbol? rounded-rect? procedure? -> any/c
;   Constructs a temporary native rounded rectangle for the callback and always deletes it.
(define (with-rrect who rr proc)
  (unless (rounded-rect? rr) (raise-argument-error who "rounded-rect?" rr))
  (define b (filter-rectangle who (rounded-rect-bounds rr)))
  (define rs (geometry-point-list who (rounded-rect-radii rr) 4))
  (geometry-budget who 4 32)
  (skia-check!)
  (call-with-native-temporary who 'rrect sk_rrect_new sk_rrect_delete
    (lambda (rp)
      (define data (malloc 32 'atomic))
      (for ([v (in-list (append* rs))] [i (in-naturals)]) (ptr-set! data _float i v))
      (sk_rrect_set_rect_radii rp b data)
      (begin0 (proc rp) (void/reference-sink data rr)))))

; rrect-value : symbol? cpointer? -> rounded-rect?
;   Copies valid native bounds and corner radii into a detached rounded-rectangle value.
(define (rrect-value who rp)
  (unless (sk_rrect_is_valid rp) (error who "native result is not a valid rounded rectangle"))
  (define b (make-sk-rect 0.0 0.0 0.0 0.0))
  (sk_rrect_get_rect rp b)
  (define xywh (float-rect who b))
  (define radii
    (for/list ([i (in-range 4)])
      (define p (make-sk-point 0.0 0.0))
      (sk_rrect_get_radii rp i p)
      (float-point who p)))
  (make-rounded-rect (vector-ref xywh 0) (vector-ref xywh 1)
                    (vector-ref xywh 2) (vector-ref xywh 3) #:radii radii))

; rounded-rect-normalize : rounded-rect? -> rounded-rect?
;   Returns native-normalized bounds and radii.
(define (rounded-rect-normalize rr)
  (with-rrect 'rounded-rect-normalize rr (lambda (rp) (rrect-value 'rounded-rect-normalize rp))))

; rounded-rect-type : rounded-rect? -> (or/c 'empty 'rect 'oval 'simple 'nine-patch 'complex)
;   Classifies the native-normalized shape.
(define (rounded-rect-type rr)
  (with-rrect 'rounded-rect-type rr
    (lambda (rp)
      (define n (sk_rrect_get_type rp))
      (unless (<= 0 n 5) (error 'rounded-rect-type "unexpected native type ~a" n))
      (vector-ref '#(empty rect oval simple nine-patch complex) n))))

; make-empty-rounded-rect : -> rounded-rect?
;   Returns a pure specification with zero bounds and zero radii, equivalent to (make-rounded-rect
;   0 0 0 0).
(define (make-empty-rounded-rect)
  ;; Existing pure value constructor is the idiomatic equivalent of setEmpty.
  (make-rounded-rect 0 0 0 0))

; make-nine-patch-rounded-rect : real? real? (and/c real? (>=/c 0)) (and/c real? (>=/c 0)) real?
;   real? real? real? -> rounded-rect?
;   Returns a native-normalized specification with corner pairs left/top, right/top, right/bottom,
;   and left/bottom.
(define (make-nine-patch-rounded-rect x y width height left top right bottom)
  (define who 'make-nine-patch-rounded-rect)
  (define b (filter-rectangle who (list x y width height)))
  (define radii (map (lambda (v) (geometry-nonnegative who v)) (list left top right bottom)))
  (skia-check!)
  (call-with-native-temporary who 'rrect sk_rrect_new sk_rrect_delete
    (lambda (rp) (apply sk_rrect_set_nine_patch rp b radii) (rrect-value who rp))))

; rrect-adjust : symbol? rounded-rect? real? real? procedure? boolean? -> rounded-rect?
;   Applies a checked two-axis adjustment to a temporary rounded rectangle and copies the result.
(define (rrect-adjust who rr x y native nonnegative?)
  (define check (if nonnegative? geometry-nonnegative geometry-float))
  (define fx (check who x)) (define fy (check who y))
  (with-rrect who rr
    (lambda (rp) (native rp fx fy) (rrect-value who rp))))

; rounded-rect-offset : rounded-rect? real? real? -> rounded-rect?
;   Translates the normalized shape by signed offsets and returns a new normalized specification.
(define (rounded-rect-offset rr dx dy)
  (rrect-adjust 'rounded-rect-offset rr dx dy sk_rrect_offset #f))

; rounded-rect-inset : rounded-rect? real? real? -> rounded-rect?
;   Insets the bounds by nonnegative horizontal and vertical distances and adjusts the radii using
;   native rounded-rectangle rules.
(define (rounded-rect-inset rr dx dy) (rrect-adjust 'rounded-rect-inset rr dx dy sk_rrect_inset #t))

; rounded-rect-outset : rounded-rect? real? real? -> rounded-rect?
;   Expands the bounds by nonnegative horizontal and vertical distances and adjusts the radii using
;   native rounded-rectangle rules.
(define (rounded-rect-outset rr dx dy)
  (rrect-adjust 'rounded-rect-outset rr dx dy sk_rrect_outset #t))

; rounded-rect-transform : rounded-rect? matrix? -> (or/c rounded-rect? #f)
;   Returns the native-normalized affine image when it can be represented as a rounded rectangle,
;   or #f otherwise.
(define (rounded-rect-transform rr m)
  (define who 'rounded-rect-transform)
  (define matrix (geometry-matrix who m))
  (with-rrect who rr
    (lambda (src)
      (call-with-native-temporary who 'rrect sk_rrect_new sk_rrect_delete
        (lambda (dst) (and (sk_rrect_transform src matrix dst) (rrect-value who dst)))))))

; path-as-rounded-rect : path? -> (or/c rounded-rect? #f)
;   Returns a detached, native-normalized rounded rectangle when recognized, or #f otherwise.
(define (path-as-rounded-rect p)
  (define who 'path-as-rounded-rect)
  (call-with-owned who (list (path-h who p))
    (lambda (pp)
      (call-with-native-temporary who 'rrect sk_rrect_new sk_rrect_delete
        (lambda (rp) (and (sk_path_is_rrect pp rp) (rrect-value who rp)))))))

; path-add-rounded-rect! : skia-path? rounded-rect? [#:direction (or/c 'cw 'ccw)]
;   [#:start-index (integer-in 0 7)] -> void?
; path-add-rounded-rect! : skia-path? real? real? (and/c real? (>=/c 0)) (and/c real? (>=/c 0))
;   (and/c real? (>=/c 0)) (and/c real? (>=/c 0)) [#:direction (or/c 'cw 'ccw)] -> void?
;   Appends a closed rounded rectangle from a value or coordinates with shared corner radii.
(define path-add-rounded-rect!
  (let ([unspecified-start (gensym 'start-index)])
    ;; Keep exact positional arities despite the keyword dispatcher's rest argument.
    (procedure-reduce-keyword-arity
     (lambda (#:direction [direction 'cw] #:start-index [start unspecified-start] . arguments)
       (define who 'path-add-rounded-rect!)
       (apply
        (case-lambda
          [(path shape)
           (define index
             (geometry-start-index who (if (eq? start unspecified-start) 0 start) 8))
           (define dir (choice who direction direction-values))
           ;; Validate the value before inspecting or mutating the path.
           (unless (rounded-rect? shape) (raise-argument-error who "rounded-rect?" shape))
           (mutate-path who path
             (lambda (pp)
               (with-rrect who shape
                 (lambda (rp) (sk_path_add_rrect_start pp rp dir index)))))]
          [(path x y width height radius-x radius-y)
           (unless (eq? start unspecified-start)
             (raise-arguments-error who "#:start-index requires the rounded-rectangle value form"
                                    "start-index" start))
           (define bounds (rect who x y width height))
           (define rx (nonnegative-scalar who radius-x))
           (define ry (nonnegative-scalar who radius-y))
           (define dir (choice who direction direction-values))
           (call-with-owned who (list (path-h who path))
             (lambda (pp) (sk_path_add_rounded_rect pp bounds rx ry dir)))])
        arguments))
     '(2 7) '() '(#:direction #:start-index) 'path-add-rounded-rect!)))
