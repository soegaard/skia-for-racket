#lang racket/base

;;;
;;; Live Native Leases
;;;

;; Retains native references and pins resource owners during callback-based I/O.
;; Prevents explicit close from invalidating resources in an active native operation.

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
;; Fields:
;;   pointer: mutable retained cpointer or #f after release/transfer. release: matching one-pointer
;;   destructor procedure. Clearing the pointer before destruction prevents duplicate release on
;;   exceptional cleanup; adoption clears it without running release because ownership transfers.

; reference-pointer : native-reference? -> cpointer?
;;   Borrows a retained pointer, rejecting references already closed or transferred.
(define (reference-pointer ref)
  (define p (native-reference-pointer ref))
  (unless p (error 'live-streams "private native reference is closed or transferred"))
  p)
; reference-close! : native-reference? -> void?
;;   Atomically clears and releases an independent native reference at most once.
(define (reference-close! ref)
  (call-as-atomic
   (lambda ()
     (define p (native-reference-pointer ref))
     (when p
       (set-native-reference-pointer! ref #f)
       ((native-reference-release ref) p)))))
; make-native-reference : cpointer? procedure? -> native-reference?
;;   Adopts a non-null native reference with its matching destructor and registers abandonment
;;   cleanup.
(define (make-native-reference ptr release)
  (unless ptr (error 'live-streams "native allocation failed"))
  (define ref (native-reference ptr release))
  (register-finalizer ref reference-close!)
  ref)
;; Must be invoked inside new-owned's atomic create thunk, so there is no gap
;; between taking this reference and installing the library's ordinary owner.
; adopt-reference! : native-reference? -> cpointer?
;;   Transfers the pointer to an ordinary owner; the caller must bridge ownership atomically without
;;   a release gap.
(define (adopt-reference! ref)
  (define p (reference-pointer ref))
  (set-native-reference-pointer! ref #f)
  p)

;; A native WStream is mutable and not ref-counted. Pin its existing owner while
;; a private Racket-port sink forwards bounded chunks to it. The lifetime layer
;; checks these tables at every public borrow/close. Weak keys do not themselves
;; keep owners alive; the live pin does so until service cleanup.
; busy : hash?
;;   Weakly marks owners exclusively pinned by an active live-stream operation.
(define busy (make-weak-hasheq))
; faulty : hash?
;;   Weakly marks output owners that must be closed after failed or cancelled native writes.
(define faulty (make-weak-hasheq))
(struct live-pin ([owner #:mutable] pointer))
;; Fields:
;;   owner: mutable owned-resource keepalive, or #f after release. pointer: borrowed native output
;;   pointer, valid only while owner is retained even though the pointer field is not cleared.
;;   Active pins reject public borrowing and explicit closure of the owning resource. Pin release
;;   removes exclusivity but does not clear the separate failed-output marker.

; check-live-pin! : symbol? any/c -> void?
;;   Rejects public borrowing or closure while a live operation holds an exclusive pin.
(define (check-live-pin! who owner)
  (when (hash-ref busy owner #f)
    (error who "resource is exclusively leased by a live-stream operation")))
; check-live-fault! : symbol? any/c -> void?
;;   Rejects reuse of an output whose native operation failed or was cancelled.
(define (check-live-fault! who owner)
  (when (hash-ref faulty owner #f)
    (error who "native output failed or was cancelled; close this stream")))
; pin-live-output! : symbol? any/c cpointer? -> live-pin?
;;   Retains an already checked owner and exclusively pins its non-reference-counted output pointer.
(define (pin-live-output! who owner pointer)
  ;; Called within a successfully checked call-with-owned scope.
  (check-live-pin! who owner)
  (check-live-fault! who owner)
  (define pin (live-pin owner pointer))
  (hash-set! busy owner #t)
  (register-finalizer pin release-live-pin!)
  pin)
; poison-live-pin! : live-pin? -> void?
;;   Marks the retained output unusable after failure without releasing its active pin.
(define (poison-live-pin! pin)
  (call-as-atomic
   (lambda ()
     (when (live-pin-owner pin) (hash-set! faulty (live-pin-owner pin) #t)))))
; release-live-pin! : live-pin? -> void?
;;   Removes the exclusive lease and owner keepalive exactly once, after native use ends.
(define (release-live-pin! pin)
  (call-as-atomic
   (lambda ()
     (define owner (live-pin-owner pin))
     (when owner
       (hash-remove! busy owner)
       (set-live-pin-owner! pin #f)))))
