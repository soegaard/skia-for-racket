#lang racket/base
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
         path-add-rect-start! path-add-rrect! path-add-polygon! path-add-transformed!
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

(define (float-point who p)
  (vector-immutable (geometry-float who (sk-point-x p)) (geometry-float who (sk-point-y p))))
(define (float-rect who r)
  (define x (geometry-float who (sk-rect-left r)))
  (define y (geometry-float who (sk-rect-top r)))
  (define right (geometry-float who (sk-rect-right r)))
  (define bottom (geometry-float who (sk-rect-bottom r)))
  (vector-immutable x y (- right x) (- bottom y)))
(define (integer-rect r)
  (vector-immutable (sk-irect-left r) (sk-irect-top r)
                    (- (sk-irect-right r) (sk-irect-left r))
                    (- (sk-irect-bottom r) (sk-irect-top r))))
(define (native-irect who value)
  (define b (geometry-irect who value))
  (make-sk-irect (vector-ref b 0) (vector-ref b 1)
                (+ (vector-ref b 0) (vector-ref b 2))
                (+ (vector-ref b 1) (vector-ref b 3))))
(define (native-point xy) (apply make-sk-point xy))
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
(define (mutate-path who p proc)
  (call-with-owned who (list (path-h who p)) proc)
  (void))
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
(define (path-arc-to! p rx ry rotation x y #:large? [large? #f] #:direction [direction 'cw])
  (endpoint-arc 'path-arc-to! sk_path_arc_to p rx ry rotation x y large? direction #f))
(define (path-rarc-to! p rx ry rotation dx dy #:large? [large? #f] #:direction [direction 'cw])
  (endpoint-arc 'path-rarc-to! sk_path_rarc_to p rx ry rotation dx dy large? direction #t))
(define (path-arc-to-oval! p x y width height start sweep #:force-move? [move? #f])
  (define who 'path-arc-to-oval!)
  (define oval (filter-rectangle who (list x y width height)))
  (define a (geometry-float who start)) (define b (geometry-float who sweep))
  (boolean who move?)
  (mutate-path who p (lambda (pp) (sk_path_arc_to_with_oval pp oval a b move?))))
(define (path-tangent-arc-to! p x1 y1 x2 y2 radius)
  (define who 'path-tangent-arc-to!)
  (define xy (map (lambda (v) (geometry-float who v)) (list x1 y1 x2 y2)))
  (define r (geometry-nonnegative who radius))
  (mutate-path who p (lambda (pp) (apply sk_path_arc_to_with_points pp (append xy (list r))))))
(define (path-add-arc! p x y width height start sweep)
  (define who 'path-add-arc!)
  (define oval (filter-rectangle who (list x y width height)))
  (define a (geometry-float who start)) (define b (geometry-float who sweep))
  (mutate-path who p (lambda (pp) (sk_path_add_arc pp oval a b))))
(define (path-add-rect-start! p x y width height start #:direction [direction 'cw])
  (define who 'path-add-rect-start!)
  (define b (filter-rectangle who (list x y width height)))
  (define index (geometry-start-index who start 4))
  (define dir (choice who direction direction-values))
  (mutate-path who p (lambda (pp) (sk_path_add_rect_start pp b dir index))))
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
(define (path-add-transformed! p other m #:mode [mode 'append])
  (define who 'path-add-transformed!)
  (define matrix (geometry-matrix who m))
  (define md (choice who mode path-add-mode-values))
  (call-with-owned who (list (path-h who p) (path-h who other))
    (lambda (pp src) (sk_path_add_path_matrix pp src matrix md)))
  (void))
(define (path-rewind! p)
  (mutate-path 'path-rewind! p
    (lambda (pp) (sk_path_rewind pp) (sk_path_set_filltype pp (sk_path_get_filltype pp)))))
(define (path-verbs p)
  ;; Existing raw snapshots already provide a replayable, peekable sequence.
  (map path-segment-verb (path-segments p #:mode 'raw)))
(define (path-segment-kinds p)
  (define bits (call-with-owned 'path-segment-kinds (list (path-h 'path-segment-kinds p))
                               sk_path_get_segment_masks))
  (for/list ([name (in-list '(line quad conic cubic))] [bit (in-list '(1 2 4 8))]
             #:when (not (zero? (bitwise-and bits bit)))) name))
(define (path-fill-bounds p)
  (define who 'path-fill-bounds)
  (define b (make-sk-rect 0.0 0.0 0.0 0.0))
  (call-with-owned who (list (path-h who p))
    (lambda (pp)
      (unless (sk_pathop_tight_bounds pp b) (error who "native path-ops bounds failed"))
      (float-rect who b))))
(struct path-rectangle (bounds closed? direction) #:transparent
  #:constructor-name make-path-rectangle-record)
(define (path-as-line p)
  (define who 'path-as-line)
  (call-with-owned who (list (path-h who p))
    (lambda (pp)
      (define data (malloc (* 2 (ctype-sizeof _sk-point)) 'atomic))
      (and (sk_path_is_line pp data)
           (vector-immutable (float-point who (ptr-ref data _sk-point 0))
                             (float-point who (ptr-ref data _sk-point 1)))))))
(define (path-as-oval p)
  (define who 'path-as-oval)
  (define b (make-sk-rect 0.0 0.0 0.0 0.0))
  (call-with-owned who (list (path-h who p))
    (lambda (pp) (and (sk_path_is_oval pp b) (float-rect who b)))))
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
(define (conic->quadratics p0 p1 p2 weight #:subdivisions [power 2])
  (define who 'conic->quadratics)
  (define-values (ps w capacity) (geometry-conic-parameters who p0 p1 p2 weight power))
  (skia-check!)
  (define data (malloc (* capacity (ctype-sizeof _sk-point)) 'atomic))
  (define count
    (sk_path_convert_conic_to_quads (native-point (car ps)) (native-point (cadr ps))
                                   (native-point (caddr ps)) w data power))
  (unless (<= 1 count (arithmetic-shift 1 power)) (error who "invalid native quadratic count: ~a" count))
  ;; Consecutive triples share endpoints; callers get copied immutable points.
  (for/list ([i (in-range count)])
    (vector-immutable (float-point who (ptr-ref data _sk-point (* 2 i)))
                      (float-point who (ptr-ref data _sk-point (add1 (* 2 i))))
                      (float-point who (ptr-ref data _sk-point (+ 2 (* 2 i)))))))
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
(define (paint-query who paint native)
  (call-with-owned who (list (paint-h who paint)) native))
(define (paint-style p) (enum-name 'paint-style (paint-query 'paint-style p sk_paint_get_style) style-values "style"))
(define (paint-stroke-width p) (paint-query 'paint-stroke-width p sk_paint_get_stroke_width))
(define (paint-miter-limit p) (paint-query 'paint-miter-limit p sk_paint_get_stroke_miter))
(define (paint-cap p) (enum-name 'paint-cap (paint-query 'paint-cap p sk_paint_get_stroke_cap) cap-values "cap"))
(define (paint-join p) (enum-name 'paint-join (paint-query 'paint-join p sk_paint_get_stroke_join) join-values "join"))
(define (paint-antialias? p) (paint-query 'paint-antialias? p sk_paint_is_antialias))
(define (paint-dither? p) (paint-query 'paint-dither? p sk_paint_is_dither))
(define (paint-blend-mode-or-src-over p)
  (enum-name 'paint-blend-mode-or-src-over
    (paint-query 'paint-blend-mode-or-src-over p sk_paint_get_blendmode) blend-values "blend mode"))
(define (paint-set-dither! p enabled?)
  (boolean 'paint-set-dither! enabled?)
  (paint-query 'paint-set-dither! p (lambda (pp) (sk_paint_set_dither pp enabled?)))
  (void))
(define (paint-reset! p)
  ;; The lifetime/audit hooks clear retained child slots after native success.
  (paint-query 'paint-reset! p sk_paint_reset) (void))
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
(define (region-h who r)
  (unless (region? r) (raise-argument-error who "region?" r))
  (region-resource-handle r))
(define (region-rect-query who r b native)
  (define rect (native-irect who b))
  (call-with-owned who (list (region-h who r)) (lambda (rp) (native rp rect))))
(define (region-intersects-rect? r b) (region-rect-query 'region-intersects-rect? r b sk_region_intersects_rect))
(define (region-quick-contains-rect? r b) (region-rect-query 'region-quick-contains-rect? r b sk_region_quick_contains))
(define (region-quick-reject-rect? r b) (region-rect-query 'region-quick-reject-rect? r b sk_region_quick_reject_rect))
(define (region-quick-reject? a b)
  (call-with-owned 'region-quick-reject? (list (region-h 'region-quick-reject? a) (region-h 'region-quick-reject? b))
                   sk_region_quick_reject))
(define (region-clear! r)
  (call-with-owned 'region-clear! (list (region-h 'region-clear! r)) sk_region_set_empty) (void))
(define (region-set-rect! r b) (region-rect-query 'region-set-rect! r b sk_region_set_rect) (void))
(define (region-op-rect r b operation)
  (define who 'region-op-rect)
  (define rect (native-irect who b))
  (define op (choice who operation (hasheq 'difference 0 'intersect 1 'union 2 'xor 3 'reverse-difference 4 'replace 5)))
  (define out (region-copy r))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! out) (raise e))])
    (call-with-owned who (list (region-h who out)) (lambda (rp) (sk_region_op_rect rp rect op)))
    out))
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
(define (in-region-clipped-rectangles r clip) (in-list (region-clipped-rectangles r clip)))
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
(define (in-region-spans r y left right) (in-list (region-spans r y left right)))

;; Round-rectangle values stay immutable. Native normalization is copied back
;; from a synchronous temporary; no heap layout for SkRRect is assumed.
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
(define (rounded-rect-normalize rr)
  (with-rrect 'rounded-rect-normalize rr (lambda (rp) (rrect-value 'rounded-rect-normalize rp))))
(define (rounded-rect-type rr)
  (with-rrect 'rounded-rect-type rr
    (lambda (rp)
      (define n (sk_rrect_get_type rp))
      (unless (<= 0 n 5) (error 'rounded-rect-type "unexpected native type ~a" n))
      (vector-ref '#(empty rect oval simple nine-patch complex) n))))
(define (make-empty-rounded-rect)
  ;; Existing pure value constructor is the idiomatic equivalent of setEmpty.
  (make-rounded-rect 0 0 0 0))
(define (make-nine-patch-rounded-rect x y width height left top right bottom)
  (define who 'make-nine-patch-rounded-rect)
  (define b (filter-rectangle who (list x y width height)))
  (define radii (map (lambda (v) (geometry-nonnegative who v)) (list left top right bottom)))
  (skia-check!)
  (call-with-native-temporary who 'rrect sk_rrect_new sk_rrect_delete
    (lambda (rp) (apply sk_rrect_set_nine_patch rp b radii) (rrect-value who rp))))
(define (rrect-adjust who rr x y native nonnegative?)
  (define check (if nonnegative? geometry-nonnegative geometry-float))
  (define fx (check who x)) (define fy (check who y))
  (with-rrect who rr
    (lambda (rp) (native rp fx fy) (rrect-value who rp))))
(define (rounded-rect-offset rr dx dy) (rrect-adjust 'rounded-rect-offset rr dx dy sk_rrect_offset #f))
(define (rounded-rect-inset rr dx dy) (rrect-adjust 'rounded-rect-inset rr dx dy sk_rrect_inset #t))
(define (rounded-rect-outset rr dx dy) (rrect-adjust 'rounded-rect-outset rr dx dy sk_rrect_outset #t))
(define (rounded-rect-transform rr m)
  (define who 'rounded-rect-transform)
  (define matrix (geometry-matrix who m))
  (with-rrect who rr
    (lambda (src)
      (call-with-native-temporary who 'rrect sk_rrect_new sk_rrect_delete
        (lambda (dst) (and (sk_rrect_transform src matrix dst) (rrect-value who dst)))))))
(define (path-as-rounded-rect p)
  (define who 'path-as-rounded-rect)
  (call-with-owned who (list (path-h who p))
    (lambda (pp)
      (call-with-native-temporary who 'rrect sk_rrect_new sk_rrect_delete
        (lambda (rp) (and (sk_path_is_rrect pp rp) (rrect-value who rp)))))))
(define (path-add-rrect! p rr #:direction [direction 'cw] #:start-index [start 0])
  (define who 'path-add-rrect!)
  (define index (geometry-start-index who start 8))
  (define dir (choice who direction direction-values))
  ;; Validate the value before inspecting or mutating the path.
  (unless (rounded-rect? rr) (raise-argument-error who "rounded-rect?" rr))
  (mutate-path who p
    (lambda (pp) (with-rrect who rr (lambda (rp) (sk_path_add_rrect_start pp rp dir index))))))
