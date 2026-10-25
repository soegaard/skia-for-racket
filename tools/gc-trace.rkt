#lang racket/base

;;;
;;; Individual Garbage-Collection Tracing
;;;

;; Converts Racket's GC log payloads into records that diagnostic launchers can save with GUI
;; and presenter spans. This developer tool does not change GC policy or load rendering code.

(provide gc-trace-enabled? make-gc-trace-receiver gc-log-message->record)

; current-gc-trace-enabled : (parameter/c boolean?)
;   Reads the opt-in once; parameterization is private test support.
(define current-gc-trace-enabled (make-parameter (equal? (getenv "SKIA_GC_TRACE") "1")))
(module+ test-support
  (provide current-gc-trace-enabled))

; gc-trace-enabled? : -> boolean?
;   Reports whether this diagnostic collector has been explicitly enabled.
(define (gc-trace-enabled?) (current-gc-trace-enabled))

; make-gc-trace-receiver : [logger?] -> (or/c #f log-receiver?)
;   Subscribes only when enabled; an existing receiver accepting GC can be used instead.
(define (make-gc-trace-receiver [logger (current-logger)])
  (and (gc-trace-enabled?) (make-log-receiver logger 'debug 'GC 'none)))

; gc-log-message->record : any/c -> (or/c #f hash?)
;   Copies a collection's payload times and sizes, ignoring the duplicate GC:major topic.
(define (gc-log-message->record message)
  (and (gc-trace-enabled?)
       (vector? message) (>= (vector-length message) 4)
       (eq? (vector-ref message 0) 'debug) (eq? (vector-ref message 3) 'GC)
       (let* ([datum (vector-ref message 2)]
              [fields (and (prefab-struct-key datum) (struct->vector datum))]
              [received-at (current-inexact-milliseconds)])
         ;; Racket documents ten fields, in this order, and permits future trailing fields.
         ;; Read the payload, not the unstable message text or the time the worker receives it.
         (cond
           [(and fields (eq? (prefab-struct-key datum) 'gc-info)
                 (>= (vector-length fields) 11)
                 (memq (vector-ref fields 1) '(major minor incremental))
                 (for/and ([i (in-range 2 11)])
                   (define value (vector-ref fields i))
                   (and (rational? value) (>= value 0)))
                 (<= (vector-ref fields 7) (vector-ref fields 8))
                 (<= (vector-ref fields 9) (vector-ref fields 10)))
            (hasheq 'type "gc" 'mode (symbol->string (vector-ref fields 1))
                    'pre_bytes (vector-ref fields 2) 'pre_admin_bytes (vector-ref fields 3)
                    'code_bytes (vector-ref fields 4) 'post_bytes (vector-ref fields 5)
                    'post_admin_bytes (vector-ref fields 6)
                    'cpu_start (vector-ref fields 7) 'cpu_end (vector-ref fields 8)
                    'cpu_ms (- (vector-ref fields 8) (vector-ref fields 7))
                    'start (vector-ref fields 9) 'end (vector-ref fields 10)
                    'wall_ms (- (vector-ref fields 10) (vector-ref fields 9))
                    'received_at received-at)]
           [else
            ;; Preserve a visible diagnostic failure instead of silently claiming there were no GCs.
            (hasheq 'type "gc-error" 'received_at received-at
                    'error "unsupported GC log payload")]))))
