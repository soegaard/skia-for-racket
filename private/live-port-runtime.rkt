#lang racket/base

;;;
;;; Live Port Operation State
;;;

;; Tracks cancellation, byte limits, positions, and callback failures for live I/O.
;; Supplies the Racket-side state machine used by native port callbacks.

;; 0.75b: promoted from the macOS-tested pure-FFI probe.
;; Scheduling/dispatch is unchanged; finish owns production leases and port cleanup.
(require ffi/unsafe ffi/unsafe/atomic ffi/unsafe/os-thread
         ffi/unsafe/os-async-channel ffi/unsafe/custodian
         racket/match)
(provide dispatch-callback guarded-callback run-operation current-operation
         operation? operation-input operation-output operation-limit operation-length
         operation-seekable? operation-base operation-position set-operation-position!
         operation-eof? set-operation-eof?! operation-written set-operation-written!
         operation-note! operation-note-max! operation-error check-cancel! wait-port! CHUNK
         active-operation-count last-operation-report in-port-service? request-in-racket)
;;;
;;; Service State and Operation Records
;;;

; CHUNK : exact-positive-integer?
;;   Bounds each Racket/native transfer copy to 65536 bytes.
(define CHUNK 65536)
; keeper : custodian?
;;   Keeps the service thread alive independently of the caller's custodian until native teardown.
(define keeper (make-custodian-at-root))
; requests : (or/c #f os-async-channel?)
;;   Carries worker callback, Racket request, and completion messages when OS threads are supported.
(define requests (and (os-thread-enabled?) (make-os-async-channel)))
; replies : (or/c #f os-async-channel?)
;;   Returns synchronous Racket service results to the native worker.
(define replies (and (os-thread-enabled?) (make-os-async-channel)))
; gate : semaphore?
;;   Allows only one live native operation to use the process callback dispatcher at a time.
(define gate (make-semaphore 1))
; current-operation : (or/c #f operation?)
;;   Holds the serialized active operation until all native callbacks and cleanup have completed.
(define current-operation #f)
; last-report : (or/c #f hash?)
;;   Retains detached failure, byte-count, and callback diagnostics from the last completed
;;   operation.
(define last-report #f)
; last-operation-report : -> (or/c #f hash?)
;;   Returns the last completed operation's detached diagnostic report.
(define (last-operation-report) last-report)
; in-port-service? : (parameter/c boolean?)
;;   Marks service-thread callback execution so nested live operations can be rejected.
(define in-port-service? (make-parameter #f))
;; Every field except immutable configuration is accessed by ordinary Racket
;; threads. The OS worker communicates only through OS-async channels.
(struct operation (input output limit length seekable? base cancel owner stop
                         [position #:mutable] [eof? #:mutable] [written #:mutable]
                         [error #:mutable] notes) #:transparent)
;; Fields:
;;   input and output: open input/output ports or #f. limit: exact positive byte budget up to
;;   #x7fffffff. length: declared nonnegative input extent <= limit, or #f. seekable?: boolean;
;;   true requires both input and length. base: nonnegative underlying starting byte position,
;;   zero for nonseekable input. cancel: optional event whose readiness requests cancellation.
;;   owner: calling Racket thread. stop: semaphore posted when the first failure is saved.
;;   position: nonnegative cursor relative to base, at most length when declared, otherwise limit.
;;   eof?: boolean recording observed EOF. written: nonnegative published output-byte count <= limit.
;;   error: #f or (cons #t raised-value), so a raised #f is distinct from no error. notes: mutable
;;   symbol-keyed hash of diagnostic counters and observations. Ordinary Racket threads access
;;   fields; the OS worker communicates through channels rather than mutating this record.

; active-operation-count : -> (integer-in 0 1)
;;   Reports whether the single serialized live-operation slot is occupied.
(define (active-operation-count) (if current-operation 1 0))
; operation-note! : symbol? [any/c] -> void?
;;   Records a diagnostic value or increments a counter on the active operation.
(define (operation-note! key [value #f])
  (define j current-operation)
  (when j
    (hash-set! (operation-notes j) key
               (if value value (add1 (hash-ref (operation-notes j) key 0))))))
; operation-note-max! : symbol? real? -> void?
;;   Retains the largest observed value for an active-operation diagnostic.
(define (operation-note-max! key value)
  (define j current-operation)
  (when j
    (hash-set! (operation-notes j) key
               (max value (hash-ref (operation-notes j) key 0)))))
;;;
;;; Failure and Cancellation
;;;

; fail! : operation? any/c -> void?
;;   Saves the first raised value and signals stop, distinguishing a raised false value from no
;;   error.
(define (fail! j value)
  ;; The cons distinguishes a raised #f from absence of an error.
  (unless (operation-error j)
    (set-operation-error! j (cons #t value))
    (semaphore-post (operation-stop j))))
; cancel-exn : string? -> exn:fail?
;;   Builds the deferred failure used when a caller cancels or leaves a native operation.
(define (cancel-exn message)
  (exn:fail (string-append "live-ffi: " message) (current-continuation-marks)))
; stopped-evt : operation? -> evt?
;;   Becomes ready on recorded failure, caller-thread death, or explicit cancellation.
(define (stopped-evt j)
  (choice-evt (semaphore-peek-evt (operation-stop j))
              (thread-dead-evt (operation-owner j))
              (or (operation-cancel j) never-evt)))
; check-cancel! : operation? -> void?
;;   Records cancellation if necessary and re-raises the saved failure on the Racket service side.
(define (check-cancel! j)
  (when (sync/timeout 0 (stopped-evt j))
    (unless (operation-error j)
      (fail! j (cancel-exn "cancelled or calling thread terminated")))
    (raise (cdr (operation-error j)))))
; wait-port! : operation? evt? -> void?
;;   Waits for port readiness or stop while keeping cancellation checks outside native frames.
(define (wait-port! j port)
  (check-cancel! j)
  (sync (wrap-evt port (lambda (_) 'ready))
        (wrap-evt (stopped-evt j) (lambda (_) 'stopped)))
  (check-cancel! j))
;;;
;;; Callback Dispatch Across the Native Boundary
;;;

;; This procedure runs in atomic mode. It neither calls the supplied thunk nor
;; touches a port. The thunk belongs to Racket's FFI, and is called exactly once.
; dispatch-callback : procedure? -> void?
;;   Queues an asynchronous FFI callback for execution by the Racket service thread.
(define (dispatch-callback thunk)
  (os-async-channel-put requests (cons 'callback thunk)))
; guarded-callback : any/c procedure? -> procedure?
;;   Wraps a callback with operation lookup, continuation barriers, and failure capture so raised
;;   values cannot unwind native frames.
(define (guarded-callback fallback proc)
  (lambda arguments
    (define j current-operation)
    (cond
      [(not j) fallback]
      [else
       (with-handlers ([(lambda (_) #t)
                        (lambda (e) (fail! j e) fallback)])
         (when (in-atomic-mode?)
           (error 'live-ffi "callback was not dispatched out of atomic mode"))
         (operation-note! 'callbacks)
         (call-with-continuation-barrier
          (lambda ()
            ;; Catch ordinary aborts as failure too, never unwind native frames.
            (call-with-continuation-prompt
             (lambda () (apply proc j arguments))
             (default-continuation-prompt-tag)
             (lambda aborted
               (fail! j (cancel-exn "port callback aborted its prompt"))
               fallback)))))])))
;; Only callable from the constrained OS worker. This transports an operation
;; such as copying native pixel data back into Racket-owned bytes, not a public
;; drawing callback. The reply synchronizes visibility of the result.
; request-in-racket : procedure? -> any/c
;;   Synchronously asks the Racket service to perform work unsafe on the OS worker.
(define (request-in-racket thunk)
  (os-async-channel-put requests (list 'request thunk replies))
  (os-async-channel-get replies))
;;;
;;; Operation Setup, Worker Execution, and Cleanup
;;;

; validate-options : any/c any/c exact-positive-integer? any/c boolean? any/c ->
;   exact-nonnegative-integer?
;;   Checks open ports, input extent, byte limit, and cancellation, returning the absolute seek base
;;   or zero.
(define (validate-options in out limit length seekable? cancel)
  (unless (and (exact-positive-integer? limit) (<= limit #x7fffffff))
    (raise-argument-error 'run-operation "positive byte limit <= 2147483647" limit))
  (unless (or (not in) (and (input-port? in) (not (port-closed? in))))
    (raise-argument-error 'run-operation "#f or open input port" in))
  (unless (or (not out) (and (output-port? out) (not (port-closed? out))))
    (raise-argument-error 'run-operation "#f or open output port" out))
  (unless (and (boolean? seekable?)
               (or (not length) (and (exact-nonnegative-integer? length) (<= length limit)))
               (or (not seekable?) (and in length)))
    (error 'run-operation "invalid declared input extent or seek capability"))
  (unless (or (not cancel) (evt? cancel))
    (raise-argument-error 'run-operation "#f or event" cancel))
  (if seekable?
      (let ([base (file-position in)])
        (unless (exact-nonnegative-integer? base)
          (error 'run-operation "seekable input must report a byte position"))
        base)
      0))
; run-operation : procedure? [#:input any/c] [#:output any/c] [#:limit exact-positive-integer?]
;   [#:length any/c] [#:seekable? boolean?] [#:cancel-evt any/c] [#:finish procedure?] -> (values
;   any/c hash? exact-nonnegative-integer? exact-nonnegative-integer?)
;;   Runs one native worker with Racket-serviced callbacks and guaranteed finish cleanup; returns
;;   its result, notes, input position, and bytes written after native teardown.
(define (run-operation native-thunk
                       #:input [in #f] #:output [out #f] #:limit [limit (* 16 1024 1024)]
                       #:length [length #f] #:seekable? [seekable? #f]
                       #:cancel-evt [cancel #f] #:finish [finish void])
  (when (in-port-service?) (error 'run-operation "live port operations cannot re-enter"))
  (unless (os-thread-enabled?)
    (error 'run-operation "requires Racket CS with OS-thread support"))
  (when (in-atomic-mode?) (error 'run-operation "cannot wait inside atomic mode"))
  (define base (validate-options in out limit length seekable? cancel))
  (unless (semaphore-try-wait? gate)
    (error 'run-operation "another live-FFI operation is active"))
  (define owner (current-thread))
  (define j (operation in out limit length seekable? base cancel owner
                       (make-semaphore 0) 0 #f 0 #f (make-hasheq)))
  (define finished (make-semaphore 0))
  (define result #f)
  (define captured (current-parameterization))
  (define finish-pending? #t)
  (define (finish-once [okay? #f])
    (when finish-pending?
      (set! finish-pending? #f)
      (with-handlers ([(lambda (_) #t) (lambda (e) (fail! j e))]) (finish okay?))))
  (define launched? #f)
  (with-handlers ([(lambda (_) #t)
                   (lambda (e)
                     (unless launched?
                       (finish-once)
                       (set! current-operation #f)
                       (semaphore-post gate))
                     (raise e))])
    ;; Setup is uninterruptible until the private service owns cleanup. It is
    ;; under a root child so killing/shutting down the caller cannot abandon an
    ;; already-dispatched callback. Custom port code must still return normally
    ;; or raise; self-killing, process exit and nonreturning callbacks are outside
    ;; this contract.
    (parameterize-break #f
      (set! current-operation j)
      (parameterize ([current-custodian keeper])
        (thread
         (lambda ()
           (call-with-parameterization captured
            (lambda ()
              (parameterize ([in-port-service? #t])
                (parameterize-break #f
                  (define launch (make-os-async-channel))
                  (define worker-started? #f)
                  (define native-result #f)
                  (with-handlers ([(lambda (_) #t)
                                   (lambda (e) (fail! j e))])
                    ;; No parameters, Racket thread/sync APIs, handlers, or
                    ;; public Skia wrappers are used in this OS-thread thunk.
                    (call-in-os-thread
                     (lambda ()
                       (define work (os-async-channel-get launch))
                       (define answer (work))
                       (os-async-channel-put requests (cons 'done answer))))
                    (set! worker-started? #t)
                    (os-async-channel-put launch native-thunk))
                  (when worker-started?
                    (let loop ()
                      (match (sync requests)
                        [(cons 'callback thunk)
                         ;; The callback itself catches every raised value.
                         (thunk)
                         (loop)]
                        [(list 'request thunk reply)
                         (define value
                           (with-handlers ([(lambda (_) #t)
                                            (lambda (e) (fail! j e) #f)])
                             (check-cancel! j)
                             (thunk)))
                         (os-async-channel-put reply value)
                         (loop)]
                        [(cons 'done answer) (set! native-result answer)])))
                  (unless (operation-error j)
                    (with-handlers ([(lambda (_) #t) (lambda (e) (fail! j e))])
                      (check-cancel! j)))
                  ;; No native stack or pending callback remains here. Cleanup
                  ;; runs even if the original Racket caller was terminated.
                  (finish-once (and (not (operation-error j))
                                    (vector? native-result)
                                    (positive? (vector-length native-result))
                                    (eq? (vector-ref native-result 0) 'ok)))
                  (set! result
                        (vector (operation-error j) native-result
                                (hash-copy (operation-notes j))
                                (operation-position j) (operation-written j)))
                  (set! last-report
                        (hasheq 'failed? (and (operation-error j) #t)
                                'notes (for/hasheq ([(k v) (in-hash (operation-notes j))])
                                         (values k v))
                                'read (operation-position j) 'written (operation-written j)))
                  (set! current-operation #f)
                  (semaphore-post gate)
                  (semaphore-post finished))))))))
      (set! launched? #t))
    ;; A break/cancellation does not abandon the service or foreign callback.
    ;; Save the first error, request cancellation, and wait for native teardown.
    (dynamic-wind
      void
      (lambda ()
        (with-handlers ([(lambda (_) #t)
                         (lambda (e)
                           (fail! j e)
                           (parameterize-break #f (sync (semaphore-peek-evt finished)))
                           (raise e))])
          (sync (semaphore-peek-evt finished))))
      (lambda ()
        ;; Also covers ordinary continuation escapes, not only exceptions.
        (unless (sync/timeout 0 (semaphore-peek-evt finished))
          (fail! j (cancel-exn "caller left the operation scope"))
          (parameterize-break #f (sync (semaphore-peek-evt finished))))))
    (when (vector-ref result 0) (raise (cdr (vector-ref result 0))))
    (values (vector-ref result 1) (vector-ref result 2)
            (vector-ref result 3) (vector-ref result 4))))
