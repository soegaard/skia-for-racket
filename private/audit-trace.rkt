#lang racket/base
(require racket/list racket/string
         "../output-policy.rkt" (submod "../output-policy.rkt" internals))
(provide audit-allocate audit-use audit-native-call audit-on-canvas
         audit-page-index audit-labels call-with-audit-collector
         call-with-audit-raster audit-raster-annotation!
         current-output-audit-event-limit call-with-audit-matrix
         audit-resource-features call-with-output-capture audit-output-group!
         call-with-audit-gpu-raster audit-output-group-execution!)

;; Weak keys are lifetime cells. Values contain only immutable symbolic
;; summaries: no native pointer, owned cell, source program, or child wrapper.
;; This makes provenance survive explicit child closure without retaining it.
(struct provenance (kind features slots) #:transparent)
(define resources (make-weak-hasheq))
(define empty-slots (hasheq))
(define (summary h)
  (hash-ref resources h (lambda () (provenance 'unknown '(unknown-resource) empty-slots))))
(define (features h)
  (define p (summary h))
  (if (eq? (provenance-kind p) 'paint)
      (remove-duplicates (append* (hash-values (provenance-slots p))))
      (provenance-features p)))
(define (union . lists) (remove-duplicates (append* lists)))
;; Dynamic pointer associations exist only within synchronous FFI scopes.
;; They are never put into a report or into the persistent provenance table.
;; Capture authoring into a picture without publishing temporary operations in
;; the receiving document's collector. Resource provenance still accumulates.
(define (audit-resource-features handle) (features handle))
(define (call-with-output-capture thunk)
  (parameterize ([collecting #f] [raster-groups '()] [gpu-raster-target #f]) (thunk)))

;; Explicit rasterization into a recording must not erase unknown resources or
;; discarded annotations. Each sink belongs to one recorder; no pointer escapes.
(define raster-loss-sinks (make-parameter '()))
(define (retain-raster-losses! fs)
  (for ([sink (in-list (raster-loss-sinks))])
    (for ([f (in-list fs)])
      (define status (output-capability-status (output-capability-for 'raster f)))
      (when (memq status '(unknown discarded unsupported))
        (define loss (if (eq? f 'annotation) 'rasterized-annotation f))
        (set-box! sink (union (unbox sink) (list loss)))))))

(define uses (make-parameter '())) ; pairs (lifetime-cell . native-pointer)
(struct allocation (who kind deps special) #:transparent)
(define allocating (make-parameter #f))
(define (handle-for p)
  (and p (for/first ([entry (in-list (uses))] #:when (eq? p (cdr entry))) (car entry))))
(define (handle-kind h) (provenance-kind (summary h)))
(define (paint-slot h slot)
  (hash-ref (provenance-slots (summary h)) slot '(unknown-resource)))
(define (put-slot! h slot fs)
  (define old (summary h))
  (hash-set! resources h
             (provenance 'paint '() (hash-set (provenance-slots old) slot fs))))
(define getter-slots
  (hasheq 'paint-shader 'shader 'paint-path-effect 'path-effect
          'paint-color-filter 'color-filter 'paint-mask-filter 'mask-filter
          'paint-image-filter 'image-filter 'paint-blender 'blend))
(define (base-features who kind)
  (case kind
    [(shader)
     (case who
       [(make-linear-gradient-shader) '(linear-gradient)]
       [(make-radial-gradient-shader) '(radial-gradient)]
       [(make-sweep-gradient-shader) '(sweep-gradient)]
       [(make-two-point-conical-gradient-shader) '(conical-gradient)]
       [(make-color-shader) '(solid-shader)]
       [(make-image-shader) '(image-shader)]
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
    [(picture) (if (memq who '(picture-from-bytes picture-from-file))
                   '(picture deserialized-picture) '(picture))]
    [(paint picture-recorder) '()]
    [else '()]))
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
(define (collect-dependencies! hs)
  (define a (allocating))
  (when (and a (memq (allocation-kind a) '(shader color-filter image-filter mask-filter path-effect blender picture path)))
    (define dependencies
      (for/list ([h (in-list hs)]
                 #:when (memq (handle-kind h)
                              '(shader color-filter image-filter mask-filter path-effect blender picture picture-recorder path)))
        (features h)))
    (set-box! (allocation-deps a) (apply union (unbox (allocation-deps a)) dependencies))))
(define (audit-use hs ps thunk)
  (collect-dependencies! hs)
  (parameterize ([uses (append (map cons hs ps) (uses))]) (thunk)))

(struct canvas-context (operation owner backend handle others) #:transparent)
(define canvas (make-parameter #f))
;; A GPU target keeps its actual GPU lifetime/affinity checks in core.rkt.
;; Only an explicitly selected bounded output raster may use raster *document
;; representation* capabilities, and only for this exact target/lifetime cell.
;; A parameter covering a whole GPU context would incorrectly bless unrelated
;; surfaces or recordings created by the same program.
(struct gpu-raster-scope (handle creator [live? #:mutable]))
(define gpu-raster-target (make-parameter #f))
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
(define collecting (make-parameter #f))
(define audit-page-index (make-parameter 1))
(define audit-labels (make-parameter '()))
(define raster-groups (make-parameter '()))
(define current-output-audit-event-limit
  (make-parameter 100000
    (lambda (n)
      (unless (exact-positive-integer? n)
        (raise-argument-error 'current-output-audit-event-limit "exact-positive-integer?" n))
      n)))
(define (checked-collector)
  (define c (collecting))
  (when (and c (not (eq? (current-thread) (collector-creator c))))
    (error 'output-audit "an audit scope cannot be used from another Racket thread"))
  c)
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
(define matrix-features (make-parameter '()))
(define (call-with-audit-matrix general? thunk)
  (unless (boolean? general?)
    (raise-argument-error 'call-with-audit-matrix "boolean?" general?))
  (parameterize ([matrix-features (if general? '(projective-transform) '())]) (thunk)))

(define (native-feature name args)
  (case name
    [(sk_canvas_draw_paint sk_canvas_draw_line sk_canvas_draw_rect sk_canvas_draw_round_rect
      sk_canvas_draw_circle sk_canvas_draw_oval sk_canvas_draw_path
      sk_canvas_draw_arc sk_canvas_draw_rrect sk_canvas_draw_drrect) '(geometry)]
    [(sk_canvas_clear) '(geometry source-replace)]
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
    [(sk_canvas_draw_color)
     (append (if (= (list-ref args 2) 3) '(geometry) '(geometry blend-mode))
             (if (and (canvas) (eq? (canvas-context-backend (canvas)) 'recording))
                 '(recorded-color-fill) '()))]
    [(sk_canvas_save_layer) '(layer)]
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
(define (drawable? name)
  (and (or (eq? name 'sk_canvas_clear)
           (string-prefix? (symbol->string name) "sk_canvas_draw_"))
       (not (memq name '(sk_canvas_draw_url_annotation sk_canvas_draw_named_destination_annotation
                        sk_canvas_draw_link_destination_annotation)))))
(define setter-slots
  (hasheq 'sk_paint_set_shader 'shader 'sk_paint_set_path_effect 'path-effect
          'sk_paint_set_colorfilter 'color-filter 'sk_paint_set_maskfilter 'mask-filter
          'sk_paint_set_imagefilter 'image-filter 'sk_paint_set_blender 'blend))
(define (after-native! name args)
  (define slot (hash-ref setter-slots name #f))
  (cond
    [slot
     (define h (handle-for (car args)))
     (when h
       (define input (cadr args))
       (define child (handle-for input))
       (put-slot! h slot (cond [(not input) '()] [child (features child)] [else '(unknown-resource)])))]
    [(eq? name 'sk_paint_set_blendmode)
     (define h (handle-for (car args)))
     ;; Blend mode 3 is SrcOver in the pinned C enum. Replacing a custom blender
     ;; must also remove its provenance; otherwise warnings would be sticky.
     (when h (put-slot! h 'blend (if (= (cadr args) 3) '() '(blend-mode))))]
    [(eq? name 'sk_blender_new_mode)
     (define a (allocating))
     (when a (set-box! (allocation-special a) (if (= (car args) 3) '() '(blend-mode))))]
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
(define (audit-native-call name args thunk)
  (define cx (canvas))
  (define fs (and cx (native-feature name args)))
  (define all
    (and fs
         (apply union fs
                (for/list ([h (in-list (canvas-context-others cx))]
                           #:when (memq (handle-kind h) '(paint picture path unknown)))
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
(define (audit-output-group! backend raster? details)
  (emit! 'draw-output-group backend
         (list (if raster? 'raster-group 'output-group)) details))

;; This event is separate from the policy decision above. It records actual
;; raster execution/transfer after a detached image exists, not GPU availability
;; inferred merely from a symbol table. A failed export returns no report/bytes.
(define (audit-output-group-execution! backend details)
  (emit! 'execute-output-group backend '(raster-group) details))
