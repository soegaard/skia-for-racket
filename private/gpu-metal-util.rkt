#lang racket/base
(require "gpu-provider.rkt" "gpu-domain.rkt" "gpu-native-scope.rkt" "gpu-metal-handles.rkt")
(provide (struct-out metal-platform-ops) (struct-out metal-context-ops)
         make-metal-components)

;; Private operations make ownership/failure paths testable without libobjc,
;; Metal, Skia, a display server or a GUI. Every callback below is an internal
;; synchronous native operation (or a test double), never application code.
(struct metal-platform-ops (scope device queue release describe))
(struct metal-context-ops (create release abandon reset describe))
(define (make-metal-components platform native)
  (unless (metal-platform-ops? platform)
    (raise-argument-error 'make-metal-components "metal-platform-ops?" platform))
  (unless (metal-context-ops? native)
    (raise-argument-error 'make-metal-components "metal-context-ops?" native))
  (define scope (metal-platform-ops-scope platform))
  (define creator (current-thread))
  (define key (gensym 'metal-queue))
  (define current-key (make-parameter #f))
  (define details (hasheq))
  (define (native-call thunk)
    (parameterize ([current-gpu-native-scope scope]) (call-with-gpu-native-scope thunk)))
  (define provider
    (make-gpu-provider
     #:name 'metal-owned #:backend 'metal #:key key
     ;; Metal has no OpenGL-style current native context. This is an ownership
     ;; token for our one private queue, not a fabricated OS current context.
     #:current? (lambda () (and (eq? creator (current-thread)) (eq? key (current-key))))
     #:call-as-current
     (lambda (thunk)
       (parameterize ([current-key key] [current-gpu-native-scope scope]) (thunk)))
     #:describe (lambda () details)))
  (define (create)
    (native-call
     (lambda ()
       (define device #f)
       (define queue #f)
       (define (release-device!)
         (when device
           (define p device) (set! device #f)
           ((metal-platform-ops-release platform) p)))
       (define (release-queue!)
         (when queue
           (define p queue) (set! queue #f)
           ((metal-platform-ops-release platform) p)))
       (dynamic-wind
         void
         (lambda ()
           (set! device ((metal-platform-ops-device platform)))
           (unless device (gpu-unavailable 'metal-device "MTLCreateSystemDefaultDevice returned null"))
           (set! queue ((metal-platform-ops-queue platform) device))
           (unless queue (gpu-unavailable 'metal-queue "newCommandQueue returned null"))
           (set! details (freeze-gpu-details ((metal-platform-ops-describe platform) device)))
           (unless (hash? details) (error 'make-gpu-context "Metal device details must be a hash"))
           ;; At mono/skia 40f75dc..., MakeMetal retains BOTH borrowed arguments.
           ;; Release our Create/new +1 references on success AND null failure.
           ;; The Ganesh context is the sole long-lived owner of its queue/device.
           (define context
             (or ((metal-context-ops-create native) device queue)
                 (gpu-unavailable 'metal-ganesh "Ganesh Metal context creation returned null")))
           ;; Registry entries are borrowed from Ganesh, not extra +1 refs.
           ;; This makes its exact submission queue available to presentation.
           (with-handlers ([(lambda (_) #t)
                            (lambda (e) ((metal-context-ops-release native) context) (raise e))])
             (register-metal-handles! context device queue))
           context)
         (lambda () (dynamic-wind void release-queue! release-device!))))))
  (define driver
    (gpu-driver
     create
     (lambda (p)
       (forget-metal-handles! p)
       (native-call (lambda () ((metal-context-ops-release native) p))))
     (lambda (p) (native-call (lambda () ((metal-context-ops-abandon native) p))))
     (lambda (p) (native-call (lambda () ((metal-context-ops-reset native) p))))
     (lambda (p)
       (native-call
        (lambda ()
          (define result ((metal-context-ops-describe native) p details))
          (unless (and (hash? result) (immutable? result))
            (error 'make-gpu-context "Metal context details must be an immutable hash"))
          result)))))
  (values provider driver))
