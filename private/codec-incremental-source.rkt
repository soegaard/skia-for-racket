#lang racket/base

;;;
;;; Incremental Codec Stream Callbacks
;;;

;; Registers incremental inputs and services native read and seek requests.
;; Connects the incremental decoder to Skia's callback-based stream interface.

;; Shared Skia managed-stream provider dispatch for bounded in-memory sources.
;; This module never installs callback tables. Unlike live Racket ports, these
;; callbacks perform only memory operations and may safely run synchronously in
;; atomic mode. Their context registry retains input storage, not a session or
;; owned handle; session finalization can therefore destroy its native codec.
(require ffi/unsafe "codec-incremental-input.rkt")
(provide incremental-source-register! incremental-source-unregister!
         incremental-source-callback incremental-source-count)
(struct source (input context [position #:mutable]))
;; Fields:
;;   input: incremental-input buffer. context: native registration context pointer. position:
;;   mutable nonnegative read cursor within the visible input prefix. Registration keeps the input
;;   reachable until native stream destruction.

; sources : hash?
;   Roots stream callback state by raw context address until each native stream is destroyed.
(define sources (make-hasheqv))

; key : cpointer? -> exact-nonnegative-integer?
;   Converts a native callback context address to its registry key.
(define (key p) (cast p _pointer _uintptr))

; incremental-source-count : -> exact-nonnegative-integer?
;   Counts retained stream contexts for leak and cleanup diagnostics.
(define (incremental-source-count) (hash-count sources))

; incremental-source-register! : incremental-input? -> cpointer?
;   Allocates a unique stream context, roots its input state, and starts its cursor at zero.
(define (incremental-source-register! input)
  (define context (malloc 1 'raw))
  (unless context (error 'make-codec-incremental "native stream context allocation failed"))
  (hash-set! sources (key context) (source input context 0))
  (set-incremental-input-streams! input (add1 (incremental-input-streams input)))
  context)

; incremental-source-unregister! : cpointer? -> void?
;   Unroots and frees a known context exactly once, updating input destruction diagnostics.
(define (incremental-source-unregister! context)
  (define s (hash-ref sources (key context) #f))
  (when s
    (hash-remove! sources (key context))
    (define input (source-input s))
    (set-incremental-input-destroys! input (add1 (incremental-input-destroys input)))
    (free (source-context s)))
  (void))

; read! : source? (or/c #f cpointer?) exact-nonnegative-integer? boolean? ->
;   exact-nonnegative-integer?
;   Copies or skips only visible bytes, leaving the cursor unchanged for peek requests.
(define (read! s destination requested peek?)
  (define input (source-input s))
  (define at (source-position s))
  (define n (min requested (- (incremental-input-visible input) at)))
  (when destination
    (let loop ([done 0])
      (when (< done n)
        (define count (min 65536 (- n done)))
        (define bytes (incremental-input-slice input (+ at done) (+ at done count)))
        (memcpy (ptr-add destination done) bytes count)
        (loop (+ done count)))))
  (unless peek? (set-source-position! s (+ at n)))
  n)

; seek! : source? exact-integer? -> boolean?
;   Moves the stream cursor only within the currently visible encoded prefix.
(define (seek! s at)
  (and (<= 0 at (incremental-input-visible (source-input s)))
       (begin (set-source-position! s at) #t)))

; incremental-source-callback : symbol? any/c list? -> any/c
;   Dispatches memory-only stream operations, capturing failures for re-raise after native frames
;   unwind.
(define (incremental-source-callback kind fallback arguments)
  (define context (cadr arguments))
  (define s (hash-ref sources (key context) #f))
  (cond
    [(not s) fallback]
    [else
     (define input (source-input s))
     ;; Never unwind a Skia frame. An exceptional condition becomes a native
     ;; failure return, then is raised by the Racket session after C returns.
     (with-handlers ([(lambda (_) #t)
                      (lambda (e)
                        (unless (incremental-input-error input)
                          (set-incremental-input-error! input (cons #t e)))
                        fallback)])
       (cond
         [(eq? kind 'destroy) (incremental-source-unregister! context)]
         [(incremental-input-error input) fallback]
         [else
          (case kind
            [(read) (read! s (caddr arguments) (cadddr arguments) #f)]
            [(peek) (read! s (caddr arguments) (cadddr arguments) #t)]
            [(at-end) (= (source-position s) (incremental-input-visible input))]
            [(has-position) #t]
            [(has-length) (incremental-input-final? input)]
            [(position) (source-position s)]
            [(length) (incremental-input-visible input)]
            [(rewind) (seek! s 0)]
            [(seek) (seek! s (caddr arguments))]
            [(move) (seek! s (+ (source-position s) (caddr arguments)))]
            [(duplicate fork) #f]
            [else fallback])]))]))
