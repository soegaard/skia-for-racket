#lang racket/base

;;;
;;; Drawing Context Output Capture
;;;

;; Records bounded drawing-context commands for later replay.
;; Allows document output to inspect and replay Racket drawing operations.

;; A short-lived command capture, not a second public recording format.
;; Requests come from the production DC state machine; no Cairo pixel renderer.

;;;
;;; Imports and Exports
;;;

(require racket/class racket/future racket/list racket/runtime-path
         "dc-class.rkt" "dc-support.rkt" "dc-bitmap.rkt"
         (submod "dc-class.rkt" canvas)
         (only-in "dc-region-adapter.rkt" dc-region-query-info)
         (only-in "check.rkt" current-skia-byte-limit))
(provide capture-output-dc skia-output-dc? output-dc-capabilities
         current-output-dc-command-limit output-dc-size output-dc-procedure!
         output-dc-special! (struct-out output-dc-command))
;;;
;;; Capture Records and Limits
;;;

(struct output-dc-command (kind arguments) #:transparent)
;; Fields:
;;   kind: 'path, 'clear, 'text, 'bitmap, 'alpha, 'url, 'destination, 'link, or 'raster. arguments:
;;   detached positional argument list for that kind's replay operation. Alpha arguments contain
;;   ordered child commands, parent clip, and opacity. Special commands contain payload, matrix,
;;   clip, and alpha in that order. The tag determines the payload layout; no live output DC is
;;   retained by a command.

(struct target ([reverse-commands #:mutable] [closed? #:mutable]))
;; Fields:
;;   reverse-commands: mutable list of output-dc-command records, newest first; reverse it for
;;   replay. closed?: mutable flag rejecting further capture after target closure.

; add-output-command! : local-member-name binding
;   Reserves the capture-only command insertion method outside ordinary public DC dispatch.
(define-local-member-name add-output-command!)

; output-dc<%> : interface?
;   Marks short-lived document DCs so annotation and raster-group helpers can reject ordinary raster
;   DCs.
(define output-dc<%> (interface ()))

; skia-output-dc? : any/c -> boolean?
;   Returns whether v is one of the callback-scoped output DC values.
(define (skia-output-dc? value) (is-a? value output-dc<%>))

; current-output-dc-command-limit : (parameter/c exact-positive-integer?)
;   Bounds the total recorded operations, including commands inside isolated alpha groups.
(define current-output-dc-command-limit
  (make-parameter 100000
    (lambda (n)
      (unless (exact-positive-integer? n)
        (raise-argument-error 'current-output-dc-command-limit "exact-positive-integer?" n))
      n)))

; capture-active? : (parameter/c boolean?)
;   Tracks dynamic capture nesting so a document callback cannot recursively start another output DC.
(define capture-active? (make-parameter #f))

; native-renderer-module : path?
;   Locates the native renderer used lazily for font metrics and path bounds during capture.
(define-runtime-path native-renderer-module "dc-render.rkt")

; native-renderer : -> dc-renderer/styles?
;   Loads the shared renderer only when capture needs native measurement or path-query callbacks.
(define (native-renderer)
  (dynamic-require native-renderer-module 'skia-dc-renderer))

; output-dc-size : symbol? real? real? -> (values real? real?)
;   Validates positive logical output dimensions no larger than 32768 without allocating raster
;   storage.
(define (output-dc-size who width height)
  (define w (dc-real who width))
  (define h (dc-real who height))
  (unless (and (< 0 w) (<= w 32768) (< 0 h) (<= h 32768))
    (raise-arguments-error who "logical dimensions must be positive and at most 32768"
                           "width" width "height" height))
  (values w h))

; output-dc-procedure! : symbol? procedure? exact-nonnegative-integer? -> void?
;   Checks a callback's positional arity and rejects required keywords.
(define (output-dc-procedure! who proc arity)
  (unless (and (procedure? proc) (procedure-arity-includes? proc arity)
               (let-values ([(required _allowed) (procedure-keywords proc)]) (null? required)))
    (raise-argument-error who (format "procedure accepting ~a arguments, no required keywords" arity)
      proc)))

; output-dc-capabilities : -> (and/c hash? immutable?)
;   Returns detached declarations for the output-DC compatibility surface.
(define (output-dc-capabilities)
  (hash-set* (dc-capabilities)
    'stage "0.63" 'class "callback-scoped-output-dc" 'storage "deferred-vector-commands"
    'lifetime "callback only; expired before native document replay"
    'coordinates "logical; inherited page units, margins and transform applied at replay"
    'alpha_groups "isolated command groups; document backend policy decides representation"
    'snapshot "unsupported: use output-page->image for an explicit page preview"
    'drawing (remq 'copy (remq 'erase (hash-ref (dc-capabilities) 'drawing)))
    'annotations '(url named-destination destination-link)
    'explicit_raster_group #t
    'deferred '(copy erase pixel-size native-handle-brushes arbitrary-combined-text-breaks)))

; output-dc-special! : (is-a?/c output-dc<%>) symbol? list? -> void?
;   Adds a supported annotation or explicit raster command through the active capture DC's lifetime
;   checks.
(define (output-dc-special! dc kind arguments)
  (unless (skia-output-dc? dc)
    (raise-argument-error 'output-dc-special! "skia-output-dc?" dc))
  (send dc add-output-command! kind arguments))

;;;
;;; Callback-Scoped Command Capture
;;;

; capture-output-dc : real? real? procedure? [#:background any/c #:smoothing symbol?] -> (values
; (listof output-dc-command?) exact-nonnegative-integer?)
;   Runs a callback once, expires its DC, and returns ordered detached commands plus the total
;   captured command count.
(define (capture-output-dc width height draw
                           #:background [background "white"]
                           #:smoothing [smoothing 'smoothed])
  (define who 'call-with-output-dc)
  (define-values (w h) (output-dc-size who width height))
  (output-dc-procedure! who draw 1)
  (when (or (capture-active?) (current-future))
    (error who "nested output DC capture and construction in futures are not supported"))
  (define count 0)
  (define payload-bytes 0)
  ;; A conservative queue budget, not a census of all Racket/native memory.
  ;; Repeated children in a completed alpha command may be counted twice.
  ;; Crucially, many legal individual bitmap requests cannot accumulate an
  ;; unbounded copied-pixel queue. Vector extents themselves reserve no pixels.
  (define (payload-size value)
    (cond [(bytes? value) (bytes-length value)]
          [(string? value) (string-utf-8-length value)]
          [(pair? value) (+ 16 (payload-size (car value)) (payload-size (cdr value)))]
          [(vector? value) (+ (* 8 (vector-length value))
                             (for/sum ([v (in-vector value)]) (payload-size v)))]
          [(struct? value) (payload-size (struct->vector value))]
          [else 8]))
  (define root #f)
  (define live '())
  (define (create _pw _ph)
    (define t (target '() #f))
    (unless root (set! root t))
    (set! live (cons t live))
    t)
  (define (close t)
    (unless (target-closed? t)
      (set-target-closed?! t #t)
      (set-target-reverse-commands! t '())
      (set! live (remq t live))))
  (define (append! t kind args)
    (when (target-closed? t) (error who "output command target has expired"))
    (when (>= count (current-output-dc-command-limit))
      (error who "current-output-dc-command-limit exceeded"))
    (define next-bytes (+ payload-bytes (payload-size args)))
    (when (> next-bytes (current-skia-byte-limit))
      (error who "queued command payload exceeds current-skia-byte-limit"))
    (set! payload-bytes next-bytes)
    (set! count (add1 count))
    (set-target-reverse-commands! t
      (cons (output-dc-command kind args) (target-reverse-commands t)))
    (void))
  (define (unsupported method)
    (lambda args (dc-unsupported method 'document-has-no-readable-pixel-backing
                                 "0.63: use draw-dc-raster-group for pixel operations")))
  (define renderer
    (dc-renderer/styles
     create close
     (lambda (t command) (append! t 'path (list command)))
     (lambda (t clip rgba erase?)
       (when erase? ((unsupported 'erase)))
       (append! t 'clear (list clip rgba #f)))
     (unsupported 'snapshot) (unsupported 'get-rgba-bytes) (unsupported 'get-png-bytes)
     (lambda args (apply (dc-renderer+-measure-text (native-renderer)) args))
     (lambda (t . args) (append! t 'text args))
     (lambda args (apply (dc-renderer+-glyph-exists? (native-renderer)) args))
     (lambda (t data rect matrix clip opacity sampling)
       (define frozen
         (struct-copy dc-bitmap-data data
           [pixels (bytes->immutable-bytes (dc-bitmap-data-pixels data))]))
       (append! t 'bitmap (list frozen (vector->immutable-vector rect) matrix clip opacity sampling)))
     (unsupported 'copy)
     (lambda (parent child clip opacity)
       (append! parent 'alpha (list (reverse (target-reverse-commands child)) clip opacity)))
     (lambda args (apply (dc-renderer/styles-path-bounds (native-renderer)) args))))
  (define base% (make-skia-dc-class renderer))
  (define document-dc%
    (class* base% (output-dc<%>)
      (super-new)
      (define/override (get-size) (super get-size) (values w h))
      (define/override (get-pixel-size)
        (super get-size) ((unsupported 'get-pixel-size)))
      (define/override (get-capabilities) (super get-capabilities) (output-dc-capabilities))
      (define/override (dc-region-query-info)
        (define-values (_w _h matrix clip) (super dc-region-query-info))
        (values w h matrix clip))
      (define/public (add-output-command! kind arguments)
        ;; The inherited method checks owner, closed state and backing reentry.
        (define-values (_w _h matrix clip) (send this dc-region-query-info))
        (unless (pair? live) (error who "output capture has expired"))
        (when (and (memq kind '(url destination link)) (not (eq? (car live) root)))
          (dc-unsupported kind 'annotation-inside-alpha-group
            "0.63: annotate outside isolated groups"))
        (unless (memq kind '(url destination link raster))
          (error who "unknown private output command"))
        (append! (car live) kind (list arguments matrix clip (send this get-alpha))))))
  (define dc #f)
  (define entered? #f)
  (call-with-continuation-barrier
   (lambda ()
     (parameterize ([capture-active? #t])
       (dynamic-wind
        (lambda ()
          (when entered? (error who "an output DC capture cannot be reentered"))
          (set! entered? #t))
        (lambda ()
          ;; Ceil is for the inherited alpha-budget bookkeeping, not a raster
          ;; allocation. Public dimensions, clips and transforms remain logical.
          (set! dc (new document-dc% [width (inexact->exact (ceiling w))]
                         [height (inexact->exact (ceiling h))] [backing-scale 1.0]
                         [background background] [smoothing smoothing]))
          (call-with-dc-canvas-paint dc
            (lambda () (call-with-values (lambda () (draw dc)) (lambda ignored (void)))))
          ;; Unfinished alpha groups have been discarded by the real DC scope.
          (values (reverse (target-reverse-commands root)) count))
        (lambda ()
          (parameterize-break #f
            (dynamic-wind void
              (lambda () (when dc (send dc close)))
              (lambda () (for ([t (in-list live)]) (close t)) (set! root #f))))))))))
