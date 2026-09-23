#lang racket/base
(require ffi/unsafe ffi/unsafe/alloc ffi/unsafe/atomic)
(provide owned? new-owned owned-closed? owned-close!
         call-with-owned call-with-scoped-resource)

;; A single mutable lifetime cell is shared by all aliases. Native pointers
;; and release procedures never escape the package's public API.
(struct owned ([ptr #:mutable] release creator kind))

(define (release-owned! h)
  (define ptr (owned-ptr h))
  (when ptr
    (set-owned-ptr! h #f) ; invalidate every alias before native destruction
    ((owned-release h) ptr)))

(define allocate-owned
  ((allocator release-owned!)
   (lambda (who kind create release)
     (define ptr (create))
     (unless ptr
       (error who "native allocation failed for ~a" kind))
     (owned ptr release (current-thread) kind))))

(define (new-owned who kind create release)
  ;; Callers resolve all native symbols before entering this allocator.
  (allocate-owned who kind create release))

(define (check-thread who h)
  (unless (eq? (owned-creator h) (current-thread))
    (error who
           "~a belongs to another Racket thread; create separate resources in each worker"
           (owned-kind h))))

(define (owned-closed? h) (not (owned-ptr h)))
(define release-explicitly! ((deallocator) release-owned!))
(define (owned-close! who h)
  (check-thread who h)
  (release-explicitly! h)
  (void))

(define (call-with-owned who handles proc)
  ;; Synchronous FFI calls plus atomic validation prevent another Racket
  ;; thread/finalizer from releasing an object between the check and call.
  ;; This is deliberately conservative; rendering does not run in parallel
  ;; on Racket threads in this first version. Separate places are possible.
  (call-as-atomic
   (lambda ()
     (define pointers
       (for/list ([h (in-list handles)])
         (check-thread who h)
         (or (owned-ptr h)
             (error who "~a is closed" (owned-kind h)))))
     (begin0 (apply proc pointers)
       (void/reference-sink handles)))))

(define (call-with-scoped-resource value close proc)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       void
       (lambda () (proc value))
       (lambda () (close value))))))
