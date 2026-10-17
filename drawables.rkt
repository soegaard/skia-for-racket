#lang racket/base

;;;
;;; Native Drawables
;;;

;; Wraps recorded pictures as drawables and exposes drawing, bounds, and change queries.
;; This public layer connects reusable native drawables to the package's owned-resource and canvas
;; protocols.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe "private/core.rkt" "private/native.rkt" "private/types.rkt"
         "private/check.rkt" "private/lifetime.rkt" "private/audit-trace.rkt"
         "matrix.rkt" "pictures.rkt"
         (submod "private/core.rkt" advanced-canvas-internals))
(provide drawable? picture->drawable call-with-drawable draw-drawable
         drawable->picture drawable-bounds drawable-generation-id
         drawable-approximate-bytes-used drawable-notify-drawing-changed!)
; drawable? : any/c -> boolean?
;;   Returns #t for a drawable wrapper, including a closed one, and #f otherwise.
(define drawable? recorded-drawable?)
; drawable-h : symbol? drawable? -> (or/c owned? domain-resource?)
;;   Checks the public drawable wrapper and retrieves its managed native handle.
(define (drawable-h who d)
  (unless (drawable? d) (raise-argument-error who "drawable?" d))
  (recorded-drawable-handle d))
; picture->drawable : picture? -> drawable?
;;   Returns an owned recorded drawable capturing the picture's content, culling bounds, and nominal
;;   dimensions.
(define (picture->drawable picture)
  (define who 'picture->drawable)
  (define ph (picture-h who picture))
  (define bounds (picture-cull-bounds picture))
  (define rect-value (apply rect who (vector->list bounds)))
  (define handle
    (call-with-owned who (list ph)
      (lambda (pp)
        ;; A real native SkRecordedDrawable. Its content is a captured immutable
        ;; picture; no Racket callback can be invoked from native playback.
        ;; This keeps transitive lifetime and output provenance on the handle.
        (new-owned who 'drawable
          (lambda ()
            (call-with-native-temporary who 'drawable-recorder
              sk_picture_recorder_new sk_picture_recorder_delete
              (lambda (rp)
                (define cp (sk_picture_recorder_begin_recording rp rect-value))
                (unless cp (error who "native drawable recorder returned no canvas"))
                (sk_canvas_draw_picture cp pp #f #f)
                (sk_picture_recorder_end_recording_as_drawable rp))))
          sk_drawable_unref))))
  (void/reference-sink rect-value picture)
  (make-drawable-record handle (picture-width picture) (picture-height picture)))
; call-with-drawable : (integer-in 1 32768) (integer-in 1 32768) (-> canvas? any) -> drawable?
;;   Calls the drawing function once on a temporary picture-recording canvas, then returns the
;;   captured recorded drawable.
(define (call-with-drawable width height draw)
  ;; call-with-picture already validates dimensions/callbacks and restores its
  ;; recorder on exceptions. Capture runs exactly once and suppresses unrelated
  ;; document collection, without suppressing retained resource provenance.
  (with-skia ([p (call-with-output-capture
                  (lambda () (call-with-picture width height draw)))])
    (picture->drawable p)))
; drawable-bounds : drawable? -> (and/c (vector/c real? real? real? real?) immutable?)
;;   Returns detached native bounds as coordinates, width, and height.
(define (drawable-bounds d)
  (define who 'drawable-bounds)
  (define bounds (make-sk-rect 0.0 0.0 0.0 0.0))
  (call-with-owned who (list (drawable-h who d))
    (lambda (dp) (sk_drawable_get_bounds dp bounds)))
  (define x (scalar who (sk-rect-left bounds)))
  (define y (scalar who (sk-rect-top bounds)))
  (vector-immutable x y (nonnegative-scalar who (- (sk-rect-right bounds) x))
                    (nonnegative-scalar who (- (sk-rect-bottom bounds) y))))
; drawable-generation-id : drawable? -> exact-nonnegative-integer?
;;   Returns the native generation identifier.
(define (drawable-generation-id d)
  (call-with-owned 'drawable-generation-id (list (drawable-h 'drawable-generation-id d))
                   sk_drawable_get_generation_id))
; drawable-approximate-bytes-used : drawable? -> exact-nonnegative-integer?
;;   Returns the native storage estimate.
(define (drawable-approximate-bytes-used d)
  (call-with-owned 'drawable-approximate-bytes-used
    (list (drawable-h 'drawable-approximate-bytes-used d)) sk_drawable_approximate_bytes_used))
; drawable-notify-drawing-changed! : drawable? -> void?
;;   Invalidates generation metadata.
(define (drawable-notify-drawing-changed! d)
  ;; Invalidates native generation metadata only. It is NOT an editing API and
  ;; cannot change the captured commands or revive a closed resource.
  (call-with-owned 'drawable-notify-drawing-changed!
    (list (drawable-h 'drawable-notify-drawing-changed! d)) sk_drawable_notify_drawing_changed)
  (void))
; drawable->picture : drawable? -> picture?
;;   Returns an independently owned native picture snapshot with the drawable's nominal dimensions.
(define (drawable->picture d)
  (define who 'drawable->picture)
  (define handle
    (call-with-owned who (list (drawable-h who d))
      (lambda (dp)
        (new-owned who 'picture (lambda () (sk_drawable_new_picture_snapshot dp)) sk_picture_unref))))
  (make-picture-record handle (recorded-drawable-width d) (recorded-drawable-height d)))
; draw-drawable : canvas? drawable? [#:matrix (or/c matrix? #f)] [#:mode (or/c 'retained
;   'immediate)] -> void?
;;   Draws the recorded content with an optional affine transform.
(define (draw-drawable c d #:matrix [transform #f] #:mode [mode 'retained])
  (define who 'draw-drawable)
  (unless (memq mode '(retained immediate))
    (raise-argument-error who "'retained or 'immediate" mode))
  (unless (or (not transform) (matrix? transform))
    (raise-argument-error who "#f or affine matrix?" transform))
  (define m (and transform
                 (make-sk-matrix (matrix-xx transform) (matrix-xy transform) (matrix-x0 transform)
                                 (matrix-yx transform) (matrix-yy transform) (matrix-y0 transform)
                                 0.0 0.0 1.0)))
  (call-on-canvas who c (list (drawable-h who d))
    (lambda (cp dp)
      (if (eq? mode 'retained) (sk_canvas_draw_drawable cp dp m) (sk_drawable_draw dp cp m))
      (void/reference-sink m d)))
  (void))
