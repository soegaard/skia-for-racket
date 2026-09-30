#lang racket/base
(require rackunit racket/list "../gpu-interop.rkt"
         "../private/gpu-d3d12-interop-policy.rkt"
         (submod "../private/gpu-external.rkt" backend-internals))
(provide gpu-interop-pure-tests)
(define desc
  (hasheq 'dimension 3 'width 37 'height 29 'depth 1 'levels 1 'format 28
          'samples 1 'quality 0 'layout 0 'flags 1 'heap_type 1 'heap_flags 0))
(define ctx (gensym 'context))
(define (fixture #:check [check void] #:operate [operate (lambda (mode p) (if p (p 'canvas) 'image))]
                 #:retire [retire void])
  (make-external-texture 'direct3d ctx 71 (hasheq 'ownership "synthetic")
                        check operate retire (lambda () (hasheq 'synthetic #t))))
(define gpu-interop-pure-tests
  (test-suite "External resource handoff contracts; no Windows/native loading"
    (test-case "all named states have the reviewed native values"
      (check-equal? (map interop-state '(common render-target pixel-shader-resource shader-read copy-dest copy-source))
                    '(0 4 128 192 1024 2048)))
    (test-case "state values cannot be guessed from integers or strings"
      (for ([x '(#f #t 0 4 "render-target" unknown)])
        (check-exn exn:fail? (lambda () (interop-state x)))))
    (test-case "timeouts are bounded positive exact milliseconds"
      (check-equal? (interop-timeout! 1) 1) (check-equal? (interop-timeout! 60000) 60000)
      (for ([x '(0 -1 60001 #f #t 1.0)]) (check-exn exn:fail? (lambda () (interop-timeout! x)))))
    (test-case "producer fence cannot use initial zero or removed sentinel"
      (check-equal? (interop-fence-value! 1) 1)
      (for ([x '(0 -1 #f #t 1.0 18446744073709551615)])
        (check-exn exn:fail? (lambda () (interop-fence-value! x)))))
    (test-case "native description accepts the intended texture subset"
      (check-equal? (check-interop-resource! desc #t) desc))
    (test-case "non-RT images can be copied but not borrowed for drawing"
      (define d (hash-set desc 'flags 0)) (check-not-exn (lambda () (check-interop-resource! d)))
      (check-exn exn:fail? (lambda () (check-interop-resource! d #t))))
    (test-case "array textures are rejected" (check-exn exn:fail? (lambda () (check-interop-resource! (hash-set desc 'depth 2)))))
    (test-case "mipmapped textures are rejected" (check-exn exn:fail? (lambda () (check-interop-resource! (hash-set desc 'levels 2)))))
    (test-case "MSAA is rejected" (check-exn exn:fail? (lambda () (check-interop-resource! (hash-set desc 'samples 4)))))
    (test-case "other formats are rejected" (check-exn exn:fail? (lambda () (check-interop-resource! (hash-set desc 'format 87)))))
    (test-case "oversized textures are rejected" (check-exn exn:fail? (lambda () (check-interop-resource! (hash-set desc 'width 16385)))))
    (test-case "zero textures are rejected" (check-exn exn:fail? (lambda () (check-interop-resource! (hash-set desc 'height 0)))))
    (test-case "wrong resource dimension is rejected" (check-exn exn:fail? (lambda () (check-interop-resource! (hash-set desc 'dimension 1)))))
    (test-case "flags cannot be booleans" (check-exn exn:fail? (lambda () (check-interop-resource! (hash-set desc 'flags #f)))))
    (test-case "simultaneous access is rejected" (check-exn exn:fail? (lambda () (check-interop-resource! (hash-set desc 'flags #x20)))))
    (test-case "cross-adapter resources are rejected" (check-exn exn:fail? (lambda () (check-interop-resource! (hash-set desc 'flags #x10)))))
    (test-case "UAV textures are rejected" (check-exn exn:fail? (lambda () (check-interop-resource! (hash-set desc 'flags 5)))))
    (test-case "shared heaps are rejected" (check-exn exn:fail? (lambda () (check-interop-resource! (hash-set desc 'heap_flags 1)))))
    (test-case "upload/readback/custom heaps are rejected"
      (for ([type '(2 3 4)]) (check-exn exn:fail? (lambda () (check-interop-resource! (hash-set desc 'heap_type type))))))
    (test-case "ordinary allocation category flags are accepted"
      (for ([flags '(0 4 68 132)]) (check-not-exn (lambda () (check-interop-resource! (hash-set desc 'heap_flags flags))))))
    (test-case "missing native metadata is not accepted"
      (for ([k (in-list (hash-keys desc))]) (check-exn exn:fail? (lambda () (check-interop-resource! (hash-remove desc k))))))
    (test-case "generic copy returns its backend-owned result"
      (check-eq? (gpu-import-image ctx (fixture)) 'image))
    (test-case "handoff cannot be copied twice"
      (define t (fixture)) (gpu-import-image ctx t)
      (check-exn #rx"consumed" (lambda () (gpu-import-image ctx t))))
    (test-case "scoped borrowing preserves multiple return values"
      (check-equal? (call-with-values (lambda () (call-with-gpu-external-surface ctx (fixture) (lambda (c) (values c 2 3)))) list)
                    '(canvas 2 3)))
    (test-case "foreign context rejects before checking or touching native storage"
      (define checks 0) (define t (fixture #:check (lambda (_) (set! checks (add1 checks)))))
      (check-exn #rx"another GPU context" (lambda () (gpu-import-image 'foreign t)))
      (check-equal? checks 0) (check-equal? (hash-ref (gpu-external-texture-info t) 'handoff_state) "ready"))
    (test-case "invalid callback does not consume a handoff"
      (define t (fixture)) (check-exn exn:fail? (lambda () (call-with-gpu-external-surface ctx t 7)))
      (check-eq? (gpu-import-image ctx t) 'image))
    (test-case "required callback keywords are rejected"
      (check-exn exn:fail? (lambda () (call-with-gpu-external-surface ctx (fixture) (lambda (x #:need n) n)))))
    (test-case "retirement is idempotent"
      (define count 0) (define t (fixture #:retire (lambda () (set! count (add1 count)))))
      (gpu-external-texture-close! t) (gpu-external-texture-close! t) (check-equal? count 1))
    (test-case "retired descriptor cannot be used"
      (define t (fixture)) (gpu-external-texture-close! t)
      (check-exn #rx"retired" (lambda () (gpu-import-image ctx t))))
    (test-case "cannot close a currently borrowed descriptor"
      (define t (fixture))
      (call-with-gpu-external-surface ctx t (lambda (_) (check-exn #rx"in use" (lambda () (gpu-external-texture-close! t))))))
    (test-case "nested imports are rejected and leave the second token ready"
      (define t (fixture)) (define other (fixture))
      (call-with-gpu-external-surface ctx t (lambda (_) (check-exn #rx"nested" (lambda () (gpu-import-image ctx other)))))
      (check-eq? (gpu-import-image ctx other) 'image))
    (test-case "failed preparation does not consume the handoff"
      (define t (fixture #:check (lambda (_) (error 'test "preflight"))))
      (check-exn #rx"preflight" (lambda () (gpu-import-image ctx t)))
      (check-equal? (hash-ref (gpu-external-texture-info t) 'handoff_state) "ready"))
    (test-case "failed native operation consumes the handoff"
      (define t (fixture #:operate (lambda (_m _p) (error 'test "native failure"))))
      (check-exn #rx"native failure" (lambda () (gpu-import-image ctx t)))
      (check-exn #rx"consumed" (lambda () (gpu-import-image ctx t))))
    (test-case "arbitrary raised values still consume the handoff"
      (define t (fixture #:operate (lambda (_m _p) (raise #f))))
      (check-exn not (lambda () (gpu-import-image ctx t)))
      (check-equal? (hash-ref (gpu-external-texture-info t) 'handoff_state) "consumed"))
    (test-case "native handles never appear in public info"
      (define i (gpu-external-texture-info (fixture)))
      (check-false (hash-ref i 'raw_handles_exposed))
      (check-false (hash-has-key? i 'context)) (check-equal? (hash-ref i 'context_generation) 71))
    (test-case "foreign Racket thread cannot use a descriptor"
      (define t (fixture)) (define ch (make-channel))
      (thread (lambda () (channel-put ch (with-handlers ([exn:fail? (lambda (_) #t)]) (gpu-import-image ctx t) #f))))
      (check-true (channel-get ch)))
    (test-case "cleanup runs after normal completion"
      (define log '())
      (check-equal? (call-with-interop-cleanup (lambda () (set! log (cons 'body log)) 19)
                       (lambda () (set! log (cons 'finish log))) (lambda (_) (error 'test "unexpected"))) 19)
      (check-equal? (reverse log) '(body finish)))
    (test-case "cleanup runs after an arbitrary exception"
      (define finished #f)
      (check-exn not (lambda () (call-with-interop-cleanup (lambda () (raise #f))
                    (lambda () (set! finished #t)) (lambda (_) (error 'test "unexpected")))))
      (check-true finished))
    (test-case "cleanup failure quarantines rather than retrying"
      (define finishes 0) (define quarantines 0)
      (check-exn #rx"timeout" (lambda () (call-with-interop-cleanup void
        (lambda () (set! finishes (add1 finishes)) (error 'test "timeout"))
        (lambda (_) (set! quarantines (add1 quarantines))))))
      (check-equal? finishes 1) (check-equal? quarantines 1))
    (test-case "escape runs cleanup and forbids handoff reuse"
      (define finishes 0)
      (check-eq? (let/ec escape
        (call-with-interop-cleanup (lambda () (escape 'escaped))
          (lambda () (set! finishes (add1 finishes))) (lambda (_) (void)))) 'escaped)
      (check-equal? finishes 1))
    (test-case "captured continuation cannot reenter retired scope"
      (define k #f)
      (call-with-interop-cleanup (lambda () (call/cc (lambda (c) (set! k c) 'first))) void void)
      (check-exn exn:fail? (lambda () (k 'again))))))
