#lang racket/base
;; Private bridge ownership. Never installs a native callback or exposes a
;; pointer through main.rkt. All mutations occur on ordinary Racket threads.
(require ffi/unsafe ffi/unsafe/atomic)
(provide make-native-reference reference-pointer reference-close! adopt-reference!
         pin-live-output! live-pin-pointer release-live-pin! poison-live-pin!
         check-live-pin! check-live-fault!)

;; An independent CPU native reference may outlive the original public wrapper.
;; The service thread releases it only after native completion. The finalizer is
;; a fallback for abandonment before launch or a result abandoned by its caller.
(struct native-reference ([pointer #:mutable] release))
(define (reference-pointer ref)
  (define p (native-reference-pointer ref))
  (unless p (error 'live-streams "private native reference is closed or transferred"))
  p)
(define (reference-close! ref)
  (call-as-atomic
   (lambda ()
     (define p (native-reference-pointer ref))
     (when p
       (set-native-reference-pointer! ref #f)
       ((native-reference-release ref) p)))))
(define (make-native-reference ptr release)
  (unless ptr (error 'live-streams "native allocation failed"))
  (define ref (native-reference ptr release))
  (register-finalizer ref reference-close!)
  ref)
;; Must be invoked inside new-owned's atomic create thunk, so there is no gap
;; between taking this reference and installing the library's ordinary owner.
(define (adopt-reference! ref)
  (define p (reference-pointer ref))
  (set-native-reference-pointer! ref #f)
  p)

;; A native WStream is mutable and not ref-counted. Pin its existing owner while
;; a private Racket-port sink forwards bounded chunks to it. The lifetime layer
;; checks these tables at every public borrow/close. Weak keys do not themselves
;; keep owners alive; the live pin does so until service cleanup.
(define busy (make-weak-hasheq))
(define faulty (make-weak-hasheq))
(struct live-pin ([owner #:mutable] pointer))
(define (check-live-pin! who owner)
  (when (hash-ref busy owner #f)
    (error who "resource is exclusively leased by a live-stream operation")))
(define (check-live-fault! who owner)
  (when (hash-ref faulty owner #f)
    (error who "native output failed or was cancelled; close this stream")))
(define (pin-live-output! who owner pointer)
  ;; Called within a successfully checked call-with-owned scope.
  (check-live-pin! who owner)
  (check-live-fault! who owner)
  (define pin (live-pin owner pointer))
  (hash-set! busy owner #t)
  (register-finalizer pin release-live-pin!)
  pin)
(define (poison-live-pin! pin)
  (call-as-atomic
   (lambda ()
     (when (live-pin-owner pin) (hash-set! faulty (live-pin-owner pin) #t)))))
(define (release-live-pin! pin)
  (call-as-atomic
   (lambda ()
     (define owner (live-pin-owner pin))
     (when owner
       (hash-remove! busy owner)
       (set-live-pin-owner! pin #f)))))
