#lang racket/base
;; Synchronous, memory-only callbacks. No user procedure, port, wait, Skia call,
;; or exception escape is permitted while Skia holds its cache locks.
(require ffi/unsafe ffi/unsafe/atomic ffi/unsafe/global racket/promise
         "native.rkt" "graphics-data.rkt"
         (only-in "live-port-runtime.rkt" in-port-service? active-operation-count))
(provide global-memory-statistics/native collect-memory-statistics/native
         call-global-cache-native trace-binding-count)
(define-cstruct _trace-procs ([numeric _fpointer] [string _fpointer])
  #:malloc-mode 'atomic-interior)
;; Reviewed Xamarin declarations, inventoried separately from include/c.
(define-syntax-rule (define-trace name type)
  (define name (delay/sync (get-ffi-obj 'name (skia-native-library-handle) type))))
(define-trace sk_managedtracememorydump_new (_fun _stdbool _stdbool _pointer -> _pointer))
(define-trace sk_managedtracememorydump_delete (_fun _pointer -> _void))
(define-trace sk_managedtracememorydump_set_procs (_fun _trace-procs -> _void))
(define trace-binding-count 3)
(define _numeric-callback
  (_fun #:atomic? #t _pointer _pointer _pointer _pointer _pointer _uint64 -> _void))
(define _string-callback
  (_fun #:atomic? #t _pointer _pointer _pointer _pointer _pointer -> _void))
(define (check-global-cache-idle! who)
  (when (in-port-service?)
    (error who "global cache operations are not allowed from a live port callback"))
  (unless (zero? (active-operation-count))
    (error who "global cache operations are not allowed while a live stream operation is active")))
(define (call-global-cache-native who thunk)
  ;; Resolve lazy library/symbol promises outside atomic mode. Recheck activity
  ;; inside atomic mode so no live worker starts before entering the cache API.
  (check-global-cache-idle! who)
  (skia-check!)
  (call-as-atomic
   (lambda () (check-global-cache-idle! who) (thunk))))
(define roots #f)
(define provider-marker #f)
(define active #f)
(define dump-lock (make-semaphore 1))
(define no-error (gensym 'no-error))
(struct capture (collector string-limit marker [dump #:mutable] [error #:mutable]))
(define (pointer=? a b)
  (and a b (= (cast a _pointer _uintptr) (cast b _pointer _uintptr))))
(define (copy-c-string ptr cap)
  (unless ptr (error 'skia-memory-statistics "native statistic contains a null string"))
  (let loop ([n 0])
    (cond [(zero? (ptr-ref ptr _ubyte n))
           (define bytes (make-bytes n))
           (unless (zero? n) (memcpy bytes ptr n))
           bytes]
          [(= n cap) #f]
          [else (loop (add1 n))])))
(define (capture-value kind dump context name key last [value #f])
  (define state active)
  ;; Do not interpret callbacks from an unowned managed object. Only our
  ;; temporary object can use this provider; foreign providers are unsupported.
  (when (and state (pointer=? context (capture-marker state))
             (pointer=? dump (capture-dump state)) (eq? (capture-error state) no-error))
    (with-handlers ([(lambda (_) #t) (lambda (e) (set-capture-error! state e) (void))])
      (define collector (capture-collector state))
      (cond [(collector-full? collector) (collector-drop! collector)]
            [else
             (let/ec omit
               (define room (collector-room collector))
               (define (read ptr)
                 (define bytes (copy-c-string ptr (min room (capture-string-limit state))))
                 (unless bytes (collector-drop! collector) (omit (void)))
                 (set! room (- room (bytes-length bytes)))
                 bytes)
               (define a (read name)) (define b (read key)) (define c (read last))
               (if (eq? kind 'numeric)
                   (collector-add! collector kind a b c value)
                   (collector-add! collector kind a b #f c)))])))
  (void))
(define (numeric-callback dump context name key units value)
  (capture-value 'numeric dump context name key units value))
(define (string-callback dump context name key value)
  (capture-value 'string dump context name key value))
(define (initialize-provider!)
  (unless roots
    ;; Resolve all symbols and construct all callback objects before claiming
    ;; the process-global table. Require never calls this initializer.
    (force sk_managedtracememorydump_new)
    (force sk_managedtracememorydump_delete)
    (define set-procs (force sk_managedtracememorydump_set_procs))
    (unless (= (ctype-sizeof _trace-procs) (* 2 (ctype-sizeof _pointer)))
      (error 'skia-memory-statistics "unexpected managed trace table layout"))
    (define numeric (function-ptr numeric-callback _numeric-callback))
    (define string (function-ptr string-callback _string-callback))
    (define table (make-trace-procs numeric string))
    ;; One byte and callback roots deliberately live for the process/provider
    ;; lifetime. A second module instance/place must not replace this table.
    (define marker (malloc 1 'raw))
    (when (register-process-global #"skia-for-racket/global-memory-statistics/m119/v1" marker)
      (free marker)
      (error 'skia-memory-statistics "memory-statistics callback table is already claimed by another module/place"))
    (set! provider-marker marker)
    (set! roots (list numeric-callback string-callback numeric string table))
    (set-procs table)))
(define (global-memory-statistics/native detailed? wrapped? max-entries string-limit byte-limit)
  (collect-memory-statistics/native 'skia-memory-statistics 'process-global-skia-caches
    sk_graphics_dump_memory_statistics detailed? wrapped? max-entries string-limit byte-limit))
;; Private native caller only. Never accepts an application callback through a
;; public API. GPU and global dumps share provider roots, limits and cleanup.
(define (collect-memory-statistics/native who scope invoke detailed? wrapped? max-entries string-limit byte-limit)
  (memory-options who detailed? wrapped? max-entries string-limit byte-limit)
  (unless (memq scope '(process-global-skia-caches gpu-context-skia-resources))
    (raise-argument-error who "known memory-statistics scope" scope))
  (check-global-cache-idle! who)
  (skia-check!)
  ;; Keep asynchronous breaks out of the foreign callback/cleanup boundary.
  ;; No locks spanning arbitrary Racket user work are introduced.
  (call-with-semaphore dump-lock
   (lambda ()
    (parameterize-break #f
     (call-as-atomic
     (lambda ()
       (check-global-cache-idle! who)
       (when active (error who "reentrant native memory dump"))
       (initialize-provider!)
       (define state (capture (make-memory-collector max-entries byte-limit detailed? wrapped?)
                              string-limit provider-marker #f no-error))
       (dynamic-wind
         (lambda () (set! active state))
         (lambda ()
           (define dump ((force sk_managedtracememorydump_new) detailed? wrapped? provider-marker))
           (unless dump (error who "native trace allocation failed"))
           (set-capture-dump! state dump)
           (dynamic-wind void
             (lambda () (invoke dump))
             (lambda () ((force sk_managedtracememorydump_delete) dump)
                        (set-capture-dump! state #f))))
         (lambda () (set! active #f)))
       ;; No native frame/object is live when a deferred callback error escapes.
       (unless (eq? (capture-error state) no-error) (raise (capture-error state)))
       (collector-finish (capture-collector state) #:scope scope)))))))

(define (set-active-for-test! state) (set! active state))
(module+ test-support
  (provide copy-c-string capture-value capture active no-error
           set-capture-dump! set-capture-error! capture-error
           set-active-for-test!)
)
