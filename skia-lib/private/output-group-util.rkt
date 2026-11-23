#lang racket/base

;;;
;;; Output Group Validation
;;;

;; Checks output-group labels, policies, geometry, and execution strategies.
;; Shares explicit fallback choices across document output groups.

(require racket/list "check.rkt" "output-util.rkt" "../output-policy.rkt")
(provide group-policy group-label group-geometry group-strategy)

; group-policy : symbol? any/c -> symbol?
;   Checks the caller's explicit vector-versus-raster fallback policy.
(define (group-policy who policy)
  (unless (memq policy '(prefer-vector require-vector raster))
    (raise-argument-error who "'prefer-vector, 'require-vector, or 'raster" policy))
  policy)

; group-label : symbol? any/c -> (or/c #f string?)
;   Copies an optional audit label containing 1 through 200 characters into an immutable string.
(define (group-label who label)
  (and label (output-label who label)))

;; Check logical bounds without imposing an RGBA allocation limit on vector
;; groups. Raster dimensions and the byte budget are checked only after choice.

; group-geometry : symbol? real? real? real? real? any/c real? -> (values real? real? real? real?
;   list? real? real? real? real?)
;   Checks logical bounds and padding; returns x, y, width, height, left/top/right/bottom insets,
;   left, top, padded width, and padded height without allocating a raster.
(define (group-geometry who x y w h padding scale)
  (define fx (scalar who x))
  (define fy (scalar who y))
  (define fw (positive-scalar who w))
  (define fh (positive-scalar who h))
  (define insets (output-insets who padding))
  (define left (car insets))
  (define top (cadr insets))
  (define bw (positive-scalar who (+ fw left (caddr insets))))
  (define bh (positive-scalar who (+ fh top (cadddr insets))))
  (scalar who (- fx left))
  (scalar who (- fy top))
  (scalar who (+ fx fw (caddr insets)))
  (scalar who (+ fy fh (cadddr insets)))
  (raster-output-scale who scale)
  (values fx fy fw fh insets left top bw bh))

;; This is deliberately a pure decision, not an analysis of native instructions.
;; Unknown provenance is never converted to a claim of safe rasterization.

; group-strategy : symbol? symbol? (listof symbol?) -> (values symbol? symbol?)
;   Chooses native execution, isolated rasterization, or rejection from declared features and
;   returns a stable audit reason; unknown provenance cannot imply safe fallback.
(define (group-strategy backend policy features)
  (unless (memq backend '(pdf svg raster))
    (raise-argument-error 'group-strategy "'pdf, 'svg, or 'raster" backend))
  (group-policy 'group-strategy policy)
  (unless (and (list? features) (andmap symbol? features))
    (raise-argument-error 'group-strategy "list of feature symbols" features))
  (define (status b f)
    (if (memq f output-feature-names)
        (output-capability-status (output-capability-for b f))
        'unknown))
  (define unknown?
    (for/or ([f (in-list features)])
      (memq (status 'raster f) '(unknown unsupported))))
  (define discarded?
    (for/or ([f (in-list features)])
      (and (not (eq? f 'annotation)) (eq? (status 'raster f) 'discarded))))
  ;; Groups have no access to the receiving backdrop. Any potentially
  ;; destination-dependent operation uses a transparent isolated surface.
  (define isolation?
    (ormap (lambda (f)
             (memq f '(source-replace blend-mode runtime-blender arithmetic-blender)))
           features))
  (define native-ok?
    (and (not isolation?)
         (or (eq? backend 'raster)
             (for/and ([f (in-list features)])
               (memq (status backend f) '(vector embedded-raster viewer-dependent))))))
  (define vector-ok?
    (and (not isolation?) (not (eq? backend 'raster))
         (for/and ([f (in-list features)]) (eq? (status backend f) 'vector))))
  (cond
    [unknown? (values 'reject 'unknown-provenance)]
    [discarded? (values 'reject 'discarded-semantics)]
    [(and (eq? policy 'require-vector) (not vector-ok?))
     (values 'reject 'vector-required)]
    [(and (not (eq? policy 'raster)) native-ok?)
     (values 'native (if (eq? backend 'raster) 'raster-target 'native-compatible))]
    [(memq 'annotation features) (values 'reject 'annotation-would-be-lost)]
    [(and (not (eq? backend 'raster)) (memq 'native-text features))
     (values 'reject 'native-text-would-be-lost)]
    [else (values 'raster (cond [(eq? policy 'raster) 'explicit-raster]
                               [isolation? 'isolated-compositing]
                               [else 'backend-fallback]))]))
