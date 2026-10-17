#lang racket/base

;;;
;;; GPU Execution Domains
;;;

;; Owns context activation, resource affinity, deferred release, and shutdown state.
;; Enforces the owner-thread and generation rules shared by all GPU backends.

(require ffi/unsafe/alloc ffi/unsafe/atomic
         racket/list racket/future "gpu-provider.rkt" "gpu-native-scope.rkt" "gpu-interop-guard.rkt")
(provide (struct-out gpu-driver)
         make-gpu-domain gpu-domain? domain-backend domain-generation domain-state
         domain-info domain-call domain-pointer domain-close! domain-abandon!
         domain-request-shutdown! drain-pending-domains! domain-drain!
         domain-live-count domain-pending-count
         domain-new-resource domain-resource?
         domain-resource-close! domain-resource-closed?
         domain-resource-domain domain-resource-keepalive domain-resource-kind
         domain-resource-retire! domain-resource-take!
         domain-capture-lease domain-check-lease! domain-lease-expired?)

;; Driver procedures are PRIVATE native operations, not application callbacks.
;; create/describe/reset/release require a current provider. abandon must follow
;; the backend's lost-context contract. GL and Metal share this state machine.
(struct gpu-driver (create release abandon reset describe))
;; Fields:
;;   create: zero-argument native-context constructor. release, abandon, reset, and describe:
;;   procedures accepting that context pointer. Native operations require the provider's current
;;   context except where abandoned-context cleanup explicitly permits otherwise.

(struct gpu-domain
  (provider driver owner generation [state #:mutable] [pointer #:mutable]
            [info #:mutable] [depth #:mutable] [live #:mutable]
            [pending #:mutable] [failed #:mutable] [requested #:mutable]))
;; Fields:
;;   provider and driver: host-context provider and native operations. owner: creator Racket thread.
;;   generation: unique domain generation used to reject stale leases.
;;   state and pointer: mutable lifecycle state and native context pointer or #f. info: immutable
;;   native diagnostic snapshot. depth: nested activation depth. live: live child-resource count.
;;   pending: release-job list, newest first, drained in reverse order. failed: quarantined failed
;;   releases. requested: shutdown reason or #f. Native work and teardown run on owner; finalizers
;;   only enqueue/request work.

(struct activation (domain generation [live? #:mutable]))
;; Fields:
;;   domain: activated GPU domain. generation: captured domain generation. live?: mutable validity
;;   flag cleared when the activation exits. All three are checked before borrowed GPU access.

(struct release-job (pointer release kind))
;; Fields:
;;   pointer: detached native resource pointer awaiting release. release: destructor procedure.
;;   kind: resource-kind symbol for diagnostics. Jobs no longer retain the public resource wrapper.

;; keepalive is normally the public gpu-context wrapper. Native root/queue
;; records do not point back to this resource or keepalive wrapper.
(struct domain-resource
  (domain generation [pointer #:mutable] release kind [keepalive #:mutable]))
;; Fields:
;;   domain and generation: owning context identity. pointer: mutable native resource pointer or #f
;;   after retirement. release: native destructor. kind: resource-kind symbol. keepalive: mutable
;;   optional public context wrapper.
;;   Retirement detaches pointer and keepalive, then schedules the destructor through the domain; a
;;   resource never migrates between generations.

; active : parameter?
;;   Identifies the dynamically active domain lease; #f means no GPU execution scope is entered.
(define active (make-parameter #f))
;; Private GUI scheduling notifications, never native destruction or user
;; drawing callbacks. Weak keys do not keep an optional GUI module alive.
; idle-notifiers : hash?
;;   Keeps weak scheduler callbacks to wake deferred GUI work after GPU scopes finish.
(define idle-notifiers (make-weak-hasheq))
; notify-domain-idle! : -> void?
;;   Notifies schedulers only after leaving GPU execution, without replacing an earlier failure.
(define (notify-domain-idle!)
  (unless (active)
    (for ([notify (in-list (hash-keys idle-notifiers))])
      ;; A scheduling failure must not hide the original GPU exception.
      (with-handlers ([(lambda (_) #t) (lambda (_) (void))]) (notify)))))
(module* presentation-internals #f
  (provide domain-execution-active? register-domain-idle-notifier!)
  ; domain-execution-active? : -> boolean?
  ;;   Reports whether any GPU activation is currently entered on this dynamic path.
  (define (domain-execution-active?) (and (active) #t))
  ; register-domain-idle-notifier! : procedure? -> void?
  ;;   Registers a weak zero-argument scheduling callback without retaining an optional GUI module.
  (define (register-domain-idle-notifier! notify)
    (unless (and (procedure? notify) (procedure-arity-includes? notify 0))
      (raise-argument-error 'register-domain-idle-notifier! "zero-argument scheduler" notify))
    (hash-set! idle-notifiers notify #t)))
; roots : hash?
;;   Retains domains awaiting explicit owner-thread teardown without retaining public wrappers.
(define roots (make-hasheq))
; claims : hash?
;;   Prevents two live domains from claiming the same backend and host-context identity.
(define claims (make-hash))
; next-generation : exact-nonnegative-integer?
;;   Provides monotonically increasing generation identities for newly created GPU domains.
(define next-generation 0)
; domain-backend : gpu-domain? -> symbol?
;;   Returns the provider's backend tag without activating the native context.
(define (domain-backend d) (gpu-provider-backend (gpu-domain-provider d)))
; domain-generation : gpu-domain? -> exact-positive-integer?
;;   Exposes the domain generation used to invalidate stale resources and leases.
(define domain-generation gpu-domain-generation)
; domain-state : gpu-domain? -> symbol?
;;   Exposes detached lifecycle state without querying native context memory.
(define domain-state gpu-domain-state)
; domain-live-count : gpu-domain? -> exact-nonnegative-integer?
;;   Exposes the number of child resources whose native references remain owned.
(define domain-live-count gpu-domain-live)
; domain-pending-count : gpu-domain? -> exact-nonnegative-integer?
;;   Counts native destructors queued for later owner-thread draining.
(define (domain-pending-count d) (length (gpu-domain-pending d)))
; claim-key : gpu-provider? -> pair?
;;   Combines backend and provider identity so independent backends cannot collide in the claim
;;   table.
(define (claim-key p) (cons (gpu-provider-backend p) (gpu-provider-key p)))
; owner! : symbol? gpu-domain? -> void?
;;   Rejects another Racket thread or a future before inspecting owner-affine GPU state.
(define (owner! who d)
  (unless (gpu-domain? d) (raise-argument-error who "gpu-domain?" d))
  (unless (and (eq? (gpu-domain-owner d) (current-thread)) (not (current-future)))
    (error who "GPU domain belongs to another execution owner; futures are not supported")))
; usable! : symbol? gpu-domain? -> void?
;;   Requires a ready, unrequested-shutdown domain and rejects forbidden interoperation reentry.
(define (usable! who d)
  (check-skia-gpu-access! who)
  (owner! who d)
  (unless (and (eq? (domain-state d) 'ready) (not (gpu-domain-requested d)))
    (error who "GPU domain is ~a~a" (domain-state d)
           (if (gpu-domain-requested d) " (shutdown requested)" ""))))
; current! : symbol? gpu-domain? -> void?
;;   Requires a live activation of the same domain generation and the provider's current native
;;   context.
(define (current! who d)
  (owner! who d)
  (define a (active))
  (unless (and a (activation-live? a) (eq? d (activation-domain a))
               (= (domain-generation d) (activation-generation a))
               ((gpu-provider-current? (gpu-domain-provider d))))
    (error who "GPU operation requires a live scope with the correct native context")))
; domain-pointer : gpu-domain? -> cpointer?
;;   Returns the native context pointer only after readiness and current-activation checks.
(define (domain-pointer d)
  (usable! 'domain-pointer d) (current! 'domain-pointer d)
  (gpu-domain-pointer d))

;; Domains remain rooted until explicit owner-thread teardown. Roots do NOT
;; retain public context/resource wrappers. GC/custodian callbacks only request
;; shutdown or append release jobs, never activate a provider or call a driver.
;; A dead owner leaves a quarantined domain, not an unsafe off-thread destructor.
; domain-request-shutdown! : gpu-domain? [symbol?] -> void?
;;   Records a shutdown request atomically without activating a provider or calling native
;;   destructors.
(define (domain-request-shutdown! d [reason 'requested])
  (call-as-atomic
   (lambda ()
     (unless (eq? (domain-state d) 'closed)
       (set-gpu-domain-requested! d reason))))
  (void))
; forget! : gpu-domain? -> void?
;;   Removes a closed domain's root and claim without disturbing a newer owner's claim.
(define (forget! d)
  (call-as-atomic
   (lambda ()
     (hash-remove! roots d)
     (define key (claim-key (gpu-domain-provider d)))
     (when (eq? d (hash-ref claims key #f)) (hash-remove! claims key)))))

; make-gpu-domain : gpu-provider? gpu-driver? -> gpu-domain?
;;   Claims one host context, constructs its native driver context, and safely records partial setup
;;   failures.
(define (make-gpu-domain provider driver)
  (check-skia-gpu-access! 'make-gpu-domain)
  (unless (gpu-provider? provider)
    (raise-argument-error 'make-gpu-domain "gpu-provider?" provider))
  (unless (gpu-driver? driver)
    (raise-argument-error 'make-gpu-domain "gpu-driver?" driver))
  (unless (eq? (gpu-provider-creator provider) (current-thread))
    (error 'make-gpu-domain "provider belongs to another Racket thread"))
  (when (or (active) (current-future))
    (error 'make-gpu-domain "cannot construct a domain inside another GPU scope or a future"))
  (define d
    (call-as-atomic
     (lambda ()
       (define key (claim-key provider))
       (when (hash-has-key? claims key)
         (error 'make-gpu-domain "this host context already has a live GPU domain"))
       (set! next-generation (add1 next-generation))
       (define value
         (gpu-domain provider driver (current-thread) next-generation
                     'initializing #f (hasheq) 0 0 '() '() #f))
       (hash-set! claims key value)
       (hash-set! roots value #t)
       value)))
  (define success? #f)
  (dynamic-wind
    void
    (lambda ()
      (provider-call
       provider
       (lambda ()
         ;; Individual native creation + registration is atomic. Provider/GUI
         ;; acquisition and the surrounding callback are deliberately not.
         (call-as-atomic
          (lambda ()
            (define p ((gpu-driver-create driver)))
            (unless p (gpu-unavailable 'ganesh-context "native Ganesh creation returned null"))
            (set-gpu-domain-pointer! d p)))
         (with-handlers ([(lambda (_) #t)
                          (lambda (e)
                            ;; Construction failed while the native context is
                            ;; current. Release before leaving its provider.
                            (define p (gpu-domain-pointer d))
                            (set-gpu-domain-pointer! d #f)
                            (set-gpu-domain-state! d 'closing)
                            (when p ((gpu-driver-release driver) p))
                            (set-gpu-domain-state! d 'initializing)
                            (raise e))])
           (define details ((gpu-driver-describe driver) (gpu-domain-pointer d)))
           (unless (and (hash? details) (immutable? details))
             (error 'make-gpu-domain "driver diagnostic snapshot must be an immutable hash"))
           (set-gpu-domain-info! d details)
           (set-gpu-domain-state! d 'ready))))
      (set! success? #t)
      d)
    (lambda ()
      (unless success?
        ;; A provider itself can fail after returning from its callback. A
        ;; native pointer then remains rooted for explicit shutdown/abandon.
        (if (or (gpu-domain-pointer d) (eq? (domain-state d) 'closing))
            (domain-request-shutdown! d 'constructor-provider-failure)
            (begin (set-gpu-domain-state! d 'closed) (forget! d)))))))

; domain-info : gpu-domain? -> (and/c hash? immutable?)
;;   Combines detached native diagnostics with lifecycle, generation, and release-queue counts.
(define (domain-info d)
  (owner! 'domain-info d)
  (hash-set* (gpu-domain-info d)
             'backend (symbol->string (domain-backend d))
             'provider (symbol->string (gpu-provider-name (gpu-domain-provider d)))
             'generation (domain-generation d)
             'state (symbol->string (domain-state d))
             'live_children (domain-live-count d)
             'pending_releases (domain-pending-count d)
             'failed_releases (length (gpu-domain-failed d))
             'shutdown_requested (and (gpu-domain-requested d) #t)))

; drain! : gpu-domain? -> exact-nonnegative-integer?
;;   Detaches queued release jobs and destroys them in queue order without retrying uncertain
;;   failures.
(define (drain! d)
  ;; Taking jobs off the queue and running their destructors must not be
  ;; interrupted by an asynchronous break that would strand detached jobs.
  ;; This suppresses breaks, not scheduling or provider activation.
  (parameterize-break #f
  ;; A successful abandon severs native GPU dependencies, so queued Skia
  ;; unrefs may subsequently run without a current (possibly lost) GL context.
  (unless (eq? (domain-state d) 'abandoned) (current! 'domain-drain! d))
  (define jobs
    (call-as-atomic
     (lambda ()
       (begin0 (reverse (gpu-domain-pending d))
         (set-gpu-domain-pending! d '())))))
  (define first-error #f)
  (for ([job (in-list jobs)])
    (with-handlers ([(lambda (_) #t)
                     (lambda (e)
                       ;; Never retry an indeterminate native release. Keep its
                       ;; record rooted and refuse normal context destruction.
                       (set-gpu-domain-failed! d (cons job (gpu-domain-failed d)))
                       (unless first-error (set! first-error e)))])
      ((release-job-release job) (release-job-pointer job))))
  (when first-error (raise first-error))
  (length jobs)))
; domain-drain! : gpu-domain? -> exact-nonnegative-integer?
;;   Drains deferred native releases inside a checked domain activation.
(define (domain-drain! d)
  (check-skia-gpu-access! 'domain-drain!)
  (owner! 'domain-drain! d)
  (unless (memq (domain-state d) '(ready closing abandoned))
    (error 'domain-drain! "domain is ~a" (domain-state d)))
  (drain! d))

; domain-call : gpu-domain? procedure? -> any
;;   Activates the provider, resets native cached state, and scopes a generation-checked GPU lease.
(define (domain-call d thunk)
  (usable! 'call-with-gpu-context d)
  (unless (and (procedure? thunk) (procedure-arity-includes? thunk 0))
    (raise-argument-error 'call-with-gpu-context "procedure accepting zero arguments" thunk))
  (define parent (active))
  (when (and parent (not (eq? d (activation-domain parent))))
    (error 'call-with-gpu-context "nested foreign GPU domains are not supported"))
  (define (run-scope)
    (define lease (activation d (domain-generation d) #t))
    (define entered? #f)
    (define completed? #f)
    (parameterize ([active lease])
      (dynamic-wind
        (lambda ()
          (when entered? (error 'call-with-gpu-context "GPU scope has expired"))
          (set! entered? #t)
          (set-gpu-domain-depth! d (add1 (gpu-domain-depth d))))
        (lambda ()
          (when (= (gpu-domain-depth d) 1)
            ((gpu-driver-reset (gpu-domain-driver d)) (gpu-domain-pointer d)))
          (drain! d)
          (begin0 (thunk) (set! completed? #t)))
        (lambda ()
          ;; Retire even when a release fails. Never allow that error to leave
          ;; a usable lease or a positive scope depth behind.
          (dynamic-wind
            void
            (lambda ()
              (define current? ((gpu-provider-current? (gpu-domain-provider d))))
              (cond
                [current?
                 (if completed? (drain! d)
                     (with-handlers ([(lambda (_) #t) (lambda (_) (void))]) (drain! d)))]
                [completed? (error 'call-with-gpu-context
                  "native context changed inside GPU scope")]))
            (lambda ()
              (set-activation-live?! lease #f)
              (set-gpu-domain-depth! d (sub1 (gpu-domain-depth d)))))))))
  (cond
    [parent
     ;; The outer scope already owns and has activated this provider. Re-entering
     ;; the host adapter is unnecessary and, for some GL hosts, can disturb the
     ;; native-current state that the outer lease depends on. A nested scope is
     ;; only a new borrow/lease boundary.
     (current! 'call-with-gpu-context d)
     (run-scope)]
    [else
     (dynamic-wind void
       (lambda () (provider-call (gpu-domain-provider d) run-scope))
       notify-domain-idle!)]))

; enqueue-resource! : domain-resource? -> void?
;;   Detaches a child pointer and queues its destructor without invoking native code from
;;   finalization.
(define (enqueue-resource! h)
  ;; Called by the FFI allocator's finalizer in atomic mode. No provider,
  ;; backend call, lock acquisition, GPU wait, or application callback here.
  (define p (domain-resource-pointer h))
  (when p
    (set-domain-resource-pointer! h #f)
    (set-domain-resource-keepalive! h #f)
    (define d (domain-resource-domain h))
    (set-gpu-domain-live! d (sub1 (gpu-domain-live d)))
    (set-gpu-domain-pending!
     d (cons (release-job p (domain-resource-release h) (domain-resource-kind h))
             (gpu-domain-pending d)))))
; allocate-resource : gpu-domain? symbol? procedure? procedure? any/c -> domain-resource?
;;   Creates and registers one native child reference atomically with the domain's live-resource
;;   count.
(define allocate-resource
  ((allocator enqueue-resource!)
   (lambda (d kind create release keepalive)
     (define p (create))
     (unless p (error 'domain-new-resource "native ~a allocation returned null" kind))
     (set-gpu-domain-live! d (add1 (gpu-domain-live d)))
     (domain-resource d (domain-generation d) p release kind keepalive))))
; domain-new-resource : gpu-domain? symbol? procedure? procedure? [#:keepalive any/c] ->
;   domain-resource?
;;   Allocates a child only within the matching live domain and retains the optional public context.
(define (domain-new-resource d kind create release #:keepalive [keepalive #f])
  (usable! 'domain-new-resource d) (current! 'domain-new-resource d)
  (allocate-resource d kind create (capture-gpu-native-release release) keepalive))
; cancel-and-enqueue! : domain-resource? -> void?
;;   Cancels the allocator finalizer before explicitly scheduling a child's native release.
(define cancel-and-enqueue! ((deallocator) enqueue-resource!))
;; Internal finalizer entry point: unlike public close, it must not check the
;; current thread. It cancels this registration and ONLY queues destruction.
; domain-resource-retire! : domain-resource? -> void?
;;   Enqueues a resource's reference without requiring an immediate native destructor call.
(define (domain-resource-retire! h)
  (cancel-and-enqueue! h)
  (void))
;; Transfer a native reference back to ordinary CPU ownership only after the
;; caller has removed its last GPU dependency (a paint setter, or a finished
;; recorder). This is NOT a release and must happen with the domain current.
; take-resource! : domain-resource? -> cpointer?
;;   Detaches a native reference from domain finalization without destroying it, transferring
;;   release responsibility.
(define take-resource!
  ((deallocator)
   (lambda (h)
     (define p (domain-resource-pointer h))
     (unless p (error 'domain-resource-take! "resource is already retired"))
     (set-domain-resource-pointer! h #f)
     (set-domain-resource-keepalive! h #f)
     (define d (domain-resource-domain h))
     (set-gpu-domain-live! d (sub1 (gpu-domain-live d)))
     p)))
; domain-resource-take! : domain-resource? -> cpointer?
;;   Transfers a live resource pointer out of domain ownership after owner checks.
(define (domain-resource-take! h)
  (checked-resource-pointer h)
  (take-resource! h))

; domain-resource-close! : domain-resource? -> void?
;;   Retires a child and drains its release under the owning domain's valid execution rules.
(define (domain-resource-close! h)
  (unless (domain-resource? h)
    (raise-argument-error 'domain-resource-close! "domain-resource?" h))
  (owner! 'domain-resource-close! (domain-resource-domain h))
  (cancel-and-enqueue! h)
  (void))
; domain-resource-closed? : domain-resource? -> boolean?
;;   Reports whether the child has relinquished its native pointer.
(define (domain-resource-closed? h) (not (domain-resource-pointer h)))
;; Checked access is exported under a separate internal name below. The raw
;; struct accessor remains local to finalization.
; checked-resource-pointer : domain-resource? -> cpointer?
;;   Rejects closed children, stale generations, and missing context activation before returning a
;;   pointer.
(define (checked-resource-pointer h)
  (unless (domain-resource? h)
    (raise-argument-error 'domain-resource-pointer "domain-resource?" h))
  (define d (domain-resource-domain h))
  (usable! 'domain-resource-pointer d) (current! 'domain-resource-pointer d)
  (unless (= (domain-resource-generation h) (domain-generation d))
    (error 'domain-resource-pointer "stale resource generation"))
  (or (domain-resource-pointer h) (error 'domain-resource-pointer "resource is closed")))

; inactive! : symbol? gpu-domain? -> void?
;;   Forbids context teardown while this or another GPU execution scope is active.
(define (inactive! who d)
  (owner! who d)
  (when (or (positive? (gpu-domain-depth d)) (active))
    (error who "context teardown is not allowed inside a GPU execution scope")))
; domain-abandon! : gpu-domain? -> void?
;;   Marks a lost native context abandoned without attempting to activate an invalid host context.
(define (domain-abandon! d)
  (inactive! 'gpu-context-abandon! d)
  (when (eq? (domain-state d) 'release-failed)
    (error 'gpu-context-abandon!
      "native release/abandon outcome is indeterminate; domain is quarantined"))
  (unless (memq (domain-state d) '(abandoned closed))
    (unless (gpu-domain-pointer d) (error 'gpu-context-abandon! "no native context"))
    ;; A private driver contract: this is the loss operation, NOT
    ;; releaseResourcesAndAbandon, and does not activate an invalid GL host.
    (parameterize-break #f
      ((gpu-driver-abandon (gpu-domain-driver d)) (gpu-domain-pointer d))
      (set-gpu-domain-state! d 'abandoned)))
  (void))
; domain-close! : gpu-domain? -> void?
;;   Releases an inactive domain only after children and release jobs are settled; uncertain
;;   destruction is never retried.
(define (domain-close! d)
  (inactive! 'gpu-context-close! d)
  (unless (eq? (domain-state d) 'closed)
    (define (finish)
      (let loop ()
        (drain! d)
        (define retry?
          (parameterize-break #f
            ;; No break may occur between detaching the native context pointer
            ;; and its one-and-only destructor. Atomic mode covers the state
            ;; transition only, not the potentially waiting native destructor.
            (define p
              (call-as-atomic
               (lambda ()
                 (unless (zero? (domain-live-count d))
                   (error 'gpu-context-close! "~a live GPU children remain" (domain-live-count d)))
                 (unless (null? (gpu-domain-failed d))
                   (error 'gpu-context-close! "indeterminate native releases are quarantined"))
                 (cond
                   [(pair? (gpu-domain-pending d)) #f]
                   [else
                    (define p (gpu-domain-pointer d))
                    (unless p (error 'gpu-context-close!
                      "missing native pointer; destruction is not retried"))
                    (set-gpu-domain-state! d 'closing)
                    (set-gpu-domain-pointer! d #f)
                    p]))))
            (cond
              [(not p) #t]
              [else
               ;; If the destructor throws, retain the domain/claim forever
               ;; instead of retrying an indeterminate native destruction.
               ((gpu-driver-release (gpu-domain-driver d)) p)
               (set-gpu-domain-state! d 'closed)
               (forget! d)
               #f])))
        (when retry? (loop))))
    (cond
      [(eq? (domain-state d) 'abandoned) (finish)]
      [(memq (domain-state d) '(ready initializing))
       (provider-call
        (gpu-domain-provider d)
        (lambda ()
          (define lease (activation d (domain-generation d) #t))
          (parameterize ([active lease])
            (dynamic-wind void finish (lambda () (set-activation-live?! lease #f))))))]
      [else (error 'gpu-context-close! "domain is ~a; native destruction is not retried" (domain-state
        d))]))
  (void))

; drain-pending-domains! : [#:abandon? (or/c #f boolean?)] -> list?
;;   Processes requested shutdowns owned by the current thread and returns detached outcome reports.
(define (drain-pending-domains! #:abandon? [abandon? #f])
  (unless (boolean? abandon?)
    (raise-argument-error 'gpu-drain-pending-contexts! "boolean?" abandon?))
  (when (active) (error 'gpu-drain-pending-contexts! "cannot shut down inside a GPU scope"))
  (define pending
    (call-as-atomic
     (lambda ()
       (for/list ([d (in-hash-keys roots)]
                  #:when (and (eq? (gpu-domain-owner d) (current-thread))
                              (gpu-domain-requested d))) d))))
  (for/list ([d (in-list pending)])
    (with-handlers ([exn:fail?
                     (lambda (e)
                       (hash-set (domain-info d) 'shutdown_error (exn-message e)))])
      (when abandon? (domain-abandon! d))
      (domain-close! d)
      (domain-info d))))

;; Only the checked accessor is visible to other modules.
(provide (rename-out [checked-resource-pointer resource-pointer]))

;; A canvas borrowed in an inner activation cannot outlive that activation,
;; even if the same domain is active again (or its outer activation survives).
; domain-capture-lease : gpu-domain? -> activation?
;;   Captures the exact live activation so a borrowed canvas cannot outlive an inner scope.
(define (domain-capture-lease d)
  (usable! 'surface-canvas d)
  (current! 'surface-canvas d)
  (active))
; domain-lease-expired? : activation? -> boolean?
;;   Checks activation validity, generation, domain readiness, and pending shutdown without native
;;   access.
(define (domain-lease-expired? lease)
  (or (not (activation? lease))
      (not (activation-live? lease))
      (not (= (activation-generation lease)
              (domain-generation (activation-domain lease))))
      (not (eq? (domain-state (activation-domain lease)) 'ready))
      (and (gpu-domain-requested (activation-domain lease)) #t)))
; domain-check-lease! : symbol? activation? -> void?
;;   Requires both an unexpired borrow lease and a currently usable matching GPU activation.
(define (domain-check-lease! who lease)
  (when (domain-lease-expired? lease)
    (error who "borrowed GPU canvas scope has expired"))
  (define d (activation-domain lease))
  (usable! who d)
  (current! who d)
  (void))

;; Advanced GL adapters need the provider's resolver, not GLX on an EGL
;; context. No raw context pointer is exposed by the public GPU module.
(module* gl-interop-internals #f
  (provide domain-gl-resolver)
  ; domain-gl-resolver : gpu-domain? -> procedure?
  ;;   Returns the active GL provider's procedure resolver rather than assuming a system GL context.
  (define (domain-gl-resolver d)
    (usable! 'gpu-gl-interop d)
    (current! 'gpu-gl-interop d)
    (unless (eq? (domain-backend d) 'opengl)
      (error 'gpu-gl-interop "an OpenGL context is required"))
    (or (gpu-provider-resolve (gpu-domain-provider d))
        (error 'gpu-gl-interop
               "provider needs #:get-proc-address for explicit GL interoperation"))))

(provide domain-release-and-abandon!)
;; Healthy-host teardown: unlike domain-abandon!, this MUST activate the host.
;; Native context lifetime is retained until children retire and domain-close!.
; domain-release-and-abandon! : gpu-domain? procedure? -> void?
;;   Releases healthy-host resources under activation, then abandons the context while retaining
;;   teardown ownership.
(define (domain-release-and-abandon! d release-and-abandon)
  (define who 'gpu-context-release-and-abandon!)
  (inactive! who d)
  (usable! who d)
  (unless (and (procedure? release-and-abandon) (procedure-arity-includes? release-and-abandon 1))
    (raise-argument-error who "private one-argument native teardown operation" release-and-abandon))
  (dynamic-wind void
    (lambda ()
      (parameterize-break #f
        (provider-call (gpu-domain-provider d)
          (lambda ()
            (define lease (activation d (domain-generation d) #t))
            (parameterize ([active lease])
              (dynamic-wind void
                (lambda ()
                  ;; Provider activation can run Racket code; revalidate before
                  ;; reading the context pointer or doing native work.
                  (usable! who d)
                  (current! who d)
                  (define cp (domain-pointer d))
                  ((gpu-driver-reset (gpu-domain-driver d)) cp)
                  (drain! d)
                  (usable! who d)
                  (current! who d)
                  (unless (null? (gpu-domain-failed d))
                    (error who "indeterminate native releases are quarantined"))
                  (set-gpu-domain-state! d 'releasing)
                  (with-handlers ([(lambda (_) #t)
                                   (lambda (e)
                                     (set-gpu-domain-state! d 'release-failed)
                                     (domain-request-shutdown! d)
                                     (raise e))])
                    (release-and-abandon cp)
                    (set-gpu-domain-state! d 'abandoned))
                  (drain! d))
                (lambda () (set-activation-live?! lease #f))))))))
    (lambda () (notify-domain-idle!)))
  (void))
