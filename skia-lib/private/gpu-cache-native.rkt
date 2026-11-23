#lang racket/base

;;;
;;; Native GPU Cache Operations
;;;

;; Loads cache-management entry points lazily and dispatches checked native requests.
;; Implements the FFI side of public GPU cache inspection and purging.

(require ffi/unsafe racket/promise
         (only-in "native.rkt" skia-native-library-handle)
         "gpu-provider.rkt" "gpu-native-scope.rkt" "gpu-raw.rkt")
(provide cache-dispatch/native gpu-cache-native-inventory)

;;;
;;; Lazy Cache Binding Registry
;;;

;; Independent, lazy optional registry; ordinary CPU requirements are unchanged.

; library : promise?
;   Defers access to the checked Skia shared-library handle until a native binding is first used.
(define library (delay/sync (skia-native-library-handle)))

; bindings : list?
;   Accumulates native symbol promises for availability checks and detached binding inventories.
(define bindings '())

; define-cache-native : syntax transformer
;   Declares a lazily resolved native procedure and registers its symbol for readiness and
;   inventory checks.
(define-syntax-rule (define-cache-native name c-name type)
  (begin
    (define binding (delay/sync (get-ffi-obj 'c-name (force library) type)))
    (set! bindings (cons (cons 'c-name binding) bindings))
    (define (name . args)
      (define call (force binding))
      (call-with-gpu-native-scope (lambda () (apply call args))))))

;;;
;;; Context Cache Operations
;;;

; abandoned? : (_fun _pointer -> _stdbool) (FFI)
;   Calls the native gr_direct_context_is_abandoned entry point using the declared FFI layout.
(define-cache-native abandoned? gr_direct_context_is_abandoned (_fun _pointer -> _stdbool))

; limit : (_fun _pointer -> _size) (FFI)
;   Calls the native gr_direct_context_get_resource_cache_limit entry point using the declared FFI
;   layout.
(define-cache-native limit gr_direct_context_get_resource_cache_limit (_fun _pointer -> _size))

; usage : (_fun _pointer _pointer _pointer -> _void) (FFI)
;   Calls the native gr_direct_context_get_resource_cache_usage entry point using the declared FFI
;   layout.
(define-cache-native usage gr_direct_context_get_resource_cache_usage
  (_fun _pointer _pointer _pointer -> _void))

; set-limit : (_fun #:blocking? #t _pointer _size -> _void) (FFI)
;   Calls the native gr_direct_context_set_resource_cache_limit entry point using the declared FFI
;   layout.
(define-cache-native set-limit gr_direct_context_set_resource_cache_limit
  (_fun #:blocking? #t _pointer _size -> _void))

; purge : (_fun #:blocking? #t _pointer _stdbool -> _void) (FFI)
;   Calls the native gr_direct_context_purge_unlocked_resources entry point using the declared FFI
;   layout.
(define-cache-native purge gr_direct_context_purge_unlocked_resources
  (_fun #:blocking? #t _pointer _stdbool -> _void))

; purge-bytes : (_fun #:blocking? #t _pointer _size _stdbool -> _void) (FFI)
;   Calls the native gr_direct_context_purge_unlocked_resources_bytes entry point using the
;   declared FFI layout.
(define-cache-native purge-bytes gr_direct_context_purge_unlocked_resources_bytes
  (_fun #:blocking? #t _pointer _size _stdbool -> _void))

; deferred : (_fun #:blocking? #t _pointer _int64 -> _void) (FFI)
;   Calls the native gr_direct_context_perform_deferred_cleanup entry point using the declared FFI
;   layout.
(define-cache-native deferred gr_direct_context_perform_deferred_cleanup
  (_fun #:blocking? #t _pointer _int64 -> _void))

; free-resources : (_fun #:blocking? #t _pointer -> _void) (FFI)
;   Calls the native gr_direct_context_free_gpu_resources entry point using the declared FFI
;   layout.
(define-cache-native free-resources gr_direct_context_free_gpu_resources
  (_fun #:blocking? #t _pointer -> _void))

;;;
;;; Readiness and Operation Dispatch
;;;

; gpu-cache-native-inventory : -> list?
;   Resolves optional cache symbols and reports availability without claiming backend or rendering
;   support.
(define (gpu-cache-native-inventory)
  (for/list ([b (in-list (reverse bindings))])
    (hasheq 'name (symbol->string (car b))
            'available (with-handlers ([exn:fail? (lambda (_) #f)]) (force (cdr b)) #t))))

; checked? : boolean?
;   Remembers successful resolution of the complete optional cache-operation binding set.
(define checked? #f)

; check! : -> void?
;   Requires every optional GPU cache symbol before the first cache operation and caches only
;   successful readiness.
(define (check!)
  (unless checked?
    (for ([b (in-list (reverse bindings))])
      (with-handlers ([exn:fail? (lambda (e)
                        (gpu-unavailable 'cache-symbols "missing GPU cache binding ~a: ~a" (car b)
                          (exn-message e)))])
        (force (cdr b))))
    (set! checked? #t)))

; cache-dispatch/native : any/c any/c any/c ... -> any
;   Dispatches checked cache requests and copies native count/byte out-parameters into ordinary
;   Racket results.
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
