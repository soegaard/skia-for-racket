#lang racket/base
(require rackunit rackunit/text-ui racket/port
         "../private/stream-buffer.rkt" "../private/check.rkt")
(provide stream-pure-tests stream-pure-test-count)
(define stream-pure-test-count 35) ; replaced from actual source case count
(define (read-buffer in [limit 32] [close? #f] [cancel #f])
  (read-port-buffered 'stream-test in limit close? cancel))
(define (write-buffer bs out [close? #f] [cancel #f])
  (write-port-buffered 'stream-test bs out close? cancel))
(define (short-input bs)
  (define position 0)
  (make-input-port 'short
    (lambda (buffer)
      (if (= position (bytes-length bs)) eof
          (begin (bytes-set! buffer 0 (bytes-ref bs position))
                 (set! position (add1 position)) 1)))
    #f void))
(define stream-pure-tests
  (test-suite "Stream buffers (pure Racket; no native callbacks)"
    (test-case "positive limit"
      (check-equal? (stream-byte-limit 'test 32) 32))
    (test-case "invalid limits"
      (for ([n (in-list '(0 -1 2.0 #f))])
        (check-exn exn:fail? (lambda () (stream-byte-limit 'test n)))))
    (test-case "current allocation ceiling"
      (parameterize ([current-skia-byte-limit 64])
        (check-exn exn:fail? (lambda () (stream-byte-limit 'test 65)))))
    (test-case "count bounds include zero"
      (check-equal? (stream-count 'test 0 3) 0)
      (check-equal? (stream-count 'test 3 3) 3)
      (check-exn exn:fail? (lambda () (stream-count 'test 4 3))))
    (test-case "byte ranges"
      (check-equal? (call-with-values (lambda () (stream-slice 'test #"abc" 1 #f)) list) '(1 3)))
    (test-case "invalid byte ranges"
      (for ([range (in-list '((-1 2) (2 1) (0 4) (0 2.0)))])
        (check-exn exn:fail? (lambda () (stream-slice 'test #"abc" (car range) (cadr range))))))
    (test-case "empty buffered input"
      (check-equal? (read-buffer (open-input-bytes #"")) #""))
    (test-case "binary bytes preserved"
      (check-equal? (read-buffer (open-input-bytes (bytes 0 255 13 10))) (bytes 0 255 13 10)))
    (test-case "current port position is the start"
      (define in (open-input-bytes #"prefixDATA"))
      (read-bytes 6 in)
      (check-equal? (read-buffer in) #"DATA"))
    (test-case "short reads are accumulated"
      (check-equal? (read-buffer (short-input #"abcdef")) #"abcdef"))
    (test-case "nonseekable input works"
      (define-values (in out) (make-pipe))
      (write-bytes #"pipe" out) (close-output-port out)
      (check-equal? (read-buffer in) #"pipe") (close-input-port in))
    (test-case "exact limit plus EOF succeeds"
      (check-equal? (read-buffer (open-input-bytes #"1234") 4) #"1234"))
    (test-case "excess input fails without reading beyond one-byte probe"
      (define in (open-input-bytes #"123456"))
      (check-exn exn:fail? (lambda () (read-buffer in 4)))
      (check-equal? (read-byte in) (char->integer #\6)))
    (test-case "input is borrowed by default"
      (define in (open-input-bytes #"a")) (read-buffer in)
      (check-false (port-closed? in)))
    (test-case "owned input closes on success"
      (define in (open-input-bytes #"a")) (read-buffer in 32 #t)
      (check-true (port-closed? in)))
    (test-case "owned input closes on failure"
      (define in (open-input-bytes #"oversize"))
      (check-exn exn:fail? (lambda () (read-buffer in 2 #t)))
      (check-true (port-closed? in)))
    (test-case "borrowed input remains open on failure"
      (define in (open-input-bytes #"oversize"))
      (check-exn exn:fail? (lambda () (read-buffer in 2)))
      (check-false (port-closed? in)))
    (test-case "ready cancellation consumes no input"
      (define in (open-input-bytes #"abc"))
      (check-exn #rx"cancelled" (lambda () (read-buffer in 32 #f always-evt)))
      (check-equal? (read-byte in) 97))
    (test-case "multi-valued cancellation event is still cancellation"
      (define stop (wrap-evt always-evt (lambda (_) (values #f 'ready))))
      (check-exn #rx"cancelled" (lambda () (read-buffer (open-input-bytes #"x") 32 #f stop))))
    (test-case "cancellation wakes an empty pipe wait"
      (define-values (in out) (make-pipe))
      (define stop (make-semaphore))
      (define worker (thread (lambda () (sleep 0.01) (semaphore-post stop))))
      (check-exn #rx"cancelled" (lambda () (read-buffer in 32 #t (semaphore-peek-evt stop))))
      (thread-wait worker) (check-true (port-closed? in)) (close-output-port out))
    (test-case "invalid cancellation is rejected before reading"
      (define in (open-input-bytes #"abc"))
      (check-exn exn:fail? (lambda () (read-buffer in 32 #t 'invalid)))
      (check-false (port-closed? in)) (check-equal? (read-byte in) 97))
    (test-case "invalid ownership flag is rejected"
      (check-exn exn:fail? (lambda () (read-buffer (open-input-bytes #"") 32 'yes))))
    (test-case "closed input rejected"
      (define in (open-input-bytes #"a")) (close-input-port in)
      (check-exn exn:fail? (lambda () (read-buffer in))))
    (test-case "arbitrary read exception survives cleanup"
      (define in (make-input-port 'failure (lambda (_) (raise 'read-failure)) #f
                                  (lambda () (raise 'close-failure))))
      (check-exn (lambda (e) (eq? e 'read-failure)) (lambda () (read-buffer in 32 #t))))
    (test-case "empty buffered output"
      (define out (open-output-bytes))
      (check-equal? (write-buffer #"" out) 0)
      (check-equal? (get-output-bytes out) #""))
    (test-case "binary output preserved"
      (define out (open-output-bytes))
      (check-equal? (write-buffer (bytes 0 255 13 10) out) 4)
      (check-equal? (get-output-bytes out) (bytes 0 255 13 10)))
    (test-case "short writes are completed"
      (define captured (open-output-bytes))
      (define out (make-output-port 'short always-evt
                    (lambda (bs start end _block? _break?)
                      (define n (min 2 (- end start)))
                      (write-bytes bs captured start (+ start n)) n) void))
      (check-equal? (write-buffer #"abcdefg" out) 7)
      (check-equal? (get-output-bytes captured) #"abcdefg"))
    (test-case "borrowed output remains open"
      (define out (open-output-bytes)) (write-buffer #"a" out)
      (check-false (port-closed? out)))
    (test-case "owned output closes after write"
      (define out (open-output-bytes)) (write-buffer #"a" out #t)
      (check-true (port-closed? out)))
    (test-case "ready cancellation writes no bytes"
      (define out (open-output-bytes))
      (check-exn #rx"cancelled" (lambda () (write-buffer #"abc" out #f always-evt)))
      (check-equal? (get-output-bytes out) #""))
    (test-case "cancellation preserves a partial output prefix"
      (define-values (in out) (make-pipe 1))
      (define stop (make-semaphore))
      (define worker (thread (lambda () (sync in) (semaphore-post stop))))
      (check-exn #rx"cancelled" (lambda () (write-buffer #"abc" out #t (semaphore-peek-evt stop))))
      (thread-wait worker)
      (check-equal? (read-bytes 10 in) #"a") (close-input-port in))
    (test-case "write error propagates after a prefix"
      (define captured (open-output-bytes))
      (define calls 0)
      (define out (make-output-port 'fail always-evt
                    (lambda (bs start end _block? _break?)
                      (set! calls (add1 calls))
                      (if (= calls 1)
                          (begin (write-bytes bs captured start (add1 start)) 1)
                          (raise 'write-failure))) void))
      (check-exn (lambda (e) (eq? e 'write-failure)) (lambda () (write-buffer #"abcd" out)))
      (check-equal? (get-output-bytes captured) #"a"))
    (test-case "closed output rejected"
      (define out (open-output-bytes)) (close-output-port out)
      (check-exn exn:fail? (lambda () (write-buffer #"a" out))))
    (test-case "chunk boundary input"
      (define bs (make-bytes 65540 37))
      (check-equal? (read-buffer (open-input-bytes bs) 65540) bs))
    (test-case "chunk boundary output"
      (define bs (make-bytes 65540 37)) (define out (open-output-bytes))
      (check-equal? (write-buffer bs out) 65540)
      (check-equal? (get-output-bytes out) bs))))
(module+ main
  (define failures (run-tests stream-pure-tests))
  (printf "stream-pure: ~a cases, ~a failures\n" stream-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
