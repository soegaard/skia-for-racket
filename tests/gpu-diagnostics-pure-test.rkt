#lang racket/base
(require rackunit rackunit/text-ui ffi/unsafe racket/list
         "../gpu-diagnostics.rkt" (submod "../gpu-diagnostics.rkt" testing)
         "../private/gpu-diagnostic-util.rkt" "../private/graphics-data.rkt"
         "../private/gpu-gl-interface.rkt" (submod "../private/gpu-gl-interface.rkt" testing)
         "../private/gpu-domain.rkt" "../private/gpu-context.rkt" "../private/gpu-provider.rkt")
(provide gpu-diagnostics-pure-tests gpu-diagnostics-pure-test-count)
(define (ptr n) (cast n _uintptr _pointer))
(define (provider [name 'diagnostic-test] [resolver (lambda (_) (ptr 99))])
  (make-gpu-provider #:name name #:backend 'opengl #:key (gensym)
    #:current? (lambda () #t) #:call-as-current (lambda (thunk) (thunk))
    #:get-proc-address resolver))
(define (interface-double thunk #:native? [native? #t] #:version [version "4.5 Mesa"]
                           #:assembled? [assembled? #t] #:callback? [callback? #f])
  (define log (box '()))
  (parameterize ([current-interface-dispatch
                 (lambda (op . args)
                   (set-box! log (append (unbox log) (list op)))
                   (case op
                     [(version) version]
                     [(native) (and native? (ptr 400))]
                     [(auto desktop gles webgl)
                      (when callback? ((cadr args) #f "glFailure"))
                      (and assembled? (ptr 401))]
                     [(unref) (void)]
                     [(extension) (string=? (cadr args) "GL_REAL_extension")]
                     [else (error 'double "unexpected call")]))])
    (thunk log)))
(define (with-context backend thunk)
  (define on? (box #f))
  (define p (make-gpu-provider #:name 'diagnostic-domain #:backend backend #:key (gensym)
              #:current? (lambda () (unbox on?))
              #:call-as-current (lambda (f)
                (dynamic-wind (lambda () (set-box! on? #t)) f (lambda () (set-box! on? #f))))))
  (define d (make-gpu-domain p (gpu-driver (lambda () (ptr 900)) void void void (lambda (_) (hasheq)))))
  (define c (wrap-gpu-domain d))
  (dynamic-wind void (lambda () (thunk c d on?))
    (lambda () (unless (eq? (domain-state d) 'closed) (domain-close! d)))))
(define (collector-report [scope 'gpu-context-skia-resources])
  (define c (make-memory-collector 10 1024 #f #f))
  (collector-add! c 'numeric #"skia/gpu_resources/resource_1" #"size" #"bytes" 1024)
  (collector-finish c #:scope scope))
(define gpu-diagnostics-pure-test-count 38)
(define gpu-diagnostics-pure-tests
  (test-suite "GPU diagnostics: native-free contracts and ownership doubles"
    (test-case "known interface modes"
      (check-true (immutable? gl-interface-modes))
      (for ([m (in-vector gl-interface-modes)]) (check-eq? (check-gl-interface-mode 'test m) m)))
    (test-case "invalid mode is not a truthy default"
      (for ([v (in-list (list #f #t 0 "auto" 'native 'vulkan))])
        (check-exn exn:fail:contract? (lambda () (check-gl-interface-mode 'test v)))))
    (test-case "non-GL default remains valid"
      (for ([b '(metal direct3d)]) (check-not-exn (lambda () (check-gl-interface-backend 'test b 'default)))))
    (test-case "non-GL explicit interface is rejected"
      (for ([b '(metal direct3d)] [m '(auto desktop)])
        (check-exn exn:fail:contract? (lambda () (check-gl-interface-backend 'test b m)))))
    (test-case "owned EGL is not a GLES host factory"
      (for ([m '(default auto desktop)]) (check-eq? (check-owned-egl-interface-mode 'test m) m))
      (for ([m '(gles webgl)]) (check-exn exn:fail:contract? (lambda () (check-owned-egl-interface-mode 'test m)))))
    (test-case "version standard follows pinned native categories"
      (check-eq? (gl-version-standard "4.6 (Core Profile) Mesa") 'desktop)
      (check-eq? (gl-version-standard "OpenGL ES 3.2 Vendor") 'gles)
      (check-eq? (gl-version-standard "OpenGL ES 3.0 (WebGL 2.0 Chromium)") 'webgl)
      (for ([v '(#f "" "WebGL 2.0" "OpenGL ES-CM 1.1" "unknown")]) (check-false (gl-version-standard v))))
    (test-case "ASCII extension identifiers"
      (for ([v '("GL_ARB_framebuffer_object" "EXT_color_buffer_float" "A" "GL_123")])
        (check-equal? (checked-gl-extension 'test v) v)))
    (test-case "extension injection and invalid names"
      (for ([v (in-list (list #f #t 'GL_X 1 "" "a b" "a\0b" "a\nb" "λ" "1abc" "GL-X"))])
        (check-exn exn:fail:contract? (lambda () (checked-gl-extension 'test v)))))
    (test-case "extension length is bounded"
      (check-equal? (string-length (checked-gl-extension 'test (make-string 255 #\a))) 255)
      (check-exn exn:fail:contract? (lambda () (checked-gl-extension 'test (make-string 256 #\a)))))
    (test-case "extension names are detached"
      (define input (string-copy "GL_X"))
      (define result (checked-gl-extension 'test input))
      (string-set! input 3 #\Y)
      (check-equal? result "GL_X") (check-true (immutable? result)))
    (test-case "global scope stays unchanged"
      (define r (collector-report 'process-global-skia-caches))
      (check-eq? (memory-statistics-scope r) 'process-global-skia-caches)
      (check-equal? (hash-ref (memory-statistics->jsexpr r) 'scope) "process-global-skia-caches"))
    (test-case "GPU scope uses shared parent accessors"
      (define r (collector-report))
      (check-true (memory-statistics? r))
      (check-eq? (memory-statistics-scope r) 'gpu-context-skia-resources)
      (check-equal? (memory-statistic-value (vector-ref (memory-statistics-entries r) 0)) 1024)
      (check-true (immutable? (memory-statistics-entries r))))
    (test-case "GPU JSON retains separate scope"
      (define r (memory-statistics->jsexpr (collector-report)))
      (check-equal? (hash-ref r 'scope) "gpu-context-skia-resources") (check-false (hash-ref r 'atomic)))
    (test-case "unknown report scope is rejected"
      (check-exn exn:fail:contract?
        (lambda () (collector-finish (make-memory-collector 0 0 #f #f) #:scope 'rss))))
    (test-case "truncation omits whole entries"
      (define c (make-memory-collector 0 0 #f #f))
      (collector-add! c 'numeric #"x" #"y" #"bytes" 1)
      (define r (collector-finish c #:scope 'gpu-context-skia-resources))
      (check-true (memory-statistics-truncated? r)) (check-equal? (memory-statistics-dropped-count r) 1)
      (check-equal? (memory-statistics-entries r) '#()))
    (test-case "memory option validation precedes context work"
      (check-exn exn:fail:contract? (lambda () (gpu-memory-statistics #f #:detailed? 1)))
      (check-exn exn:fail:contract? (lambda () (gpu-memory-statistics #f #:max-entries -1))))
    (test-case "current-domain dispatch preserves options"
      (with-context 'opengl (lambda (c d on?)
        (parameterize ([current-gpu-diagnostics-dispatch
                       (lambda (op dom . args)
                         (check-eq? op 'memory) (check-eq? dom d)
                         (check-equal? args '(#t #t 10 20 100)) (collector-report))])
          (domain-call d (lambda ()
            (check-true (memory-statistics? (gpu-memory-statistics c #:detailed? #t #:dump-wrapped? #t
                                              #:max-entries 10 #:string-limit 20 #:byte-limit 100)))))))))
    (test-case "invalid context rejects without native dispatch"
      (parameterize ([current-gpu-diagnostics-dispatch (lambda _ (error 'double "must not run"))])
        (check-exn exn:fail:contract? (lambda () (gpu-memory-statistics #f)))
        (check-exn exn:fail:contract? (lambda () (gpu-gl-interface-info #f)))))
    (test-case "inactive domain is rejected"
      (with-context 'opengl (lambda (c d on?)
        (check-exn exn:fail? (lambda () (gpu-memory-statistics c)))
        (check-exn exn:fail? (lambda () (gpu-gl-has-extension? c "GL_X"))))))
    (test-case "closed domain is rejected"
      (with-context 'opengl (lambda (c d on?)
        (domain-close! d)
        (check-exn exn:fail? (lambda () (gpu-memory-statistics c)))
        (check-exn exn:fail? (lambda () (gpu-gl-interface-info c))))))
    (test-case "shutdown request prevents diagnostic access"
      (with-context 'opengl (lambda (c d on?)
        (domain-call d (lambda ()
          (domain-request-shutdown! d)
          (check-exn exn:fail? (lambda () (gpu-memory-statistics c))))))))
    (test-case "foreign Racket owner is rejected"
      (with-context 'opengl (lambda (c d on?)
        (define ch (make-channel))
        (thread (lambda ()
          (with-handlers ([exn:fail? (lambda (_) (channel-put ch #t))])
            (gpu-memory-statistics c) (channel-put ch #f))))
        (check-eq? (sync/timeout 5 ch) #t))))
    (test-case "GL query on another backend is rejected"
      (with-context 'metal (lambda (c d on?)
        (domain-call d (lambda ()
          (check-exn exn:fail:contract? (lambda () (gpu-gl-interface-info c)))
          (check-exn exn:fail:contract? (lambda () (gpu-gl-has-extension? c "GL_X"))))))))
    (test-case "host-current mismatch is rejected"
      (with-context 'opengl (lambda (c d on?)
        (domain-call d (lambda ()
          (dynamic-wind (lambda () (set-box! on? #f))
            (lambda () (check-exn exn:fail? (lambda () (gpu-gl-interface-info c))))
            (lambda () (set-box! on? #t))))))))
    (test-case "default native factory remains first"
      (interface-double (lambda (log)
        (define-values (p factory) (create-gl-interface/native (provider) 'default))
        (check-equal? factory "native") (check-equal? (unbox log) '(native)))))
    (test-case "default fallback is desktop"
      (interface-double (lambda (log)
        (define-values (p factory) (create-gl-interface/native (provider) 'default))
        (check-equal? factory "assembled-desktop-gl") (check-equal? (unbox log) '(native version desktop))) #:native? #f))
    (test-case "EGL never calls native GLX factory"
      (interface-double (lambda (log)
        (create-gl-interface/native (provider 'egl-owned) 'default)
        (check-equal? (unbox log) '(version desktop)))))
    (test-case "all explicit factory routes are separate"
      (for ([mode '(auto desktop gles webgl)]
            [version '("4.5 Mesa" "4.5 Mesa" "OpenGL ES 3.2" "OpenGL ES 3.0 (WebGL 2.0 X)")])
        (interface-double (lambda (log)
          (create-gl-interface/native (provider) mode)
          (check-equal? (unbox log) (list 'version mode))) #:version version)))
    (test-case "explicit assembly requires resolver"
      (interface-double (lambda (log)
        (check-exn exn:fail:gpu:unavailable? (lambda () (create-gl-interface/native (provider 'test #f) 'auto)))
        (check-equal? (unbox log) '()))))
    (test-case "factory mismatch fails before native assembly"
      (interface-double (lambda (log)
        (for ([mode '(gles webgl)])
          (check-exn exn:fail:gpu:unavailable? (lambda () (create-gl-interface/native (provider) mode))))
        (check-equal? (unbox log) '(version version)))))
    (test-case "unknown host standard is rejected"
      (interface-double (lambda (log)
        (check-exn exn:fail:gpu:unavailable? (lambda () (create-gl-interface/native (provider) 'auto)))) #:version "Unknown"))
    (test-case "resolver raised false is deferred and allocated interface freed"
      (interface-double (lambda (log)
        (check-exn (lambda (e) (eq? e #f))
          (lambda () (create-gl-interface/native (provider 'test (lambda (_) (raise #f))) 'desktop)))
        (check-equal? (unbox log) '(version desktop unref))) #:callback? #t))
    (test-case "invalid resolver result is caught at native boundary"
      (interface-double (lambda (log)
        (check-exn exn:fail? (lambda () (create-gl-interface/native (provider 'test (lambda (_) 42)) 'auto)))
        (check-equal? (unbox log) '(version auto unref))) #:callback? #t))
    (test-case "explicit failure never falls back"
      (interface-double (lambda (log)
        (check-exn exn:fail:gpu:unavailable? (lambda () (create-gl-interface/native (provider) 'auto)))
        (check-equal? (unbox log) '(version auto))) #:assembled? #f))
    (test-case "retained interface queried and unrefed exactly once"
      (interface-double (lambda (log)
        (register-gl-interface! (ptr 1001) (ptr 400) 'auto "assembled-auto")
        (dynamic-wind void
          (lambda ()
            (check-true (gl-context-has-extension?/native (ptr 1001) "GL_REAL_extension"))
            (check-false (gl-context-has-extension?/native (ptr 1001) "GL_FAKE_extension")))
          (lambda () (release-gl-interface! (ptr 1001))))
        (release-gl-interface! (ptr 1001))
        (check-equal? (unbox log) '(extension extension unref)))))
    (test-case "duplicate context registration cannot replace live interface"
      (interface-double (lambda (log)
        (register-gl-interface! (ptr 1002) (ptr 400) 'desktop "assembled-desktop-gl")
        (dynamic-wind void
          (lambda () (check-exn exn:fail? (lambda () (register-gl-interface! (ptr 1002) (ptr 401) 'auto "assembled-auto"))))
          (lambda () (release-gl-interface! (ptr 1002)))))))
    (test-case "interface information is detached"
      (interface-double (lambda (log)
        (define name (string-copy "assembled-auto"))
        (register-gl-interface! (ptr 1003) (ptr 400) 'auto name)
        (define report (gl-context-interface-info/native (ptr 1003)))
        (release-gl-interface! (ptr 1003)) (string-set! name 0 #\X)
        (check-true (immutable? report))
        (check-equal? (hash-ref report 'factory) "assembled-auto")
        (check-true (immutable? (hash-ref report 'factory)))
        (check-exn exn:fail? (lambda () (gl-context-interface-info/native (ptr 1003)))))))
    (test-case "lookup never accepts raw false or unregistered pointers"
      (check-exn exn:fail? (lambda () (gl-context-interface-info/native #f)))
      (check-exn exn:fail? (lambda () (gl-context-interface-info/native (ptr 1999)))))
  ))
(module+ main
  (define failures (run-tests gpu-diagnostics-pure-tests))
  (printf "gpu-diagnostics-pure: ~a cases, ~a failures\n" gpu-diagnostics-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
