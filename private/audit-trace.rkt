#lang racket/base
(require racket/list racket/string
         "../output-policy.rkt" (submod "../output-policy.rkt" internals))
(provide audit-allocate audit-use audit-native-call audit-on-canvas
         audit-page-index audit-labels call-with-audit-collector
         call-with-audit-raster audit-raster-annotation!
         current-output-audit-event-limit)

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
       [(make-blend-shader) '(shader-composition)]
       [(shader-with-local-matrix) '(shader-local-matrix)]
       [(runtime-effect->shader) '(runtime-shader)]
       [else '(unknown-resource)])]
    [(color-filter) (if (eq? who 'runtime-effect->color-filter)
                        '(runtime-color-filter) '(color-filter))]
    [(image-filter) '(image-filter)] [(mask-filter) '(mask-filter)]
    [(path-effect) (if (eq? who 'make-dash-path-effect) '(dash-effect) '(path-effect))]
    [(blender) (if (eq? who 'make-blend-mode-blender) '(blend-mode) '(runtime-blender))]
    [(image raster-image) '(image)] [(picture) '(picture)]
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
  (define fs
    (cond [(and getter initial-paint) (paint-slot initial-paint getter)]
          [else (union (base-features who kind) (unbox (allocation-deps a)))]))
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
(define (audit-on-canvas operation owner backend handle others thunk)
  (parameterize ([canvas (canvas-context operation owner backend handle others)]) (thunk)))

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

(define (native-feature name args)
  (case name
    [(sk_canvas_draw_paint sk_canvas_draw_line sk_canvas_draw_rect sk_canvas_draw_round_rect
      sk_canvas_draw_circle sk_canvas_draw_oval sk_canvas_draw_path sk_canvas_clear) '(geometry)]
    [(sk_canvas_draw_simple_text sk_canvas_draw_text_blob) '(native-text)]
    [(sk_canvas_draw_image sk_canvas_draw_image_rect) '(image)]
    [(sk_canvas_draw_picture) '(picture)]
    [(sk_canvas_draw_url_annotation sk_canvas_draw_named_destination_annotation
      sk_canvas_draw_link_destination_annotation) '(annotation)]
    [(sk_canvas_clip_rect_with_operation sk_canvas_clip_path_with_operation)
     (list (if (= (list-ref args 2) 0) 'clip-difference 'clip-intersect))]
    [(sk_canvas_translate sk_canvas_scale sk_canvas_rotate_degrees sk_canvas_rotate_radians
      sk_canvas_skew sk_canvas_reset_matrix sk_canvas_set_matrix sk_canvas_concat) '(transform)]
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
    [(eq? name 'sk_picture_recorder_begin_recording)
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

(define (call-with-audit-raster backend width height details thunk)
  (define c (checked-collector))
  (if (and c (or (eq? backend (collector-backend c))
                 (and (eq? backend 'raster) (pair? (raster-groups)))))
      (let ([id (add1 (collector-next-group c))])
        (set-collector-next-group! c id)
        (emit! 'draw-rasterized backend '(raster-group)
               (hash-set (hash-set details 'pixel_width width) 'pixel_height height))
        (parameterize ([raster-groups (cons id (raster-groups))]) (thunk)))
      (thunk)))
(define (audit-raster-annotation! operation backend)
  ;; The public annotation layer intentionally makes raster annotations no-ops.
  ;; Report their semantic loss within an explicit group even though no native
  ;; annotation call is emitted by that layer.
  (when (and (eq? backend 'raster) (pair? (raster-groups)))
    (emit! operation 'raster '(annotation))))

(module* testing #f
  (provide provenance resources summary features put-slot! uses canvas-context
           native-feature after-native! emit!))
