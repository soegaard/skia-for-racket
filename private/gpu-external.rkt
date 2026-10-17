#lang racket/base

;;;
;;; External Texture Descriptions
;;;

;; Wraps externally supplied GPU texture identities and tracks their lifetime.
;; Provides a common representation for backend-specific texture interoperation.

;; Source-only, backend-neutral, single-handoff capability. Native pointers
;; and backend factories live in explicitly unsafe modules, never this API.
(require racket/future "gpu-backends.rkt")
(provide gpu-external-texture? gpu-external-texture-info gpu-external-texture-close!
         gpu-import-image call-with-gpu-external-surface)
(struct external-texture
  (backend context generation owner description check operate retire observe [state #:mutable]))
;; Fields:
;;   backend, context, and generation: imported texture's backend and context identity. owner:
;;   creator thread. description: immutable texture metadata.
;;   check, operate, retire, and observe: backend-specific validation, use, cleanup, and diagnostic
;;   procedures. state: mutable lifetime state. The descriptor does not grant unrestricted use of
;;   the underlying pointer.

; gpu-external-texture? : any/c -> boolean?
;   Returns whether v is an external-texture handoff wrapper.
(define gpu-external-texture? external-texture?)

; current-external-operation : parameter?
;   Marks an active external-resource handoff so nested operations cannot reuse incompatible
;   borrowed state.
(define current-external-operation (make-parameter #f))

; procedure! : symbol? procedure? exact-nonnegative-integer? -> void?
;   Checks callback arity and rejects required keywords before a native resource handoff begins.
(define (procedure! who p n)
  (unless (and (procedure? p) (procedure-arity-includes? p n)
               (let-values ([(required allowed) (procedure-keywords p)]) (null? required)))
    (raise-argument-error who (format "procedure accepting ~a arguments without required keywords" n)
      p)))

; owner! : symbol? external-texture? -> void?
;   Requires the texture token's creating Racket thread and rejects execution in futures.
(define (owner! who t)
  (unless (external-texture? t) (raise-argument-error who "gpu-external-texture?" t))
  (unless (and (eq? (current-thread) (external-texture-owner t)) (not (current-future)))
    (error who "external texture belongs to another execution owner")))

; gpu-external-texture-info : gpu-external-texture? -> (and/c hash? immutable?)
;   Returns detached diagnostic information on the token's creating thread.
(define (gpu-external-texture-info t)
  (owner! 'gpu-external-texture-info t)
  (hash-set* (external-texture-description t)
    'backend (symbol->string (external-texture-backend t))
    'context_generation (external-texture-generation t)
    'handoff_state (symbol->string (external-texture-state t))
    'native ((external-texture-observe t))
    'raw_handles_exposed #f))

; gpu-external-texture-close! : gpu-external-texture? -> void?
;   Retires the token and its retained backend references on the creating execution owner.
(define (gpu-external-texture-close! t)
  (owner! 'gpu-external-texture-close! t)
  (when (eq? (external-texture-state t) 'active)
    (error 'gpu-external-texture-close! "external texture is in use"))
  (unless (eq? (external-texture-state t) 'retired)
    ;; Never retry an indeterminate retire callback. Native backends must queue
    ;; destruction on the owner; this generic object never runs a finalizer.
    (set-external-texture-state! t 'retired)
    ((external-texture-retire t)))
  (void))

; run : symbol? any/c external-texture? any/c any/c -> any
;   Consumes one ready texture handoff in its exact context and expires the callback lease on every
;   exit.
(define (run who context t mode proc)
  (owner! who t)
  (unless (eq? context (external-texture-context t))
    (error who "external texture belongs to another GPU context"))
  (unless (eq? (external-texture-state t) 'ready)
    (error who "external texture handoff is ~a; construct a new handoff for reuse"
           (external-texture-state t)))
  (when (current-external-operation) (error who
    "nested external-resource operations are not supported"))
  ((external-texture-check t) mode)
  (define entered? #f)
  (call-with-continuation-barrier
    (lambda ()
      (dynamic-wind
        (lambda ()
          (when entered? (error who "external texture handoff has expired"))
          (set! entered? #t) (set-external-texture-state! t 'active))
        (lambda ()
          (parameterize ([current-external-operation (external-texture-backend t)])
            ((external-texture-operate t) mode proc)))
        (lambda () (set-external-texture-state! t 'consumed))))))

; gpu-import-image : gpu-context? gpu-external-texture? -> gpu-image?
;   Consumes a ready token by making an independent Skia-owned GPU image in the exact associated
;   context.
(define (gpu-import-image context texture)
  (run 'gpu-import-image context texture 'copy #f))

; call-with-gpu-external-surface : gpu-context? gpu-external-texture? (-> canvas? any) -> any
;   Consumes a ready token by temporarily exposing its external texture as a drawing target.
(define (call-with-gpu-external-surface context texture proc)
  (procedure! 'call-with-gpu-external-surface proc 1)
  ;; The callback receives ONLY a borrowed Skia canvas, not a snapshot-capable
  ;; surface. Its lease expires even when the outer GPU activation survives.
  (run 'call-with-gpu-external-surface context texture 'surface proc))
(module* backend-internals #f
  (provide make-external-texture current-external-operation)

  ; make-external-texture : any/c any/c exact-positive-integer? hash? procedure? procedure?
  ;   procedure? procedure? -> external-texture?
  ;   Creates a single-use, owner-thread handoff token after validating its backend callbacks and
  ;   immutable description.
  (define (make-external-texture backend context generation description check operate retire observe)
    (check-gpu-backend! 'make-external-texture backend)
    (unless (exact-positive-integer? generation) (error 'make-external-texture "invalid generation"))
    (unless (and (hash? description) (immutable? description)) (error 'make-external-texture
      "immutable description required"))
    (procedure! 'make-external-texture check 1) (procedure! 'make-external-texture operate 2)
    (procedure! 'make-external-texture retire 0) (procedure! 'make-external-texture observe 0)
    (external-texture backend context generation (current-thread) description check operate retire
      observe 'ready)))
