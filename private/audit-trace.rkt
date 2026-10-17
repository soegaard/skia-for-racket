#lang racket/base

;;;
;;; Output Provenance and Audit Tracing
;;;

;; Tracks resource provenance and drawing events without exposing native handles.
;; Supports output diagnostics that distinguish vector commands from raster fallbacks.

(require racket/list racket/string
         "../output-policy.rkt" (submod "../output-policy.rkt" internals))
(provide call-with-audit-layer-rec audit-specialized-scope! audit-inherit-image-precision!
         audit-mark-float-pixels! audit-allocate audit-use audit-native-call audit-on-canvas
         audit-page-index audit-labels call-with-audit-collector
         call-with-audit-raster audit-raster-annotation!
         current-output-audit-event-limit call-with-audit-matrix
         audit-resource-features call-with-output-capture audit-output-group!
         call-with-audit-gpu-raster audit-output-group-execution!)

;; Weak keys are lifetime cells. Values contain only immutable symbolic
;; summaries: no native pointer, owned cell, source program, or child wrapper.
;; This makes provenance survive explicit child closure without retaining it.
(struct provenance (kind features slots) #:transparent)
;; Fields:
;;   kind: resource-kind symbol. features: detached feature-symbol list. slots: immutable hash of
;;   paint attachment names to feature lists. No field retains a native pointer or child resource.

; resources : hash?
;;   Associates weak lifetime-cell keys with detached provenance, never retaining native pointers or
;;   child resources.
(define resources (make-weak-hasheq))
; empty-slots : hash?
;;   Supplies the immutable empty attachment map for fresh paint and non-paint provenance records.
(define empty-slots (hasheq))
; summary : any/c -> any
;;   Looks up detached resource provenance and conservatively labels untracked handles as unknown.
(define (summary h)
  (hash-ref resources h (lambda () (provenance 'unknown '(unknown-resource) empty-slots))))
; features : any/c -> any
;;   Combines a paint's current attachment features or returns the resource's retained feature
;;   summary.
(define (features h)
  (define p (summary h))
  (if (eq? (provenance-kind p) 'paint)
      (remove-duplicates (append* (hash-values (provenance-slots p))))
      (provenance-features p)))
; union : any/c ... -> list?
;;   Combines feature lists without duplicates while preserving their first-occurrence order.
(define (union . lists) (remove-duplicates (append* lists)))
;; Dynamic pointer associations exist only within synchronous FFI scopes.
;; They are never put into a report or into the persistent provenance table.
;; Capture authoring into a picture without publishing temporary operations in
;; the receiving document's collector. Resource provenance still accumulates.
; audit-resource-features : any/c -> any
;;   Exposes detached provenance features without exposing the resource's native pointer or child
;;   wrappers.
(define (audit-resource-features handle) (features handle))
; call-with-output-capture : procedure? -> any
;;   Suppresses destination audit events while authored picture content continues accumulating
;;   resource provenance.
(define (call-with-output-capture thunk)
  (parameterize ([collecting #f] [raster-groups '()] [gpu-raster-target #f]) (thunk)))

;; Explicit rasterization into a recording must not erase unknown resources or
;; discarded annotations. Each sink belongs to one recorder; no pointer escapes.
; raster-loss-sinks : parameter?
;;   Holds recorder-specific boxes that retain unknown or discarded semantics across explicit
;;   rasterization.
(define raster-loss-sinks (make-parameter '()))
; retain-raster-losses! : list? -> void?
;;   Carries raster-unsupported, discarded, and unknown features into every active recording loss
;;   sink.
(define (retain-raster-losses! fs)
  (for ([sink (in-list (raster-loss-sinks))])
    (for ([f (in-list fs)])
      (define status (output-capability-status (output-capability-for 'raster f)))
      (when (memq status '(unknown discarded unsupported))
        (define loss (if (eq? f 'annotation) 'rasterized-annotation f))
        (set-box! sink (union (unbox sink) (list loss)))))))

; uses : parameter?
;;   Associates lifetime cells with borrowed native pointers only for the current synchronous FFI
;;   scope.
(define uses (make-parameter '())) ; pairs (lifetime-cell . native-pointer)
(struct allocation (who kind deps special) #:transparent)
;; Fields:
;;   who and kind: operation and resource-kind symbols. deps: box of accumulated dependency
;;   features. special: box holding an optional special provenance result. Boxes collect data only
;;   during the allocation scope.

; allocating : parameter?
;;   Identifies the allocation currently accumulating dependency and special-case provenance.
(define allocating (make-parameter #f))
; handle-for : any/c -> any
;;   Finds a native pointer's lifetime cell only among currently borrowed synchronous arguments.
(define (handle-for p)
  (and p (for/first ([entry (in-list (uses))] #:when (eq? p (cdr entry))) (car entry))))
; handle-kind : any/c -> any
;;   Returns the tracked resource kind, including the conservative unknown kind for untracked cells.
(define (handle-kind h) (provenance-kind (summary h)))
; paint-slot : any/c any/c -> any
;;   Reads one paint attachment's features and conservatively marks an untracked attachment as
;;   unknown.
(define (paint-slot h slot)
  (hash-ref (provenance-slots (summary h)) slot '(unknown-resource)))
; put-slot! : any/c any/c any/c -> void?
;;   Replaces one detached paint attachment summary without retaining the attached native resource.
(define (put-slot! h slot fs)
  (define old (summary h))
  (hash-set! resources h
             (provenance 'paint '() (hash-set (provenance-slots old) slot fs))))
; getter-slots : hash?
;;   Maps public paint getters to the attachment slot whose provenance their returned wrapper
;;   inherits.
(define getter-slots
  (hasheq 'paint-shader 'shader 'paint-path-effect 'path-effect
          'paint-color-filter 'color-filter 'paint-mask-filter 'mask-filter
          'paint-image-filter 'image-filter 'paint-blender 'blend))
; base-features : symbol? any/c -> list?
;;   Classifies constructor/resource pairs into conservative output-capability features before
;;   adding child dependencies.
(define (base-features who kind)
  (case kind
    [(shader)
     (case who
       [(make-color4f-shader make-linear-gradient-color4f-shader
         make-radial-gradient-color4f-shader make-sweep-gradient-color4f-shader
         make-two-point-conical-gradient-color4f-shader) '(float-color)]
       [(make-linear-gradient-shader) '(linear-gradient)]
       [(make-radial-gradient-shader) '(radial-gradient)]
       [(make-sweep-gradient-shader) '(sweep-gradient)]
       [(make-two-point-conical-gradient-shader) '(conical-gradient)]
       [(make-color-shader) '(solid-shader)]
       [(make-image-shader) '(image-shader)]
       [(make-raw-image-shader) '(raw-image-shader)]
       [(make-picture-shader) '(picture-shader)]
       [(make-blend-shader make-blender-shader shader-with-color-filter) '(shader-composition)]
       [(make-fractal-noise-shader make-turbulence-shader) '(perlin-noise)]
       [(make-empty-shader) '(empty-shader)]
       [(shader-with-local-matrix) '(shader-local-matrix)]
       [(runtime-effect->shader) '(runtime-shader)]
       [else '(unknown-resource)])]
    [(color-filter) (if (eq? who 'runtime-effect->color-filter)
                        '(runtime-color-filter) '(color-filter))]
    [(image-filter) '(image-filter)] [(mask-filter) '(mask-filter)]
    [(path-effect) (if (eq? who 'make-dash-path-effect) '(dash-effect) '(path-effect))]
    [(blender)
     (case who
       [(make-blend-mode-blender) '(blend-mode)]
       [(make-arithmetic-blender) '(arithmetic-blender)]
       [else '(runtime-blender)])]
    [(image raster-image) '(image)]
    [(picture) (if (memq who '(picture-from-bytes picture-from-file picture-from-stream
      picture-from-port))
                   '(picture deserialized-picture) '(picture))]
    [(drawable) '(drawable)]
    [(paint picture-recorder) '()]
    [else '()]))
; audit-allocate : symbol? any/c any/c -> any
;;   Captures constructor dependencies and special paint/picture cases into a new weakly keyed
;;   provenance record.
(define (audit-allocate who kind thunk)
  (define a (allocation who kind (box '()) (box #f)))
  (define initial-paint
    (for/first ([entry (in-list (uses))] #:when (eq? (handle-kind (car entry)) 'paint)) (car entry)))
  (define getter (hash-ref getter-slots who #f))
  (define h (parameterize ([allocating a])
              ;; Capture enclosing dependencies as well as uses inside create.
              (collect-dependencies! (map car (uses)))
              (thunk)))
  (define initial-fs
    (cond [(and getter initial-paint) (paint-slot initial-paint getter)]
          [else (union (base-features who kind) (unbox (allocation-deps a)))]))
  ;; A picture shader samples pixels; recorded URL metadata does not become
  ;; clickable shader geometry. Keep this loss visible even outside a group.
  (define fs
    (if (and (eq? who 'make-picture-shader) (memq 'annotation initial-fs))
        (union (remq 'annotation initial-fs) '(picture-shader-annotation))
        initial-fs))
  (define slots
    (if (and (eq? who 'paint-copy) initial-paint)
        (provenance-slots (summary initial-paint)) empty-slots))
  (define special (unbox (allocation-special a)))
  (hash-set! resources h (provenance kind (or special fs) slots))
  h)
; collect-dependencies! : list? -> void?
;;   Propagates relevant child features and floating-point precision requirements into the active
;;   allocation.
(define (collect-dependencies! hs)
  (define a (allocating))
  (when (and a (memq (allocation-kind a) '(shader color-filter image-filter mask-filter path-effect
    blender picture drawable path)))
    (define dependencies
      (for/list ([h (in-list hs)]
                 #:when (memq (handle-kind h)
                              '(shader color-filter image-filter mask-filter path-effect blender
                                picture drawable picture-recorder path)))
        (features h)))
    (set-box! (allocation-deps a) (apply union (unbox (allocation-deps a)) dependencies)))
  ;; Precision requirements survive image snapshots/subsets and image shaders.
  ;; rgba-bytes->image is an explicit eight-bit materialization boundary.
  (when (and a (memq (allocation-kind a) '(image raster-image shader))
             (not (eq? (allocation-who a) 'rgba-bytes->image))
             (for/or ([h (in-list hs)])
               (and (memq (handle-kind h) '(image raster-image surface))
                    (memq 'float-pixels (features h)))))
    (set-box! (allocation-deps a) (union (unbox (allocation-deps a)) '(float-pixels)))))
; audit-use : list? any/c procedure? -> any
;;   Registers ordered handle/pointer associations and collects allocation dependencies for one
;;   synchronous operation.
(define (audit-use hs ps thunk)
  (collect-dependencies! hs)
  (parameterize ([uses (append (map cons hs ps) (uses))]) (thunk)))

(struct canvas-context (operation owner backend handle others) #:transparent)
;; Fields:
;;   operation: drawing-operation symbol. owner: destination resource. backend: output backend
;;   symbol. handle: destination lifetime cell. others: ordered auxiliary lifetime cells used by
;;   this synchronous drawing call.

; canvas : parameter?
;;   Carries the active drawing destination and auxiliary handles only through the immediate native
;;   operation.
(define canvas (make-parameter #f))
;; A GPU target keeps its actual GPU lifetime/affinity checks in core.rkt.
;; Only an explicitly selected bounded output raster may use raster *document
;; representation* capabilities, and only for this exact target/lifetime cell.
;; A parameter covering a whole GPU context would incorrectly bless unrelated
;; surfaces or recordings created by the same program.
(struct gpu-raster-scope (handle creator [live? #:mutable]))
;; Fields:
;;   handle: destination lifetime cell. creator: owning Racket thread. live?: mutable scope-validity
;;   flag, cleared on exit so captured continuations cannot reuse the raster scope.

; gpu-raster-target : parameter?
;;   Identifies the exact live GPU target authorized to use bounded raster-output capability rules.
(define gpu-raster-target (make-parameter #f))
; call-with-audit-gpu-raster : any/c any/c -> any
;;   Grants raster-output audit treatment to one owner-thread target and expires the grant on scope
;;   exit.
(define (call-with-audit-gpu-raster handle thunk)
  (define scope (gpu-raster-scope handle (current-thread) #t))
  (call-with-continuation-barrier
   (lambda ()
     (parameterize ([gpu-raster-target scope])
       (dynamic-wind
         (lambda ()
           (unless (gpu-raster-scope-live? scope)
             (error 'output-audit "GPU raster audit scope has expired")))
         thunk
         (lambda () (set-gpu-raster-scope-live?! scope #f)))))))
; audit-on-canvas : any/c any/c any/c any/c any/c procedure? -> any
;;   Installs drawing provenance and checks any target-specific GPU raster authorization before the
;;   native call.
(define (audit-on-canvas operation owner backend handle others thunk)
  (define scope (gpu-raster-target))
  (define bounded?
    (and (eq? backend 'gpu) scope (eq? handle (gpu-raster-scope-handle scope))))
  (when bounded?
    (unless (and (gpu-raster-scope-live? scope)
                 (eq? (current-thread) (gpu-raster-scope-creator scope)))
      (error 'output-audit "GPU raster audit scope has expired or belongs to another thread")))
  (parameterize ([canvas (canvas-context operation owner (if bounded? 'raster backend)
                                         handle others)])
    (thunk)))

(struct collector (backend policy dry? creator pages events count next-group) #:mutable)
;; Fields:
;;   backend and policy: selected output backend and output policy. dry?: whether the collector
;;   records a dry run. creator: owner thread.
;;   pages: nonnegative supplied page count. events: emitted events, newest first until the final
;;   report reverses them. count: nonnegative emitted-event count; next-group: last allocated group
;;   number,
;;   initially zero. Fields belong to the creator; count is bounded by
;;   current-output-audit-event-limit.

; collecting : parameter?
;;   Holds the optional owner-thread collector receiving output-policy events in the current dynamic
;;   extent.
(define collecting (make-parameter #f))
; audit-page-index : parameter?
;;   Supplies the one-based page number attached to newly emitted audit events.
(define audit-page-index (make-parameter 1))
; audit-labels : parameter?
;;   Stores nested output labels innermost first; emission reverses them into outer-to-inner scope
;;   order.
(define audit-labels (make-parameter '()))
; raster-groups : parameter?
;;   Tracks nested raster group identifiers innermost first for event scope and fallback-policy
;;   interpretation.
(define raster-groups (make-parameter '()))
; current-output-audit-event-limit : parameter?
;;   Caps emitted events so oversized audits fail instead of returning an incomplete report as
;;   complete.
(define current-output-audit-event-limit
  (make-parameter 100000
    (lambda (n)
      (unless (exact-positive-integer? n)
        (raise-argument-error 'current-output-audit-event-limit "exact-positive-integer?" n))
      n)))
; checked-collector : -> any
;;   Returns the active collector only on its creating Racket thread.
(define (checked-collector)
  (define c (collecting))
  (when (and c (not (eq? (current-thread) (collector-creator c))))
    (error 'output-audit "an audit scope cannot be used from another Racket thread"))
  c)
; call-with-audit-collector : symbol? (or/c 'report 'error 'vector-only) boolean?
;   exact-nonnegative-integer? procedure?
;   -> (values any/c output-audit-report?)
;;   Runs authoring with isolated audit state and returns its result plus an arrival-ordered
;;   preflight or export report.
(define (call-with-audit-collector backend policy dry? pages thunk)
  (check-backend 'output-audit backend)
  (unless (memq policy '(report error vector-only))
    (raise-argument-error 'output-audit "'report, 'error, or 'vector-only" policy))
  (define c (collector backend policy dry? (current-thread) pages '() 0 0))
  (call-with-continuation-barrier
   (lambda ()
     (parameterize ([collecting c] [audit-page-index 1] [audit-labels '()] [raster-groups '()])
       (define result (thunk))
       (values result (output-audit-report backend pages (reverse (collector-events c))
                                          (if dry? 'preflight 'export)))))))
; emit! : any/c any/c any/c [any/c] -> void?
;;   Emits bounded, feature-sorted events for the receiving backend and enforces its strict output
;;   policy.
(define (emit! op backend fs [details (hasheq)])
  (define c (checked-collector))
  (when (and c (or (eq? backend (collector-backend c))
                  (and (eq? backend 'raster) (pair? (raster-groups)))))
    (define in-group? (and (eq? backend 'raster) (pair? (raster-groups))))
    (for ([feature (in-list (sort (remove-duplicates fs) symbol<?))])
      (when (>= (collector-count c) (current-output-audit-event-limit))
        (error 'output-audit "event limit exceeded; no complete report/output is returned"))
      (define cap (output-capability-for (if in-group? 'raster backend) feature))
      (define scope (append (reverse (audit-labels))
                            (for/list ([g (in-list (reverse (raster-groups)))])
                              (string->immutable-string (format "raster-group-~a" g)))))
      (define event
        (output-audit-event (audit-page-index) op scope feature
                            (output-capability-status cap) (output-capability-reason cap) details))
      (set-collector-count! c (add1 (collector-count c)))
      (set-collector-events! c (cons event (collector-events c)))
      (when (or (and (eq? (collector-policy c) 'error)
                     (blocking-status? (output-audit-event-status event)))
                (and (eq? (collector-policy c) 'vector-only)
                     (not (eq? (output-audit-event-status event) 'vector))))
        (raise (exn:fail:output-audit
                (format "output-audit: ~a / ~a: ~a (~a)"
                        backend op feature (output-audit-event-status event))
                (current-continuation-marks) event))))))

;; Only the synchronous matrix FFI call is wrapped, never user drawing code.
;; This also records non-affine matrix use in picture provenance when no audit
;; collector is installed. The policy is deliberately operation-conservative.
; matrix-features : parameter?
;;   Carries projective-transform evidence through the immediate matrix FFI call, including picture
;;   recording.
(define matrix-features (make-parameter '()))
; call-with-audit-matrix : boolean? procedure? -> any
;;   Marks general matrix operations as projective for the duration of their synchronous native
;;   call.
(define (call-with-audit-matrix general? thunk)
  (unless (boolean? general?)
    (raise-argument-error 'call-with-audit-matrix "boolean?" general?))
  (parameterize ([matrix-features (if general? '(projective-transform) '())]) (thunk)))

; native-feature : symbol? list? -> any
;;   Classifies reviewed native canvas operations and arguments into output features, marking
;;   unknown drawing calls conservatively.
(define (native-feature name args)
  (case name
    [(sk_canvas_draw_paint sk_canvas_draw_line sk_canvas_draw_rect sk_canvas_draw_round_rect
      sk_canvas_draw_circle sk_canvas_draw_oval sk_canvas_draw_path
      sk_canvas_draw_arc sk_canvas_draw_rrect sk_canvas_draw_drrect) '(geometry)]
    [(sk_canvas_clear) '(geometry source-replace)]
    [(sk_canvas_clear_color4f) '(geometry source-replace float-color)]
    [(sk_canvas_draw_region) '(geometry)]
    [(sk_canvas_draw_vertices) '(vertices)]
    [(sk_canvas_draw_patch) '(coons-patch)]
    [(sk_canvas_draw_atlas) '(image-atlas)]
    [(sk_canvas_draw_image_nine sk_canvas_draw_image_lattice) '(image-grid)]
    [(sk_canvas_clip_region)
     (append '(device-region-clip)
             (if (= (list-ref args 2) 0) '(clip-difference) '(clip-intersect)))]
    [(sk_canvas_draw_point) '(point-sprites)]
    [(sk_canvas_draw_points) (if (= (cadr args) 0) '(point-sprites) '(geometry))]
    [(sk_canvas_draw_color sk_canvas_draw_color4f)
     (append (if (eq? name 'sk_canvas_draw_color4f) '(float-color) '())
             (if (= (list-ref args 2) 3) '(geometry) '(geometry blend-mode))
             (if (and (canvas) (eq? (canvas-context-backend (canvas)) 'recording))
                 '(recorded-color-fill) '()))]
    [(sk_canvas_save_layer) '(layer)]
    [(sk_canvas_save_layer_rec) (cons 'layer (layer-rec-features))]
    [(sk_canvas_discard) '(discard-content)]
    [(sk_canvas_draw_drawable sk_drawable_draw) '(drawable)]
    [(sk_canvas_draw_simple_text sk_canvas_draw_text_blob) '(native-text)]
    [(sk_canvas_draw_image sk_canvas_draw_image_rect) '(image)]
    [(sk_canvas_draw_picture) '(picture)]
    [(sk_canvas_draw_url_annotation sk_canvas_draw_named_destination_annotation
      sk_canvas_draw_link_destination_annotation) '(annotation)]
    [(sk_canvas_clip_rect_with_operation sk_canvas_clip_path_with_operation)
     (list (if (= (list-ref args 2) 0) 'clip-difference 'clip-intersect))]
    [(sk_canvas_translate sk_canvas_scale sk_canvas_rotate_degrees sk_canvas_rotate_radians
      sk_canvas_skew sk_canvas_reset_matrix) '(transform)]
    [(sk_canvas_set_matrix sk_canvas_concat) (append '(transform) (matrix-features))]
    [else
     (and (string-prefix? (symbol->string name) "sk_canvas_draw_") '(unknown-operation))]))
; drawable? : symbol? -> any
;;   Recognizes native pixel-drawing operations that dry-run auditing may suppress, excluding
;;   annotations whose metadata must still be recorded.
(define (drawable? name)
  (and (or (memq name '(sk_canvas_clear sk_canvas_clear_color4f sk_drawable_draw))
           (string-prefix? (symbol->string name) "sk_canvas_draw_"))
       (not (memq name '(sk_canvas_draw_url_annotation sk_canvas_draw_named_destination_annotation
                        sk_canvas_draw_link_destination_annotation)))))
; setter-slots : hash?
;;   Maps native paint attachment setters to the provenance slot they replace after successful
;;   mutation.
(define setter-slots
  (hasheq 'sk_paint_set_shader 'shader 'sk_paint_set_path_effect 'path-effect
          'sk_paint_set_colorfilter 'color-filter 'sk_paint_set_maskfilter 'mask-filter
          'sk_paint_set_imagefilter 'image-filter 'sk_paint_set_blender 'blend))
; after-native! : any/c any/c -> void?
;;   Updates detached provenance after successful setters, resets, transformations, and recording
;;   initialization.
(define (after-native! name args)
  (define slot (hash-ref setter-slots name #f))
  (cond
    [slot
     (define h (handle-for (car args)))
     (when h
       (define input (cadr args))
       (define child (handle-for input))
       (put-slot! h slot (cond [(not input) '()] [child (features child)] [else
         '(unknown-resource)])))]
    [(eq? name 'sk_paint_set_blendmode)
     (define h (handle-for (car args)))
     ;; Blend mode 3 is SrcOver in the pinned C enum. Replacing a custom blender
     ;; must also remove its provenance; otherwise warnings would be sticky.
     (when h (put-slot! h 'blend (if (= (cadr args) 3) '() '(blend-mode))))]
    [(eq? name 'sk_blender_new_mode)
     (define a (allocating))
     (when a (set-box! (allocation-special a) (if (= (car args) 3) '() '(blend-mode))))]
    [(memq name '(sk_paint_set_color sk_paint_set_color4f))
     (define h (handle-for (car args)))
     (when h (put-slot! h 'float-color (if (eq? name 'sk_paint_set_color4f) '(float-color) '())))]
    [(eq? name 'sk_paint_set_dither)
     (define h (handle-for (car args)))
     (when h (put-slot! h 'dither (if (cadr args) '(dither) '())))]
    [(eq? name 'sk_paint_reset)
     (define h (handle-for (car args)))
     (when h (hash-set! resources h (provenance 'paint '() empty-slots)))]
    [(eq? name 'sk_path_set_filltype)
     (define h (handle-for (car args)))
     (when h (hash-set! resources h
                       (provenance 'path (if (>= (cadr args) 2) '(inverse-path) '()) empty-slots)))]
    [(eq? name 'sk_path_reset)
     (define h (handle-for (car args)))
     (when h (hash-set! resources h (provenance 'path '() empty-slots)))]
    [(eq? name 'sk_path_transform_to_dest)
     (define src (handle-for (car args)))
     (define dst (handle-for (caddr args)))
     (when (and src dst)
       (hash-set! resources dst (provenance 'path (features src) empty-slots)))]
    [(memq name '(sk_picture_recorder_begin_recording
                   sk_picture_recorder_begin_recording_with_bbh_factory))
     (define h (handle-for (car args)))
     (when h (hash-set! resources h (provenance 'picture-recorder '() empty-slots)))]
    [else (void)]))
; audit-native-call : any/c any/c procedure? -> any
;;   Records operation and dependency features before native work, suppressing drawing in dry runs
;;   and updating successful mutations.
(define (audit-native-call name args thunk)
  (define cx (canvas))
  (define fs (and cx (native-feature name args)))
  (define all
    (and fs
         (apply union fs
                (for/list ([h (in-list (canvas-context-others cx))]
                           #:when (memq (handle-kind h) '(paint picture drawable image-filter path
                             image raster-image unknown)))
                  (features h)))))
  (when (and all (eq? (canvas-context-backend cx) 'raster))
    (retain-raster-losses! all))
  (when all
    (cond
      [(eq? (canvas-context-backend cx) 'recording)
       (define h (canvas-context-handle cx))
       (define old (summary h))
       (hash-set! resources h (provenance 'picture-recorder
                                         (union (provenance-features old) all) empty-slots))]
      [else (emit! (canvas-context-operation cx) (canvas-context-backend cx) all)]))
  (define c (and all (checked-collector)))
  (define skip?
    (and c (collector-dry? c) (drawable? name)
         (eq? (canvas-context-backend cx) (collector-backend c))))
  (if skip? (void)
      (begin0 (thunk) (after-native! name args))))

; call-with-audit-raster : any/c any/c any/c any/c any/c [#:recording-handle any/c] -> any
;;   Reports an explicit raster group and carries semantic losses into an optional enclosing picture
;;   recording.
(define (call-with-audit-raster backend width height details thunk
                                #:recording-handle [recording-handle #f])
  (define losses (box '()))
  (define (run)
    (define result
      (parameterize ([raster-loss-sinks
                      (if recording-handle
                          (cons losses (raster-loss-sinks)) (raster-loss-sinks))])
        (thunk)))
    (when recording-handle
      (define old (summary recording-handle))
      (hash-set! resources recording-handle
                 (provenance 'picture-recorder
                             (union (provenance-features old) (unbox losses)) empty-slots)))
    result)
  (define c (checked-collector))
  (if (and c (or (eq? backend (collector-backend c))
                 (and (eq? backend 'raster) (pair? (raster-groups)))))
      (let ([id (add1 (collector-next-group c))])
        (set-collector-next-group! c id)
        (emit! 'draw-rasterized backend '(raster-group)
               (hash-set (hash-set details 'pixel_width width) 'pixel_height height))
        (parameterize ([raster-groups (cons id (raster-groups))]) (run)))
      (run)))
; audit-raster-annotation! : any/c any/c -> void?
;;   Records annotation loss even when the raster annotation API intentionally emits no native
;;   drawing call.
(define (audit-raster-annotation! operation backend)
  (retain-raster-losses! '(annotation))
  ;; The public annotation layer intentionally makes raster annotations no-ops.
  ;; Report their semantic loss within an explicit group even though no native
  ;; annotation call is emitted by that layer.
  (when (and (eq? backend 'raster) (pair? (raster-groups)))
    (emit! operation 'raster '(annotation))))

(module* testing #f
  (provide provenance resources summary features put-slot! uses canvas-context
           native-feature after-native! emit!))

;; A single decision event complements the ordinary replay/resource events.
;; It is emitted before destination drawing, so an outer strict policy can veto
;; a raster strategy even when the local group policy permits that strategy.
; audit-output-group! : any/c any/c any/c -> any
;;   Emits the representation decision before drawing so an enclosing strict policy can reject
;;   raster fallback.
(define (audit-output-group! backend raster? details)
  (emit! 'draw-output-group backend
         (list (if raster? 'raster-group 'output-group)) details))

;; This event is separate from the policy decision above. It records actual
;; raster execution/transfer after a detached image exists, not GPU availability
;; inferred merely from a symbol table. A failed export returns no report/bytes.
; audit-output-group-execution! : any/c any/c -> any
;;   Records actual completed raster execution and transfer separately from the earlier
;;   representation decision.
(define (audit-output-group-execution! backend details)
  (emit! 'execute-output-group backend '(raster-group) details))

;; Private precision tag, installed while the new resource is still owned.
;; Native buffers stay F16/F32; direct PDF/SVG encoding must not silently
;; quantize them. Explicit conversion to an integer image ends this requirement.
; audit-mark-float-pixels! : any/c -> void?
;;   Adds a precision requirement without changing a resource's other features or paint attachment
;;   summaries.
(define (audit-mark-float-pixels! handle)
  (define old (summary handle))
  (hash-set! resources handle
    (provenance (provenance-kind old)
                (union (provenance-features old) '(float-pixels))
                (provenance-slots old))))


;; Precision requirements survive explicit filter evaluation and owned aliases.
;; Integer pixel conversion is still the explicitly authorized loss boundary.
; audit-inherit-image-precision! : any/c list? -> void?
;;   Propagates floating-point color or pixel requirements through image aliases and filter
;;   evaluation.
(define (audit-inherit-image-precision! target sources)
  (when (for/or ([source (in-list sources)])
          (or (memq 'float-pixels (features source)) (memq 'float-color (features source))))
    (audit-mark-float-pixels! target)))


;; Dynamic options cover just the immediate native call, not application code.
; layer-rec-features : parameter?
;;   Carries save-layer options only through their immediate native call, not through user drawing
;;   callbacks.
(define layer-rec-features (make-parameter '()))
; call-with-audit-layer-rec : exact-nonnegative-integer? boolean? procedure? -> any
;;   Checks reviewed layer flags and records backdrop, initialization, LCD-text, and floating-point
;;   requirements.
(define (call-with-audit-layer-rec flags backdrop? thunk)
  (unless (and (exact-nonnegative-integer? flags) (= 0 (bitwise-and flags (bitwise-not 22)))
               (boolean? backdrop?))
    (error 'call-with-audit-layer-rec "invalid layer flag contract"))
  (parameterize ([layer-rec-features
                 (append (if backdrop? '(layer-backdrop) '())
                         (if (zero? (bitwise-and flags 4)) '() '(layer-initialization))
                         (if (zero? (bitwise-and flags 2)) '() '(layer-lcd-text))
                         (if (zero? (bitwise-and flags 16)) '() '(float-pixels)))])
    (thunk)))
; audit-specialized-scope! : -> void?
;;   Prevents diagnostic multi-sink canvases from inheriting a bounded raster target's fallback
;;   authority.
(define (audit-specialized-scope!)
  ;; A native multi-sink wrapper is not the exact bounded raster target named
  ;; by the output policy. It must not inherit that target's fallback authority.
  (when (or (pair? (raster-groups)) (gpu-raster-target))
    (error 'specialized-canvas "diagnostic canvases cannot replace a bounded output raster target")))
