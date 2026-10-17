#lang racket/base

;;;
;;; Path Transforms and Inspection
;;;

;; Converts matrix layouts, transforms resources, and snapshots path commands.
;; Extends the core geometry API without exposing native iterators or buffers.

(require ffi/unsafe racket/list
         "core.rkt" "native.rkt" "types.rkt" "lifetime.rkt" "check.rkt"
         "../matrix.rkt"
         (submod "core.rkt" path-matrix-internals))
(provide canvas-transform canvas-set-transform! canvas-concat!
         path-transform path-transform! shader-with-local-matrix
         path-segment? path-segment-verb path-segment-points
         path-segment-conic-weight path-segment-closing-line?
         path-segments in-path-segments path->commands
         path-contour? path-contour-segments path-contour-closed? path-contours
         path-measure-matrix)

;; Skia's path/shader interface uses a row-major nine-float sk_matrix_t.
; native-m33 : symbol? matrix? -> sk-matrix?
;;   Embeds the affine transform in Skia's row-major nine-float path and shader matrix layout.
(define (native-m33 who m)
  (unless (matrix? m) (raise-argument-error who "matrix?" m))
  (make-sk-matrix (matrix-xx m) (matrix-xy m) (matrix-x0 m)
                  (matrix-yx m) (matrix-yy m) (matrix-y0 m) 0.0 0.0 1.0))

; from-m33 : symbol? sk-matrix? -> matrix?
;;   Copies an affine native 3-by-3 matrix while rejecting perspective terms that the public matrix
;;   cannot represent.
(define (from-m33 who m)
  (unless (and (= (sk-matrix-p0 m) 0) (= (sk-matrix-p1 m) 0) (= (sk-matrix-p2 m) 1))
    (error who "native matrix is not affine"))
  (make-matrix (sk-matrix-xx m) (sk-matrix-yx m) (sk-matrix-xy m)
               (sk-matrix-yy m) (sk-matrix-x0 m) (sk-matrix-y0 m)))

;; IMPORTANT: m119 canvas get/set/concat take SIXTEEN floats, not sk_matrix_t.
;; The C shim reinterprets them as SkM44, whose actual storage is column-major,
;; despite the misleading row-major field-name comment in include/c/sk_types.h.
;; Translation is at float indices 12 and 13. A native translate/readback test
;; checks this independently of our write-side conversion.
; native-m44 : symbol? matrix? -> sk-m44?
;;   Embeds a two-dimensional affine transform in the column-major SkM44 storage required by canvas
;;   operations.
(define (native-m44 who m)
  (unless (matrix? m) (raise-argument-error who "matrix?" m))
  (make-sk-m44 (matrix-xx m) (matrix-yx m) 0.0 0.0
               (matrix-xy m) (matrix-yy m) 0.0 0.0
               0.0 0.0 1.0 0.0
               (matrix-x0 m) (matrix-y0 m) 0.0 1.0))

; from-m44 : symbol? sk-m44? -> matrix?
;;   Copies a native canvas transform only when all 3D and perspective terms match a two-dimensional
;;   affine matrix.
(define (from-m44 who m)
  ;; The public layer is affine 2D. Never silently discard 3D/perspective terms.
  (unless (and (= (sk-m44-c0r2 m) 0) (= (sk-m44-c0r3 m) 0)
               (= (sk-m44-c1r2 m) 0) (= (sk-m44-c1r3 m) 0)
               (= (sk-m44-c2r0 m) 0) (= (sk-m44-c2r1 m) 0)
               (= (sk-m44-c2r2 m) 1) (= (sk-m44-c2r3 m) 0)
               (= (sk-m44-c3r2 m) 0) (= (sk-m44-c3r3 m) 1))
    (error who "native canvas matrix is not a 2D affine transform"))
  (make-matrix (sk-m44-c0r0 m) (sk-m44-c0r1 m) (sk-m44-c1r0 m)
               (sk-m44-c1r1 m) (sk-m44-c3r0 m) (sk-m44-c3r1 m)))

; canvas-transform : canvas? -> matrix?
;;   Returns a detached snapshot of the current two-dimensional affine transform.
(define (canvas-transform c)
  (define who 'canvas-transform)
  (define m (native-m44 who matrix-identity))
  (call-on-canvas who c '() (lambda (cp) (sk_canvas_get_matrix cp m)))
  (from-m44 who m))

; canvas-set-transform! : canvas? matrix? -> void?
;;   Replaces the current transform with matrix.
(define (canvas-set-transform! c m)
  (define native (native-m44 'canvas-set-transform! m))
  (call-on-canvas 'canvas-set-transform! c '()
    (lambda (cp) (sk_canvas_set_matrix cp native))))

; canvas-concat! : canvas? matrix? -> void?
;;   Concatenates matrix after the current transform, using the product C M, where C is the current
;;   transform and M is matrix.
(define (canvas-concat! c m)
  (define native (native-m44 'canvas-concat! m))
  (call-on-canvas 'canvas-concat! c '()
    (lambda (cp) (sk_canvas_concat cp native))))

; path-transform : skia-path? matrix? -> skia-path?
;;   Returns a new owned path containing the affine transformation of path.
(define (path-transform p m)
  (define who 'path-transform)
  (define h (path-h who p))
  (define native (native-m33 who m))
  ;; Check source liveness/thread before allocating the destination.
  (call-with-owned who (list h) (lambda (_) (void)))
  (define out (make-path))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! out) (raise e))])
    (call-with-owned who (list h (path-h who out))
      (lambda (src dst) (sk_path_transform_to_dest src native dst)))
    out))

; path-transform! : skia-path? matrix? -> void?
;;   Applies the affine transform to path in place.
(define (path-transform! p m)
  (define h (path-h 'path-transform! p))
  (define native (native-m33 'path-transform! m))
  (call-with-owned 'path-transform! (list h)
    (lambda (pp) (sk_path_transform pp native))))

; shader-with-local-matrix : shader? matrix? -> shader?
;;   Returns a new shader whose local mapping includes matrix.
(define (shader-with-local-matrix shader m)
  (define who 'shader-with-local-matrix)
  (define h (shader-h who shader))
  (define native (native-m33 who m))
  (call-with-owned
   who (list h)
   (lambda (sp)
     (make-shader-record
      (new-owned who 'shader (lambda () (sk_shader_with_local_matrix sp native))
                 sk_shader_unref)))))

(struct path-segment (verb points conic-weight closing-line?)
  #:transparent #:constructor-name make-path-segment-record)
;; Fields:
;;   verb: 'move, 'line, 'quad, 'conic, 'cubic, or 'close. points: list of (list x y) coordinates
;;   in native iterator order: segment start, control points, then endpoint; move has one point and
;;   close has none. conic-weight: real weight only for 'conic, otherwise #f. closing-line?: whether
;;   normal iteration supplied a closing line; always #f for raw iteration and other verbs.

(struct path-contour (segments closed?)
  #:transparent #:constructor-name make-path-contour-record)
;; Fields:
;;   segments: detached path-segment list in traversal order. closed?: explicit contour closure
;;   flag. Segment order is significant and preserves native contour traversal.


; verb-names : vector?
;;   Maps native path verb codes zero through five to move, line, quad, conic, cubic, and close in
;;   ABI order.
(define verb-names '#(move line quad conic cubic close))
; verb-point-counts : vector?
;;   Gives the native iterator point count for each corresponding verb, including segment starts and
;;   control points.
(define verb-point-counts '#(1 2 3 3 4 0))

; snapshot-segments : symbol? skia-path? (or/c 'normal 'raw) boolean? -> (listof path-segment?)
;;   Copies bounded path segments while the native iterator and source are retained, so later
;;   traversal needs no native lease.
(define (snapshot-segments who p mode force-closed?)
  (define h (path-h who p))
  (unless (memq mode '(normal raw))
    (raise-argument-error who "'normal or 'raw" mode))
  (boolean who force-closed?)
  (when (and (eq? mode 'raw) force-closed?)
    (raise-arguments-error who "raw iteration cannot force contour closure"
                           "mode" mode "force-closed?" force-closed?))
  (define raw? (eq? mode 'raw))
  (define next (if raw? sk_path_rawiter_next sk_path_iter_next))
  (define conic-weight (if raw? sk_path_rawiter_conic_weight sk_path_iter_conic_weight))
  (call-with-owned
   who (list h)
   (lambda (pp)
     ;; There are no user callbacks or yields while the native iterator exists.
     ;; It cannot outlive the locked source or escape through a lazy sequence.
     (call-with-native-temporary
      who 'path-iterator
      (lambda () (if raw? (sk_path_create_rawiter pp)
                     (sk_path_create_iter pp (if force-closed? 1 0))))
      (if raw? sk_path_rawiter_destroy sk_path_iter_destroy)
      (lambda (it)
        (define buffer (malloc (* 4 (ctype-sizeof _sk-point)) 'atomic))
        (let loop ([out '()] [charged 0])
          (define verb (next it buffer))
          (cond
            [(= verb 6) (reverse out)]
            [else
             (unless (<= 0 verb 5) (error who "unexpected native path verb ~a" verb))
             (define count (vector-ref verb-point-counts verb))
             ;; A bounded logical payload, not an exact Racket heap estimate.
             (define bytes (+ charged 16 (* count (ctype-sizeof _sk-point))))
             (unless (<= bytes (current-skia-byte-limit))
               (error who "path snapshot exceeds current-skia-byte-limit"))
             (define points
               (for/list ([i (in-range count)])
                 (define point (ptr-ref buffer _sk-point i))
                 (list (scalar who (sk-point-x point)) (scalar who (sk-point-y point)))))
             ;; Never read conicWeight or isCloseLine for the wrong verb.
             (define weight (and (= verb 3) (scalar who (conic-weight it))))
             (define closing? (and (not raw?) (= verb 1)
                                   (not (zero? (sk_path_iter_is_close_line it)))))
             (loop (cons (make-path-segment-record (vector-ref verb-names verb)
                                                   points weight closing?) out)
                   bytes)])))))))

; path-segments : skia-path? [#:mode (or/c 'normal 'raw)] [#:force-closed? boolean?] -> (listof
;   path-segment?)
;;   Returns a snapshot of path segments.
(define (path-segments p #:mode [mode 'normal] #:force-closed? [force-closed? #f])
  (snapshot-segments 'path-segments p mode force-closed?))

; in-path-segments : skia-path? [#:mode (or/c 'normal 'raw)] [#:force-closed? boolean?] -> sequence?
;;   Returns a sequence over the same detached snapshot as path-segments.
(define (in-path-segments p #:mode [mode 'normal] #:force-closed? [force-closed? #f])
  ;; Snapshot NOW. Source mutation/closure before the first for iteration is safe.
  (in-list (snapshot-segments 'in-path-segments p mode force-closed?)))

; path->commands : skia-path? -> list?
;;   Returns a detached list of commands accepted by make-path, derived from raw native path
;;   iteration.
(define (path->commands p)
  (for/list ([segment (in-list (snapshot-segments 'path->commands p 'raw #f))])
    (define verb (path-segment-verb segment))
    (define points (path-segment-points segment))
    (define arguments
      (if (memq verb '(move close)) (append* points) (append* (cdr points))))
    (append (list verb) arguments
            (if (eq? verb 'conic) (list (path-segment-conic-weight segment)) '()))))

; path-contours : skia-path? [#:mode (or/c 'normal 'raw)] [#:force-closed? boolean?] -> (listof
;   path-contour?)
;;   Groups a detached segment snapshot into contours.
(define (path-contours p #:mode [mode 'normal] #:force-closed? [force-closed? #f])
  (define segments (snapshot-segments 'path-contours p mode force-closed?))
  (define (finish rev)
    (make-path-contour-record (reverse rev)
                             (and (pair? rev) (eq? (path-segment-verb (car rev)) 'close))))
  (let loop ([rest segments] [current '()] [out '()])
    (cond
      [(null? rest) (reverse (if (null? current) out (cons (finish current) out)))]
      [(and (eq? (path-segment-verb (car rest)) 'move) (pair? current))
       (loop (cdr rest) (list (car rest)) (cons (finish current) out))]
      [else (loop (cdr rest) (cons (car rest) current) out)])))

; path-measure-matrix : path-measure? (and/c real? (>=/c 0)) [#:mode (or/c 'position 'tangent
;   'position+tangent)] -> (or/c matrix? #f)
;;   Returns a detached placement matrix at distance.
(define (path-measure-matrix measure distance #:mode [mode 'position+tangent])
  (define who 'path-measure-matrix)
  (define h (path-measure-h who measure))
  (define d (nonnegative-scalar who distance))
  (define flags
    (case mode [(position) 1] [(tangent) 2] [(position+tangent) 3]
      [else (raise-argument-error who "'position, 'tangent, or 'position+tangent" mode)]))
  (define m (native-m33 who matrix-identity))
  (and (call-with-owned who (list h)
         (lambda (mp) (sk_pathmeasure_get_matrix mp d m flags)))
       (from-m33 who m)))
