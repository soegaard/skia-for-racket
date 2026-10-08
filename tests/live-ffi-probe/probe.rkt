#lang racket/base
(require rackunit rackunit/text-ui racket/cmdline racket/file racket/port
         racket/list racket/runtime-path json "../../private/live-port-native.rkt")
(define library-path #f)
(define directory #f)
(define fixtures #f)
(define token #f)
(command-line
 #:program "pure Racket / real Skia stream probe"
 #:once-each
 [("--library") value "Existing pinned libSkiaSharp library" (set! library-path value)]
 [("--directory") value "Fresh output directory" (set! directory value)]
 [("--fixtures") value "Python-authored input fixtures" (set! fixtures value)]
 [("--token") value "Unique run token" (set! token value)])
(unless (and library-path directory fixtures token (regexp-match? #px"^[0-9a-f]{32}$" token))
  (error 'probe "--library, --directory, --fixtures and a valid --token are required"))
(when (directory-exists? directory) (error 'probe "output directory already exists"))
(make-directory* directory)
(initialize-native! library-path)
(define png-input (file->bytes (build-path fixtures "reference.png")))
(define rgba-input (file->bytes (build-path fixtures "reference.rgba")))
(define payload (file->bytes (build-path fixtures "payload.bin")))
(define reports (make-hasheq))
(define (capture thunk) (call-with-values thunk list))
(define (notes reply) (cadr reply))
(define (save name bytes)
  (call-with-output-file (build-path directory name)
    (lambda (out) (write-bytes bytes out)) #:mode 'binary #:exists 'error))
(define (record key reply)
  (hash-set! reports key
             (hasheq 'notes (notes reply) 'read (caddr reply) 'written (cadddr reply))))
(define (check-clean reply inputs outputs)
  (check-equal? (active-operation-count) 0)
  (check-true (positive? (hash-ref (notes reply) 'callbacks 0)))
  (check-equal? (hash-ref (notes reply) 'input-destroyed 0) inputs)
  (check-equal? (hash-ref (notes reply) 'output-destroyed 0) outputs))
(define (check-failed-clean inputs outputs)
  (check-equal? (active-operation-count) 0)
  (define report (last-operation-report))
  (check-true (hash-ref report 'failed?))
  (check-equal? (hash-ref (hash-ref report 'notes) 'input-destroyed 0) inputs)
  (check-equal? (hash-ref (hash-ref report 'notes) 'output-destroyed 0) outputs))
(define (wait-for pred message)
  (define end (+ (current-inexact-milliseconds) 5000))
  (let loop ()
    (unless (pred)
      (when (> (current-inexact-milliseconds) end) (error 'probe message))
      (sleep 0.005)
      (loop))))
(define (partial-output destination maximum [observe void])
  (make-output-port
   'partial always-evt
   (lambda (bytes start end nonblock? breakable?)
     (observe)
     (define n (min maximum (- end start)))
     (write-bytes bytes destination start (+ start n))
     n)
   void))
(define tests
  (test-suite
   "compiler-free FFI with real m119 Skia"
   (test-case "binary copy uses real managed input and output"
     (define out (open-output-bytes))
     (define reply (capture (lambda () (native-copy (open-input-bytes payload) out))))
     (check-equal? (get-output-bytes out) payload)
     (check-equal? (caddr reply) (bytes-length payload))
     (check-equal? (cadddr reply) (bytes-length payload))
     (check-clean reply 1 1)
     (check-true (<= (hash-ref (notes reply) 'max-copy) 65536))
     (save "copied.bin" (get-output-bytes out))
     (record 'copy reply))
   (test-case "empty input completes with EOF"
     (define out (open-output-bytes))
     (define reply (capture (lambda () (native-copy (open-input-bytes #"") out))))
     (check-equal? (get-output-bytes out) #"")
     (check-clean reply 1 1))
   (test-case "bounded output pipe permits another Racket thread to drain it"
     (define-values (in out) (make-pipe 17))
     (define collected (box #f))
     (define reader (thread (lambda () (set-box! collected (port->bytes in)))))
     (define reply (capture (lambda () (native-copy (open-input-bytes payload) out))))
     (close-output-port out)
     (thread-wait reader)
     (check-equal? (unbox collected) payload)
     (close-input-port in)
     (check-clean reply 1 1)
     (record 'bounded-pipe reply))
   (test-case "short writes are fully acknowledged"
     (define bytes (open-output-bytes))
     (define count 0)
     (define out (partial-output bytes 7 (lambda () (set! count (add1 count)))))
     (define reply (capture (lambda () (native-copy (open-input-bytes payload) out))))
     (check-true (> count 1000))
     (check-equal? (get-output-bytes bytes) payload)
     (close-output-port out)
     (check-clean reply 1 1))
   (test-case "callbacks inherit parameters but run on a protected Racket service thread"
     (define mark (make-parameter 'missing))
     (define caller (current-thread))
     (define seen #f)
     (define out
       (partial-output (open-output-bytes) 17
                       (lambda ()
                         (check-equal? (mark) 'correct)
                         (check-true (in-port-service?))
                         (check-false (eq? caller (current-thread)))
                         (set! seen #t))))
     (parameterize ([mark 'correct])
       (capture (lambda () (native-copy (open-input-bytes #"parameter") out))))
     (check-true seen)
     (close-output-port out))
   (test-case "collections during callbacks retain buffers and callback pointers"
     (define count 0)
     (define bytes (open-output-bytes))
     (define out
       (partial-output bytes 4096
         (lambda ()
           (when (< count 3) (collect-garbage) (set! count (add1 count))))))
     (define reply (capture (lambda () (native-copy (open-input-bytes payload) out))))
     (check-equal? count 3)
     (check-equal? (get-output-bytes bytes) payload)
     (check-clean reply 1 1)
     (close-output-port out)
     (record 'gc reply))
   (test-case "input exception is re-raised after native stream destruction"
     (define sentinel (gensym 'input-failed))
     (define in (make-input-port 'throws (lambda (bytes) (raise sentinel))
                                 (lambda (bytes skip progress) (raise sentinel)) void))
     (define got
       (with-handlers ([(lambda (_) #t) values])
         (capture (lambda () (native-copy in (open-output-bytes))))))
     (check-eq? got sentinel)
     (check-failed-clean 1 1)
     (close-input-port in))
   (test-case "output can raise a non-exception value without crossing native frames"
     (define sentinel (gensym 'output-failed))
     (define out
       (make-output-port 'throws always-evt
                         (lambda (bytes start end nonblock? breakable?) (raise sentinel)) void))
     (define got
       (with-handlers ([(lambda (_) #t) values])
         (capture (lambda () (native-copy (open-input-bytes #"failure") out)))))
     (check-eq? got sentinel)
     (check-failed-clean 1 1)
     (close-output-port out))
   (test-case "a raised false value is preserved"
     (define out (make-output-port 'throws-false always-evt (lambda args (raise #f)) void))
     (define caught 'not-caught)
     (with-handlers ([(lambda (_) #t) (lambda (e) (set! caught e))])
       (capture (lambda () (native-copy (open-input-bytes #"x") out))))
     (check-false caught)
     (check-failed-clean 1 1)
     (close-output-port out))
   (test-case "reentrant live operation rejects without deadlocking"
     (define out
       (make-output-port 'reenter always-evt
         (lambda args
           (native-copy (open-input-bytes #"nested") (open-output-bytes))) void))
     (check-exn #rx"re-enter"
                (lambda () (capture (lambda () (native-copy (open-input-bytes #"x") out)))))
     (check-failed-clean 1 1)
     (close-output-port out))
   (test-case "input quota performs at most a one-byte excess probe"
     (define in (open-input-bytes payload))
     (check-exn #rx"byte limit"
                (lambda () (capture (lambda () (native-copy in (open-output-bytes) #:limit 1000)))))
     (check-equal? (file-position in) 1001)
     (check-failed-clean 1 1)
     (close-input-port in))
   (test-case "output quota fails and native PDF resources still close"
     (check-exn #rx"byte limit"
                (lambda () (capture (lambda () (native-document (open-output-bytes) 'pdf #:limit 16)))))
     (check-failed-clean 0 1))
   (test-case "cancellation releases a native worker blocked on input"
     (define-values (in out) (make-pipe 1))
     (define cancel (make-semaphore 0))
     (define signal (thread (lambda () (sleep 0.05) (semaphore-post cancel))))
     (check-exn #rx"cancelled"
                (lambda () (capture (lambda () (native-copy in (open-output-bytes)
                                                        #:cancel-evt (semaphore-peek-evt cancel))))))
     (thread-wait signal)
     (check-failed-clean 1 1)
     (close-input-port in) (close-output-port out))
   (test-case "cancellation releases a native worker blocked on output"
     (define-values (in out) (make-pipe 1))
     (define cancel (make-semaphore 0))
     (define signal (thread (lambda () (sleep 0.05) (semaphore-post cancel))))
     (check-exn #rx"cancelled"
                (lambda () (capture (lambda () (native-copy (open-input-bytes payload) out
                                                        #:cancel-evt (semaphore-peek-evt cancel))))))
     (thread-wait signal)
     (check-failed-clean 1 1)
     (close-input-port in) (close-output-port out))
   (test-case "caller break waits for native cleanup"
     (define-values (in out) (make-pipe 1))
     (define caught (box #f))
     (define caller
       (thread (lambda ()
                 (with-handlers ([(lambda (_) #t) (lambda (e) (set-box! caught e))])
                   (capture (lambda () (native-copy in (open-output-bytes))))))))
     (wait-for (lambda () (= (active-operation-count) 1)) "operation did not start")
     (break-thread caller)
     (thread-wait caller)
     (check-pred exn:break? (unbox caught))
     (check-failed-clean 1 1)
     (close-input-port in) (close-output-port out))
   (test-case "killed caller does not kill the callback service"
     (define-values (in out) (make-pipe 1))
     (define caller (thread (lambda () (capture (lambda () (native-copy in (open-output-bytes)))))))
     (wait-for (lambda () (= (active-operation-count) 1)) "operation did not start")
     (kill-thread caller)
     (wait-for (lambda () (= (active-operation-count) 0)) "native worker remained after caller death")
     (check-failed-clean 1 1)
     (close-input-port in) (close-output-port out))
   (test-case "caller custodian shutdown still permits native cleanup"
     (define cust (make-custodian))
     (parameterize ([current-custodian cust])
       (define-values (in out) (make-pipe 1))
       (thread (lambda () (capture (lambda () (native-copy in (open-output-bytes)))))))
     (wait-for (lambda () (= (active-operation-count) 1)) "operation did not start")
     (custodian-shutdown-all cust)
     (wait-for (lambda () (= (active-operation-count) 0)) "native worker remained after custodian shutdown")
     (check-failed-clean 1 1))
   (test-case "a subsequent operation succeeds after all failure paths"
     (define out (open-output-bytes))
     (define reply (capture (lambda () (native-copy (open-input-bytes #"still alive") out))))
     (check-equal? (get-output-bytes out) #"still alive")
     (check-clean reply 1 1))
   (test-case "seek is relative to the initial port position"
     (define in (open-input-bytes #"xxabcdef"))
     (file-position in 2)
     (define out (open-output-bytes))
     (define reply (capture (lambda () (native-seek-copy in out 6 3))))
     (check-equal? (get-output-bytes out) #"def")
     (check-equal? (file-position in) 8)
     (check-equal? (caddr reply) 6)
     (check-clean reply 1 1))
   (test-case "real codec decodes delayed nonseekable input"
     (define-values (in out) (make-pipe 13))
     (define producer
       (thread (lambda ()
                 (for ([i (in-range 0 (bytes-length png-input) 11)])
                   (write-bytes png-input out i (min (+ i 11) (bytes-length png-input)))
                   (sleep 0.001))
                 (close-output-port out))))
     (define reply (capture (lambda () (native-decode in))))
     (thread-wait producer)
     (check-equal? (vector-ref (car reply) 1) rgba-input)
     (check-equal? (vector-ref (car reply) 2) 32)
     (check-equal? (vector-ref (car reply) 3) 24)
     (check-clean reply 1 0)
     (save "decoded.rgba" (vector-ref (car reply) 1))
     (close-input-port in)
     (record 'decode reply))
   (test-case "truncated codec input rejects and destroys the consumed stream"
     (check-exn exn:fail?
                (lambda () (capture (lambda () (native-decode (open-input-bytes (subbytes png-input 0 16)))))))
     (check-equal? (active-operation-count) 0)
     (check-equal? (hash-ref (hash-ref (last-operation-report) 'notes) 'input-destroyed 0) 1))
   (test-case "decode dimensions are checked before pixel allocation"
     (check-exn exn:fail?
                (lambda () (capture (lambda () (native-decode (open-input-bytes png-input) #:limit 2048)))))
     (check-equal? (active-operation-count) 0))
   (test-case "native encoders write through partial Racket ports"
     (for ([format (in-list '(png jpeg webp))])
       (define bytes (open-output-bytes))
       (define out (partial-output bytes 11))
       (define reply (capture (lambda () (native-encode rgba-input 32 24 out #:format format))))
       (check-clean reply 0 1)
       (check-equal? (bytes-length (get-output-bytes bytes)) (cadddr reply))
       (save (string-append "encoded." (symbol->string format)) (get-output-bytes bytes))
       (record format reply)
       (close-output-port out)))
   (test-case "native PDF and SVG call the managed stream during publication"
     (for ([format (in-list '(pdf svg))])
       (define bytes (open-output-bytes))
       (define out (partial-output bytes 13))
       (define reply (capture (lambda () (native-document out format))))
       (check-clean reply 0 1)
       (when (eq? format 'svg)
         (check-true (positive? (hash-ref (notes reply) 'bytes-before-close 0))))
       (check-equal? (cadddr reply) (bytes-length (get-output-bytes bytes)))
       (save (string-append "document." (symbol->string format)) (get-output-bytes bytes))
       (record format reply)
       (close-output-port out)))
   (test-case "all worker operations and managed streams have finished"
     (check-equal? (active-operation-count) 0))))
(define failures (run-tests tests))
(define report
  (hasheq 'schema 1 'stage "0.75b-pure-ffi-probe" 'status (if (zero? failures) "passed" "failed")
          'run_token token 'racket_version (version) 'vm (symbol->string (system-type 'vm))
          'os (symbol->string (system-type 'os)) 'native_version "119.0"
          'test_cases 25 'failures failures 'active_operations (active-operation-count)
          'compiler_required #f 'callback_thread "protected Racket service thread"
          'operations reports))
(call-with-output-file (build-path directory "native-report.json")
  (lambda (out) (write-json report out) (newline out)) #:exists 'error)
(printf "pure-ffi-native: 25 cases, ~a failures\n" failures)
(exit (if (zero? failures) 0 1))
