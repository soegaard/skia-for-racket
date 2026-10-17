#lang racket/base

;;;
;;; Regions, Meshes, Atlases, and Patches
;;;

;; Constructs integer regions, vertex meshes, image lattices, atlas transforms, and cubic patches.
;; This public geometry layer validates ordered drawing data before converting it into native
;; buffers and canvas operations.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe racket/list racket/math racket/vector
         "color.rkt" "private/core.rkt" "private/native.rkt" "private/types.rkt"
         "private/check.rkt" "private/lifetime.rkt" "private/geometry-util.rkt"
         (submod "private/core.rkt" geometry-internals))
(provide region? make-region region-copy region-empty? region-rect? region-complex?
         region-bounds region-rectangles in-region-rectangles
         region-contains-point? region-contains-rect? region-contains-region? region-intersects?
         region-op region-union region-intersect region-difference region-xor
         region-translate path->region region->path draw-region canvas-clip-region!
         vertices? make-vertices vertices-mode vertices-positions vertices-texture-coordinates
         vertices-colors vertices-indices vertices-count draw-vertices
         image-lattice? make-image-lattice image-lattice-x-divisions image-lattice-y-divisions
         image-lattice-bounds image-lattice-cell-types image-lattice-colors
         draw-image-nine draw-image-lattice
         atlas-transform? make-atlas-transform atlas-transform-coefficients draw-atlas
         cubic-patch? make-cubic-patch cubic-patch-points cubic-patch-colors
         cubic-patch-texture-coordinates draw-patch)

;; All public snapshots are ordinary immutable data. Native buffers below are
;; temporary, have no callback, and are kept reachable through each FFI call.
; flat-buffer : list? ctype? -> (or/c #f cpointer?)
;;   Copies ordered elements to native storage, using a null pointer for an empty list.
(define (flat-buffer values type)
  (and (pair? values)
       (let ([p (malloc (* (length values) (ctype-sizeof type)) 'atomic)])
         (for ([v (in-list values)] [i (in-naturals)]) (ptr-set! p type i v))
         p)))
; vector-buffer : (or/c #f vector?) ctype? -> (or/c #f cpointer?)
;;   Copies an optional vector into native storage without changing element order.
(define (vector-buffer v type) (and v (flat-buffer (vector->list v) type)))
; point-buffer : (or/c #f vector?) -> (or/c #f cpointer?)
;;   Flattens ordered x/y points into an interleaved native float buffer.
(define (point-buffer v)
  (and v (flat-buffer (append* (for/list ([p (in-vector v)]) (vector->list p))) _float)))
; native-rect : vector? -> sk-rect?
;;   Converts a checked x/y/width/height rectangle to native left/top/right/bottom edges.
(define (native-rect v)
  (make-sk-rect (vector-ref v 0) (vector-ref v 1)
                (+ (vector-ref v 0) (vector-ref v 2)) (+ (vector-ref v 1) (vector-ref v 3))))
; native-irect : vector? -> sk-irect?
;;   Converts checked integer x/y/width/height bounds to native rectangle edges.
(define (native-irect v)
  (make-sk-irect (vector-ref v 0) (vector-ref v 1)
                 (+ (vector-ref v 0) (vector-ref v 2)) (+ (vector-ref v 1) (vector-ref v 3))))
; irect-value : sk-irect? -> vector?
;;   Copies native rectangle edges to an immutable x/y/width/height vector.
(define (irect-value r)
  (vector-immutable (sk-irect-left r) (sk-irect-top r)
                    (- (sk-irect-right r) (sk-irect-left r))
                    (- (sk-irect-bottom r) (sk-irect-top r))))

;;;
;;; Integer Regions
;;;

; region? : any/c -> boolean?
;;   Returns #t for a region wrapper, including a closed one, and #f otherwise.
(define (region? v) (region-resource? v))
; region-h : symbol? region? -> (or/c owned? domain-resource?)
;;   Checks a region wrapper and retrieves its managed native handle.
(define (region-h who r)
  (unless (region? r) (raise-argument-error who "region?" r))
  (region-resource-handle r))
; fresh-region : symbol? procedure? -> region?
;;   Allocates and initializes an owned region, closing it if initialization fails.
(define (fresh-region who init)
  (skia-check!)
  (define r (make-region-record (new-owned who 'region sk_region_new sk_region_delete)))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! r) (raise e))])
    (call-with-owned who (list (region-h who r)) init)
    r))
; make-region : [(or/c list? vector?)] -> region?
;;   Returns an independently owned region containing the union of the supplied rectangles.
(define (make-region [rectangles '()])
  (define who 'make-region)
  (define xs (geometry-list who rectangles))
  (geometry-budget who (length xs) (* 16 (length xs)))
  (define boxes (map (lambda (b) (geometry-irect who b)) xs))
  (fresh-region
   who
   (lambda (rp)
     (unless (null? boxes)
       (define buf
         (flat-buffer
          (append* (for/list ([b (in-list boxes)])
                     (list (vector-ref b 0) (vector-ref b 1)
                           (+ (vector-ref b 0) (vector-ref b 2))
                           (+ (vector-ref b 1) (vector-ref b 3))))) _int32))
       ;; False means the resulting region is empty, not allocation failure.
       (sk_region_set_rects rp buf (length boxes))
       (void/reference-sink buf)))))
; region-copy : region? -> region?
;;   Returns an independently owned copy.
(define (region-copy r)
  (define who 'region-copy)
  (call-with-owned who (list (region-h who r))
    (lambda (rp) (fresh-region who (lambda (out) (sk_region_set_region out rp))))))
; region-empty? : region? -> boolean?
;;   Reports whether the region contains no pixels.
(define (region-empty? r)
  (call-with-owned 'region-empty? (list (region-h 'region-empty? r)) sk_region_is_empty))
; region-rect? : region? -> boolean?
;;   Reports whether the nonempty region is one rectangle.
(define (region-rect? r)
  (call-with-owned 'region-rect? (list (region-h 'region-rect? r)) sk_region_is_rect))
; region-complex? : region? -> boolean?
;;   Reports whether the nonempty region requires more than one rectangle.
(define (region-complex? r)
  (call-with-owned 'region-complex? (list (region-h 'region-complex? r)) sk_region_is_complex))
; region-bounds : region? -> (and/c (vector/c exact-integer? exact-integer? exact-integer?
;   exact-integer?) immutable?)
;;   Returns an immutable enclosing rectangle.
(define (region-bounds r)
  (define b (make-sk-irect 0 0 0 0))
  (call-with-owned 'region-bounds (list (region-h 'region-bounds r))
    (lambda (rp) (sk_region_get_bounds rp b) (irect-value b))))
; region-contains-point? : region? (integer-in -1073741823 1073741823) (integer-in -1073741823
;   1073741823) -> boolean?
;;   Reports whether the integer-coordinate pixel is in the region.
(define (region-contains-point? r x y)
  (define who 'region-contains-point?)
  (define ix (geometry-int who x)) (define iy (geometry-int who y))
  (call-with-owned who (list (region-h who r)) (lambda (rp) (sk_region_contains_point rp ix iy))))
; region-contains-rect? : region? (or/c (list/c exact-integer? exact-integer? exact-integer?
;   exact-integer?) (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)) ->
;   boolean?
;;   Reports whether the region contains the nonempty rectangle in full.
(define (region-contains-rect? r rectangle)
  (define who 'region-contains-rect?)
  (define b (native-irect (geometry-irect who rectangle)))
  (call-with-owned who (list (region-h who r)) (lambda (rp) (sk_region_contains_rect rp b))))
; region-contains-region? : region? region? -> boolean?
;;   Reports whether the first region contains the nonempty second region in full.
(define (region-contains-region? a b)
  (define who 'region-contains-region?)
  (call-with-owned who (list (region-h who a) (region-h who b)) sk_region_contains))
; region-intersects? : region? region? -> boolean?
;;   Reports whether the two regions share any pixels.
(define (region-intersects? a b)
  (define who 'region-intersects?)
  (call-with-owned who (list (region-h who a) (region-h who b)) sk_region_intersects))
; region-ops : (hash/c symbol? exact-nonnegative-integer?)
;;   Maps public region-operation names to the native ABI enumeration.
(define region-ops
  (hasheq 'difference 0 'intersect 1 'union 2 'xor 3 'reverse-difference 4 'replace 5))
; region-op : region? region? (or/c 'difference 'intersect 'union 'xor 'reverse-difference 'replace)
;   -> region?
;;   Returns the selected set operation.
(define (region-op a b operation)
  (define who 'region-op)
  (define op (choice who operation region-ops))
  (call-with-owned who (list (region-h who a) (region-h who b))
    (lambda (ap bp)
      (fresh-region who (lambda (rp) (sk_region_set_region rp ap) (sk_region_op rp bp op))))))
; region-union : region? region? -> region?
;;   Returns (region-op a b 'union).
(define (region-union a b) (region-op a b 'union))
; region-intersect : region? region? -> region?
;;   Returns (region-op a b 'intersect).
(define (region-intersect a b) (region-op a b 'intersect))
; region-difference : region? region? -> region?
;;   Returns (region-op a b 'difference).
(define (region-difference a b) (region-op a b 'difference))
; region-xor : region? region? -> region?
;;   Returns (region-op a b 'xor).
(define (region-xor a b) (region-op a b 'xor))
; region-translate : region? (integer-in -1073741823 1073741823) (integer-in -1073741823 1073741823)
;   -> region?
;;   Returns a translated, independently owned region.
(define (region-translate r dx dy)
  (define who 'region-translate)
  (define ix (geometry-int who dx)) (define iy (geometry-int who dy))
  (call-with-owned
   who (list (region-h who r))
   (lambda (rp)
     (define b (make-sk-irect 0 0 0 0))
     (sk_region_get_bounds rp b)
     (unless (sk_region_is_empty rp)
       (for ([x (in-list (list (+ ix (sk-irect-left b)) (+ ix (sk-irect-right b))
                              (+ iy (sk-irect-top b)) (+ iy (sk-irect-bottom b))))])
         (geometry-int who x)))
     (fresh-region who
                   (lambda (out)
                     (sk_region_set_region out rp)
                     (sk_region_translate out ix iy))))))
; path->region : path? region? -> region?
;;   Rasterizes the path's fill into a new integer region, constrained by the clip region.
(define (path->region path clip)
  (define who 'path->region)
  (call-with-owned who (list (path-h who path) (region-h who clip))
    (lambda (pp cp) (fresh-region who (lambda (out) (sk_region_set_path out pp cp))))))
; region->path : region? -> path?
;;   Returns a new owned boundary path.
(define (region->path r)
  (define who 'region->path)
  (call-with-owned
   who (list (region-h who r))
   (lambda (rp)
     (define p (make-path))
     (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! p) (raise e))])
       (call-with-owned who (list (path-h who p)) (lambda (pp) (sk_region_get_boundary_path rp pp)))
       p))))
; region-rectangles : region? -> (listof (and/c (vector/c exact-integer? exact-integer?
;   exact-integer? exact-integer?) immutable?))
;;   Returns the native band decomposition as immutable rectangles, in native iteration order.
(define (region-rectangles r)
  (define who 'region-rectangles)
  (call-with-owned
   who (list (region-h who r))
   (lambda (rp)
     (call-with-native-temporary
      who 'region-iterator (lambda () (sk_region_iterator_new rp)) sk_region_iterator_delete
      (lambda (it)
        (define b (make-sk-irect 0 0 0 0))
        (let loop ([n 0] [out '()])
          (if (sk_region_iterator_done it)
              (reverse out)
              (begin
                (geometry-budget who (add1 n) (* 16 (add1 n)))
                (sk_region_iterator_rect it b)
                (let ([value (irect-value b)])
                  (sk_region_iterator_next it)
                  (loop (add1 n) (cons value out)))))))))))
; in-region-rectangles : region? -> sequence?
;;   Returns a sequence over a newly created region-rectangles snapshot.
(define (in-region-rectangles r) (in-list (region-rectangles r)))
; draw-region : canvas? region? paint? -> void?
;;   Draws the region under the current canvas transform and clip.
(define (draw-region c r paint)
  (define who 'draw-region)
  (define rh (region-h who r))
  (define ph (paint-h who paint))
  ;; SkCanvas::drawRegion decomposes the region into rectangles. That is fine
  ;; for native raster/PDF devices, but SVG serializes those rectangles
  ;; independently and browsers can expose hairline seams between touching
  ;; fill bands. A filled region is exactly represented by its boundary path,
  ;; so submit that single path for fill paints. Preserve Skia's native
  ;; rectangle semantics for stroke and stroke-and-fill paints.
  (define style
    (call-with-owned who (list ph) (lambda (pp) (sk_paint_get_style pp))))
  (if (= style 0) ; FILL_SK_PAINT_STYLE
      (with-skia ([boundary (region->path r)])
        (call-on-canvas who c (list (path-h who boundary) ph) sk_canvas_draw_path))
      (call-on-canvas who c (list rh ph) sk_canvas_draw_region)))
; canvas-clip-region! : canvas? region? [#:operation (or/c 'intersect 'difference)] -> void?
;;   Combines the current clip with the integer region in device coordinates.
(define (canvas-clip-region! c r #:operation [operation 'intersect])
  (define who 'canvas-clip-region!)
  (define op (choice who operation clip-values))
  ;; This intentionally matches native device-coordinate clipping; it does not
  ;; reinterpret region coordinates through the current canvas matrix.
  (call-on-canvas who c (list (region-h who r)) (lambda (cp rp) (sk_canvas_clip_region cp rp op))))

;; SkVertices is immutable and owns copies of its submitted data. These Racket
;; snapshots are independent too, including after explicit native closure.

;;;
;;; Triangle Meshes
;;;

; vertices? : any/c -> boolean?
;;   Returns #t for a vertices wrapper, including a closed one, and #f otherwise.
(define (vertices? v) (vertices-resource? v))
; vertices-h : symbol? vertices? -> (or/c owned? domain-resource?)
;;   Checks a triangle-mesh wrapper and retrieves its managed native handle.
(define (vertices-h who v)
  (unless (vertices? v) (raise-argument-error who "vertices?" v))
  (vertices-resource-handle v))
; checked-vertices : vertices? symbol? procedure? -> any/c
;;   Checks the mesh wrapper before returning its retained metadata.
(define (checked-vertices v who getter) (vertices-h who v) (getter v))
; vertices-mode : vertices? -> (or/c 'triangles 'triangle-strip 'triangle-fan)
;;   Returns the mesh's submitted topology.
(define (vertices-mode v) (checked-vertices v 'vertices-mode vertices-resource-mode))
; vertices-positions : vertices? -> (and/c vector? immutable?)
;;   Returns the immutable vector of immutable two-coordinate position vectors.
(define (vertices-positions v) (checked-vertices v 'vertices-positions vertices-resource-positions))
; vertices-texture-coordinates : vertices? -> (or/c #f (and/c vector? immutable?))
;;   Returns the copied immutable point vector, or #f if texture coordinates were omitted.
(define (vertices-texture-coordinates v)
  (checked-vertices v 'vertices-texture-coordinates vertices-resource-texture))
; vertices-colors : vertices? -> (or/c #f (and/c vector? immutable?))
;;   Returns the immutable packed-ARGB color vector, or #f if omitted.
(define (vertices-colors v) (checked-vertices v 'vertices-colors vertices-resource-colors))
; vertices-indices : vertices? -> (or/c #f (and/c vector? immutable?))
;;   Returns the immutable unsigned 16-bit index vector, or #f when positions are submitted directly
;;   in order.
(define (vertices-indices v) (checked-vertices v 'vertices-indices vertices-resource-indices))
; vertices-count : vertices? -> (integer-in 3 65536)
;;   Returns the number of positions, not the number of indices or triangles.
(define (vertices-count v) (vector-length (vertices-positions v)))
; make-vertices : (or/c 'triangles 'triangle-strip 'triangle-fan) (or/c list? vector?)
;   [#:texture-coordinates (or/c #f list? vector?)] [#:colors (or/c #f list? vector?)] [#:indices
;   (or/c #f list? vector?)] -> vertices?
;;   Returns an owned mesh with 3 through 65536 positions.
(define (make-vertices mode positions
                       #:texture-coordinates [tex #f]
                       #:colors [colors #f]
                       #:indices [indices #f])
  (define who 'make-vertices)
  (define-values (ps ts cs is) (geometry-vertices who mode positions tex colors indices))
  (define m (case mode [(triangles) 0] [(triangle-strip) 1] [else 2]))
  (skia-check!)
  (define pb (point-buffer ps)) (define tb (point-buffer ts))
  (define cb (vector-buffer cs _uint32)) (define ib (vector-buffer is _uint16))
  (define h
    (new-owned who 'vertices
      (lambda () (sk_vertices_make_copy m (vector-length ps) pb tb cb
                                        (if is (vector-length is) 0) ib)) sk_vertices_unref))
  (void/reference-sink pb tb cb ib)
  (make-vertices-record h mode ps ts cs is))
; draw-vertices : canvas? vertices? paint? [#:blend-mode (or/c 'clear 'src 'dst 'src-over 'dst-over
;   'src-in 'dst-in 'src-out 'dst-out 'src-atop 'dst-atop 'xor 'plus 'modulate 'screen 'overlay
;   'darken 'lighten 'color-dodge 'color-burn 'hard-light 'soft-light 'difference 'exclusion
;   'multiply 'hue 'saturation 'color 'luminosity)] -> void?
;;   Draws the live mesh with the supplied paint.
(define (draw-vertices c v paint #:blend-mode [blend 'modulate])
  (define who 'draw-vertices)
  (define mode (choice who blend blend-values))
  (call-on-canvas who c (list (vertices-h who v) (paint-h who paint))
    (lambda (cp vp pp) (sk_canvas_draw_vertices cp vp mode pp))))

;; Lattices are dimension-independent value specifications. Bounds/divisions
;; are checked against the actual image immediately before drawing.
(struct image-lattice (x-divisions y-divisions bounds cell-types colors)
  #:transparent #:constructor-name make-image-lattice-record)
;; An image-lattice is an immutable source-grid specification, independent of an image.
;;  - x-divisions  immutable vector  Strictly increasing integer column divisions.
;;  - y-divisions  immutable vector  Strictly increasing integer row divisions.
;;  - bounds       #f or immutable vector  Nonempty source x, y, width, and height;
;;                                       #f uses the actual image bounds at draw time.
;;  - cell-types   #f or immutable vector  'default, 'transparent, or 'fixed-color
;;                                       for every grid cell, in row-major order.
;;  - colors       #f or immutable vector  Packed ARGB colors in the same cell order.
;; At least one axis has a division. Explicit cell arrays cover the complete grid;
;; fixed-color cells require colors, and colors require explicit cell types.
;; Drawing checks the bounds and division coordinates against the actual image.

; cell-type-values : (hash/c symbol? exact-nonnegative-integer?)
;;   Maps the public lattice-cell choices to their native enum values.
(define cell-type-values (hasheq 'default 0 'transparent 1 'fixed-color 2))

;;;
;;; Image Lattices and Nine-Patch Drawing
;;;

; make-image-lattice : (or/c list? vector?) (or/c list? vector?) [#:bounds (or/c #f list? vector?)]
;   [#:cell-types (or/c #f list? vector?)] [#:colors (or/c #f list? vector?)] -> image-lattice?
;;   Copies strictly increasing integer division coordinates.
(define (make-image-lattice x-divisions y-divisions #:bounds [bounds #f]
                             #:cell-types [cell-types #f] #:colors [colors #f])
  (define who 'make-image-lattice)
  (define xs (geometry-divisions who x-divisions))
  (define ys (geometry-divisions who y-divisions))
  (unless (> (+ (vector-length xs) (vector-length ys)) 0)
    (raise-arguments-error who "at least one axis must contain a division"))
  (define box (and bounds (geometry-irect who bounds)))
  (when (and box (or (zero? (vector-ref box 2)) (zero? (vector-ref box 3))))
    (raise-argument-error who "nonempty source bounds" bounds))
  (define n (* (add1 (vector-length xs)) (add1 (vector-length ys))))
  (geometry-budget who n (+ (* 4 (+ (vector-length xs) (vector-length ys))) (* n 5)))
  (define types
    (and cell-types
         (let ([ts (geometry-list who cell-types)])
           (unless (= n (length ts))
             (raise-arguments-error who "cell types must cover the complete grid, row-major"
                                    "expected count" n "given" (length ts)))
           (for ([t (in-list ts)]) (choice who t cell-type-values))
           (vector->immutable-vector (list->vector ts)))))
  (define cs (geometry-colors who colors n))
  (when (and cs (not types)) (raise-arguments-error who "colors require explicit cell types"))
  (when (and types (for/or ([t (in-vector types)]) (eq? t 'fixed-color)) (not cs))
    (raise-arguments-error who "fixed-color cells require one color per grid cell"))
  (when box (check-lattice-divisions who xs ys box))
  (make-image-lattice-record xs ys box types cs))
; check-lattice-divisions : symbol? vector? vector? vector? -> void?
;;   Requires each lattice division to lie strictly inside the source x/y/width/height bounds.
(define (check-lattice-divisions who xs ys box)
  ;; Strict interior coordinates avoid the native edge-division special case,
  ;; whose rect-type array indexing otherwise changes at the outer boundary.
  (for ([x (in-vector xs)])
    (unless (< (vector-ref box 0) x (+ (vector-ref box 0) (vector-ref box 2)))
      (raise-arguments-error who "x divisions must be strictly inside source bounds" "division" x)))
  (for ([y (in-vector ys)])
    (unless (< (vector-ref box 1) y (+ (vector-ref box 1) (vector-ref box 3)))
      (raise-arguments-error who "y divisions must be strictly inside source bounds" "division" y))))
; draw-image-nine : canvas? image? (or/c (list/c exact-integer? exact-integer? exact-integer?
;   exact-integer?) (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)) real?
;   real? (and/c real? (>=/c 0)) (and/c real? (>=/c 0)) [#:sampling (or/c 'nearest 'linear)]
;   [#:paint (or/c paint? #f)] -> void?
;;   Draws the image as a nine-patch grid.
(define (draw-image-nine c im center x y width height #:sampling [filter 'linear] #:paint [paint #f])
  (define who 'draw-image-nine)
  (define ih (image-h who im))
  (define b
    (geometry-source-bounds who (geometry-irect who center) (image-width im) (image-height im)))
  (define dst (rect who x y width height))
  (define f (choice who filter sampling-values))
  (define ph (and paint (paint-h who paint)))
  (call-on-canvas who c (if ph (list ih ph) (list ih))
    (lambda (cp ip . pps)
      (sk_canvas_draw_image_nine cp ip (native-irect b) dst f (if ph (car pps) #f)))))
; draw-image-lattice : canvas? image? image-lattice? real? real? (and/c real? (>=/c 0)) (and/c real?
;   (>=/c 0)) [#:sampling (or/c 'nearest 'linear)] [#:paint (or/c paint? #f)] -> void?
;;   Draws the selected lattice inside the local destination rectangle.
(define (draw-image-lattice c im lattice x y width height
                            #:sampling [filter 'linear]
                            #:paint [paint #f])
  (define who 'draw-image-lattice)
  (define ih (image-h who im))
  (unless (image-lattice? lattice) (raise-argument-error who "image-lattice?" lattice))
  (define b
    (or (image-lattice-bounds lattice)
        (vector-immutable 0 0 (image-width im) (image-height im))))
  (geometry-source-bounds who b (image-width im) (image-height im))
  (define xs (image-lattice-x-divisions lattice))
  (define ys (image-lattice-y-divisions lattice))
  (check-lattice-divisions who xs ys b)
  (define n (* (add1 (vector-length xs)) (add1 (vector-length ys))))
  (geometry-budget who n (+ (* 4 (+ (vector-length xs) (vector-length ys))) (* n 5)))
  (define dst (rect who x y width height))
  (define f (choice who filter sampling-values))
  (define ph (and paint (paint-h who paint)))
  (call-on-canvas
   who c (if ph (list ih ph) (list ih))
   (lambda (cp ip . pps)
     (define xb (vector-buffer xs _int32)) (define yb (vector-buffer ys _int32))
     (define types (image-lattice-cell-types lattice))
     ;; The C shim reinterprets pointers without converting enum arrays. Native
     ;; SkCanvas::Lattice::RectType is uint8_t, unlike the public C enum.
     (define tb
       (and types
            (flat-buffer (for/list ([t (in-vector types)]) (hash-ref cell-type-values t)) _uint8)))
     ;; SkLatticeIter advances a color pointer alongside every cell type, even
     ;; for default/transparent cells. Supply a full zero buffer when the caller
     ;; has no fixed colors instead of relying on null-pointer arithmetic.
     (define cb (or (vector-buffer (image-lattice-colors lattice) _uint32)
                    (and types (flat-buffer (make-list n 0) _uint32))))
     (define nb (native-irect b))
     (define lat (make-sk-lattice xb yb tb (vector-length xs) (vector-length ys) nb cb))
     (sk_canvas_draw_image_lattice cp ip lat dst f (if ph (car pps) #f))
     (void/reference-sink xb yb tb cb nb lat lattice))))

;; Each transform maps a sprite's local source origin (not atlas coordinates).
(struct atlas-transform (coefficients) #:transparent #:constructor-name make-atlas-transform-record)
;; An atlas-transform is a detached native RSXform specification.
;;  - coefficients  immutable vector  scos, ssin, tx, ty, in that exact order;
;;                                    scos/ssin combine uniform scale and rotation,
;;                                    and tx/ty map the sprite-local anchor.
;; All coefficients fit drawing-scalar bounds. The origin belongs to the selected
;; sprite rectangle, not the full atlas image; no native transform is retained.

;;;
;;; Atlas Placement
;;;

; make-atlas-transform : real? real? [#:scale (and/c real? (>=/c 0))] [#:rotation real?] [#:anchor
;   (or/c (list/c real? real?) (vector/c real? real?))] -> atlas-transform?
;;   Returns a transform that maps the local anchor to coordinates x and y, with uniform scale and
;;   rotation by degrees.
(define (make-atlas-transform x y #:scale [scale 1] #:rotation [degrees 0] #:anchor [anchor '(0 0)])
  (define who 'make-atlas-transform)
  (define fx (scalar who x)) (define fy (scalar who y))
  (define s (nonnegative-scalar who scale)) (define d (scalar who degrees))
  (define a (vector-ref (geometry-points who (list anchor) 1) 0))
  (define theta (* (/ d 180.0) pi))
  (define sc (scalar who (* s (cos theta)))) (define ss (scalar who (* s (sin theta))))
  (define tx (scalar who (+ fx (- (* sc (vector-ref a 0))) (* ss (vector-ref a 1)))))
  (define ty (scalar who (- fy (* ss (vector-ref a 0)) (* sc (vector-ref a 1)))))
  (make-atlas-transform-record (vector-immutable sc ss tx ty)))
; draw-atlas : canvas? image? (or/c list? vector?) (or/c list? vector?) [#:colors (or/c #f list?
;   vector?)] [#:blend-mode (or/c 'clear 'src 'dst 'src-over 'dst-over 'src-in 'dst-in 'src-out
;   'dst-out 'src-atop 'dst-atop 'xor 'plus 'modulate 'screen 'overlay 'darken 'lighten 'color-dodge
;   'color-burn 'hard-light 'soft-light 'difference 'exclusion 'multiply 'hue 'saturation 'color
;   'luminosity)] [#:sampling (or/c 'nearest 'linear)] [#:cull (or/c #f list? vector?)] [#:paint
;   (or/c paint? #f)] -> void?
;;   Draws one image batch with matching transform and source-rectangle counts.
(define (draw-atlas c im transforms sources #:colors [colors #f] #:blend-mode [blend 'modulate]
                   #:sampling [filter 'linear] #:cull [cull #f] #:paint [paint #f])
  (define who 'draw-atlas)
  (define ih (image-h who im))
  (define ts (geometry-list who transforms)) (define boxes (geometry-list who sources))
  (define n (length ts))
  ;; The base device expands each sprite to six vertices; protect that count too.
  (geometry-budget who (* n 6) (* n (if colors 36 32)))
  (unless (= n (length boxes))
    (raise-arguments-error who "sprite transform/source counts must match"))
  (for ([t (in-list ts)])
    (unless (atlas-transform? t) (raise-argument-error who "atlas-transform?" t)))
  (define bs (for/list ([b (in-list boxes)])
               (geometry-source-bounds who (geometry-rectangle who b)
                                       (image-width im) (image-height im))))
  (define cs (geometry-colors who colors n))
  (define mode (choice who blend blend-values))
  (define samp (sampling who filter))
  (define cbounds (and cull (geometry-rectangle who cull)))
  (define ph (and paint (paint-h who paint)))
  (call-on-canvas
   who c (if ph (list ih ph) (list ih))
   (lambda (cp ip . pps)
     (unless (zero? n)
       (define xb
         (flat-buffer
          (append* (map (lambda (t) (vector->list (atlas-transform-coefficients t))) ts))
          _float))
       (define sb (flat-buffer (append* (for/list ([b (in-list bs)])
                                         (list (vector-ref b 0) (vector-ref b 1)
                                               (+ (vector-ref b 0) (vector-ref b 2))
                                               (+ (vector-ref b 1) (vector-ref b 3))))) _float))
       (define cb (vector-buffer cs _uint32))
       (define nb (and cbounds (native-rect cbounds)))
       (sk_canvas_draw_atlas cp ip xb sb cb n mode samp nb (if ph (car pps) #f))
       (void/reference-sink xb sb cb nb samp ts bs))))
  (void))

(struct cubic-patch (points colors texture-coordinates)
  #:transparent #:constructor-name make-cubic-patch-record)
;; A cubic-patch is a detached twelve-point Coons boundary specification.
;;  - points               immutable vector  Twelve immutable (x,y) vectors in
;;                                           boundary traversal order; corners
;;                                           occupy indices 0, 3, 6, and 9.
;;  - colors               #f or immutable vector  Four packed ARGB corner colors.
;;  - texture-coordinates  #f or immutable vector  Four immutable shader (x,y)
;;                                                coordinates in the same corner order.
;; Optional arrays have four entries, not twelve. Construction copies and checks
;; every coordinate; native submission buffers exist only while drawing.

;;;
;;; Cubic Patches
;;;

; make-cubic-patch : (or/c list? vector?) [#:colors (or/c #f list? vector?)] [#:texture-coordinates
;   (or/c #f list? vector?)] -> cubic-patch?
;;   Copies exactly twelve two-coordinate boundary points.
(define (make-cubic-patch points #:colors [colors #f] #:texture-coordinates [tex #f])
  (define who 'make-cubic-patch)
  (define ps (geometry-points who points 12))
  (define cs (geometry-colors who colors 4))
  (define ts (and tex (geometry-points who tex 4)))
  (geometry-budget who 12 (+ 96 (if cs 16 0) (if ts 32 0)))
  (make-cubic-patch-record ps cs ts))
; draw-patch : canvas? cubic-patch? paint? [#:blend-mode (or/c 'clear 'src 'dst 'src-over 'dst-over
;   'src-in 'dst-in 'src-out 'dst-out 'src-atop 'dst-atop 'xor 'plus 'modulate 'screen 'overlay
;   'darken 'lighten 'color-dodge 'color-burn 'hard-light 'soft-light 'difference 'exclusion
;   'multiply 'hue 'saturation 'color 'luminosity)] -> void?
;;   Tessellates and draws the patch with native Skia.
(define (draw-patch c patch paint #:blend-mode [blend 'modulate])
  (define who 'draw-patch)
  (unless (cubic-patch? patch) (raise-argument-error who "cubic-patch?" patch))
  (define mode (choice who blend blend-values))
  (geometry-budget who 12 (+ 96 (if (cubic-patch-colors patch) 16 0)
                               (if (cubic-patch-texture-coordinates patch) 32 0)))
  (call-on-canvas
   who c (list (paint-h who paint))
   (lambda (cp pp)
     (define pb (point-buffer (cubic-patch-points patch)))
     (define cb (vector-buffer (cubic-patch-colors patch) _uint32))
     (define tb (point-buffer (cubic-patch-texture-coordinates patch)))
     (sk_canvas_draw_patch cp pb cb tb mode pp)
     (void/reference-sink pb cb tb patch))))
