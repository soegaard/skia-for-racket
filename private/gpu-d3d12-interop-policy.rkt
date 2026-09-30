#lang racket/base
;; Pure validation of the intentionally small initial Direct3D handoff subset.
(provide interop-state interop-timeout! interop-fence-value!
         check-interop-resource! call-with-interop-cleanup)
(define states
  (hasheq 'common 0 'render-target 4 'pixel-shader-resource #x80
          'shader-read #xc0 'copy-dest #x400 'copy-source #x800))
(define (interop-state value)
  (hash-ref states value
    (lambda () (raise-argument-error 'd3d12-interop
      "'common, 'render-target, 'pixel-shader-resource, 'shader-read, 'copy-dest, or 'copy-source" value))))
(define (interop-timeout! n)
  (unless (and (exact-positive-integer? n) (<= n 60000))
    (raise-argument-error 'd3d12-interop "exact timeout in [1, 60000] milliseconds" n)) n)
(define (interop-fence-value! n)
  (unless (and (exact-positive-integer? n) (< n #xffffffffffffffff))
    (raise-argument-error 'd3d12-interop "positive uint64 fence value excluding the device-loss sentinel" n)) n)
(define (check-interop-resource! desc [render? #f])
  (unless (and (hash? desc)
               (for/and ([k '(dimension width height depth levels format samples quality layout flags heap_type heap_flags)])
                 (exact-nonnegative-integer? (hash-ref desc k #f))))
    (error 'd3d12-interop "invalid native resource description"))
  (unless (and (= (hash-ref desc 'dimension) 3) ; D3D12_RESOURCE_DIMENSION_TEXTURE2D
               (<= 1 (hash-ref desc 'width) 16384) (<= 1 (hash-ref desc 'height) 16384)
               (= (hash-ref desc 'depth) 1) (= (hash-ref desc 'levels) 1)
               (= (hash-ref desc 'samples) 1) (= (hash-ref desc 'quality) 0)
               (= (hash-ref desc 'format) 28) (= (hash-ref desc 'layout) 0)
               (= (hash-ref desc 'heap_type) 1) ; DEFAULT, not upload/readback/custom
               ;; No shared, cross-adapter, protected, display or unusual heap flags.
               ;; ALLOW_ONLY_NON_RT_DS_TEXTURES / ALLOW_ONLY_RT_DS_TEXTURES are
               ;; allocation category flags, not ownership/synchronization changes.
               (zero? (bitwise-and (hash-ref desc 'heap_flags) (bitwise-not #xc4)))
               ;; Allow only ALLOW_RENDER_TARGET; no depth, UAV, deny-SRV,
               ;; cross-adapter or simultaneous-access resources in this stage.
               (zero? (bitwise-and (hash-ref desc 'flags) (bitwise-not 1))))
    (error 'd3d12-interop "requires an unshared DEFAULT-heap, single-level, single-sample RGBA8 2D texture"))
  (when (and render? (not (bitwise-bit-set? (hash-ref desc 'flags) 0)))
    (error 'd3d12-interop "scoped rendering requires ALLOW_RENDER_TARGET"))
  desc)
;; body may raise any Racket value or escape; cleanup must still finish. A
;; cleanup failure quarantines and supersedes the original failure. Re-entry
;; cannot reuse a completed native handoff. Used by production and pure tests.
(define (call-with-interop-cleanup body finish quarantine)
  (define entered? #f)
  (call-with-continuation-barrier
    (lambda ()
      (dynamic-wind
        (lambda ()
          (when entered? (error 'd3d12-interop "external lease expired"))
          (set! entered? #t))
        body
        (lambda ()
          (parameterize-break #f
            (with-handlers ([(lambda (_) #t) (lambda (e) (quarantine e) (raise e))])
              (finish))))))))
