#lang racket/base
;; Pure Metal 3-era MTLCommandQueue contracts; not Metal 4 queue interop.
(provide metal-timeout! metal-check-texture! metal-wait-completed!
         (struct-out exn:fail:metal-interop) metal-interop-fail)
(struct exn:fail:metal-interop exn:fail (reason) #:transparent)
(define (metal-interop-fail reason message . xs)
  (raise (exn:fail:metal-interop (apply format message xs)
                               (current-continuation-marks) reason)))
(define (metal-timeout! n)
  (unless (and (exact-positive-integer? n) (<= n 60000))
    (raise-argument-error 'metal-interop "exact timeout in [1, 60000] milliseconds" n))
  n)
(define (metal-check-texture! d [render? #f])
  (unless (and (hash? d)
               (for/and ([k '(width height depth levels array_length samples format texture_type
                                   usage storage_mode hazard_tracking_mode)])
                 (exact-nonnegative-integer? (hash-ref d k #f)))
               (for/and ([k '(same_device framebuffer_only has_parent has_buffer has_heap has_iosurface shareable has_remote_storage
                                         producer_retained_references)])
                 (boolean? (hash-ref d k 'missing))))
    (metal-interop-fail 'descriptor "incomplete native Metal texture description"))
  (unless (hash-ref d 'same_device)
    (metal-interop-fail 'device "texture/producer belong to another Metal device"))
  (unless (and (<= 1 (hash-ref d 'width) 16384) (<= 1 (hash-ref d 'height) 16384)
               (= (hash-ref d 'texture_type) 2) (= (hash-ref d 'format) 70)
               (= (hash-ref d 'depth) 1) (= (hash-ref d 'levels) 1)
               (= (hash-ref d 'array_length) 1) (= (hash-ref d 'samples) 1)
               (memv (hash-ref d 'storage_mode) '(0 2)) ; shared or private; never managed/memoryless
               (= (hash-ref d 'hazard_tracking_mode) 2)
               (equal? (hash-ref d 'swizzle #f) '(2 3 4 5))
               (positive? (bitwise-and (hash-ref d 'usage) 1)) ; explicit ShaderRead
               (zero? (bitwise-and (hash-ref d 'usage) (bitwise-not 5))) ; ShaderRead | RenderTarget
               (hash-ref d 'producer_retained_references)
               (for/and ([k '(framebuffer_only has_parent has_buffer has_heap has_iosurface shareable has_remote_storage)])
                 (not (hash-ref d k))))
    (metal-interop-fail 'descriptor
      "requires tracked, non-view/non-heap, single-level/sample RGBA8Unorm 2D storage with explicit ShaderRead usage"))
  (when (and render? (zero? (bitwise-and (hash-ref d 'usage) 4)))
    (metal-interop-fail 'render-usage "external drawing requires RenderTarget usage"))
  d)
;; Every status/error query is one short native call. No native pool spans
;; sleep, a callback or the whole polling interval. The private injection
;; points make exact deadline/status behavior testable without a GPU.
(define (metal-wait-completed! status error-text timeout
                               #:clock [clock current-inexact-monotonic-milliseconds]
                               #:pause [pause sleep])
  (metal-timeout! timeout)
  (define start (clock))
  (let loop ([polls 0])
    (define s (status))
    (define elapsed (max 0 (- (clock) start)))
    (cond
      [(eqv? s 4) (hasheq 'status 4 'polls (add1 polls) 'elapsed_ms elapsed)]
      [(eqv? s 5) (metal-interop-fail 'command-error "Metal command buffer failed: ~a" (error-text))]
      [(not (memv s '(2 3)))
       (metal-interop-fail 'uncommitted "expected a committed Metal command buffer; status ~a" s)]
      [(>= elapsed timeout) (metal-interop-fail 'timeout "Metal completion timed out after ~a ms" timeout)]
      [else (pause (/ (min 1 (- timeout elapsed)) 1000.0)) (loop (add1 polls))])))
