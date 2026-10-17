#lang racket/base

;;;
;;; Drawing Context Shared Data
;;;

;; Defines renderer protocols, detached drawing records, and matrix helpers.
;; Provides the common vocabulary used by the dc<%> adapter modules.

;; Backend-independent DC values. No GUI, renderer, or native allocation.

;;;
;;; Imports and Exports
;;;

(require racket/list racket/math racket/vector)
(provide (struct-out exn:fail:skia-dc:unsupported)
         dc-unsupported dc-real dc-unit dc-extent dc-matrix dc-transformation
         dc-identity dc-multiply dc-effective dc-point dc-singular?
         dc-physical-size dc-path-map dc-capabilities
         (struct-out dc-renderer) (struct-out dc-renderer+) (struct-out dc-renderer/alpha) (struct-out
           dc-renderer/styles) (struct-out dc-ink) (struct-out dc-ink/style) (struct-out
           dc-paint-source) (struct-out dc-draw)
         (struct-out dc-clip) (struct-out dc-clip-path) dc-scale-clip)

;;;
;;; Checked Values and Compatibility Errors
;;;

(struct exn:fail:skia-dc:unsupported exn:fail:contract (method feature stage) #:transparent)
;; Fields:
;;   method: requested dc<%> method symbol. feature: unsupported feature description. stage: point
;;   at which compatibility failed. Inherited exception fields carry the diagnostic and continuation
;;   marks.

; dc-unsupported : symbol? any/c [string?] -> none/c
;   Raises a structured compatibility-boundary exception naming the requested method, feature, and
;   stage.
(define (dc-unsupported who feature [stage "deferred"])
  (raise (exn:fail:skia-dc:unsupported
          (format "~a: ~a is outside skia-dc% 0.57; compatibility boundary ~a"
                  who feature stage)
          (current-continuation-marks) who feature stage)))

; dc-real : symbol? any/c -> real?
;   Validates the finite Skia binary32 coordinate range and returns an inexact real.
(define (dc-real who v)
  (unless (and (real? v) (<= -3.402823e38 v 3.402823e38))
    (raise-argument-error who "finite real in the Skia binary32 coordinate range" v))
  (exact->inexact v))

; dc-unit : symbol? any/c -> real?
;   Returns a checked inexact real in the inclusive interval from zero through one.
(define (dc-unit who v)
  (define n (dc-real who v))
  (unless (<= 0 n 1) (raise-argument-error who "real in [0,1]" v))
  n)

; dc-extent : symbol? any/c -> real?
;   Returns a checked nonnegative inexact extent within the native coordinate range.
(define (dc-extent who v)
  (define n (dc-real who v))
  (when (< n 0) (raise-argument-error who "nonnegative finite real" v))
  n)

;;;
;;; Affine Transforms and Path Coordinates
;;;

; dc-identity : (and/c vector? immutable?)
;   Stores the identity affine transform in xx/yx/xy/yy/x0/y0 coefficient order.
(define dc-identity '#(1.0 0.0 0.0 1.0 0.0 0.0))

; dc-matrix : symbol? vector? -> (and/c vector? immutable?)
;   Copies six finite affine coefficients into immutable inexact storage in Racket's matrix order.
(define (dc-matrix who v)
  (unless (and (vector? v) (= (vector-length v) 6))
    (raise-argument-error who "vector of six finite affine coefficients" v))
  (vector->immutable-vector (for/vector ([n (in-vector v)]) (dc-real who n))))

; dc-transformation : symbol? vector? -> (and/c vector? immutable?)
;   Validates and copies matrix, origin-x, origin-y, scale-x, scale-y, and rotation-in-radians
;   fields.
(define (dc-transformation who v)
  (unless (and (vector? v) (= (vector-length v) 6))
    (raise-argument-error who "#(matrix origin-x origin-y scale-x scale-y rotation)" v))
  (vector-immutable (dc-matrix who (vector-ref v 0))
                    (dc-real who (vector-ref v 1)) (dc-real who (vector-ref v 2))
                    (dc-real who (vector-ref v 3)) (dc-real who (vector-ref v 4))
                    (dc-real who (vector-ref v 5))))
;; Column-vector algebra, with Racket's #(xx yx xy yy x0 y0) ordering.

; dc-multiply : vector? vector? -> vector?
;   Composes column-vector affine transforms as a times b, applying b first and checking result
;   coordinates.
(define (dc-multiply a b)
  (define (r i) (vector-ref a i))
  (define (s i) (vector-ref b i))
  (dc-matrix 'skia-dc-transform
   (vector (+ (* (r 0) (s 0)) (* (r 2) (s 1)))
           (+ (* (r 1) (s 0)) (* (r 3) (s 1)))
           (+ (* (r 0) (s 2)) (* (r 2) (s 3)))
           (+ (* (r 1) (s 2)) (* (r 3) (s 3)))
           (+ (* (r 0) (s 4)) (* (r 2) (s 5)) (r 4))
           (+ (* (r 1) (s 4)) (* (r 3) (s 5)) (r 5)))))

; dc-effective : vector? -> vector?
;   Combines the initial matrix, origin, scales, and counterclockwise Racket rotation into one affine
;   transform.
(define (dc-effective t)
  (define a (vector-ref t 5))
  (define c (cos a))
  (define s (sin a))
  ;; Positive Racket angles turn counter-clockwise on a y-down destination.
  (dc-multiply
   (dc-multiply
    (dc-multiply (vector-ref t 0) (vector 1 0 0 1 (vector-ref t 1) (vector-ref t 2)))
    (vector (vector-ref t 3) 0 0 (vector-ref t 4) 0 0))
   (vector c (- s) s c 0 0)))

; dc-point : vector? real? real? -> (values real? real?)
;   Applies an affine matrix to one xy point and validates both resulting coordinates.
(define (dc-point m x y)
  (values (dc-real 'skia-dc-point (+ (* (vector-ref m 0) x) (* (vector-ref m 2) y) (vector-ref m 4)))
          (dc-real 'skia-dc-point (+ (* (vector-ref m 1) x) (* (vector-ref m 3) y) (vector-ref m
            5)))))

; dc-singular? : vector? -> boolean?
;   Tests whether the linear part of an affine transform has zero determinant.
(define (dc-singular? m)
  (zero? (- (* (vector-ref m 0) (vector-ref m 3)) (* (vector-ref m 1) (vector-ref m 2)))))

; dc-physical-size : symbol? exact-positive-integer? exact-positive-integer? real? -> (values
; exact-positive-integer? exact-positive-integer? real?)
;   Rounds scaled logical dimensions upward to positive signed-32-bit pixel dimensions and returns
;   the checked backing scale.
(define (dc-physical-size who width height backing)
  (unless (and (exact-positive-integer? width) (exact-positive-integer? height))
    (raise-arguments-error who "logical dimensions must be positive exact integers"
                           "width" width "height" height))
  (define b (dc-real who backing))
  (unless (> b 0) (raise-argument-error who "positive finite backing scale" backing))
  (define w (inexact->exact (ceiling (dc-real who (* width b)))))
  (define h (inexact->exact (ceiling (dc-real who (* height b)))))
  (unless (and (<= 1 w #x7fffffff) (<= 1 h #x7fffffff))
    (raise-arguments-error who "physical dimensions exceed Skia's positive int range"
                           "pixel width" w "pixel height" h))
  (values w h b))
;; Internal immutable commands: #(move x y), #(line x y), #(cubic ...), #(close).

; dc-path-map : (listof vector?) procedure? -> (listof vector?)
;   Maps every command coordinate pair through a two-value callback while preserving verbs and
;   command order.
(define (dc-path-map commands point-proc)
  (for/list ([v (in-list commands)])
    (define values-list
      (append (list (vector-ref v 0))
              (append*
               (for/list ([i (in-range 1 (vector-length v) 2)])
                 (call-with-values (lambda () (point-proc (vector-ref v i) (vector-ref v (add1 i))))
                   list)))))
    (vector->immutable-vector (list->vector values-list))))

;;;
;;; Renderer Protocol and Detached Drawing Records
;;;

;; The renderer is private injection for testing the actual class, not a public
;; fallback or pluggable Cairo backend. Public construction always uses Skia.
(struct dc-renderer (create close draw clear snapshot rgba png) #:transparent)
;; Fields:
;;   create: (pixel-width pixel-height -> target), allocating a transparent target. close:
;;   (target -> void), releasing that target. draw: (target dc-draw -> void). clear:
;;   (target clip rgba erase? -> void), using a detached device clip and RGB-byte/unit-alpha color.
;;   snapshot: (target -> image), producing an independently owned image. rgba:
;;   (target premultiplied? -> bytes), copying tightly packed RGBA. png: (target -> bytes), encoding
;;   the target. All callbacks use the target representation returned by create; snapshots do not
;;   transfer the target's ownership. Test renderers may substitute detached stand-ins.

(struct dc-renderer+ dc-renderer (measure-text draw-text glyph-exists? draw-bitmap copy)
  #:transparent)
;; Fields:
;;   measure-text: (target font-or-text-request -> width height descent leading), returning four
;;   values. draw-text: (target request matrix clip x y angle foreground background solid? -> void).
;;   glyph-exists?: (target font-request character -> boolean). draw-bitmap:
;;   (target bitmap-data rectangle matrix clip opacity sampling -> void), where rectangle stores
;;   physical source xywh followed by logical destination xywh. copy:
;;   (target matrix clip x y width height x2 y2 -> void). The callbacks borrow their target and
;;   consume detached request records, preserving the base renderer's target representation.

(struct dc-renderer/alpha dc-renderer+ (composite) #:transparent)
;; Fields:
;;   composite: (parent child clip opacity -> void), compositing a temporary child at physical
;;   origin (0,0) through the parent's saved clip and opacity in [0,1]. It borrows both targets;
;;   the alpha controller releases the child after this call, including on failure.

(struct dc-renderer/styles dc-renderer/alpha (path-bounds) #:transparent)
;; Fields:
;;   path-bounds: (commands kind ink -> left top width height), where kind is 'path, 'fill, or
;;   'stroke. It queries detached geometry and stroke settings without borrowing or changing a
;;   drawing target; the returned four values use the native path-tight-bounds convention.

(struct dc-clip (paths) #:transparent)
;; Fields:
;;   paths: ordered list of dc-clip-path constraints. Rendering intersects these paths; an empty
;;   list clips everything, unlike #f used outside this record to mean no clip. The list is detached
;;   from mutable racket/draw region objects.

(struct dc-clip-path (commands rule) #:transparent)
;; Fields:
;;   commands: ordered immutable #(move x y), #(line x y), #(cubic x1 y1 x2 y2 x y), and
;;   #(close) vectors. rule: 'winding or 'odd-even. Coordinate pairs and command order determine
;;   contour geometry; clips store these coordinates in the owning DC's device space.

; dc-scale-clip : (or/c #f dc-clip?) real? -> (or/c #f dc-clip?)
;   Scales detached clip coordinates for a backing store while preserving fill rules and unrestricted
;   #f clips.
(define (dc-scale-clip clip backing)
  (and clip
       (dc-clip
        (for/list ([p (in-list (dc-clip-paths clip))])
          (dc-clip-path
           (dc-path-map (dc-clip-path-commands p)
                        (lambda (x y) (values (dc-real 'skia-dc-clip (* backing x))
                                              (dc-real 'skia-dc-clip (* backing y)))))
           (dc-clip-path-rule p))))))
(struct dc-ink (rgba stroke? width cap join dashes) #:transparent)
;; Fields:
;;   rgba: immutable #(red green blue alpha), with byte RGB channels and real alpha in [0,1].
;;   stroke?: boolean selecting stroke instead of fill. width: nonnegative stroke width in drawing
;;   units. cap: 'butt, 'round, or 'square. join: 'miter, 'round, or 'bevel. dashes: ordered list of
;;   alternating on/off lengths; the empty list means a solid stroke. No native paint is retained.

(struct dc-ink/style dc-ink (source phase) #:transparent)
;; Fields:
;;   source: #f for solid color, otherwise a detached dc-paint-source for a gradient, hatch, or
;;   stipple. phase: real offset into the ordered dash pattern. Inherited rgba supplies either the
;;   solid color or source opacity; inherited stroke fields describe the same draw.

(struct dc-paint-source (kind data matrix) #:transparent)
;; Fields:
;;   kind: 'gradient, 'stipple, or 'hatch; data is interpreted according to this tag.
;;   Gradient data is #(linear-or-radial geometry stops): geometry lists x1/y1/x2/y2 for a line or
;;   x1/y1/r1/x2/y2/r2 for circles; stops are ordered (offset rgba-vector) lists with offsets in
;;   [0,1], preserving equal-offset order. Stipple data is dc-bitmap-data; hatch data is
;;   #(hatch-style rgba-vector). matrix: six affine source-local coefficients in xx/yx/xy/yy/x0/y0
;;   order. All payloads are detached values, not borrowed native pointers.

(struct dc-draw (commands rule matrix clip ink antialias?) #:transparent)
;; Fields:
;;   commands: ordered command vectors using the dc-clip-path vocabulary. rule: 'winding or
;;   'odd-even. matrix: six affine coefficients in xx/yx/xy/yy/x0/y0 order. clip: #f or detached
;;   dc-clip in target device coordinates. ink: dc-ink/style or dc-ink. antialias?: boolean smoothing
;;   flag. The record snapshots the state needed for replay without retaining a mutable Racket DC.

;;;
;;; Declared Baseline Capabilities
;;;

; dc-capabilities : -> (and/c hash? immutable?)
;   Reports the baseline DC implementation's declared features and limits without probing native or
;   GUI facilities.
(define (dc-capabilities)
  (hasheq 'schema 1 'stage "0.57" 'scope "wrapper-declarations" 'class "skia-dc%" 'interface "dc<%>"
          'storage "persistent-cpu-raster" 'native_probe_performed #f
          'full_drop_in_compatibility #f 'gui_initialized #f
          'drawing '(draw-arc draw-ellipse draw-line draw-lines draw-path draw-point
                              draw-polygon draw-rectangle draw-rounded-rectangle draw-spline clear
                                erase
                              draw-text draw-bitmap draw-bitmap-section copy)
          'pen_styles '(solid transparent xor hilite dot long-dash short-dash dot-dash
                              xor-dot xor-long-dash xor-short-dash xor-dot-dash)
          'brush_styles '(solid transparent opaque xor hilite panel horizontal-hatch vertical-hatch
                                cross-hatch bdiagonal-hatch fdiagonal-hatch crossdiag-hatch)
          'gradients '(linear radial) 'stipple_brushes #t 'stipple_pens #t
          'smoothing '(unsmoothed smoothed aligned)
          'alignment "finite affine row-norm snapping; no universal Cairo edge identity"
          'selection_semantics "selected pen/brush identity and locking; release on replacement/close"
          'clipping
            "region% paths and intersections; construction/install transforms; selected region locking"
          'text "Skia/HarfBuzz; characters, graphemes, combined; single-line"
          'minimum_racket "8.18" 'minimum_draw_lib "1.22"
          'recorded_procedure_replay #t 'recorded_datum_replay #t
          'alpha_groups "nested isolated raster groups; parent clip at merge; root-only snapshots"
          'path_bounds '(path fill stroke)
          'region_queries "upstream utilities with isolated query-only Cairo context; no Skia pixels"
          'deferred '(native-handle-brushes arbitrary-combined-text-breaks gui gpu)))
