#lang racket/base
(require ffi/unsafe ffi/unsafe/alloc ffi/unsafe/atomic
         racket/list racket/string "audit-trace.rkt" "gpu-domain.rkt" "gpu-native-scope.rkt")
(provide owned? new-owned new-gpu-owned owned-closed? owned-close!
         call-with-owned call-with-scoped-resource
         owned-gpu-domain owned-gpu-context owned-clear-recording-affinity!
         call-with-owned-canvas lifetime-native-call)

;; A handle keeps exactly ONE native reference. Once GPU-affine, that reference
;; is managed by its gpu cell, never by an off-thread CPU destructor. Slots hold
;; detached affinity descriptions, NOT the original mutable/closeable handles.
(struct owned ([ptr #:mutable] release creator kind [gpu #:mutable] [slots #:mutable]))
(struct affinity (domain context))
(struct allocation (who kind [binding #:mutable]))
(struct canvas-use (who handle backend others))
(define uses (make-parameter '())) ; (handle . native pointer), synchronous only
(define allocating (make-parameter #f))
(define destination (make-parameter #f))
(define empty-slots (hasheq))

(define (gpu-cell h)
  (cond [(domain-resource? h) h] [(owned? h) (owned-gpu h)] [else #f]))
(define (owned-gpu-domain h)
  (define cell (gpu-cell h))
  (and cell (domain-resource-domain cell)))
(define (owned-gpu-context h)
  (define cell (gpu-cell h))
  (and cell (domain-resource-keepalive cell)))
(define (handle-kind h)
  (if (domain-resource? h) (domain-resource-kind h) (owned-kind h)))
(define (binding h)
  (define d (owned-gpu-domain h))
  (and d (affinity d (owned-gpu-context h))))
(define (join who . bindings)
  (for/fold ([result #f]) ([b (in-list bindings)] #:when b)
    (when (and result (not (eq? (affinity-domain result) (affinity-domain b))))
      (error who "resources belong to different GPU contexts; detach and upload explicitly"))
    (if (and result (affinity-context result)) result b)))
(define (slot-binding slots)
  (apply join 'gpu-affinity (hash-values slots)))
(define getter-slots
  (hasheq 'paint-shader 'shader 'paint-path-effect 'path-effect
          'paint-color-filter 'color-filter 'paint-mask-filter 'mask-filter
          'paint-image-filter 'image-filter 'paint-blender 'blend))
(define (dependency who h)
  (define slot (hash-ref getter-slots who #f))
  (if (and slot (owned? h) (eq? (owned-kind h) 'paint))
      (hash-ref (owned-slots h) slot #f)
      (binding h)))
;; These native objects cannot retain GPU content. In particular, a retained
;; color-space getter is CPU-independent even when queried on a GPU image.
(define independent-kinds
  '(surface image raster-image color-space path path-effect mask-filter
    region vertices runtime-effect font-manager font-style-set typeface font text-blob text-blob-builder shaper shaper-font
    path-measure codec encoded-data native-string data raster-buffer pixmap
    runtime-uniform-data runtime-name sksl-source sksl-diagnostic rtree-factory))
(define (collect! a handles)
  ;; Only shader masks (and retained mask getters) can inherit GPU content.
  ;; Plain blur/table masks remain independent even in an ambient GPU scope.
  (unless (and (memq (allocation-kind a) independent-kinds)
               (not (and (eq? (allocation-kind a) 'mask-filter)
                         (memq (allocation-who a)
                               '(make-shader-mask-filter paint-mask-filter)))))
    (for ([h (in-list handles)])
      ;; Destination surfaces are not dependencies of objects created while
      ;; drawing; their textures are exposed only by explicit snapshot APIs.
      (unless (memq (handle-kind h) '(surface))
        (set-allocation-binding!
         a (join (allocation-who a) (allocation-binding a)
                 (dependency (allocation-who a) h)))))))

(define (release-owned! h)
  (define ptr (owned-ptr h))
  (when ptr
    (define cell (owned-gpu h))
    (set-owned-ptr! h #f)
    (set-owned-gpu! h #f)
    (set-owned-slots! h empty-slots)
    (if cell
        (domain-resource-retire! cell)
        ((owned-release h) ptr))))
(define (install-binding! who h next)
  (define old (owned-gpu h))
  (when next
    (join who (binding h) next)
    (domain-pointer (affinity-domain next)))
  (cond
    [(and next (not old))
     (define cell
       (domain-new-resource (affinity-domain next) (owned-kind h)
         (lambda () (owned-ptr h)) (owned-release h)
         #:keepalive (affinity-context next)))
     (set-owned-gpu! h cell)]
    [(and old (not next))
     (domain-resource-take! old)
     (set-owned-gpu! h #f)])
  (void))
(define allocate-owned
  ((allocator release-owned!)
   (lambda (who kind create release a slots)
     (define ptr (create))
     (unless ptr (error who "native allocation failed for ~a" kind))
     (define h (owned ptr release (current-thread) kind #f slots))
     ;; Native creation and ownership installation run in the allocator's
     ;; atomic section. If setup fails, release the one reference right here.
     (with-handlers ([(lambda (_) #t)
                      (lambda (e) (release-owned! h) (raise e))])
       (install-binding! who h (allocation-binding a)))
     h)))
(define (new-owned who kind create release)
  (define a (allocation who kind #f))
  (collect! a (map car (uses)))
  (define copy-source
    (and (eq? who 'paint-copy)
         (for/first ([entry (in-list (uses))]
                     #:when (and (owned? (car entry)) (eq? (owned-kind (car entry)) 'paint)))
           (car entry))))
  (define slots (if copy-source (owned-slots copy-source) empty-slots))
  (audit-allocate who kind
    (lambda ()
      (parameterize ([allocating a])
        (allocate-owned who kind create release a slots)))))
(define (new-gpu-owned who kind domain context create release)
  (audit-allocate who kind
    (lambda () (domain-new-resource domain kind create release #:keepalive context))))

(define (check-thread who h)
  (unless (eq? (owned-creator h) (current-thread))
    (error who "~a belongs to another Racket thread; create separate resources in each worker"
           (owned-kind h))))
(define (owned-closed? h)
  (if (domain-resource? h) (domain-resource-closed? h) (not (owned-ptr h))))
(define release-explicitly! ((deallocator) release-owned!))
(define (owned-close! who h)
  (cond [(domain-resource? h) (domain-resource-close! h)]
        [else (check-thread who h) (release-explicitly! h)])
  (void))
;; These existing entry points promise CPU pixels or a portable serialized
;; stream. A GPU graph must not trigger a hidden readback, texture loss, or SKP
;; serialization. Metadata and native retained getters are intentionally absent.
(define cpu-only-operations
  '(image->rgba-bytes image->png-bytes image->jpeg-bytes image->webp-bytes
    image->encoded-bytes image-convert-color-space image-original-encoded-bytes
    image-subset picture->bytes picture->image
    image->non-texture-image image->raster-image image-read-pixmap!
    image-scale-pixmap! image->raster-buffer image-apply-filter))
(define (call-with-owned who handles proc)
  (call-as-atomic
   (lambda ()
     (define combined (apply join who (map binding handles)))
     (when (and combined (memq who cpu-only-operations))
       (error who "GPU-dependent input: detach explicitly with gpu-image->raster-image (or render the picture to a GPU surface first)"))
     (define pointers
       (for/list ([h (in-list handles)])
         (cond
           [(domain-resource? h) (resource-pointer h)]
           [else
            (check-thread who h)
            (unless (owned-ptr h) (error who "~a is closed" (owned-kind h)))
            (if (owned-gpu h) (resource-pointer (owned-gpu h)) (owned-ptr h))])))
     (define a (allocating))
     (when a (collect! a handles))
     (parameterize ([uses (append (map cons handles pointers) (uses))])
       (begin0 (audit-use handles pointers (lambda () (apply proc pointers)))
         (void/reference-sink handles))))))

(define (call-with-owned-canvas who handle backend others thunk)
  (define b (apply join who (map binding others)))
  (when b
    (case backend
      [(gpu)
       (unless (eq? (owned-gpu-domain handle) (affinity-domain b))
         (error who "drawing target and retained GPU inputs have different contexts"))]
      [(recording) (void)]
      [else
       (error who "GPU-dependent content cannot be drawn into a CPU/PDF/SVG target; detach explicitly")]))
  (parameterize ([destination (canvas-use who handle backend others)]) (thunk)))

(define (pointer=? a b)
  (or (eq? a b)
      (and (cpointer? a) (cpointer? b)
           (= (cast a _pointer _uintptr) (cast b _pointer _uintptr)))))
(define (handle-for p)
  (and p (for/first ([entry (in-list (uses))] #:when (pointer=? p (cdr entry)))
           (car entry))))
(define setter-slots
  (hasheq 'sk_paint_set_shader 'shader 'sk_paint_set_path_effect 'path-effect
          'sk_paint_set_colorfilter 'color-filter 'sk_paint_set_maskfilter 'mask-filter
          'sk_paint_set_imagefilter 'image-filter 'sk_paint_set_blender 'blend))
(define (set-slot/native who h slot next thunk)
  (define slots (owned-slots h))
  (define exact (hash-set slots slot next))
  ;; Keep a conservative union while entering the native setter. An exception
  ;; with indeterminate native mutation must not make finalization CPU-only.
  (define conservative (hash-set slots slot (join who (hash-ref slots slot #f) next)))
  (install-binding! who h (slot-binding conservative))
  (set-owned-slots! h conservative)
  (begin0 (thunk)
    (set-owned-slots! h exact)
    (install-binding! who h (slot-binding exact))))
(define (owned-clear-recording-affinity! h)
  (unless (and (owned? h) (eq? (owned-kind h) 'picture-recorder))
    (raise-argument-error 'owned-clear-recording-affinity! "picture-recorder handle" h))
  (call-with-owned 'owned-clear-recording-affinity! (list h)
    (lambda (_)
      (install-binding! 'owned-clear-recording-affinity! h #f)
      (set-owned-slots! h empty-slots))))

;; Called inside audit-native-call's execution thunk, never for skipped dry
;; draws. This module imports no native module, so this bridge has no cycle.
(define (lifetime-native-call name args thunk)
  ;; Keep the native pool inside the actual execution thunk, after preflight
  ;; and policy checks. Dry/skipped calls do not allocate an autorelease pool.
  (lifetime-native-call/unscoped name args
    (lambda () (call-with-gpu-native-scope thunk))))
(define (lifetime-native-call/unscoped name args thunk)
  (define slot (hash-ref setter-slots name #f))
  (define cx (destination))
  (cond
    [slot
     (define h (handle-for (car args)))
     (define p (cadr args))
     (define child (handle-for p))
     (unless (and (owned? h) (eq? (owned-kind h) 'paint) (or (not p) child))
       (error name "untracked paint/child at the safe native ownership boundary"))
     (set-slot/native name h slot (and child (binding child)) thunk)]
    [(eq? name 'sk_paint_reset)
     (define h (handle-for (car args)))
     (unless (and (owned? h) (eq? (owned-kind h) 'paint))
       (error name "untracked paint at the safe native reset boundary"))
     (begin0 (thunk)
       (set-owned-slots! h empty-slots)
       (install-binding! name h #f))]
    [(eq? name 'sk_paint_set_blendmode)
     (define h (handle-for (car args)))
     (unless (and (owned? h) (eq? (owned-kind h) 'paint))
       (error name "untracked paint at the safe native ownership boundary"))
     (set-slot/native name h 'blend #f thunk)]
    [(and cx (eq? (canvas-use-backend cx) 'recording)
          (or (string-prefix? (symbol->string name) "sk_canvas_draw_")
              (eq? name 'sk_canvas_save_layer)))
     (define h (canvas-use-handle cx))
     (define next (apply join name (binding h) (map binding (canvas-use-others cx))))
     (install-binding! name h next)
     (thunk)]
    [else (thunk)]))

(define (call-with-scoped-resource value close proc)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind void (lambda () (proc value)) (lambda () (close value))))))
