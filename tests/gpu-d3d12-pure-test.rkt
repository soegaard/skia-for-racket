#lang racket/base
(require rackunit ffi/unsafe racket/list
         "../gpu.rkt" "../private/gpu-domain.rkt"
         "../private/gpu-d3d12-util.rkt" "../private/gpu-d3d12-types.rkt"
         "../private/gpu-types.rkt" "../private/gpu-cache-util.rkt")
(provide gpu-d3d12-pure-tests)

(define (fixture [failure #f] [selection 'warp] [flags 2])
  (define log (box '()))
  (define lost (box 0))
  (define abandoned (box #f))
  (define (note x) (set-box! log (append (unbox log) (list x))))
  (define (create step result)
    (note step)
    (and (not (eq? failure step)) result))
  (define platform
    (d3d12-platform-ops
     (lambda (selected index) (note (list selected index)) (create 'adapter 'adapter-p))
     (lambda (a) (check-eq? a 'adapter-p) (create 'device 'device-p))
     (lambda (d) (check-eq? d 'device-p) (create 'queue 'queue-p))
     (lambda (p) (note (list 'release p)))
     (lambda (a) (note 'describe-adapter) (hasheq 'adapter_flags flags 'renderer "fixture"))
     (lambda (d) (check-eq? d 'device-p) (unbox lost))))
  (define native
    (d3d12-context-ops
     (lambda (a d q) (check-equal? (list a d q) '(adapter-p device-p queue-p)) (create 'ganesh 'context-p))
     (lambda (p) (note 'release-context) (when (eq? failure 'release) (error 'fixture "release failed")))
     (lambda (p) (note 'abandon) (set-box! abandoned #t))
     (lambda (p) (unbox abandoned))
     (lambda (p) (note 'wait) (when (eq? failure 'wait) (error 'fixture "wait failed")))
     (lambda (p details)
       (when (eq? failure 'describe) (error 'fixture "describe failed"))
       (hash-set details 'native_backend 3))))
  (define-values (provider driver) (make-d3d12-components platform native selection 0))
  (values provider driver log lost))
(define (exercise failure proc)
  (define-values (provider driver log lost) (fixture failure))
  (proc provider driver log lost))
(define (released log)
  (filter (lambda (x) (and (pair? x) (eq? (car x) 'release))) (unbox log)))

(define gpu-d3d12-pure-tests
  (test-suite
   "D3D12 ownership and ABI without native libraries"
   (test-case "backend identity" (check-equal? (gpu-backend-native-id 'direct3d) 3))
   (test-case "existing identities unchanged"
     (check-equal? (map gpu-backend-native-id '(opengl metal)) '(0 2)))
   (test-case "64-bit layouts"
     (when (= (ctype-sizeof _pointer) 8) (check-not-exn check-d3d12-layouts!)))
   (test-case "by-value descriptor includes trailing bool"
     (when (= (ctype-sizeof _pointer) 8) (check-equal? (ctype-sizeof _gr-d3d-backend-context) 40)))
   (test-case "GUID widths" (for ([g (list iid-factory4 iid-adapter1 iid-device iid-queue)]) (check-equal? (bytes-length g) 16)))
   (test-case "warp selection" (check-not-exn (lambda () (d3d12-selection! 'warp 0))))
   (test-case "hardware selection" (check-not-exn (lambda () (d3d12-selection! 'hardware 3))))
   (test-case "unknown adapter" (check-exn exn:fail:contract? (lambda () (d3d12-selection! 'auto 0))))
   (test-case "negative index" (check-exn exn:fail:contract? (lambda () (d3d12-selection! 'hardware -1))))
   (test-case "inexact index" (check-exn exn:fail:contract? (lambda () (d3d12-selection! 'hardware 0.0))))
   (test-case "overflow index" (check-exn exn:fail:contract? (lambda () (d3d12-selection! 'hardware #x100000000))))
   (test-case "warp index is not ignored" (check-exn exn:fail:contract? (lambda () (d3d12-selection! 'warp 1))))
   (test-case "other backends reject adapter keywords"
     (check-exn exn:fail:contract? (lambda () (make-gpu-context #:backend 'metal #:adapter 'warp))))
   (test-case "bad selection rejected before platform loading"
     (check-exn exn:fail:contract? (lambda () (make-gpu-context #:backend 'direct3d #:adapter 'auto))))
   (test-case "no construction on component creation"
     (exercise #f (lambda (p d log lost) (check-equal? (unbox log) '()))))
   (test-case "context retains its independent COM references"
     (exercise #f (lambda (p driver log lost)
                   (define d (make-gpu-domain p driver))
                   (check-equal? (released log) '())
                   (domain-close! d))))
   (test-case "normal release waits then releases Ganesh before COM"
     (exercise #f (lambda (p driver log lost)
                   (define d (make-gpu-domain p driver))
                   (set-box! log '()) (domain-close! d)
                   (check-equal? (unbox log) '(wait release-context (release queue-p) (release device-p) (release adapter-p))))))
   (test-case "close is idempotent"
     (exercise #f (lambda (p driver log lost)
                   (define d (make-gpu-domain p driver)) (domain-close! d)
                   (define before (unbox log)) (domain-close! d) (check-equal? (unbox log) before))))
   (test-case "adapter failure owns nothing"
     (exercise 'adapter (lambda (p d log lost) (check-exn exn:fail? (lambda () (make-gpu-domain p d))) (check-equal? (released log) '()))))
   (test-case "device failure releases adapter"
     (exercise 'device (lambda (p d log lost) (check-exn exn:fail? (lambda () (make-gpu-domain p d))) (check-equal? (released log) '((release adapter-p))))))
   (test-case "queue failure releases device then adapter"
     (exercise 'queue (lambda (p d log lost) (check-exn exn:fail? (lambda () (make-gpu-domain p d))) (check-equal? (released log) '((release device-p) (release adapter-p))))))
   (test-case "Ganesh null releases all owned COM references"
     (exercise 'ganesh (lambda (p d log lost) (check-exn exn:fail? (lambda () (make-gpu-domain p d))) (check-equal? (released log) '((release queue-p) (release device-p) (release adapter-p))))))
   (test-case "description failure cleans up successful construction"
     (exercise 'describe (lambda (p d log lost) (check-exn exn:fail? (lambda () (make-gpu-domain p d))) (check-not-false (member 'release-context (unbox log))) (check-equal? (length (released log)) 3))))
   (test-case "WARP cannot masquerade as hardware"
     (define-values (p d log lost) (fixture #f 'hardware 2))
     (check-exn exn:fail? (lambda () (make-gpu-domain p d)))
     (check-false (member 'device (unbox log))))
   (test-case "hardware cannot masquerade as WARP"
     (define-values (p d log lost) (fixture #f 'warp 0))
     (check-exn exn:fail? (lambda () (make-gpu-domain p d)))
     (check-false (member 'device (unbox log))))
   (test-case "reports classify WARP without acceleration claims"
     (exercise #f (lambda (p driver log lost)
                   (define d (make-gpu-domain p driver)) (define info (domain-info d))
                   (check-equal? (hash-ref info 'renderer_class) "software")
                   (check-true (hash-ref info 'd3d12_warp))
                   (check-false (hash-ref info 'hardware_acceleration_verified))
                   (check-false (hash-ref info 'window_created)) (domain-close! d))))
   (test-case "abandon never waits"
     (exercise #f (lambda (p driver log lost)
                   (define d (make-gpu-domain p driver)) (set-box! log '())
                   (domain-abandon! d) (domain-close! d)
                   (check-false (member 'wait (unbox log))) (check-equal? (length (released log)) 3))))
   (test-case "device removal blocks drawing and retires without waiting"
     (exercise #f (lambda (p driver log lost)
                   (define d (make-gpu-domain p driver)) (set-box! lost -1) (set-box! log '())
                   (check-exn exn:fail? (lambda () (domain-call d void))) (domain-close! d)
                   (check-not-false (member 'abandon (unbox log))) (check-false (member 'wait (unbox log))))))
   (test-case "foreign owner rejected before COM work"
     (exercise #f (lambda (p driver log lost)
                   (define d (make-gpu-domain p driver)) (define ch (make-channel)) (set-box! log '())
                   (thread (lambda () (with-handlers ([exn:fail? (lambda (e) (channel-put ch #t))]) (domain-call d void) (channel-put ch #f))))
                   (check-true (channel-get ch)) (check-equal? (unbox log) '()) (domain-close! d))))
   (test-case "independent contexts get distinct generations"
     (define-values (p1 drv1 log1 lost1) (fixture))
     (define-values (p2 drv2 log2 lost2) (fixture))
     (define d1 (make-gpu-domain p1 drv1)) (define d2 (make-gpu-domain p2 drv2))
     (check-not-equal? (domain-generation d1) (domain-generation d2))
     (domain-close! d2) (domain-close! d1))
   (test-case "cache snapshot knows Direct3D"
     (check-equal? (hash-ref (cache-snapshot 'direct3d 1 1024 0 0) 'backend) "direct3d"))
   (test-case "native DLLs are not needed for pure tests"
     (when (not (eq? (system-type 'os) 'windows))
       (check-exn exn:fail:gpu:unavailable? (lambda () (make-gpu-context #:backend 'direct3d #:adapter 'warp)))))))
