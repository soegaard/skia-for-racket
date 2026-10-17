#lang racket/base

;;;
;;; Explicit Raster Output Groups
;;;

;; Records a drawing group and chooses its permitted native or raster output representation.
;; This public compositing layer makes bounded fallback execution and its audit report explicit
;; within document rendering.

;;;
;;; Imports and Exports
;;;

(require racket/list
         "private/core.rkt"
         (submod "private/core.rkt" output-group-internals)
         "private/check.rkt"
         "private/output-util.rkt"
         "private/output-group-util.rkt"
         "private/audit-trace.rkt"
         "private/output-executor.rkt"
         "canvas-matrix.rkt"
         "projective-matrix.rkt")
(provide draw-output-group output-raster-executor?
         output-group-report? output-group-report-backend output-group-report-policy
         output-group-report-strategy output-group-report-reason
         output-group-report-bounds output-group-report-padded-bounds
         output-group-report-pixel-size output-group-report-scale
         output-group-report-features output-group-report-label output-group-report-children
         output-group-report-execution output-group-report->jsexpr
         exn:fail:output-group? exn:fail:output-group-report)

(struct output-group-report
  (backend policy strategy reason bounds padded-bounds pixel-size scale
           features label children execution)
  #:transparent #:constructor-name make-group-report)
;; An output-group-report describes one capture and its representation decision.
;;  - backend        symbol?       Receiving 'pdf, 'svg, or 'raster representation.
;;  - policy         symbol?       'prefer-vector, 'require-vector, or 'raster.
;;  - strategy       symbol?       Selected 'native, 'raster, or 'reject replay.
;;  - reason         symbol?       Stable classification explaining that choice.
;;  - bounds         immutable vector  Original destination-local x, y, width,
;;                                   and height, in that order.
;;  - padded-bounds  immutable vector  Destination-local bounds including padding,
;;                                   also x, y, width, and height.
;;  - pixel-size     #f or immutable vector  Raster width and height, in that order;
;;                                        absent for nonraster strategies.
;;  - scale          real?         Requested pixels per logical unit, 1/1024..1024.
;;  - features       (listof symbol?)  Sorted, duplicate-free feature summaries.
;;  - label          #f or immutable string  Copied author-supplied group label.
;;  - children       (listof output-group-report?)  Nested reports in capture order.
;;  - execution      immutable hash  Requested executor and observed execution
;;                                 phase/backend, including readback information.
;; Reports distinguish planned, rejected, and completed work. Children reflect
;; capture order, not another execution of author callbacks. The representation
;; backend is not a GPU backend name.

(struct exn:fail:output-group exn:fail (report) #:transparent)
;; An exn:fail:output-group preserves the rejected representation decision.
;;  - report  output-group-report?  Rejection details before destination replay.
;; The inherited fields hold the message and continuation marks. Capture callback
;; side effects may have happened even though no group reached the destination.

(struct capture-target (backend creator recording-handle executor) #:transparent)
;; A capture-target authorizes nested groups within one active recording.
;;  - backend           symbol?     Receiving 'pdf, 'svg, or 'raster representation.
;;  - creator           thread?     Thread allowed to inherit the capture state.
;;  - recording-handle  owned handle  Identity of this capture's native recorder.
;;  - executor          'cpu or output-raster-executor?  Inheritable raster executor.
;; Only that same recording handle on its creator thread may inherit the target;
;; an unrelated recorder cannot acquire a backend from ambient dynamic state.

; enclosing-target : (parameter/c (or/c #f capture-target?))
;;   Identifies the currently active output-group capture for checked nesting.
(define enclosing-target (make-parameter #f))
; enclosing-children : (parameter/c (or/c #f box?))
;;   Accumulates child reports in reverse capture order until the parent finishes.
(define enclosing-children (make-parameter #f))

; output-group-report->jsexpr : output-group-report? -> (and/c hash? immutable?)
;;   Returns a detached JSON-compatible hash of the report.
(define (output-group-report->jsexpr report)
  (unless (output-group-report? report)
    (raise-argument-error 'output-group-report->jsexpr "output-group-report?" report))
  (define (v x) (and x (vector->list x)))
  (hasheq 'backend (symbol->string (output-group-report-backend report))
          'policy (symbol->string (output-group-report-policy report))
          'strategy (symbol->string (output-group-report-strategy report))
          'reason (symbol->string (output-group-report-reason report))
          'bounds (v (output-group-report-bounds report))
          'padded_bounds (v (output-group-report-padded-bounds report))
          'pixel_size (v (output-group-report-pixel-size report))
          'scale (exact->inexact (output-group-report-scale report))
          'features (map symbol->string (output-group-report-features report))
          'label (output-group-report-label report)
          'execution (output-group-report-execution report)
          'captured_children (map output-group-report->jsexpr (output-group-report-children report))))

; reject-group! : output-group-report? -> none/c
;;   Raises a policy exception carrying a group that was not replayed to its target.
(define (reject-group! report)
  (raise (exn:fail:output-group
          (format "draw-output-group: ~a (~a, ~a); no group was drawn to the destination"
                  (output-group-report-reason report)
                  (output-group-report-backend report) (output-group-report-policy report))
          (current-continuation-marks) report)))

; draw-output-group : canvas? real? real? (and/c real? (>/c 0)) (and/c real? (>/c 0)) (-> canvas?
;   any) [#:policy (or/c 'prefer-vector 'require-vector 'raster)] [#:padding (or/c real? list?)]
;   [#:scale (real-in 1/1024 1024)] [#:color-space (or/c #f color-space?)] [#:label (or/c #f
;   string?)] [#:raster-executor (or/c #f 'cpu output-raster-executor?)] -> output-group-report?
;;   Captures draw with a borrowed recording canvas whose local origin is placed at x and y on the
;;   destination.
(define (draw-output-group c x y width height draw
                           #:policy [policy 'prefer-vector]
                           #:padding [padding 0]
                           #:scale [scale (current-raster-output-scale)]
                           #:color-space [cs #f]
                           #:label [label #f]
                           #:raster-executor [requested-executor #f])
  (define who 'draw-output-group)
  (group-policy who policy)
  (define copied-label (group-label who label))
  (output-drawing-procedure who draw)
  (define-values (fx fy fw fh insets left top bw bh)
    (group-geometry who x y width height padding scale))
  (when cs
    (unless (color-space? cs) (raise-argument-error who "color-space? or #f" cs))
    ;; Check lifetime/thread before the authoring callback, without changing it.
    (color-space-srgb? cs))
  (define receiver (output-group-canvas-backend who c)) ; checks lifetime and owning thread
  (define parent (enclosing-target))
  (when (and parent (not (eq? (current-thread) (capture-target-creator parent))))
    (error who "an output-group capture cannot be used from another Racket thread"))
  (define receiver-recording-handle
    (and (eq? receiver 'recording)
         (output-group-canvas-recording-handle who c)))
  (when (eq? receiver 'recording)
    (unless parent
      (error who
             "an ordinary picture recorder has no output backend; use groups in a document/raster callback"))
    (unless (eq? receiver-recording-handle (capture-target-recording-handle parent))
      (error who
             "a recording canvas can inherit an output backend only from its own enclosing output-group capture")))
  (define backend (if (eq? receiver 'recording) (capture-target-backend parent) receiver))
  (unless (memq backend '(pdf svg raster)) (error who "unsupported canvas backend: ~a" backend))
  ;; Inherit only through the receiver's verified enclosing capture, never an
  ;; ambient context from a callback drawing into an unrelated surface.
  (define executor
    (or requested-executor
        (and (eq? receiver 'recording) (capture-target-executor parent))
        'cpu))
  (check-output-raster-executor! who executor)
  (when (and (eq? policy 'require-vector) (eq? backend 'raster))
    (error who "require-vector is a document-output policy, not a raster-target policy"))
  (when (and (memq receiver '(pdf svg)) (not (matrix4-affine-2d? (canvas-matrix4 c))))
    (error who "outer document matrix is not affine; put perspective inside the group callback"))
  (define captured-children (box '()))
  (define parent-children (and (eq? receiver 'recording) (enclosing-children)))
  ;; All temporary resources are scoped across errors, breaks, and escapes.
  ;; A callback executes once; no preflight/retry reruns authoring side effects.
  (with-skia ([recorder (make-picture-recorder)])
       (define picture
         (call-with-output-capture
          (lambda ()
            (define rc (picture-recorder-begin-recording! recorder (- left) (- top) bw bh))
            (define capture-handle
              (output-group-canvas-recording-handle who rc))
            (parameterize ([enclosing-target
                            (capture-target backend (current-thread) capture-handle executor)]
                           [enclosing-children captured-children])
              (with-canvas-state rc
                ;; Both strategies see exactly the same padded local clip.
                (canvas-clip-rect! rc (- left) (- top) bw bh #:antialias? #f)
                (call-with-values (lambda () (draw rc)) (lambda ignored (void)))))
            (picture-recorder-finish-recording! recorder))))
       (call-with-skia-resource
        picture
        (lambda (p)
          (define fs (sort (remove-duplicates (audit-resource-features (picture-h who p))) symbol<?))
          (define-values (strategy reason) (group-strategy backend policy fs))
          (define pixels
            (and (eq? strategy 'raster)
                 (let-values ([(pw ph _l _t _w _h)
                               (rasterized-geometry who fw fh scale insets)])
                   (vector-immutable pw ph))))
          (define report
            (make-group-report backend policy strategy reason
                               (vector-immutable fx fy fw fh)
                               (vector-immutable (- fx left) (- fy top) bw bh)
                               pixels scale fs copied-label (reverse (unbox captured-children))
                               (output-execution-details
                                executor
                                (case strategy
                                  [(native) 'native] [(reject) 'rejected] [else 'planned])
                                (and (eq? strategy 'native) backend))))
          ;; Reject device-coordinate regions, whose playback ignores the
          ;; intended group-local-to-receiver transformation.
          (when (or (eq? strategy 'reject) (memq 'device-region-clip fs))
            (reject-group!
             (if (memq 'device-region-clip fs)
                 (struct-copy output-group-report report
                              [strategy 'reject] [reason 'device-space-clip]
                              [execution (output-execution-details executor 'rejected #f)]) report)))
          (define details (output-group-report->jsexpr report))
          (parameterize ([audit-labels (if copied-label
                                          (cons copied-label (audit-labels))
                                          (audit-labels))])
            (audit-output-group! receiver (eq? strategy 'raster) details)
            (case strategy
              [(native)
               (with-canvas-state c
                 (canvas-translate! c fx fy)
                 (draw-picture c p))]
              [else
               ;; Representation and the outer strict audit have already accepted
               ;; rasterization. Only now may a lazy executor acquire a GPU.
               (define plan (prepare-output-raster executor p))
               (define execution-backend (output-raster-plan-backend plan))
               (define (record-execution! phase target)
                 (set! report
                   (struct-copy output-group-report report
                     [execution (output-execution-details executor phase execution-backend
                                                          #:plan plan #:target target)])))
               (cond
                 [(eq? execution-backend 'raster)
                  ;; Preserve the existing CPU path, including its audit loss
                  ;; propagation and transparent-backdrop/bitmap-glyph behavior.
                  (draw-rasterized c fx fy fw fh (lambda (rc) (draw-picture rc p))
                                   #:padding insets #:scale scale #:color-space cs)
                  (record-execution! 'completed #f)
                  (audit-output-group-execution! receiver (output-group-report->jsexpr report))]
                 [else
                  (define pw (vector-ref pixels 0))
                  (define ph (vector-ref pixels 1))
                  ((output-raster-plan-render plan)
                   pw ph cs
                   (lambda (rc)
                     ;; Use ceil-derived pixel extents exactly like draw-rasterized.
                     ;; x/y placement stays outside the isolated local picture.
                     (canvas-scale! rc (/ pw bw) (/ ph bh))
                     (canvas-translate! rc left top)
                     (call-with-audit-raster
                      receiver pw ph
                      (hasheq 'x (- fx left) 'y (- fy top) 'width bw 'height bh
                              'execution
                              (output-execution-details executor 'planned execution-backend
                                                        #:plan plan))
                      (lambda ()
                        (parameterize ([current-text-output-mode 'native]) (draw-picture rc p)))
                      #:recording-handle receiver-recording-handle))
                   (lambda (image target)
                     (record-execution! 'rasterized target)
                     (audit-output-group-execution! receiver (output-group-report->jsexpr report))
                     (draw-image-rect c image (- fx left) (- fy top) bw bh #:sampling 'linear)
                     (record-execution! 'completed target)))])]))
          (when parent-children
            (set-box! parent-children (cons report (unbox parent-children))))
          report))))
