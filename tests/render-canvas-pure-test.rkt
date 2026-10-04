#lang racket/base
(require rackunit racket/list
         "../private/render-canvas-policy.rkt" "../private/render-canvas-state.rkt")
(provide render-canvas-pure-tests render-canvas-pure-test-count)
(define (select renderer [backend 'auto] [os 'unix] [arch 'x86_64]
                #:adapter [adapter #f] #:index [index #f] #:sync [sync #f])
  (resolve-render-canvas-policy renderer backend adapter index sync #:os os #:arch arch))
(define (choice . args)
  (define p (apply select args))
  (list (hash-ref p 'renderer) (hash-ref p 'backend)))
(define (session-count s key) (hash-ref (render-session-info s) key))
(define render-canvas-pure-tests
  (test-suite
   "Unified canvas declarative selection and callback scope; no GUI or native code"
   (test-case "explicit raster does not request a GPU backend on any platform"
     (for ([os '(macosx unix windows unknown)])
       (check-equal? (choice 'raster 'auto os) '(raster raster))))
   (test-case "automatic native backend choices are deterministic"
     (check-equal? (choice 'auto 'auto 'macosx 'aarch64) '(gpu metal))
     (check-equal? (choice 'auto 'auto 'windows) '(gpu direct3d))
     (check-equal? (choice 'auto) '(gpu opengl)))
   (test-case "unknown platforms select raster only for automatic requests"
     (check-equal? (choice 'auto 'auto 'unknown) '(raster raster))
     (check-exn exn:fail? (lambda () (select 'gpu 'auto 'unknown))))
   (test-case "Windows arm64 has no implicit unsupported built-in GPU host"
     (check-equal? (choice 'auto 'auto 'windows 'aarch64) '(raster raster))
     (check-exn exn:fail? (lambda () (select 'gpu 'auto 'windows 'aarch64))))
   (test-case "explicit OpenGL can override the native preference"
     (check-equal? (choice 'gpu 'opengl 'macosx 'aarch64) '(gpu opengl))
     (check-equal? (choice 'auto 'opengl 'windows) '(gpu opengl)))
   (test-case "unknown renderer values are rejected"
     (for ([r '(metal cpu #f 0)]) (check-exn exn:fail? (lambda () (select r)))))
   (test-case "unknown backend values are rejected"
     (for ([b '(raster egl vulkan #f)]) (check-exn exn:fail? (lambda () (select 'gpu b)))))
   (test-case "raster rejects conflicting backend options"
     (for ([b '(opengl metal direct3d)]) (check-exn exn:fail? (lambda () (select 'raster b)))))
   (test-case "explicit Metal rejects non-macOS hosts"
     (for ([os '(unix windows unknown)]) (check-exn exn:fail? (lambda () (select 'auto 'metal os)))))
   (test-case "explicit Direct3D requires Windows x64"
     (for ([os '(macosx unix unknown)]) (check-exn exn:fail? (lambda () (select 'gpu 'direct3d os))))
     (check-exn exn:fail? (lambda () (select 'gpu 'direct3d 'windows 'aarch64))))
   (test-case "explicit OpenGL rejects unsupported hosts"
     (check-exn exn:fail? (lambda () (select 'gpu 'opengl 'unknown)))
     (check-exn exn:fail? (lambda () (select 'gpu 'opengl 'windows 'aarch64))))
   (test-case "Direct3D default values are recorded explicitly"
     (define p (select 'gpu 'auto 'windows))
     (check-eq? (hash-ref p 'adapter) 'hardware)
     (check-equal? (hash-ref p 'adapter_index) 0)
     (check-equal? (hash-ref p 'sync_interval) 1))
   (test-case "WARP and zero sync interval are not replaced by defaults"
     (define p (select 'gpu 'direct3d 'windows #:adapter 'warp #:sync 0))
     (check-eq? (hash-ref p 'adapter) 'warp)
     (check-equal? (hash-ref p 'sync_interval) 0))
   (test-case "WARP cannot select a nonzero hardware adapter index"
     (check-exn exn:fail? (lambda () (select 'gpu 'direct3d 'windows #:adapter 'warp #:index 1))))
   (test-case "adapter values and indices are checked"
     (for ([a '(unknown #t 0)])
       (check-exn exn:fail? (lambda () (select 'gpu 'direct3d 'windows #:adapter a))))
     (for ([n '(-1 0.0 2147483648 #t)])
       (check-exn exn:fail? (lambda () (select 'gpu 'direct3d 'windows #:index n)))))
   (test-case "presentation sync interval is an exact integer in range"
     (for ([n '(-1 5 1.0 #t)])
       (check-exn exn:fail? (lambda () (select 'gpu 'direct3d 'windows #:sync n)))))
   (test-case "GPU-only options are never ignored on raster or OpenGL"
     (for ([r '(raster gpu)])
       (check-exn exn:fail? (lambda () (select r #:adapter 'hardware)))
       (check-exn exn:fail? (lambda () (select r #:index 0)))
       (check-exn exn:fail? (lambda () (select r #:sync 0)))))
   (test-case "policy is immutable and does not claim runtime availability"
     (define p (select 'auto))
     (check-true (immutable? p))
     (check-false (hash-ref p 'runtime_fallback))
     (check-false (hash-has-key? p 'driver_available))
     (check-eq? (hash-ref p 'requested_renderer) 'auto))
   (test-case "capabilities disclose actual raster versus GPU lifetime"
     (define a (render-canvas-capabilities (select 'raster)))
     (define b (render-canvas-capabilities (select 'gpu)))
     (check-eq? (hash-ref a 'dc_lifetime) 'persistent)
     (check-eq? (hash-ref b 'dc_lifetime) 'frame-scoped)
     (check-true (hash-ref a 'persistent_dc))
     (check-false (hash-ref b 'persistent_dc))
     (check-eq? (hash-ref a 'get_dc) 'callback-only)
     (check-eq? (hash-ref b 'get_dc) 'callback-only))
   (test-case "capabilities do not promise implicit GPU readback or fallback"
     (for ([r '(raster gpu)])
       (define c (render-canvas-capabilities (select r)))
       (check-true (immutable? c))
       (check-false (hash-ref c 'implicit_gpu_readback))
       (check-false (hash-ref c 'runtime_fallback))))
   (test-case "callback arity checked before constructing a session"
     (for ([p (list #f 42 (lambda () (void)) (lambda (_one) (void)))])
       (check-exn exn:fail? (lambda () (make-render-session p))))
     (check-not-exn (lambda () (make-render-session void))))
   (test-case "required keywords are rejected but optional ones are allowed"
     (check-exn exn:fail? (lambda () (make-render-session (lambda (c d #:required x) x))))
     (check-not-exn (lambda () (make-render-session (lambda (c d #:optional [x #f]) x)))))
   (test-case "callback receives exact canvas and DC and active scope"
     (define seen #f)
     (define s (make-render-session
                (lambda (c d) (set! seen (list c d))
                  (check-eq? (render-session-current-dc s) 'dc))))
     (render-session-deliver! s 'canvas 'dc)
     (check-equal? seen '(canvas dc))
     (check-false (render-session-current-dc s))
     (check-equal? (session-count s 'callbacks_completed) 1))
   (test-case "zero and multiple callback values are ignored"
     (for ([p (list (lambda (c d) (values)) (lambda (c d) (values 1 2 3)))])
       (check-true (void? (render-session-deliver! (make-render-session p) 'canvas 'dc)))))
   (test-case "one-shot callbacks do not replace the regular callback"
     (define seen '())
     (define s (make-render-session (lambda (_c _d) (set! seen (cons 'regular seen)))))
     (render-session-deliver! s 'canvas 'dc (lambda (_d) (set! seen (cons 'one-shot seen))))
     (render-session-deliver! s 'canvas 'dc)
     (check-equal? (reverse seen) '(one-shot regular)))
   (test-case "callback replacement is validated and does not draw"
     (define seen 0)
     (define s (make-render-session void))
     (render-session-set-callback! s (lambda (_c _d) (set! seen (add1 seen))))
     (check-equal? seen 0)
     (check-exn exn:fail? (lambda () (render-session-set-callback! s 0)))
     (render-session-deliver! s 'canvas 'dc)
     (check-equal? seen 1))
   (test-case "nested delivery and callback mutation reject"
     (define s (make-render-session
                (lambda (_c _d)
                  (check-exn #rx"during a paint callback"
                    (lambda () (render-session-deliver! s 'canvas 'nested)))
                  (check-exn exn:fail? (lambda () (render-session-set-callback! s void))))))
     (render-session-deliver! s 'canvas 'dc)
     (check-equal? (session-count s 'callbacks_started) 1))
   (test-case "exception unwinds the active DC and a subsequent call works"
     (define s (make-render-session (lambda (_c _d) (error 'test "paint-failed"))))
     (check-exn #rx"paint-failed" (lambda () (render-session-deliver! s 'canvas 'dc)))
     (check-false (render-session-current-dc s))
     (check-equal? (session-count s 'callbacks_started) 1)
     (check-equal? (session-count s 'callbacks_completed) 0)
     (render-session-set-callback! s void)
     (render-session-deliver! s 'canvas 'new)
     (check-equal? (session-count s 'callbacks_completed) 1))
   (test-case "non-exception raised values also unwind"
     (define s (make-render-session (lambda (_c _d) (raise 'paint-failed))))
     (check-eq? (with-handlers ([(lambda (_) #t) values]) (render-session-deliver! s 'canvas 'dc)) 'paint-failed)
     (check-false (render-session-current-dc s)))
   (test-case "continuation escape retires the callback scope"
     (define s (make-render-session void))
     (check-eq?
      (let/ec out (render-session-deliver! s 'canvas 'dc (lambda (_d) (out 'escaped))))
      'escaped)
     (check-false (render-session-current-dc s))
     (check-equal? (session-count s 'callbacks_completed) 0)
     (render-session-deliver! s 'canvas 'next)
     (check-equal? (session-count s 'callbacks_completed) 1))
   (test-case "cross-thread access rejects both state and drawing"
     (define s (make-render-session void))
     (for ([p (list (lambda () (render-session-current-dc s))
                    (lambda () (render-session-info s))
                    (lambda () (render-session-set-callback! s void))
                    (lambda () (render-session-deliver! s 'canvas 'dc)))])
       (define ch (make-channel))
       (thread (lambda () (channel-put ch (with-handlers ([exn:fail? values]) (p)))))
       (check-true (exn:fail? (channel-get ch)))))
   (test-case "callback info is detached and immutable"
     (define s (make-render-session void))
     (define before (render-session-info s))
     (render-session-deliver! s 'canvas 'dc)
     (check-true (immutable? before))
     (check-equal? (hash-ref before 'callbacks_started) 0)
     (check-equal? (session-count s 'callbacks_started) 1))
   (test-case "bad one-shot arity and false DC reject before scope entry"
     (define s (make-render-session void))
     (check-exn exn:fail? (lambda () (render-session-deliver! s 'canvas 'dc (lambda (c d) (void)))))
     (check-exn exn:fail? (lambda () (render-session-deliver! s 'canvas #f)))
     (check-equal? (session-count s 'callbacks_started) 0))))
(define render-canvas-pure-test-count 33)
(module+ main
  (require rackunit/text-ui)
  (define failures (run-tests render-canvas-pure-tests))
  (printf "render-canvas-pure: ~a cases, ~a failures; no GUI or native rendering.\n"
          render-canvas-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
