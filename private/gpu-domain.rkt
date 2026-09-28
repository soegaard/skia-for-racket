#lang racket/base
(require ffi/unsafe/alloc ffi/unsafe/atomic
         racket/list racket/future "gpu-provider.rkt" "gpu-native-scope.rkt")
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
(struct gpu-domain
  (provider driver owner generation [state #:mutable] [pointer #:mutable]
            [info #:mutable] [depth #:mutable] [live #:mutable]
            [pending #:mutable] [failed #:mutable] [requested #:mutable]))
(struct activation (domain generation [live? #:mutable]))
(struct release-job (pointer release kind))
;; keepalive is normally the public gpu-context wrapper. Native root/queue
;; records do not point back to this resource or keepalive wrapper.
(struct domain-resource
  (domain generation [pointer #:mutable] release kind [keepalive #:mutable]))
(define active (make-parameter #f))
(define roots (make-hasheq))
(define claims (make-hash))
(define next-generation 0)
(define (domain-backend d) (gpu-provider-backend (gpu-domain-provider d)))
(define domain-generation gpu-domain-generation)
(define domain-state gpu-domain-state)
(define domain-live-count gpu-domain-live)
(define (domain-pending-count d) (length (gpu-domain-pending d)))
(define (claim-key p) (cons (gpu-provider-backend p) (gpu-provider-key p)))
(define (owner! who d)
  (unless (gpu-domain? d) (raise-argument-error who "gpu-domain?" d))
  (unless (and (eq? (gpu-domain-owner d) (current-thread)) (not (current-future)))
    (error who "GPU domain belongs to another execution owner; futures are not supported")))
(define (usable! who d)
  (owner! who d)
  (unless (and (eq? (domain-state d) 'ready) (not (gpu-domain-requested d)))
    (error who "GPU domain is ~a~a" (domain-state d)
           (if (gpu-domain-requested d) " (shutdown requested)" ""))))
(define (current! who d)
  (owner! who d)
  (define a (active))
  (unless (and a (activation-live? a) (eq? d (activation-domain a))
               (= (domain-generation d) (activation-generation a))
               ((gpu-provider-current? (gpu-domain-provider d))))
    (error who "GPU operation requires a live scope with the correct native context")))
(define (domain-pointer d)
  (usable! 'domain-pointer d) (current! 'domain-pointer d)
  (gpu-domain-pointer d))

;; Domains remain rooted until explicit owner-thread teardown. Roots do NOT
;; retain public context/resource wrappers. GC/custodian callbacks only request
;; shutdown or append release jobs, never activate a provider or call a driver.
;; A dead owner leaves a quarantined domain, not an unsafe off-thread destructor.
(define (domain-request-shutdown! d [reason 'requested])
  (call-as-atomic
   (lambda ()
     (unless (eq? (domain-state d) 'closed)
       (set-gpu-domain-requested! d reason))))
  (void))
(define (forget! d)
  (call-as-atomic
   (lambda ()
     (hash-remove! roots d)
     (define key (claim-key (gpu-domain-provider d)))
     (when (eq? d (hash-ref claims key #f)) (hash-remove! claims key)))))

(define (make-gpu-domain provider driver)
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
(define (domain-drain! d)
  (owner! 'domain-drain! d)
  (unless (memq (domain-state d) '(ready closing abandoned))
    (error 'domain-drain! "domain is ~a" (domain-state d)))
  (drain! d))

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
                [completed? (error 'call-with-gpu-context "native context changed inside GPU scope")]))
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
     (provider-call (gpu-domain-provider d) run-scope)]))

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
(define allocate-resource
  ((allocator enqueue-resource!)
   (lambda (d kind create release keepalive)
     (define p (create))
     (unless p (error 'domain-new-resource "native ~a allocation returned null" kind))
     (set-gpu-domain-live! d (add1 (gpu-domain-live d)))
     (domain-resource d (domain-generation d) p release kind keepalive))))
(define (domain-new-resource d kind create release #:keepalive [keepalive #f])
  (usable! 'domain-new-resource d) (current! 'domain-new-resource d)
  (allocate-resource d kind create (capture-gpu-native-release release) keepalive))
(define cancel-and-enqueue! ((deallocator) enqueue-resource!))
;; Internal finalizer entry point: unlike public close, it must not check the
;; current thread. It cancels this registration and ONLY queues destruction.
(define (domain-resource-retire! h)
  (cancel-and-enqueue! h)
  (void))
;; Transfer a native reference back to ordinary CPU ownership only after the
;; caller has removed its last GPU dependency (a paint setter, or a finished
;; recorder). This is NOT a release and must happen with the domain current.
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
(define (domain-resource-take! h)
  (checked-resource-pointer h)
  (take-resource! h))

(define (domain-resource-close! h)
  (unless (domain-resource? h)
    (raise-argument-error 'domain-resource-close! "domain-resource?" h))
  (owner! 'domain-resource-close! (domain-resource-domain h))
  (cancel-and-enqueue! h)
  (void))
(define (domain-resource-closed? h) (not (domain-resource-pointer h)))
;; Checked access is exported under a separate internal name below. The raw
;; struct accessor remains local to finalization.
(define (checked-resource-pointer h)
  (unless (domain-resource? h)
    (raise-argument-error 'domain-resource-pointer "domain-resource?" h))
  (define d (domain-resource-domain h))
  (usable! 'domain-resource-pointer d) (current! 'domain-resource-pointer d)
  (unless (= (domain-resource-generation h) (domain-generation d))
    (error 'domain-resource-pointer "stale resource generation"))
  (or (domain-resource-pointer h) (error 'domain-resource-pointer "resource is closed")))

(define (inactive! who d)
  (owner! who d)
  (when (or (positive? (gpu-domain-depth d)) (active))
    (error who "context teardown is not allowed inside a GPU execution scope")))
(define (domain-abandon! d)
  (inactive! 'gpu-context-abandon! d)
  (unless (memq (domain-state d) '(abandoned closed))
    (unless (gpu-domain-pointer d) (error 'gpu-context-abandon! "no native context"))
    ;; A private driver contract: this is the loss operation, NOT
    ;; releaseResourcesAndAbandon, and does not activate an invalid GL host.
    (parameterize-break #f
      ((gpu-driver-abandon (gpu-domain-driver d)) (gpu-domain-pointer d))
      (set-gpu-domain-state! d 'abandoned)))
  (void))
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
                    (unless p (error 'gpu-context-close! "missing native pointer; destruction is not retried"))
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
      [else (error 'gpu-context-close! "domain is ~a; native destruction is not retried" (domain-state d))]))
  (void))

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
(define (domain-capture-lease d)
  (usable! 'surface-canvas d)
  (current! 'surface-canvas d)
  (active))
(define (domain-lease-expired? lease)
  (or (not (activation? lease))
      (not (activation-live? lease))
      (not (= (activation-generation lease)
              (domain-generation (activation-domain lease))))
      (not (eq? (domain-state (activation-domain lease)) 'ready))
      (and (gpu-domain-requested (activation-domain lease)) #t)))
(define (domain-check-lease! who lease)
  (when (domain-lease-expired? lease)
    (error who "borrowed GPU canvas scope has expired"))
  (define d (activation-domain lease))
  (usable! who d)
  (current! who d)
  (void))
