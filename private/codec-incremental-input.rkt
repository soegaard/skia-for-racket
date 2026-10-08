#lang racket/base
;; Feed storage and PNG framing, independent of Skia and the foreign callbacks.
;; Native PNG resumption in m119 must stop between complete chunks. We never
;; splice/re-encode IDAT data, rewind an active decode, or decode pixels here.
(provide make-incremental-input incremental-input? incremental-input-size
         incremental-input-visible incremental-input-final? incremental-input-kind
         incremental-input-error incremental-input-destroys incremental-input-streams
         set-incremental-input-error! set-incremental-input-destroys!
         set-incremental-input-streams! incremental-input-append!
         incremental-input-slice incremental-input-discard!)
(struct incremental-input ([storage #:mutable] [size #:mutable] [visible #:mutable]
                           [final? #:mutable] [kind #:mutable] [framed #:mutable]
                           limit [error #:mutable] [destroys #:mutable] [streams #:mutable])
  #:constructor-name make-input)
(define signature #"\211PNG\r\n\32\n")
(define (make-incremental-input limit)
  (unless (and (exact-positive-integer? limit) (<= limit #x7fffffff))
    (raise-argument-error 'make-incremental-input "positive 31-bit byte limit" limit))
  (make-input #"" 0 0 #f 'unknown 8 limit #f 0 0))
(define (incremental-input-slice input start end)
  (unless (and (exact-nonnegative-integer? start) (exact-nonnegative-integer? end)
               (<= start end (incremental-input-size input)))
    (error 'incremental-input-slice "invalid retained-input range"))
  (subbytes (incremental-input-storage input) start end))
(define (frame! input)
  (define data (incremental-input-storage input))
  (define size (incremental-input-size input))
  (when (and (eq? (incremental-input-kind input) 'unknown) (>= size 8))
    (set-incremental-input-kind! input
      (if (bytes=? (subbytes data 0 8) signature) 'png 'other)))
  (cond
    [(incremental-input-final? input)
     ;; Final input may be truncated. Expose that tail exactly once; a native
     ;; incomplete result then becomes terminal, never a false success.
     (set-incremental-input-visible! input size)]
    [(eq? (incremental-input-kind input) 'png)
     (let loop ([at (incremental-input-framed input)])
       (set-incremental-input-visible! input at)
       (when (<= (+ at 8) size)
         (define length (integer-bytes->integer data #f #t at (+ at 4)))
         (unless (<= length #x7fffffff)
           (error 'codec-incremental-feed! "invalid PNG chunk length"))
         (define end (+ at 12 length))
         (unless (<= end (incremental-input-limit input))
           (error 'codec-incremental-feed! "PNG chunk exceeds the retained-input byte limit"))
         (when (<= end size)
           (set-incremental-input-framed! input end)
           (loop end))))]
    [else
     ;; Arbitrary partial-input behavior of other native formats is not an
     ;; audited promise. Their incremental mode can still be attempted on a
     ;; sealed input and must return native success, without a decode fallback.
     (set-incremental-input-visible! input 0)]))
(define (incremental-input-append! input data final? [limit #x7fffffff])
  (unless (bytes? data) (raise-argument-error 'codec-incremental-feed! "bytes?" data))
  (unless (boolean? final?) (raise-argument-error 'codec-incremental-feed! "boolean?" final?))
  (when (incremental-input-final? input) (error 'codec-incremental-feed! "input is already final"))
  (define old (incremental-input-size input))
  (define next (+ old (bytes-length data)))
  ;; Budget rejection leaves the existing prefix and final flag unchanged.
  (unless (<= next (min limit (incremental-input-limit input)))
    (error 'codec-incremental-feed! "input exceeds the retained-input byte limit"))
  (define storage (incremental-input-storage input))
  (when (> next (bytes-length storage))
    (define capacity (min (incremental-input-limit input) limit
                          (max next (* 2 (bytes-length storage)) 4096)))
    (define replacement (make-bytes capacity))
    (bytes-copy! replacement 0 storage 0 old)
    (set! storage replacement)
    (set-incremental-input-storage! input storage))
  (when (positive? (bytes-length data)) (bytes-copy! storage old data))
  (set-incremental-input-size! input next)
  (set-incremental-input-final?! input final?)
  (frame! input)
  (bytes-length data))
(define (incremental-input-discard! input)
  ;; Logical counters survive for detached diagnostics; no later read is legal
  ;; after the owning codec and all its native streams have been destroyed.
  (set-incremental-input-storage! input #""))
