#lang racket/base
(require ffi/unsafe rackunit "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt")
(provide make-gpu-egl-native-tests gpu-egl-native-test-count)
(define gpu-egl-native-test-count 10)
(define (make-gpu-egl-native-tests factory)
  ;; This function is called only by the explicit Linux/headless doctor.
  (define egl (ffi-lib "libEGL.so.1"))
  (define (bind name type) (get-ffi-obj name egl type))
  (define api (bind "eglQueryAPI" (_fun -> _uint32)))
  (define bind-api (bind "eglBindAPI" (_fun _uint32 -> _uint32)))
  (define current (bind "eglGetCurrentContext" (_fun -> _pointer)))
  (define display (bind "eglGetCurrentDisplay" (_fun -> _pointer)))
  (define (addr p) (and p (cast p _pointer _uintptr)))
  (define (with-context proc)
    (define c (factory))
    (dynamic-wind void (lambda () (proc c)) (lambda () (gpu-context-close! c))))
  (test-suite
   "EGL native ownership and true headless contexts"
   (test-case "owned provider is headless desktop OpenGL"
     (with-context (lambda (c)
       (define info (gpu-context-info c))
       (check-eq? (gpu-context-backend c) 'opengl)
       (check-equal? (hash-ref info 'provider) "egl-owned")
       (check-true (hash-ref info 'headless))
       (check-false (hash-ref info 'window_created))
       (check-false (hash-ref info 'requires_glx)))))
   (test-case "owned context uses the assembled EGL procedure table"
     (with-context (lambda (c)
       (check-equal? (hash-ref (gpu-context-info c) 'interface_factory) "assembled-desktop-gl"))))
   (test-case "constructor and teardown preserve bound EGL client API"
     (define previous (api))
     (dynamic-wind
       (lambda () (check-equal? (bind-api #x30A0) 1))
       (lambda () (with-context (lambda (_) (check-equal? (api) #x30A0)))
                  (check-equal? (api) #x30A0))
       (lambda () (bind-api previous))))
   (test-case "activation restores previous current native context"
     (define previous (addr (current)))
     (with-context (lambda (c)
       (call-with-gpu-context c (lambda () (check-not-false (current))))
       (check-equal? (addr (current)) previous))))
   (test-case "one context closing does not terminate a sibling's display"
     (define a (factory)) (define b #f)
     (dynamic-wind void
       (lambda ()
         (set! b (factory))
         (check-equal? (call-with-gpu-context a (lambda () (addr (display))))
                       (call-with-gpu-context b (lambda () (addr (display)))))
         (gpu-context-close! a)
         (check-true (hash-ref (gpu-smoke-test b) 'exact_pixels)))
       (lambda () (when b (gpu-context-close! b)) (gpu-context-close! a))))
   (test-case "independent owned contexts have distinct generations"
     (with-context (lambda (a) (with-context (lambda (b)
       (check-not-equal? (gpu-context-generation a) (gpu-context-generation b)))))))
   (test-case "borrowed current provider cannot duplicate an owned Ganesh context"
     (with-context (lambda (c) (call-with-gpu-context c
       (lambda () (check-exn exn:fail:gpu:unavailable? make-current-egl-gpu-provider))))))
   (test-case "borrowed EGL provider leaves host context and surfaces owned by the host"
     (with-context
      (lambda (owner)
        (define host #f) (define d #f) (define borrowed #f)
        (define choose (bind "eglChooseConfig" (_fun _pointer _pointer _pointer _int _pointer -> _uint32)))
        (define query-context (bind "eglQueryContext" (_fun _pointer _pointer _int _pointer -> _uint32)))
        (define create (bind "eglCreateContext" (_fun _pointer _pointer _pointer _pointer -> _pointer)))
        (define destroy (bind "eglDestroyContext" (_fun _pointer _pointer -> _uint32)))
        (define make-current (bind "eglMakeCurrent" (_fun _pointer _pointer _pointer _pointer -> _uint32)))
        (define current-surface (bind "eglGetCurrentSurface" (_fun _int -> _pointer)))
        (define (ints . xs)
          (define p (malloc _int (length xs) 'atomic))
          (for ([x (in-list xs)] [i (in-naturals)]) (ptr-set! p _int i x)) p)
        (dynamic-wind
          void
          (lambda ()
            (define provider
              (call-with-gpu-context owner
                (lambda ()
                  (set! d (display))
                  (define original (current))
                  (define draw (current-surface #x3059)) (define read (current-surface #x305A))
                  (define config-id (ints 0)) (define count (ints 0))
                  (define config (malloc _pointer 'atomic)) (ptr-set! config _pointer #f)
                  (check-equal? (query-context d original #x3028 config-id) 1)
                  (check-equal? (choose d (ints #x3028 (ptr-ref config-id _int) #x3038) config 1 count) 1)
                  (check-equal? (ptr-ref count _int) 1)
                  (set! host (create d (ptr-ref config _pointer) #f (ints #x3098 3 #x30FB 3 #x30FD 1 #x3038)))
                  (check-not-false host)
                  (dynamic-wind
                    (lambda () (check-equal? (make-current d draw read host) 1))
                    make-current-egl-gpu-provider
                    (lambda () (check-equal? (make-current d draw read original) 1))))))
            (set! borrowed (make-gpu-context provider))
            (check-equal? (hash-ref (gpu-context-info borrowed) 'provider) "egl-current")
            (check-false (hash-ref (gpu-context-info borrowed) 'owns_egl_context))
            (check-true (hash-ref (gpu-smoke-test borrowed) 'exact_pixels))
            (gpu-context-close! borrowed)
            ;; The host name still designates an EGL context after Ganesh closes.
            (check-equal? (query-context d host #x3028 (ints 0)) 1)
            (check-true (hash-ref (gpu-smoke-test owner) 'exact_pixels)))
          (lambda ()
            (when borrowed (gpu-context-close! borrowed))
            (when host (check-equal? (destroy d host) 1)))))))
   (test-case "EGL teardown retains the live-child guard"
     (with-context (lambda (c)
       (define s (call-with-gpu-context c (lambda () (make-gpu-surface c 8 8))))
       (dynamic-wind void
         (lambda () (check-exn #rx"live GPU children" (lambda () (gpu-context-close! c))))
         (lambda () (skia-close! s))))))
   (test-case "callback failure restores EGL and allows later rendering"
     (with-context (lambda (c)
       (define previous (addr (current)))
       (check-exn #rx"intentional" (lambda () (call-with-gpu-context c (lambda () (error 'test "intentional")))))
       (check-equal? (addr (current)) previous)
       (check-true (hash-ref (gpu-smoke-test c) 'exact_pixels)))))))
