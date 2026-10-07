#lang racket/base
;; Pure Racket buffering. No Skia calls, native callbacks or handle borrows.
(require "check.rkt")
(provide stream-byte-limit stream-count stream-slice check-stream-cancel
         read-port-buffered write-port-buffered)

(define (stream-byte-limit who limit)
  (unless (and (exact-positive-integer? limit) (<= limit (min #x7fffffff (current-skia-byte-limit))))
    (raise-argument-error who "positive byte limit <= min(2147483647, current-skia-byte-limit)" limit))
  limit)
(define (stream-count who n limit)
  (unless (and (exact-nonnegative-integer? n) (<= n limit))
    (raise-arguments-error who "byte count exceeds the stream/operation limit"
                           "count" n "limit" limit))
  n)
(define (stream-slice who bs start end)
  (unless (bytes? bs) (raise-argument-error who "bytes?" bs))
  (define stop (if end end (bytes-length bs)))
  (unless (and (exact-nonnegative-integer? start) (exact-nonnegative-integer? stop)
               (<= start stop (bytes-length bs)))
    (raise-arguments-error who "invalid byte range" "start" start "end" stop))
  (values start stop))
(define (cancel-event who value)
  (unless (or (not value) (evt? value))
    (raise-argument-error who "#f or evt?" value))
  (and value (wrap-evt value (lambda results 'cancelled))))
(define (cancel! who) (error who "port transfer cancelled; partial I/O is not rolled back"))
(define (check-stream-cancel who event)
  (define wrapped (cancel-event who event))
  (when (and wrapped (sync/timeout 0 wrapped)) (cancel! who)))
(define (wait-ready who port event)
  (define wrapped (cancel-event who event))
  (when (eq? (if wrapped (sync port wrapped) (sync port)) 'cancelled)
    (cancel! who)))
(define (call-with-port-policy who port input? close? thunk)
  (unless ((if input? input-port? output-port?) port)
    (raise-argument-error who (if input? "input-port?" "output-port?") port))
  (unless (boolean? close?) (raise-argument-error who "boolean?" close?))
  (when (port-closed? port) (error who "port is closed"))
  ;; No continuation can re-enter a transfer after its owned port was closed.
  ;; Preserve the original raised value even when a user-defined close also fails.
  (define completed? #f)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       void
       (lambda () (begin0 (thunk) (set! completed? #t)))
       (lambda ()
         (when (and close? (not (port-closed? port)))
           (define (close) ((if input? close-input-port close-output-port) port))
           (if completed? (close)
               (with-handlers ([(lambda (_) #t) (lambda (_) (void))]) (close)))))))))

(define (read-port-buffered who in limit close? cancel)
  (stream-byte-limit who limit)
  (cancel-event who cancel) ; validate before taking ownership or reading
  (call-with-port-policy who in #t close?
    (lambda ()
      (define out (open-output-bytes))
      (define scratch (make-bytes (min 65536 (add1 limit))))
      (let loop ([total 0])
        (check-stream-cancel who cancel)
        ;; A one-byte over-limit probe distinguishes exact-bound EOF from excess
        ;; input. On failure, at most limit+1 bytes have been consumed.
        (define n (read-bytes-avail!* scratch in 0 (min (bytes-length scratch) (add1 (- limit total)))))
        (cond [(eof-object? n) (bytes->immutable-bytes (get-output-bytes out))]
              [(procedure? n) (error who "binary stream input cannot contain special values")]
              [(zero? n) (wait-ready who in cancel) (loop total)]
              [else
               (define next (+ total n))
               (stream-count who next limit)
               (write-bytes scratch out 0 n)
               (loop next)])))))

(define (write-port-buffered who bs out close? cancel)
  (unless (bytes? bs) (raise-argument-error who "bytes?" bs))
  (stream-count who (bytes-length bs) (current-skia-byte-limit))
  (cancel-event who cancel)
  (define snapshot (bytes->immutable-bytes bs))
  (call-with-port-policy who out #f close?
    (lambda ()
      (define size (bytes-length snapshot))
      (let loop ([position 0])
        (check-stream-cancel who cancel)
        (cond [(= position size) size]
              [else
               (define n (write-bytes-avail* snapshot out position (min size (+ position 65536))))
               (if (and n (positive? n))
                   (loop (+ position n))
                   (begin (wait-ready who out cancel) (loop position)))])))))
