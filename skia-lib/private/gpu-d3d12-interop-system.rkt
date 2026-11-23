#lang racket/base

;;;
;;; Direct3D Interoperation System
;;;

;; Coordinates Direct3D resource states, fences, and interoperation sessions.
;; Provides Windows-specific synchronization beneath the portable interoperation API.

;; Windows x64 COM only. No helper DLL is needed by applications. The
;; separately built CI producer validates these calls against the Windows SDK.
(require ffi/unsafe
         "gpu-d3d12-types.rkt" "gpu-dxgi-types.rkt"
         "gpu-d3d12-interop-policy.rkt" "gpu-provider.rkt"
         (submod "gpu-d3d12-system.rkt" dxgi-internals))
(provide make-interop-session session-description session-resource session-bridge
         session-copy-source! session-begin-target! session-return-target!
         session-complete! session-close! session-quarantine! session-info
         resource-description/native same-device/native?)

;;;
;;; COM Identity and Resource Inspection
;;;

; iid-unknown : bytes?
;   Identifies IUnknown for canonical COM object-identity comparisons.
(define iid-unknown #"\000\000\000\000\000\000\000\000\300\000\000\000\000\000\000\106")

; platform! : -> any
;   Requires Windows x64 and the reviewed Direct3D/DXGI record layouts before COM access.
(define (platform!)
  (unless (and (eq? (system-type 'os) 'windows) (eq? (system-type 'arch) 'x86_64))
    (gpu-unavailable 'd3d12-interop-platform "Direct3D interop requires Windows x64"))
  (check-dxgi-layouts!))

; checked : any/c any/c -> void?
;   Rejects a failing HRESULT while preserving the native status as hexadecimal diagnostic text.
(define (checked step hr)
  (unless (zero? hr)
    (error 'd3d12-interop "~a failed: HRESULT 0x~a" step
           (number->string (bitwise-and hr #xffffffff) 16))))

; query : any/c any/c -> any
;   Obtains one owned COM interface reference through QueryInterface.
(define (query p iid)
  (out-interface 'QueryInterface
    (lambda (out) ((method p 0 (_fun _pointer _bytes _pointer -> _int32)) p iid out))))

; child-device : any/c -> any
;   Obtains the device interface that owns a queue, texture, or fence.
(define (child-device child)
  (out-interface 'GetDevice
    (lambda (out) ((method child 7 (_fun _pointer _bytes _pointer -> _int32)) child iid-device out))))

; same-device/native? : any/c any/c -> any
;   Compares canonical IUnknown identities and releases every temporary interface reference.
(define (same-device/native? child device)
  (define cd #f) (define ci #f) (define di #f)
  (dynamic-wind void
    (lambda ()
      (set! cd (child-device child)) (set! ci (query cd iid-unknown)) (set! di (query device
        iid-unknown))
      (= (cast ci _pointer _uintptr) (cast di _pointer _uintptr)))
    (lambda () (when di (release di)) (when ci (release ci)) (when cd (release cd)))))

; resource-description/native : any/c -> any
;   Copies a Direct3D resource and heap description using the Windows aggregate-return calling
;   convention.
(define (resource-description/native resource)
  (platform!)
  (raw 56
    (lambda (out)
      ;; MS x64 COM C++ aggregate return: RCX=this, RDX=caller result buffer.
      ;; NOT (_fun _pointer -> _d3d12-resource-desc), which uses C's sret order.
      ;; The native interop suite compares this actual call with SDK C++ GetDesc.
      ((method resource 10 (_fun _pointer _pointer -> _pointer)) resource out)
      (define d (cast out _pointer _d3d12-resource-desc-pointer))
      (raw 20
        (lambda (heap)
          (raw 4
            (lambda (flags)
              (checked 'GetHeapProperties
                ((method resource 14 (_fun _pointer _pointer _pointer -> _int32)) resource heap
                  flags))
              (hasheq 'dimension (d3d12-resource-desc-dimension d)
                      'width (d3d12-resource-desc-width d) 'height (d3d12-resource-desc-height d)
                      'depth (d3d12-resource-desc-depth d) 'levels (d3d12-resource-desc-levels d)
                      'format (d3d12-resource-desc-format d) 'samples (d3d12-resource-desc-samples d)
                      'quality (d3d12-resource-desc-quality d) 'layout (d3d12-resource-desc-layout d)
                      'flags (d3d12-resource-desc-flags d) 'heap_type (ptr-ref heap _int32)
                      'heap_flags (ptr-ref flags _uint32)))))))))

;;;
;;; Session Ownership and Quarantine
;;;

(struct interop-session
  (device queue resource producer value incoming outgoing timeout description
   [fence #:mutable] [serial #:mutable] [jobs #:mutable] [bridge #:mutable]
   [state #:mutable] [current-state #:mutable] [in-flight? #:mutable]
   [producer-complete? #:mutable] [returned? #:mutable] [broken #:mutable]
   [waits #:mutable] [submissions #:mutable] [copies #:mutable]))
;; Fields:
;;   device, queue, resource, and producer: retained COM interfaces on the same Direct3D device.
;;   value: producer fence value. incoming and outgoing: declared external resource states. timeout:
;;   wait limit. description: checked detached resource metadata.
;;   fence and serial: completion fence and next signal value. jobs: retained command allocator/list
;;   jobs. bridge: optional intermediate resource. state and current-state: lifecycle and current
;;   native resource state.
;;   in-flight?, producer-complete?, and returned?: synchronization milestones. broken: saved
;;   diagnostic or #f. waits, submissions, and copies: counters. Uncertain in-flight ownership is
;;   quarantined rather than released.

; session-description : interop-session? -> any
;   Exposes the session's checked detached texture description without lending a native interface.
(define session-description interop-session-description)

; session-resource : interop-session? -> any
;   Exposes the retained source texture pointer to the private session implementation.
(define session-resource interop-session-resource)

; session-bridge : interop-session? -> any
;   Exposes the optional intermediate copy resource used by the private import path.
(define session-bridge interop-session-bridge)

; quarantined-sessions : list?
;   Keeps sessions with uncertain in-flight ownership alive until process exit instead of retrying
;   destruction.
(define quarantined-sessions '())

; session-quarantine! : interop-session? any/c -> void?
;   Records the first failure and roots the session when native completion or cleanup is uncertain.
(define (session-quarantine! s e)
  (unless (interop-session-broken s)
    (set-interop-session-broken! s
      (string->immutable-string (if (exn? e) (exn-message e) (format "~s" e))))
    (set-interop-session-state! s 'quarantined)
    ;; Never let an abandoned descriptor or finalizer free an in-flight source,
    ;; allocator or command list. This exceptional retention lasts to process exit.
    (set! quarantined-sessions (cons s quarantined-sessions))))

; session-info : interop-session? -> hash?
;   Reports synchronization milestones, state declarations, and native-copy counts as detached
;   values.
(define (session-info s)
  (hasheq 'state (symbol->string (interop-session-state s))
          'producer_completion_verified (interop-session-producer-complete? s)
          'external_state_returned (interop-session-returned? s)
          'incoming_state (symbol->string (interop-session-incoming s))
          'outgoing_state (symbol->string (interop-session-outgoing s))
          'state_declaration_verified_by_runtime #f
          'same_device_verified #t 'fence_waits (interop-session-waits s)
          'queue_submissions (interop-session-submissions s) 'native_gpu_copies
            (interop-session-copies s)
          'quarantined (and (interop-session-broken s) #t)
          'error (interop-session-broken s)
          'cpu_pixel_readbacks 0))

; make-interop-session : any/c any/c any/c any/c any/c any/c any/c any/c -> any
;   Retains same-device COM interfaces and initializes explicit resource-state/fence ownership.
(define (make-interop-session device queue resource producer value incoming outgoing timeout)
  (platform!) (interop-fence-value! value) (interop-state incoming) (interop-state outgoing)
  (interop-timeout! timeout)
  (for ([p (in-list (list device queue resource producer))])
    (unless (and p (cpointer? p)) (raise-argument-error 'd3d12-interop
      "non-null, live COM interface pointer" p)))
  (define refs '()) (define ok? #f)
  (define (retain p iid)
    (define ref (query p iid)) (set! refs (cons ref refs)) ref)
  (parameterize-break #f
    (dynamic-wind void
      (lambda ()
        (define dev (retain device iid-device)) (define q (retain queue iid-queue))
        (define r (retain resource iid-resource)) (define f (retain producer iid-fence))
        (unless (and (same-device/native? q dev) (same-device/native? r dev) (same-device/native? f
          dev))
          (error 'd3d12-interop
            "resource, producer fence and queue must belong to the exact context device"))
        (define desc (check-interop-resource! (resource-description/native r)))
        (define s (interop-session dev q r f value incoming outgoing timeout desc
                                  #f 0 '() #f 'ready (interop-state incoming) #f #f #f #f 0 0 0))
        (set! ok? #t) s)
      (lambda () (unless ok? (for ([p (in-list refs)]) (release p)))))))

;;;
;;; Device Checks and Producer Synchronization
;;;

; open! : interop-session? -> void?
;   Rejects closed or quarantined Direct3D sessions before native work.
(define (open! s)
  (when (or (eq? (interop-session-state s) 'closed) (interop-session-broken s))
    (error 'd3d12-interop "native external-resource session is ~a" (interop-session-state s))))

; device! : interop-session? -> any
;   Checks device removal before further interoperation work or synchronization.
(define (device! s)
  (checked 'GetDeviceRemovedReason
    ((method (interop-session-device s) device-removed-reason-slot (_fun _pointer -> _int32))
     (interop-session-device s))))

; wait-fence! : interop-session? any/c any/c -> any
;   Waits for the required fence value within the session timeout and records completion
;   diagnostics.
(define (wait-fence! s fence value)
  (define deadline (+ (current-inexact-monotonic-milliseconds) (interop-session-timeout s)))
  (define counted? #f)
  (let loop ()
    (device! s)
    (define done ((method fence fence-completed-slot (_fun _pointer -> _uint64)) fence))
    (when (= done #xffffffffffffffff) (error 'd3d12-interop "device lost while waiting for a fence"))
    (unless (>= done value)
      (unless counted? (set-interop-session-waits! s (add1 (interop-session-waits s))) (set! counted?
        #t))
      (when (>= (current-inexact-monotonic-milliseconds) deadline)
        (error 'd3d12-interop "fence timeout; native references retained, not released"))
      ;; No kernel event registration can outlive a timeout. Sleep yields Racket
      ;; scheduling, not a nested GUI event loop. Owner/context guards stay live.
      (sleep 0.001) (loop))))

; producer-ready! : interop-session? -> void?
;   Verifies the declared producer fence has completed before Skia touches the shared resource.
(define (producer-ready! s)
  (open! s)
  (unless (interop-session-producer-complete? s)
    (wait-fence! s (interop-session-producer s) (interop-session-value s))
    ;; Queue-side dependency is explicit as well; the bounded CPU check above
    ;; avoids poisoning the context queue with an indefinitely unsignaled wait.
    (checked 'QueueWait
      ((method (interop-session-queue s) 15 (_fun _pointer _pointer _uint64 -> _int32))
       (interop-session-queue s) (interop-session-producer s) (interop-session-value s)))
    (set-interop-session-producer-complete?! s #t)))

; ensure-fence! : interop-session? -> void?
;   Creates the session's completion fence lazily so submitted command jobs can be retired safely.
(define (ensure-fence! s)
  (unless (interop-session-fence s)
    (set-interop-session-fence! s
      (out-interface 'CreateFence
        (lambda (out)
          ((method (interop-session-device s) device-create-fence-slot
                   (_fun _pointer _uint64 _uint32 _bytes _pointer -> _int32))
           (interop-session-device s) 0 0 iid-fence out))))))

; release-jobs! : interop-session? -> any
;   Releases retained command allocators and lists only after their submitted work has completed.
(define (release-jobs! s)
  (let loop ()
    (unless (null? (interop-session-jobs s))
      (define p (car (interop-session-jobs s)))
      (set-interop-session-jobs! s (cdr (interop-session-jobs s))) (release p) (loop))))

; session-complete! : interop-session? -> any
;   Waits for outstanding session submissions before releasing command jobs or external resources.
(define (session-complete! s)
  (open! s) (ensure-fence! s)
  (when (>= (interop-session-serial s) #xfffffffffffffffe) (error 'd3d12-interop "fence overflow"))
  (define value (add1 (interop-session-serial s)))
  (set-interop-session-in-flight?! s #t)
  (checked 'QueueSignal
    ((method (interop-session-queue s) queue-signal-slot (_fun _pointer _pointer _uint64 -> _int32))
     (interop-session-queue s) (interop-session-fence s) value))
  (set-interop-session-serial! s value)
  (wait-fence! s (interop-session-fence s) value)
  (set-interop-session-in-flight?! s #f)
  (release-jobs! s))

;;;
;;; Command Submission and Resource Transitions
;;;

; commands! : interop-session? procedure? -> any
;   Records and submits a private command list while retaining its allocator until fence
;   completion.
(define (commands! s record)
  (open! s) (device! s)
  (define device (interop-session-device s))
  (define alloc
    (out-interface 'CreateCommandAllocator
      (lambda (out)
        ((method device device-create-allocator-slot (_fun _pointer _int32 _bytes _pointer -> _int32))
         device 0 iid-allocator out))))
  (set-interop-session-jobs! s (cons alloc (interop-session-jobs s)))
  (define list
    (out-interface 'CreateCommandList
      (lambda (out)
        ((method device device-create-list-slot (_fun _pointer _uint32 _int32 _pointer _pointer _bytes
          _pointer -> _int32))
         device 0 0 alloc #f iid-command-list out))))
  (set-interop-session-jobs! s (cons list (interop-session-jobs s)))
  (record list)
  (checked 'CloseCommandList ((method list list-close-slot (_fun _pointer -> _int32)) list))
  (raw 8 (lambda (p)
    (ptr-set! p _pointer list)
    (set-interop-session-in-flight?! s #t)
    ((method (interop-session-queue s) queue-execute-slot (_fun _pointer _uint32 _pointer -> _void))
     (interop-session-queue s) 1 p)))
  (set-interop-session-submissions! s (add1 (interop-session-submissions s)))
  (session-complete! s))

; barrier! : any/c any/c any/c any/c -> void?
;   Emits a transition barrier only when the before and after resource states differ.
(define (barrier! list resource before after)
  (unless (= before after)
    (define b (make-d3d12-transition 0 0 resource #xffffffff before after))
    ((method list list-barrier-slot (_fun _pointer _uint32 _d3d12-transition-pointer -> _void)) list 1
      b)))

; make-bridge! : interop-session? -> any
;   Creates a compatible private texture for importing source pixels without changing external
;   ownership.
(define (make-bridge! s)
  (define d (interop-session-description s))
  (define desc (make-d3d12-resource-desc 3 0 (hash-ref d 'width) (hash-ref d 'height) 1 1 28 1 0 0 0))
  (define heap (make-d3d12-heap-properties 1 0 0 1 1))
  (set-interop-session-bridge! s
    (out-interface 'CreateCommittedResource
      (lambda (out)
        ((method (interop-session-device s) device-create-resource-slot
                 (_fun _pointer _d3d12-heap-properties-pointer _uint32 _d3d12-resource-desc-pointer
                       _uint32 _pointer _bytes _pointer -> _int32))
         (interop-session-device s) heap 0 desc d3d12-state-copy-dest #f iid-resource out)))))

; session-copy-source! : interop-session? -> any
;   Transitions and copies the producer-complete texture into the private bridge, then restores the
;   declared outgoing state.
(define (session-copy-source! s)
  (parameterize-break #f
    (producer-ready! s) (make-bridge! s)
    (commands! s
      (lambda (list)
        (barrier! list (session-resource s) (interop-state (interop-session-incoming s))
          d3d12-state-copy-source)
        ((method list 17 (_fun _pointer _pointer _pointer -> _void)) list (session-bridge s)
          (session-resource s))
        (barrier! list (session-resource s) d3d12-state-copy-source (interop-state
          (interop-session-outgoing s)))
        (barrier! list (session-bridge s) d3d12-state-copy-dest #x80)))
    (set-interop-session-copies! s (add1 (interop-session-copies s)))
    (set-interop-session-current-state! s (interop-state (interop-session-outgoing s)))
    (set-interop-session-returned?! s #t)
    (set-interop-session-state! s 'copied)))

; session-begin-target! : interop-session? -> any
;   Establishes the producer-complete render-target state before lending the external texture to
;   Skia.
(define (session-begin-target! s)
  (parameterize-break #f
    (producer-ready! s)
    (commands! s (lambda (list)
      (barrier! list (session-resource s) (interop-state (interop-session-incoming s))
        d3d12-state-render-target)))
    (set-interop-session-current-state! s d3d12-state-render-target)
    (set-interop-session-state! s 'drawing)))

; session-return-target! : interop-session? -> any
;   Transitions a borrowed render target back to the caller's declared outgoing state.
(define (session-return-target! s)
  ;; The high-level adapter normalizes via a distinct snapshot + full src draw,
  ;; completes Ganesh work and destroys BOTH wrappers before this transition.
  (parameterize-break #f
    (commands! s (lambda (list)
      (barrier! list (session-resource s) d3d12-state-render-target (interop-state
        (interop-session-outgoing s)))))
    (set-interop-session-current-state! s (interop-state (interop-session-outgoing s)))
    (set-interop-session-returned?! s #t)
    (set-interop-session-state! s 'returned)))

;;;
;;; Session Retirement
;;;

; session-close! : interop-session? -> void?
;   Releases session-owned native interfaces only after outstanding work and return transitions are
;   settled.
(define (session-close! s)
  (unless (eq? (interop-session-state s) 'closed)
    (open! s)
    (with-handlers ([(lambda (_) #t) (lambda (e) (session-quarantine! s e) (raise e))])
      (parameterize-break #f
        ;; Closing an unused handoff must also retain the producer's resource
        ;; until its promised completion point. It does not change its state.
        (unless (interop-session-producer-complete? s) (producer-ready! s))
        (when (interop-session-in-flight? s) (session-complete! s))
        (release-jobs! s)
        (when (session-bridge s)
          (define p (session-bridge s)) (set-interop-session-bridge! s #f) (release p))
        (when (interop-session-fence s)
          (define p (interop-session-fence s)) (set-interop-session-fence! s #f) (release p))
        ;; Mark closed first; these four +1 references are never released twice.
        (set-interop-session-state! s 'closed)
        (release (interop-session-producer s)) (release (session-resource s))
        (release (interop-session-queue s)) (release (interop-session-device s))))))
