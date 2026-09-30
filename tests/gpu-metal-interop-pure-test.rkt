#lang racket/base
(require rackunit racket/list "../gpu-interop.rkt"
         "../private/gpu-metal-interop-policy.rkt" "../private/gpu-metal-interop-session.rkt"
         "../private/gpu-interop-cleanup.rkt"
         (submod "../private/gpu-external.rkt" backend-internals))
(provide gpu-metal-interop-pure-tests)
(define desc
  (hasheq 'width 37 'height 29 'depth 1 'levels 1 'array_length 1 'samples 1
          'format 70 'texture_type 2 'usage 5 'storage_mode 2 'hazard_tracking_mode 2
          'swizzle '(2 3 4 5) 'same_device #t 'framebuffer_only #f 'has_parent #f
          'has_buffer #f 'has_heap #f 'has_iosurface #f 'shareable #f 'has_remote_storage #f
          'producer_retained_references #t))
(define (reason r)
  (lambda (e) (and (exn:fail:metal-interop? e) (eq? (exn:fail:metal-interop-reason e) r))))
(define (fixture #:producer-status [ps (lambda () 4)] #:tail-status [ts (lambda () 4)]
                 #:retain [retain values] #:release [release void]
                 #:tail [tail (lambda () 'tail)] #:commit [commit void]
                 #:description [d desc] #:timeout [timeout 1])
  (define calls (box '()))
  (define (record k p) (set-box! calls (append (unbox calls) (list (list k p)))))
  (define ops
    (metal-interop-ops
     (lambda (_t _p) d)
     (lambda (p) (record 'retain p) (retain p))
     (lambda (p) (record 'release p) (release p))
     (lambda (p) (if (eq? p 'producer) (ps) (ts)))
     (lambda (_) "synthetic command failure") tail commit))
  (values (make-metal-session ops 'texture 'producer timeout) calls))
(define gpu-metal-interop-pure-tests
 (test-suite "Metal external-resource contracts without native/GUI loading"
  (test-case "valid private descriptor"
    (check-eq? (metal-check-texture! desc #t) desc))
  (test-case "shared storage accepted explicitly"
    (check-not-exn (lambda () (metal-check-texture! (hash-set desc 'storage_mode 0)))))
  (test-case "read-only source cannot be drawn into"
    (define d (hash-set desc 'usage 1)) (metal-check-texture! d)
    (check-exn (reason 'render-usage) (lambda () (metal-check-texture! d #t))))
  (test-case "missing native metadata fails"
    (for ([k (in-list (hash-keys desc))])
      (check-exn exn:fail? (lambda () (metal-check-texture! (hash-remove desc k))))))
  (test-case "reject width 0"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'width 0)))))
  (test-case "reject height 16385"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'height 16385)))))
  (test-case "reject levels 2"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'levels 2)))))
  (test-case "reject array_length 2"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'array_length 2)))))
  (test-case "reject samples 4"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'samples 4)))))
  (test-case "reject format 80"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'format 80)))))
  (test-case "reject texture_type 3"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'texture_type 3)))))
  (test-case "reject storage_mode 1"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'storage_mode 1)))))
  (test-case "reject hazard_tracking_mode 1"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'hazard_tracking_mode 1)))))
  (test-case "reject usage 0"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'usage 0)))))
  (test-case "reject usage 7"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'usage 7)))))
  (test-case "reject same_device #f"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'same_device #f)))))
  (test-case "reject framebuffer_only #t"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'framebuffer_only #t)))))
  (test-case "reject has_parent #t"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'has_parent #t)))))
  (test-case "reject has_buffer #t"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'has_buffer #t)))))
  (test-case "reject has_heap #t"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'has_heap #t)))))
  (test-case "reject has_iosurface #t"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'has_iosurface #t)))))
  (test-case "reject shareable #t"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'shareable #t)))))
  (test-case "reject has_remote_storage #t"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'has_remote_storage #t)))))
  (test-case "reject producer_retained_references #f"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'producer_retained_references #f)))))
  (test-case "reject swizzle '(4 3 2 5)"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'swizzle '(4 3 2 5))))))
  (test-case "reject width #t"
    (check-exn exn:fail? (lambda () (metal-check-texture! (hash-set desc 'width #t)))))
  (test-case "bounded exact timeout"
    (for ([n '(0 -1 60001 1.0 #t #f)]) (check-exn exn:fail? (lambda () (metal-timeout! n))))
    (check-equal? (metal-timeout! 60000) 60000))
  (test-case "completed producer needs no sleep"
    (define r (metal-wait-completed! (lambda () 4) void 1 #:clock (lambda () 0)
                  #:pause (lambda (_) (error 'test "unexpected sleep"))))
    (check-equal? (hash-ref r 'status) 4) (check-equal? (hash-ref r 'polls) 1))
  (test-case "committed and scheduled are not completed"
    (define states '(2 3 4))
    (define r (metal-wait-completed! (lambda () (begin0 (car states) (set! states (cdr states))))
                  void 10 #:clock (lambda () 0) #:pause void))
    (check-equal? (hash-ref r 'polls) 3))
  (test-case "uncommitted statuses fail"
    (for ([v '(0 1 #f 6)])
      (check-exn (reason 'uncommitted) (lambda () (metal-wait-completed! (lambda () v) void 10)))))
  (test-case "asynchronous error has its own reason"
    (check-exn (reason 'command-error) (lambda () (metal-wait-completed! (lambda () 5) (lambda () "bad") 10))))
  (test-case "fake clock establishes a real deadline"
    (define now 0)
    (check-exn (reason 'timeout)
      (lambda () (metal-wait-completed! (lambda () 2) void 3 #:clock (lambda () now)
                     #:pause (lambda (seconds) (set! now (+ now (* seconds 1000)))))))
    (check-equal? now 3.0))
  (test-case "unconsumed session releases exact two references once"
    (define-values (s calls) (fixture))
    (metal-session-close! s) (metal-session-close! s)
    (check-equal? (unbox calls) '((retain texture) (retain producer) (release producer) (release texture)))
    (check-equal? (hash-ref (metal-session-info s) 'state) "closed"))
  (test-case "completed handoff verifies both completion boundaries"
    (define-values (s calls) (fixture))
    (metal-session-begin! s) (metal-session-complete! s) (metal-session-close! s)
    (check-equal? (map (lambda (x) (hash-ref x 'phase)) (hash-ref (metal-session-info s) 'waits))
                  '("producer" "ganesh-queue-tail"))
    (check-equal? (unbox calls) '((retain texture) (retain producer) (release tail) (release producer) (release texture))))
  (test-case "active session cannot be closed"
    (define-values (s calls) (fixture)) (metal-session-begin! s)
    (check-exn #rx"cannot release" (lambda () (metal-session-close! s)))
    (check-equal? (length (unbox calls)) 2)
    (metal-session-complete! s) (metal-session-close! s))
  (test-case "double begin fails"
    (define-values (s calls) (fixture)) (metal-session-begin! s)
    (check-exn #rx"not ready" (lambda () (metal-session-begin! s)))
    (metal-session-complete! s) (metal-session-close! s))
  (test-case "finish requires a started handoff"
    (define-values (s calls) (fixture))
    (check-exn #rx"not active" (lambda () (metal-session-complete! s))) (metal-session-close! s))
  (test-case "second retain failure rolls back first reference"
    (define released '())
    (check-exn #rx"retain failed" (lambda ()
      (fixture #:retain (lambda (p) (when (eq? p 'producer) (error 'test "retain failed")) p)
               #:release (lambda (p) (set! released (cons p released))))))
    (check-equal? released '(texture)))
  (test-case "producer timeout retains storage in quarantine"
    (define-values (s calls) (fixture #:producer-status (lambda () 2)))
    (check-exn (reason 'timeout) (lambda () (metal-session-begin! s)))
    (check-true (hash-ref (metal-session-info s) 'quarantined))
    (check-exn exn:fail? (lambda () (metal-session-close! s)))
    (check-equal? (length (unbox calls)) 2))
  (test-case "missing tail allocation quarantines"
    (define-values (s calls) (fixture #:tail (lambda () #f))) (metal-session-begin! s)
    (check-exn (reason 'allocation) (lambda () (metal-session-complete! s)))
    (check-true (hash-ref (metal-session-info s) 'quarantined)))
  (test-case "commit failure keeps the completion buffer"
    (define-values (s calls) (fixture #:commit (lambda (_) (error 'test "commit failed"))))
    (metal-session-begin! s) (check-exn #rx"commit failed" (lambda () (metal-session-complete! s)))
    (check-true (hash-ref (metal-session-info s) 'retained_completion_buffer)))
  (test-case "tail asynchronous error quarantines"
    (define-values (s calls) (fixture #:tail-status (lambda () 5))) (metal-session-begin! s)
    (check-exn (reason 'command-error) (lambda () (metal-session-complete! s)))
    (check-true (hash-ref (metal-session-info s) 'quarantined)))
  (test-case "tail timeout quarantines"
    (define-values (s calls) (fixture #:tail-status (lambda () 2))) (metal-session-begin! s)
    (check-exn (reason 'timeout) (lambda () (metal-session-complete! s)))
    (check-true (hash-ref (metal-session-info s) 'retained_completion_buffer)))
  (test-case "indeterminate destructor is never retried"
    (define-values (s calls) (fixture #:release (lambda (_) (error 'test "release failed"))))
    (check-exn #rx"release failed" (lambda () (metal-session-close! s)))
    (check-exn exn:fail? (lambda () (metal-session-close! s)))
    (check-equal? (length (unbox calls)) 3))
  (test-case "thread cannot observe or mutate native session"
    (define-values (s calls) (fixture)) (define ch (make-channel))
    (thread (lambda () (channel-put ch (with-handlers ([exn:fail? (lambda (_) 'rejected)]) (metal-session-info s)))))
    (check-eq? (channel-get ch) 'rejected) (metal-session-close! s))
  (test-case "generic Metal copy is one handoff"
    (define context (gensym))
    (define t (make-external-texture 'metal context 19 (hasheq) void
                (lambda (_mode _proc) 'owned-image) void (lambda () (hasheq))))
    (check-eq? (gpu-import-image context t) 'owned-image)
    (check-exn #rx"consumed" (lambda () (gpu-import-image context t))))
  (test-case "generic Metal callback keeps multiple values"
    (define context (gensym))
    (define t (make-external-texture 'metal context 19 (hasheq) void
                (lambda (_mode proc) (proc 'scoped-canvas)) void (lambda () (hasheq))))
    (check-equal? (call-with-values
      (lambda () (call-with-gpu-external-surface context t (lambda (c) (values c 42)))) list)
      '(scoped-canvas 42)))
  (test-case "shared cleanup executes after arbitrary exception"
    (define finished? #f)
    (check-exn (lambda (e) (eq? e 'boom))
      (lambda () (call-with-interop-cleanup (lambda () (raise 'boom))
                   (lambda () (set! finished? #t)) (lambda (_) (error 'test "unexpected quarantine")))))
    (check-true finished?))
  (test-case "shared cleanup failure quarantines once"
    (define n 0)
    (check-exn #rx"completion failed"
      (lambda () (call-with-interop-cleanup (lambda () (raise 'boom))
                   (lambda () (error 'test "completion failed")) (lambda (_) (set! n (add1 n))))))
    (check-equal? n 1))
))
