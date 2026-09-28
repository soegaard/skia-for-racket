#lang racket/base
(require rackunit racket/list "../private/gpu-egl-util.rkt" "../private/gpu-domain.rkt"
         "../private/gpu-provider.rkt" "../private/gpu-interop-guard.rkt"
         "../private/gpu-gl-interop-util.rkt")
(provide gpu-egl-pure-tests)
(define (fixture proc #:fail [failure #f])
  (define log (box '()))
  (define (record item) (set-box! log (append (unbox log) (list item))))
  (define current 'foreign)
  (define opened? #f)
  (define children '())
  (define (operation item [value (void)])
    (record item) (when (eq? item failure) (error 'mock-egl "~a" item)) value)
  (define ops
    (egl-platform-ops
     (lambda () (operation 'open) (set! opened? #t) 'egl-host)
     (lambda (_) (operation 'host-close) (set! opened? #f) (when (eq? current 'ours) (set! current #f)))
     (lambda (_)
       (operation 'enter)
       (define previous current) (set! current 'ours)
       (lambda () (operation 'restore) (set! current previous)))
     (lambda (_) (and opened? (eq? current 'ours)))
     (lambda (_) (hasheq 'headless #t 'renderer "mock"))
     (lambda (name) (operation 'resolve name))))
  (define-values (provider driver)
    (make-egl-components ops
      (lambda (_)
        (gpu-driver (lambda () (operation 'create 'ganesh))
                    (lambda (_) (operation 'release))
                    (lambda (_) (operation 'abandon))
                    (lambda (_) (operation 'reset))
                    (lambda (_) (operation 'describe (hasheq 'renderer "mock" 'native_backend 0)))))))
  (define d #f)
  (dynamic-wind
    void
    (lambda ()
      (set! d (make-gpu-domain provider driver))
      (proc d provider log
            (lambda () current)
            (lambda () (define h (domain-new-resource d 'mock (lambda () 'child) (lambda (_) (record 'child-release))))
                        (set! children (cons h children)) h)))
    (lambda ()
      (for ([h (in-list children)]) (domain-resource-close! h))
      (when (and d (not (eq? (domain-state d) 'closed)))
        (domain-close! d)))))
(define gpu-egl-pure-tests
  (test-suite
   "EGL ownership, callback scopes and GL interop contracts"
   (test-case "extension matching uses whole tokens"
     (check-true (egl-extension? "EGL_A EGL_B\nEGL_C" "EGL_B")))
   (test-case "extension prefix is not a match"
     (check-false (egl-extension? "EGL_A_extended" "EGL_A")))
   (test-case "absent extension string is not a match"
     (check-false (egl-extension? #f "EGL_A")))
   (test-case "surfaceless options"
     (check-not-exn (lambda () (check-egl-options 'test 'surfaceless 0 'surfaceless))))
   (test-case "device options"
     (check-not-exn (lambda () (check-egl-options 'test 'device 2 'pbuffer))))
   (test-case "reject default-display platform"
     (check-exn exn:fail? (lambda () (check-egl-options 'test 'default 0 'pbuffer))))
   (test-case "reject negative device index"
     (check-exn exn:fail? (lambda () (check-egl-options 'test 'device -1 'pbuffer))))
   (test-case "reject fractional device index"
     (check-exn exn:fail? (lambda () (check-egl-options 'test 'device 0.5 'pbuffer))))
   (test-case "reject unused device index"
     (check-exn exn:fail? (lambda () (check-egl-options 'test 'surfaceless 1 'pbuffer))))
   (test-case "reject hidden window surface option"
     (check-exn exn:fail? (lambda () (check-egl-options 'test 'device 0 'window))))
   (test-case "host is opened once and restored after construction"
     (fixture (lambda (d p log current child)
       (check-equal? (current) 'foreign)
       (check-equal? (count (lambda (e) (eq? e 'open)) (unbox log)) 1))))
   (test-case "provider is EGL but backend remains OpenGL"
     (fixture (lambda (d p log current child)
       (check-eq? (gpu-provider-name p) 'egl-owned) (check-eq? (domain-backend d) 'opengl))))
   (test-case "activation restores foreign native current binding"
     (fixture (lambda (d p log current child)
       (domain-call d (lambda () (check-eq? (current) 'ours)))
       (check-eq? (current) 'foreign))))
   (test-case "multiple values cross provider scopes"
     (fixture (lambda (d p log current child)
       (check-equal? (call-with-values (lambda () (domain-call d (lambda () (values 2 3)))) list) '(2 3)))))
   (test-case "callback exceptions restore current binding"
     (fixture (lambda (d p log current child)
       (check-exn #rx"callback" (lambda () (domain-call d (lambda () (error 'callback "failure")))))
       (check-eq? (current) 'foreign))))
   (test-case "non-exception raised values restore current binding"
     (fixture (lambda (d p log current child)
       (check-equal? (with-handlers ([(lambda (_) #t) values]) (domain-call d (lambda () (raise 'marker)))) 'marker)
       (check-eq? (current) 'foreign))))
   (test-case "nested same-domain scopes do not rebind EGL"
     (fixture (lambda (d p log current child)
       (define n (count (lambda (e) (eq? e 'enter)) (unbox log)))
       (domain-call d (lambda () (domain-call d void)))
       (check-equal? (count (lambda (e) (eq? e 'enter)) (unbox log)) (+ n 1)))))
   (test-case "no EGL host recreation between activations"
     (fixture (lambda (d p log current child)
       (domain-call d void) (domain-call d void)
       (check-equal? (count (lambda (e) (eq? e 'open)) (unbox log)) 1))))
   (test-case "native child close is queued before host teardown"
     (fixture (lambda (d p log current child)
       (define h (domain-call d child))
       (domain-resource-close! h)
       (domain-close! d)
       (check-true (< (index-of (unbox log) 'child-release) (index-of (unbox log) 'release)))
       (check-true (< (index-of (unbox log) 'release) (index-of (unbox log) 'host-close))))))
   (test-case "close rejects still-live children"
     (fixture (lambda (d p log current child)
       (domain-call d child)
       (check-exn #rx"live GPU children" (lambda () (domain-close! d))))))
   (test-case "normal close is idempotent"
     (fixture (lambda (d p log current child)
       (domain-close! d) (domain-close! d)
       (check-equal? (count (lambda (e) (eq? e 'host-close)) (unbox log)) 1))))
   (test-case "abandon closes without acquiring provider again"
     (fixture (lambda (d p log current child)
       (define n (count (lambda (e) (eq? e 'enter)) (unbox log)))
       (domain-abandon! d) (domain-close! d)
       (check-equal? (count (lambda (e) (eq? e 'enter)) (unbox log)) n))))
   (test-case "host-creation failure is explicit"
     (check-exn #rx"open" (lambda () (fixture void #:fail 'open))))
   (test-case "EGL activation failure is explicit"
     (check-exn #rx"enter" (lambda () (fixture void #:fail 'enter))))
   (test-case "Ganesh construction failure is explicit"
     (check-exn #rx"create" (lambda () (fixture void #:fail 'create))))
   (test-case "Ganesh describe failure is explicit"
     (check-exn #rx"describe" (lambda () (fixture void #:fail 'describe))))
   (test-case "wrong Racket thread cannot activate provider"
     (fixture (lambda (d p log current child)
       (define ch (make-channel))
       (thread (lambda () (channel-put ch (with-handlers ([exn:fail? (lambda (_) #t)]) (domain-call d void) #f))))
       (check-true (channel-get ch)))))
   (test-case "external GL callback blocks Skia pointer access"
     (fixture (lambda (d p log current child)
       (domain-call d (lambda ()
         (parameterize ([current-external-gl? #t])
           (check-exn #rx"external OpenGL callback" (lambda () (domain-pointer d)))))))))
   (test-case "external GL callback blocks nested domain activation"
     (fixture (lambda (d p log current child)
       (domain-call d (lambda ()
         (parameterize ([current-external-gl? #t])
           (check-exn exn:fail? (lambda () (domain-call d void)))))))))
   (test-case "external GL callback blocks queued native destruction"
     (fixture (lambda (d p log current child)
       (domain-call d (lambda ()
         (parameterize ([current-external-gl? #t])
           (check-exn exn:fail? (lambda () (domain-drain! d)))))))))
   (test-case "external guard unwinds after failure"
     (fixture (lambda (d p log current child)
       (domain-call d (lambda ()
         (with-handlers ([exn:fail? void])
           (parameterize ([current-external-gl? #t]) (error 'test "intentional")))
         (check-eq? (domain-pointer d) 'ganesh))))))
   (test-case "provider resolver must accept one argument"
     (check-exn exn:fail?
       (lambda () (make-gpu-provider #:name 'x #:backend 'opengl #:key 'x
                    #:call-as-current (lambda (thunk) (thunk)) #:current? (lambda () #t)
                    #:get-proc-address (lambda () #f)))))
   (test-case "default framebuffer is deliberately not imported"
     (check-exn exn:fail? (lambda () (check-gl-name 'test 0))))
   (test-case "GL name cannot exceed uint32"
     (check-exn exn:fail? (lambda () (check-gl-name 'test #x100000000))))
   (test-case "GL extent cannot be zero or fractional"
     (check-exn exn:fail? (lambda () (check-gl-extent 'test 0 8)))
     (check-exn exn:fail? (lambda () (check-gl-extent 'test 4.5 8))))
   (test-case "origins are explicit pinned values"
     (check-equal? (gl-origin-value 'test 'top-left) 0)
     (check-equal? (gl-origin-value 'test 'bottom-left) 1)
     (check-exn exn:fail? (lambda () (gl-origin-value 'test 'auto))))
   (test-case "wait policy is boolean"
     (check-exn exn:fail? (lambda () (check-gl-borrow-options 'test 1 8 8 'top-left 'auto))))))
