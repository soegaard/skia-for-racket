#lang racket/base
;; Required real selected-backend execution. No CPU or synthetic fallback.
(require racket/cmdline racket/file racket/path racket/list json rackunit rackunit/text-ui
         ffi/unsafe
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt" "../private/gpu-io-trace.rkt"
         (only-in "../private/gpu-gl-interface.rkt" create-gl-interface/native)
         (only-in "../private/gpu-native.rkt" gr_glinterface_unref)
         (only-in "../private/live-port-runtime.rkt" in-port-service?))
(define WIDTH 32)
(define HEIGHT 24)
(define GPU-CASES 20)
(define (paint-pattern canvas)
  (canvas-clear! canvas (rgb 17 34 51))
  (with-skia ([red (make-paint #:color (rgb 229 41 53) #:antialias? #f)]
              [green (make-paint #:color (rgb 11 179 67) #:antialias? #f)])
    (draw-rect canvas 2 3 11 7 red)
    (draw-rect canvas 15 10 13 10 green)))
(define (native-string pointer [cap 65536])
  (unless pointer (error 'gpu-diagnostics-test "null native GL string"))
  (define n (let loop ([i 0])
              (cond [(zero? (ptr-ref pointer _ubyte i)) i]
                    [(= i cap) (error 'gpu-diagnostics-test "GL string exceeds test bound")]
                    [else (loop (add1 i))])))
  (define result (make-bytes n))
  (unless (zero? n) (memcpy result pointer n))
  (bytes->string/utf-8 result #f))
(define (host-gl-resolver)
  ;; Look up host GL symbols without borrowing an already-owned EGL context.
  ;; This is not a GPU provider and never creates a second Ganesh wrapper.
  (define egl (ffi-lib "libEGL.so.1"))
  (define get-proc-address
    (get-ffi-obj "eglGetProcAddress" egl (_fun _string/utf-8 -> _pointer)))
  (define gl
    (or (ffi-lib "libOpenGL.so.0" #:fail (lambda () #f))
        (ffi-lib "libGL.so.1" #:fail (lambda () #f))))
  (lambda (name)
    (or (get-proc-address name)
        (get-ffi-obj name egl _fpointer (lambda () #f))
        (and gl (get-ffi-obj name gl _fpointer (lambda () #f))))))
(define (first-host-extension)
  ;; Independently query the active native driver rather than the Skia interface.
  ;; Required Linux EGL uses a desktop context with indexed GL extensions.
  (define resolve (host-gl-resolver))
  (define get-int-p (resolve "glGetIntegerv"))
  (define get-string-p (resolve "glGetStringi"))
  (unless (and get-int-p get-string-p) (error 'gpu-diagnostics-test "indexed GL extensions unavailable"))
  (define get-int (cast get-int-p _pointer (_fun _uint _pointer -> _void)))
  (define get-string (cast get-string-p _pointer (_fun _uint _uint -> _pointer)))
  (define count (malloc _int 'atomic))
  (get-int #x821d count) ; GL_NUM_EXTENSIONS
  (unless (positive? (ptr-ref count _int)) (error 'gpu-diagnostics-test "host reports no GL extensions"))
  (define result (native-string (get-string #x1f03 0) 255))
  (void/reference-sink resolve get-int get-string)
  result)
(module+ main
  (define backend 'auto) (define adapter 'hardware) (define report-path #f) (define token #f)
  (command-line #:once-each
    [("--backend") b "egl, metal or direct3d" (set! backend (string->symbol b))]
    [("--adapter") a "hardware or warp" (set! adapter (string->symbol a))]
    [("--report") p "New evidence receipt" (set! report-path (path->complete-path p))]
    [("--token") t "Invocation identity" (set! token t)] #:args () (void))
  (unless (and report-path token) (error 'gpu-diagnostics "--report and --token required"))
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))
  (unless (memq backend '(egl metal direct3d)) (error 'gpu-diagnostics "invalid backend"))
  (unless (memq adapter '(hardware warp)) (error 'gpu-diagnostics "invalid adapter"))
  (define directory (path-only report-path)) (make-directory* directory)
  (define labels '()) (define failures 0) (define cleanup-errors '())
  (define contexts '()) (define resources '()) (define captures '()) (define traces '())
  (define reports (make-hasheq)) (define interface-rows '()) (define extension #f)
  (define lifecycle (make-hasheq))
  (define (fresh [mode 'default])
    (define c (case backend
      [(egl) (make-egl-gpu-context #:gl-interface mode)]
      [(metal) (make-gpu-context #:backend 'metal)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]))
    (set! contexts (cons c contexts)) c)
  (define (retain v) (set! resources (cons v resources)) v)
  (define (test! label thunk)
    (set! labels (append labels (list label)))
    (set! failures (+ failures (run-tests (test-suite label (test-case label (thunk)))))))
  (define (trace! name thunk)
    (define ledger (box '()))
    (define result (parameterize ([current-gpu-io-ledger ledger]) (thunk)))
    (define events (reverse (unbox ledger)))
    (set! traces (append traces (list (hasheq 'name name 'events events))))
    (check-equal? events '() "diagnostics must not add GPU I/O or cache operations")
    result)
  (define (save! name bytes)
    (call-with-output-file (build-path directory name) (lambda (out) (write-bytes bytes out))
      #:exists 'error #:mode 'binary))
  (define (pixels! name s)
    (define bytes (gpu-surface->rgba-bytes s))
    (save! (string-append name ".rgba") bytes)
    (set! captures (append captures (list (hasheq 'name name 'file (string-append name ".rgba")
                                                'width WIDTH 'height HEIGHT)))))
  (define c #f) (define s #f) (define im #f) (define kept #f) (define saved-data #f)
  (define (active thunk) (call-with-gpu-context c thunk))
  (dynamic-wind void
    (lambda ()
      (test! "create a real context and allocated surface"
        (lambda ()
          (set! c (fresh))
          (active (lambda ()
            (set! s (retain (make-gpu-surface c WIDTH HEIGHT)))
            (paint-pattern (surface-canvas s))
            (set! im (retain (gpu-surface-snapshot s)))
            (gpu-flush! c) (gpu-submit! c #:wait? #t)
            (pixels! "before" s)
            (hash-set! reports 'cache_before (gpu-cache-info c))))))
      (test! "light GPU report contains native resource sizes"
        (lambda () (active (lambda ()
          (set! kept (trace! "light" (lambda () (gpu-memory-statistics c))))
          (check-eq? (memory-statistics-scope kept) 'gpu-context-skia-resources)
          (check-false (memory-statistics-truncated? kept))
          (check-not-false
            (for/or ([e (in-vector (memory-statistics-entries kept))])
              (and (eq? (memory-statistic-kind e) 'numeric)
                   (equal? (memory-statistic-value-name e) "size")
                   (equal? (memory-statistic-units e) "bytes")
                   (>= (memory-statistic-value e) (* WIDTH HEIGHT 4)))))
          (hash-set! reports 'light (memory-statistics->jsexpr kept))))))
      (test! "detailed report uses the same bounded collector"
        (lambda () (active (lambda ()
          (define r (trace! "detailed" (lambda () (gpu-memory-statistics c #:detailed? #t))))
          (check-true (memory-statistics-detailed? r)) (check-false (memory-statistics-truncated? r))
          (hash-set! reports 'detailed (memory-statistics->jsexpr r))))))
      (test! "dump-wrapped option remains explicit"
        (lambda () (active (lambda ()
          (define r (trace! "wrapped" (lambda () (gpu-memory-statistics c #:dump-wrapped? #t))))
          (check-true (memory-statistics-dump-wrapped? r))
          (hash-set! reports 'wrapped (memory-statistics->jsexpr r))))))
      (test! "entry limit reports dropped records"
        (lambda () (active (lambda ()
          (define r (trace! "zero-entries" (lambda () (gpu-memory-statistics c #:max-entries 0))))
          (check-true (memory-statistics-truncated? r))
          (check-true (positive? (memory-statistics-dropped-count r)))
          (check-equal? (memory-statistics-entries r) '#())
          (hash-set! reports 'zero_entries (memory-statistics->jsexpr r))))))
      (test! "string budget cannot silently shorten a resource name"
        (lambda () (active (lambda ()
          (define r (trace! "zero-strings" (lambda () (gpu-memory-statistics c #:string-limit 0))))
          (check-equal? (memory-statistics-entries r) '#())
          (check-true (memory-statistics-truncated? r))
          (hash-set! reports 'zero_strings (memory-statistics->jsexpr r))))))
      (test! "total byte budget is separate from entry count"
        (lambda () (active (lambda ()
          (define r (trace! "zero-bytes" (lambda () (gpu-memory-statistics c #:byte-limit 0))))
          (check-equal? (memory-statistics-entries r) '#())
          (check-true (memory-statistics-truncated? r))
          (hash-set! reports 'zero_bytes (memory-statistics->jsexpr r))))))
      (test! "global and GPU reports coexist without provider replacement"
        (lambda () (active (lambda ()
          (define global (skia-memory-statistics))
          (check-eq? (memory-statistics-scope global) 'process-global-skia-caches)
          (hash-set! reports 'global (memory-statistics->jsexpr global))
          (define again (trace! "after-global" (lambda () (gpu-memory-statistics c))))
          (check-eq? (memory-statistics-scope again) 'gpu-context-skia-resources)))))
      (test! "diagnostic queries leave limits and pixels intact"
        (lambda () (active (lambda ()
          (hash-set! reports 'cache_after (gpu-cache-info c))
          (check-equal? (hash-ref (hash-ref reports 'cache_before) 'limit_bytes)
                        (hash-ref (hash-ref reports 'cache_after) 'limit_bytes))
          (pixels! "after" s)))))
      (test! "snapshot stays immutable across subsequent allocation and GC"
        (lambda ()
          (set! saved-data (memory-statistics->jsexpr kept))
          (active (lambda ()
            (with-skia ([extra (make-gpu-surface c 64 48)])
              (gpu-flush! c) (gpu-submit! c #:wait? #t)
              (define r (trace! "extra-resource" (lambda () (gpu-memory-statistics c))))
              (hash-set! reports 'extra (memory-statistics->jsexpr r)))))
          (collect-garbage)
          (check-equal? (memory-statistics->jsexpr kept) saved-data)))
      (test! "inactive GPU diagnostic access is rejected"
        (lambda () (check-exn exn:fail? (lambda () (gpu-memory-statistics c)))))
      (test! "foreign Racket owner is rejected"
        (lambda ()
          (define ch (make-channel))
          (thread (lambda ()
            (with-handlers ([exn:fail? (lambda (_) (channel-put ch #t))])
              (gpu-memory-statistics c) (channel-put ch #f))))
          (check-eq? (sync/timeout 5 ch) #t)))
      (test! "live port service cannot enter the native diagnostic collector"
        (lambda () (active (lambda ()
          (parameterize ([in-port-service? #t])
            (check-exn #rx"live port callback" (lambda () (gpu-memory-statistics c))))))))
      (test! "invalid limits and extension names fail before native entry"
        (lambda () (active (lambda ()
          (check-exn exn:fail:contract? (lambda () (gpu-memory-statistics c #:detailed? 1)))
          (check-exn exn:fail:contract? (lambda () (gpu-gl-has-extension? c "GL_bad\0name")))))))
      (test! "selected backend interface contract is explicit"
        (lambda ()
          (if (eq? backend 'egl)
              (active (lambda ()
                ;; Capturing the already-owned context as another provider is forbidden.
                (check-exn
                  (lambda (e) (and (exn:fail:gpu:unavailable? e)
                                   (eq? (exn:fail:gpu:unavailable-step e) 'egl-current-ownership)))
                  (lambda () (make-current-egl-gpu-provider)))
                (set! extension (first-host-extension))
                (define info (trace! "gl-info" (lambda () (gpu-gl-interface-info c))))
                (check-equal? (hash-ref info 'factory) "assembled-desktop-gl")
                (check-true (trace! "gl-present" (lambda () (gpu-gl-has-extension? c extension))))
                (check-false (trace! "gl-absent" (lambda () (gpu-gl-has-extension? c "GL_SKIA_RACKET_NONEXISTENT_077C"))))
                (set! interface-rows (list (hasheq 'mode "default" 'info info 'extension extension
                                                  'host_extension_present #t 'fabricated_extension_present #f)))))
              (active (lambda ()
                (check-exn exn:fail:contract? (lambda () (gpu-gl-interface-info c)))
                (check-exn exn:fail:contract? (lambda () (gpu-gl-has-extension? c "GL_X"))))))))
      (test! "explicit assembly routes render or reject non-GL selection"
        (lambda ()
          (if (eq? backend 'egl)
              (for ([mode '(auto desktop)])
                (define other (fresh mode))
                (call-with-gpu-context other (lambda ()
                  (with-skia ([target (make-gpu-surface other WIDTH HEIGHT)])
                    (paint-pattern (surface-canvas target))
                    (gpu-flush! other) (gpu-submit! other #:wait? #t)
                    (define info (trace! (symbol->string mode) (lambda () (gpu-gl-interface-info other))))
                    (check-true (gpu-gl-has-extension? other extension))
                    (pixels! (symbol->string mode) target)
                    (set! interface-rows (append interface-rows (list
                      (hasheq 'mode (symbol->string mode) 'info info 'extension extension
                              'host_extension_present #t 'fabricated_extension_present
                              (gpu-gl-has-extension? other "GL_SKIA_RACKET_NONEXISTENT_077C"))))))))
                (gpu-context-close! other))
              (check-exn exn:fail:contract? (lambda () (make-gpu-context #:backend backend #:gl-interface 'auto))))))
      (test! "incompatible GLES WebGL factories fail without a standard fallback"
        (lambda ()
          (when (eq? backend 'egl)
            (active (lambda ()
              ;; Resolver-only probe. It cannot activate or wrap the owned EGL context.
              (define provider
                (make-gpu-provider
                  #:name 'gl-diagnostics-probe #:backend 'opengl
                  #:key (gensym 'gl-diagnostics-probe)
                  #:call-as-current
                  (lambda (_) (error 'gl-diagnostics-probe "not a GPU activation provider"))
                  #:current? (lambda () #f)
                  #:get-proc-address (host-gl-resolver)))
              (for ([mode '(gles webgl)])
                (check-exn
                  (lambda (e) (and (exn:fail:gpu:unavailable? e)
                                   (eq? (exn:fail:gpu:unavailable-step e) 'gl-interface-standard)))
                  (lambda () (create-gl-interface/native provider mode)))))))
          (for ([mode '(gles webgl)])
            (check-exn exn:fail:contract? (lambda () (make-egl-gpu-context #:gl-interface mode))))))
      (test! "healthy abandonment invalidates live diagnostic access"
        (lambda ()
          (gpu-context-release-and-abandon! c)
          (check-eq? (gpu-context-state c) 'abandoned)
          (check-exn exn:fail? (lambda () (gpu-memory-statistics c)))
          (check-exn exn:fail? (lambda () (gpu-gl-interface-info c)))
          (hash-set! lifecycle 'after_release (gpu-context-info c))))
      (test! "children retire before final close and saved diagnostics survive"
        (lambda ()
          (skia-close! im) (skia-close! s) (gpu-context-close! c)
          (check-eq? (gpu-context-state c) 'closed)
          (check-equal? (memory-statistics->jsexpr kept) saved-data)
          (hash-set! lifecycle 'after_close (gpu-context-info c))))
      (test! "fresh context after cleanup still diagnoses and renders"
        (lambda ()
          (define other (fresh))
          (call-with-gpu-context other (lambda ()
            (with-skia ([target (make-gpu-surface other WIDTH HEIGHT)])
              (paint-pattern (surface-canvas target))
              (gpu-flush! other) (gpu-submit! other #:wait? #t)
              (check-true (memory-statistics? (gpu-memory-statistics other)))
              (pixels! "after-close" target))))
          (gpu-context-close! other)))
    )
    (lambda ()
      (for ([r (in-list resources)])
        (with-handlers ([exn:fail? (lambda (e) (set! cleanup-errors (cons (exn-message e) cleanup-errors)))])
          (skia-close! r)))
      (for ([context (in-list contexts)])
        (with-handlers ([exn:fail? (lambda (e) (set! cleanup-errors (cons (exn-message e) cleanup-errors)))])
          (gpu-context-close! context)))))
  (define passed? (and (= (length labels) GPU-CASES) (zero? failures) (null? cleanup-errors)))
  (call-with-output-file report-path
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.77c" 'status (if passed? "passed" "failed")
                         'run_token token 'native_version (skia-native-version)
                         'backend (symbol->string backend) 'adapter (symbol->string adapter)
                         'gpu_executed #t 'driver_memory_measured #f 'process_memory_measured #f
                         'gles_rendering_executed #f 'webgl_rendering_executed #f
                         'cases (length labels) 'failures failures 'labels labels
                         'reports reports 'diagnostic_traces traces 'captures captures
                         'interfaces interface-rows 'lifecycle lifecycle
                         'cleanup_errors cleanup-errors) out)) #:exists 'error)
  (printf "gpu-diagnostics-gpu: ~a cases, ~a failures\n" (length labels) failures)
  (exit (if passed? 0 1)))
