#lang racket/base

;;;
;;; Reference GPU Interop Pure Test
;;;

;; Checks token consumption and Direct3D, Metal, OpenGL, and EGL handoff policies without native
;; contexts.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Native-free policy and safe-token tests. They do not establish GPU availability
;; or validate any native pointer supplied to an unsafe interop constructor.
(require rackunit racket/list
         skia/gpu-interop
         (submod "../private/gpu-external.rkt" backend-internals)
         "../private/gpu-d3d12-interop-policy.rkt"
         "../private/gpu-metal-interop-policy.rkt"
         "../private/gpu-egl-util.rkt"
         "../private/gpu-diagnostic-util.rkt"
         "../private/gpu-gl-interop-util.rkt")


;;;
;;; Diagnostic Operations
;;;

; make-fake-token : [#:check procedure? #:operate procedure? #:retire procedure?] ->
; external-texture?
;   Creates a synthetic Metal texture token with injectable lifecycle callbacks for native-free
;   interop checks.
(define (make-fake-token #:check [check void] #:operate [operate (lambda (mode proc) mode)]
                         #:retire [retire void])
  (make-external-texture 'metal 'context 7
    (hasheq 'width 3 'height 2)
    check operate retire (lambda () (hasheq 'observed #t))))


; valid-metal-description : hash?
;   Describes a retained, two-dimensional single-sample Metal texture accepted by the pure
;   validator.
(define valid-metal-description
  (hasheq 'width 4 'height 3 'depth 1 'levels 1 'array_length 1 'samples 1
          'format 70 'texture_type 2 'usage 1 'storage_mode 2 'hazard_tracking_mode 2
          'same_device #t 'framebuffer_only #f 'has_parent #f 'has_buffer #f
          'has_heap #f 'has_iosurface #f 'shareable #f 'has_remote_storage #f
          'producer_retained_references #t 'swizzle '(2 3 4 5)))

(module+ test
  (test-case "external token reports detached state without raw handles"
    (define t (make-fake-token))
    (define info (gpu-external-texture-info t))
    (check-true (immutable? info))
    (check-equal? (hash-ref info 'backend) "metal")
    (check-equal? (hash-ref info 'context_generation) 7)
    (check-equal? (hash-ref info 'handoff_state) "ready")
    (check-false (hash-ref info 'raw_handles_exposed)))

  (test-case "copy consumes a token and explicit close retires once"
    (define retired 0)
    (define t (make-fake-token #:operate (lambda (mode proc) (list 'result mode))
                               #:retire (lambda () (set! retired (add1 retired)))))
    (check-equal? (gpu-import-image 'context t) '(result copy))
    (check-exn exn:fail? (lambda () (gpu-import-image 'context t)))
    (gpu-external-texture-close! t)
    (gpu-external-texture-close! t)
    (check-equal? retired 1))

  (test-case "validation failure before activation keeps the token ready"
    (define reject-surface? #t)
    (define t
      (make-fake-token
       #:check (lambda (mode)
                 (when (and reject-surface? (eq? mode 'surface)) (error 'check "reject")))
       #:operate (lambda (mode proc) mode)))
    (check-exn exn:fail? (lambda () (call-with-gpu-external-surface 'context t values)))
    (check-equal? (hash-ref (gpu-external-texture-info t) 'handoff_state) "ready")
    (set! reject-surface? #f)
    (check-equal? (gpu-import-image 'context t) 'copy))

  (test-case "surface callback values are preserved and the token is consumed"
    (define t
      (make-fake-token
       #:operate (lambda (mode proc)
                   (check-equal? mode 'surface)
                   (proc 'borrowed-canvas))))
    (check-equal?
     (call-with-values
      (lambda () (call-with-gpu-external-surface 'context t
                   (lambda (canvas) (values canvas 2))))
      list)
     '(borrowed-canvas 2))
    (check-equal? (hash-ref (gpu-external-texture-info t) 'handoff_state) "consumed"))

  (test-case "active handoffs cannot close or nest"
    (define outer #f)
    (define inner (make-fake-token))
    (set! outer
      (make-fake-token
       #:operate
       (lambda (mode proc)
         (check-exn exn:fail? (lambda () (gpu-external-texture-close! outer)))
         (check-exn exn:fail? (lambda () (gpu-import-image 'context inner)))
         'done)))
    (check-equal? (gpu-import-image 'context outer) 'done))

  (test-case "tokens are tied to their exact context identity"
    (define t (make-fake-token))
    (check-exn exn:fail? (lambda () (gpu-import-image 'different t)))
    (check-equal? (hash-ref (gpu-external-texture-info t) 'handoff_state) "ready"))

  (test-case "D3D12 state names are explicit and bounded"
    (for ([state '(common render-target pixel-shader-resource shader-read copy-dest copy-source)])
      (check-true (exact-nonnegative-integer? (interop-state state))))
    (check-exn exn:fail? (lambda () (interop-state 'present)))
    (check-equal? (interop-timeout! 1) 1)
    (check-equal? (interop-timeout! 60000) 60000)
    (check-exn exn:fail? (lambda () (interop-timeout! 0))))

  (test-case "D3D12 fence values reserve zero and the all-ones sentinel"
    (check-equal? (interop-fence-value! 1) 1)
    (check-equal? (interop-fence-value! #xfffffffffffffffe) #xfffffffffffffffe)
    (check-exn exn:fail? (lambda () (interop-fence-value! 0)))
    (check-exn exn:fail? (lambda () (interop-fence-value! #xffffffffffffffff))))

  (test-case "Metal descriptor policy distinguishes copy from rendering"
    (check-eq? (metal-check-texture! valid-metal-description) valid-metal-description)
    (check-exn exn:fail? (lambda () (metal-check-texture! valid-metal-description #t)))
    (define renderable (hash-set valid-metal-description 'usage 5))
    (check-eq? (metal-check-texture! renderable #t) renderable))

  (test-case "Metal timeout bounds are detached policy checks"
    (check-equal? (metal-timeout! 1) 1)
    (check-equal? (metal-timeout! 60000) 60000)
    (check-exn exn:fail? (lambda () (metal-timeout! 60001))))

  (test-case "GL object names extents and origins use explicit ranges"
    (check-equal? (check-gl-name 'test 1) 1)
    (check-equal? (check-gl-name 'test #xffffffff) #xffffffff)
    (check-exn exn:fail? (lambda () (check-gl-name 'test 0)))
    (check-not-exn (lambda () (check-gl-extent 'test 1 #x7fffffff)))
    (check-equal? (gl-origin-value 'test 'top-left) 0)
    (check-equal? (gl-origin-value 'test 'bottom-left) 1))

  (test-case "EGL options keep platform device and binding surface separate"
    (check-not-exn (lambda () (check-egl-options 'test 'surfaceless 0 'surfaceless)))
    (check-not-exn (lambda () (check-egl-options 'test 'device 2 'pbuffer)))
    (check-exn exn:fail? (lambda () (check-egl-options 'test 'surfaceless 1 'pbuffer))))

  (test-case "GL host standard classification is explicit"
    (check-equal? (gl-version-standard "4.6 Mesa") 'desktop)
    (check-equal? (gl-version-standard "OpenGL ES 3.2 Vendor") 'gles)
    (check-equal? (gl-version-standard "OpenGL ES 3.0 (WebGL 2.0 Vendor)") 'webgl)
    (check-false (gl-version-standard "unknown"))))
