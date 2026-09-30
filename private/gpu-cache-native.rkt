#lang racket/base
(require ffi/unsafe racket/promise
         (only-in "native.rkt" skia-native-library-handle)
         "gpu-provider.rkt" "gpu-native-scope.rkt" "gpu-raw.rkt")
(provide cache-dispatch/native gpu-cache-native-inventory)
;; Independent, lazy optional registry; ordinary CPU requirements are unchanged.
(define library (delay/sync (skia-native-library-handle)))
(define bindings '())
(define-syntax-rule (define-cache-native name c-name type)
  (begin
    (define binding (delay/sync (get-ffi-obj 'c-name (force library) type)))
    (set! bindings (cons (cons 'c-name binding) bindings))
    (define (name . args)
      (define call (force binding))
      (call-with-gpu-native-scope (lambda () (apply call args))))))
(define-cache-native abandoned? gr_direct_context_is_abandoned (_fun _pointer -> _stdbool))
(define-cache-native limit gr_direct_context_get_resource_cache_limit (_fun _pointer -> _size))
(define-cache-native usage gr_direct_context_get_resource_cache_usage (_fun _pointer _pointer _pointer -> _void))
(define-cache-native set-limit gr_direct_context_set_resource_cache_limit (_fun #:blocking? #t _pointer _size -> _void))
(define-cache-native purge gr_direct_context_purge_unlocked_resources (_fun #:blocking? #t _pointer _stdbool -> _void))
(define-cache-native purge-bytes gr_direct_context_purge_unlocked_resources_bytes (_fun #:blocking? #t _pointer _size _stdbool -> _void))
(define-cache-native deferred gr_direct_context_perform_deferred_cleanup (_fun #:blocking? #t _pointer _int64 -> _void))
(define-cache-native free-resources gr_direct_context_free_gpu_resources (_fun #:blocking? #t _pointer -> _void))
(define (gpu-cache-native-inventory)
  (for/list ([b (in-list (reverse bindings))])
    (hasheq 'name (symbol->string (car b))
            'available (with-handlers ([exn:fail? (lambda (_) #f)]) (force (cdr b)) #t))))
(define checked? #f)
(define (check!)
  (unless checked?
    (for ([b (in-list (reverse bindings))])
      (with-handlers ([exn:fail? (lambda (e)
                        (gpu-unavailable 'cache-symbols "missing GPU cache binding ~a: ~a" (car b) (exn-message e)))])
        (force (cdr b))))
    (set! checked? #t)))
(define (cache-dispatch/native op context . args)
  (check!)
  (case op
    [(abandoned?) (abandoned? context)]
    [(info)
     ;; The output ABI is int* followed by size_t*, not two size_t pointers.
     (call-with-gpu-raw (ctype-sizeof _int)
       (lambda (count)
         (call-with-gpu-raw (ctype-sizeof _size)
           (lambda (bytes)
             (ptr-set! count _int 0) (ptr-set! bytes _size 0)
             (usage context count bytes)
             (values (limit context) (ptr-ref count _int) (ptr-ref bytes _size))))))]
    [(set-limit) (apply set-limit context args)]
    [(purge) (apply purge context args)]
    [(purge-bytes) (apply purge-bytes context args)]
    [(deferred) (apply deferred context args)]
    [(free-resources) (free-resources context)]
    [else (error 'gpu-cache "unknown private operation: ~a" op)]))
