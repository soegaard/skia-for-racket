#lang racket/base

;;;
;;; EGL Provider Operations
;;;

;; Defines injectable EGL operations and validates provider options.
;; Separates EGL configuration policy from platform loading and activation.

(require "gpu-provider.rkt" "gpu-domain.rkt")
(provide (struct-out egl-platform-ops) make-egl-components egl-extension?
         check-egl-options call-with-egl-lock)

;;;
;;; Platform Protocol and Serialized Access
;;;

;; No EGL, GL, GUI or Skia initialization. Operations are private synchronous
;; native procedures (or test doubles). enter returns a restoration thunk.

(struct egl-platform-ops (create close enter current? describe resolve))
;; Fields:
;;   create, close, enter, current?, describe, and resolve: injected procedures for host
;;   construction, teardown, activation, current-context checks, diagnostics, and procedure lookup.
;;   enter preserves/restores the previous native context.

; gate : semaphore?
;   Serializes EGL display/context bookkeeping shared by provider construction and teardown.
(define gate (make-semaphore 1))

; inside-gate? : parameter?
;   Marks reentrant calls already inside the EGL bookkeeping lock.
(define inside-gate? (make-parameter #f))

; call-with-egl-lock : any/c -> any
;   Serializes EGL bookkeeping without deadlocking nested calls on the same dynamic path.
(define (call-with-egl-lock proc)
  (when (inside-gate?)
    (error 'egl-provider "nested EGL provider activation is not supported"))
  (call-with-semaphore gate (lambda () (parameterize ([inside-gate? (current-thread)]) (proc)))))

; egl-extension? : any/c any/c -> any
;   Matches a complete EGL extension token rather than a substring of another extension name.
(define (egl-extension? text name)
  (and (string? text)
       (for/or ([s (in-list (regexp-split #px"\\s+" text))]) (string=? s name))))

; check-egl-options : symbol? any/c exact-nonnegative-integer? any/c -> void?
;   Checks requested EGL platform, device index, and surface mode before loading native services.
(define (check-egl-options who platform index surface)
  (unless (memq platform '(surfaceless device))
    (raise-argument-error who "'surfaceless or 'device" platform))
  (unless (exact-nonnegative-integer? index)
    (raise-argument-error who "exact-nonnegative-integer? for device-index" index))
  (when (and (eq? platform 'surfaceless) (not (zero? index)))
    (error who "device-index applies only to #:platform 'device"))
  (unless (memq surface '(surfaceless pbuffer))
    (raise-argument-error who "'surfaceless or 'pbuffer" surface)))

;;;
;;; Owned EGL Driver Construction
;;;

; make-egl-components : egl-platform-ops? any/c -> (values any/c gpu-driver?)
;   Combines injected EGL host operations with a GL driver while preserving failure cleanup.
(define (make-egl-components ops make-driver)
  (unless (egl-platform-ops? ops)
    (raise-argument-error 'make-egl-components "egl-platform-ops?" ops))
  (define host #f)
  (define closed? #f)
  (define poisoned? #f)
  (define native-live? #f)
  (define (close-host!)
    (unless closed?
      ;; A partially failed native teardown is never retried.
      (set! poisoned? #t)
      (when host ((egl-platform-ops-close ops) host))
      (set! closed? #t)
      (set! poisoned? #f)))
  (define (activate thunk)
    (when (or closed? poisoned?) (error 'egl-provider "EGL host is closed or quarantined"))
    (call-with-egl-lock
     (lambda ()
       (define restore #f)
       (define entered? #f)
       (dynamic-wind
         (lambda ()
           (when entered? (error 'egl-provider "EGL activation has expired"))
           (set! entered? #t))
         (lambda ()
           (with-handlers ([(lambda (_) #t)
                            (lambda (e)
                              (unless native-live? (close-host!))
                              (raise e))])
             (parameterize-break #f
               (unless host (set! host ((egl-platform-ops-create ops)))))
             (unless host (gpu-unavailable 'egl-context "EGL host creation returned null"))
             (parameterize-break #f (set! restore ((egl-platform-ops-enter ops) host))))
           (thunk))
         (lambda ()
           (parameterize-break #f
             (dynamic-wind
               void
               (lambda ()
                 (when (and host (not native-live?) (not closed?) (not poisoned?))
                   (close-host!)))
               (lambda ()
                 (when restore
                   ;; Normal release may have destroyed our EGL context, but
                   ;; the saved foreign binding must still be restored.
                   (define restore-now restore)
                   (set! restore #f)
                   (with-handlers ([(lambda (_) #t)
                                    (lambda (e) (set! poisoned? #t) (raise e))])
                     (restore-now)))))))))))
  (define provider
    (make-gpu-provider
     #:name 'egl-owned #:backend 'opengl #:key (gensym 'egl-context)
     #:call-as-current activate
     #:current? (lambda () (and host (not closed?) (not poisoned?)
                                ((egl-platform-ops-current? ops) host)))
     #:describe (lambda () ((egl-platform-ops-describe ops) host))
     #:get-proc-address (lambda (name) ((egl-platform-ops-resolve ops) name))))
  (define native (make-driver provider))
  (define driver
    (gpu-driver
     (lambda ()
       (with-handlers ([(lambda (_) #t)
                        (lambda (e) (close-host!) (raise e))])
         (define p ((gpu-driver-create native)))
         (unless p (gpu-unavailable 'egl-ganesh "Ganesh context creation returned null"))
         (set! native-live? #t)
         p))
     (lambda (p)
       (define (finish)
         ((gpu-driver-release native) p)
         (set! native-live? #f)
         ;; Ganesh destruction comes before EGL destruction. Normal activation
         ;; already owns the gate; abandoned-domain teardown acquires it here.
         (close-host!))
       (if (eq? (inside-gate?) (current-thread))
           (finish)
           (call-with-egl-lock finish)))
     (gpu-driver-abandon native) (gpu-driver-reset native) (gpu-driver-describe native)))
  (values provider driver))
