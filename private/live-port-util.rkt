#lang racket/base

;;;
;;; Live Port Validation
;;;

;; Checks port capabilities, cancellation, limits, and execution ownership.
;; Shares preflight validation across streaming image and document operations.

;; Pure validation and bounded SVG root transformation. No native calls.
(require "stream-buffer.rkt" "check.rkt" (only-in "live-port-runtime.rkt" in-port-service?))
(provide live-port-options live-read-chunk live-write-all make-svg-header-filter
         check-live-cancel live-pause current-live-port-operation)

;;;
;;; Operation Options and Cancellation
;;;

; current-live-port-operation : (parameter/c any/c)
;   Marks the public live-operation scope to reject reentry from user port callbacks.
(define current-live-port-operation (make-parameter #f))

; check-live-cancel : symbol? (or/c #f evt?) -> void?
;   Applies the shared stream cancellation check before further port I/O.
(define (check-live-cancel who event) (check-stream-cancel who event))

; live-pause : symbol? (or/c #f evt?) -> void?
;   Briefly yields when a nonblocking port makes no progress, checking cancellation on both sides.
(define (live-pause who event)
  (check-live-cancel who event) (sleep 0.001) (check-live-cancel who event))

; live-port-options : symbol? any/c any/c any/c boolean? boolean? boolean? exact-positive-integer?
;   any/c -> (or/c #f exact-nonnegative-integer?)
;   Checks distinct open ports, limits, close flags, and seek requirements before callbacks;
;   returns the input seek base when applicable.
(define (live-port-options who in out length seekable? close-in? close-out? limit cancel)
  (stream-byte-limit who limit)
  (for ([flag (in-list (list seekable? close-in? close-out?))])
    (unless (boolean? flag) (raise-argument-error who "boolean?" flag)))
  (unless (or (not cancel) (evt? cancel)) (raise-argument-error who "#f or evt?" cancel))
  (unless (or (not length) (and (exact-nonnegative-integer? length) (<= length limit)))
    (raise-argument-error who "#f or exact input length within byte limit" length))
  (when (or (current-live-port-operation) (in-port-service?))
    (error who "live port operations cannot re-enter from a port callback"))
  (for ([p (in-list (list in out))] [input? (in-list '(#t #f))] #:when p)
    (unless ((if input? input-port? output-port?) p)
      (raise-argument-error who (if input? "input-port?" "output-port?") p))
    (when (port-closed? p) (error who "port is closed")))
  (unless (or in out) (error who "an input or output port is required"))
  (when (and in out (eq? in out)) (error who "input and output ports must be distinct"))
  (when (and seekable? (or (not in) (not length)))
    (error who "seekable input requires an input port and an explicit #:length"))
  (define base (and seekable? (file-position in)))
  (when (and seekable? (not (exact-nonnegative-integer? base)))
    (error who "input cannot report an exact position"))
  base)

;;;
;;; Port Transfers and SVG Header Filtering
;;;

; live-read-chunk : symbol? input-port? exact-nonnegative-integer? boolean? any/c -> (values bytes?
;   boolean?)
;   Reads or peeks at most 65536 binary bytes, returning the bytes and whether EOF ended the
;   request.
(define (live-read-chunk who in count peek? cancel)
  (unless (and (exact-nonnegative-integer? count) (<= count 65536))
    (error who "invalid native chunk request"))
  (define bytes (make-bytes count))
  (let loop ([at 0])
    (check-live-cancel who cancel)
    (cond [(= at count) (values bytes #f)]
          [else
           (define n (if peek? (peek-bytes-avail!* bytes at #f in at count)
                         (read-bytes-avail!* bytes in at count)))
           (cond [(eof-object? n) (values (subbytes bytes 0 at) #t)]
                 [(procedure? n) (error who "binary input cannot contain special values")]
                 [(zero? n) (live-pause who cancel) (loop at)]
                 [else (loop (+ at n))])])) )

; live-write-all : symbol? output-port? bytes? box? exact-positive-integer? any/c -> void?
;   Writes a bounded chunk completely, updating the published-byte counter after each successful
;   partial write.
(define (live-write-all who out bytes published limit cancel)
  (stream-count who (+ (unbox published) (bytes-length bytes)) limit)
  (let loop ([at 0])
    (check-live-cancel who cancel)
    (unless (= at (bytes-length bytes))
      (define n (write-bytes-avail* bytes out at (bytes-length bytes)))
      (cond [(and n (positive? n))
             (set-box! published (+ (unbox published) n)) (loop (+ at n))]
            [else (live-pause who cancel) (loop at)]))))
;; Rewrite only a bounded native-produced root tag, never a whole XML document.

; make-svg-header-filter : symbol? real? real? -> (values procedure? procedure?)
;   Creates a streaming point-size SVG root rewrite with a 16-KiB header bound, plus a finish check
;   that rejects incomplete headers.
(define (make-svg-header-filter who width height)
  (define buffered #"") (define complete? #f)
  (define dimensions
    (string->bytes/utf-8
     (format "<svg width=\"~apt\" height=\"~apt\" viewBox=\"0 0 ~a ~a\"" width height width height)))
  (define (filter bytes)
    (cond [complete? bytes]
          [else
           (set! buffered (bytes-append buffered bytes))
           (define found (regexp-match-positions #px#"<svg\\s[^>]*>" buffered))
           (cond
             [found
              (define start (caar found)) (define end (cdar found))
              (when (> end 16384) (error who "native SVG header exceeds 16 KiB"))
              (define root (subbytes buffered start end))
              (for ([name (in-list (list #px#"\\swidth=\"[^\"]*\"" #px#"\\sheight=\"[^\"]*\""))])
                (unless (= (length (regexp-match* name root)) 1)
                  (error who "native SVG has missing/duplicate dimensions")))
              (define clean (regexp-replace* #px#"\\s(?:width|height|viewBox)=\"[^\"]*\"" root #""))
              (define replaced (regexp-replace #rx#"<svg" clean dimensions))
              (define out (bytes-append (subbytes buffered 0 start) replaced (subbytes buffered end)))
              (set! buffered #"") (set! complete? #t) out]
             [else
              (when (> (bytes-length buffered) 16384) (error who "native SVG root was not found"))
              #""])]))
  (values filter (lambda () (unless complete? (error who "native SVG root header is incomplete")))))
