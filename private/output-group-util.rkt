#lang racket/base
(require racket/list "check.rkt" "output-util.rkt" "../output-policy.rkt")
(provide group-policy group-label group-geometry group-strategy)

(define (group-policy who policy)
  (unless (memq policy '(prefer-vector require-vector raster))
    (raise-argument-error who "'prefer-vector, 'require-vector, or 'raster" policy))
  policy)
(define (group-label who label)
  (unless (or (not label) (string? label))
    (raise-argument-error who "string? or #f" label))
  (and label (string->immutable-string label)))

;; Check logical bounds without imposing an RGBA allocation limit on vector
;; groups. Raster dimensions and the byte budget are checked only after choice.
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
  (define isolation? (ormap (lambda (f) (memq f '(source-replace blend-mode runtime-blender))) features))
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
