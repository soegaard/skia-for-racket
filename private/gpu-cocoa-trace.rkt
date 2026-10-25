#lang racket/base

;;;
;;; Cocoa Presenter Diagnostics
;;;

;; Reads Racket's private flush state and observes the main Core Foundation run loop.
;; Helps distinguish drawable waits from delayed GUI progress without pumping or flushing events.

(require ffi/unsafe)
(provide make-cocoa-presenter-trace record-cocoa-presenter-trace! close-cocoa-presenter-trace!)

; current-metal-cocoa-trace-enabled : (parameter/c boolean?)
;   Enables private diagnostics independently of presenter timings and layer-update experiments.
(define current-metal-cocoa-trace-enabled
  (make-parameter (equal? (getenv "SKIA_METAL_COCOA_TRACE") "1")))

(struct metal-presenter-cocoa-state (time host phase fields) #:prefab)
;; Fields:
;;   time: epoch milliseconds before sampling. host: presenter identity string. phase: boundary
;;   symbol. fields: immutable copied state; unavailable observations carry errors, not false flags.
;;   Field order matches the layer-state record, but this record has its own type and logger topic.

(struct cocoa-trace (logger host sample close [closed? #:mutable]))
;; Fields:
;;   logger and host: diagnostic destination and identity captured at installation. sample: reads
;;   state for a borrowed window pointer without storing it. close: unregisters the observer and
;;   releases its callback. closed?: makes cleanup idempotent and prevents later observations.
;;   All operations run on the presenter's main OS thread; no observer owns a window or drawable.

; make-cocoa-presenter-trace : string? [(-> (values procedure? procedure?))] -> any/c
;   Installs an observer only with opt-in and a receiver; installation errors become diagnostics.
(define (make-cocoa-presenter-trace host [install install-cocoa-observer])
  (and (current-metal-cocoa-trace-enabled)
       (log-level? (current-logger) 'debug 'skia-metal-presenter-cocoa)
       (let-values ([(sample close)
                     (with-handlers ([exn:fail?
                                      (lambda (e)
                                        (values (lambda (window)
                                                  (hasheq 'installation_error (exn-message e)))
                                                void))])
                       (install))])
         (cocoa-trace (current-logger) host sample close #f))))

; record-cocoa-presenter-trace! : any/c symbol? any/c -> void?
;   Queues copied state without file I/O, event dispatch, a flush, or a GPU completion wait.
(define (record-cocoa-presenter-trace! trace phase window)
  (when (and trace (not (cocoa-trace-closed? trace)))
    (define time (current-inexact-milliseconds))
    (define start (current-inexact-monotonic-milliseconds))
    (define fields
      (with-handlers ([exn:fail? (lambda (e) (hasheq 'observation_error (exn-message e)))])
        ((cocoa-trace-sample trace) window)))
    (log-message (cocoa-trace-logger trace) 'debug 'skia-metal-presenter-cocoa
                 (format "~a: ~a" (cocoa-trace-host trace) phase)
                 (metal-presenter-cocoa-state
                  time (cocoa-trace-host trace) phase
                  (hash-set fields 'observation_ms
                            (- (current-inexact-monotonic-milliseconds) start))) #f))
  (void))

; close-cocoa-presenter-trace! : any/c -> void?
;   Removes the passive observer once, even if the opt-in parameter has subsequently changed.
(define (close-cocoa-presenter-trace! trace)
  (when (and trace (not (cocoa-trace-closed? trace)))
    ((cocoa-trace-close trace))
    (set-cocoa-trace-closed?! trace #t))
  (void))

;;;
;;; Read-Only Racket State and Native Run-Loop Observer
;;;

; private-reader : module-path? -> (symbol? -> any/c)
;   Reads an already instantiated GUI module; never changes its bindings or loads another GUI.
(define (private-reader module)
  (define ns (module->namespace module))
  (lambda (name)
    (parameterize ([current-namespace ns])
      (namespace-variable-value
       name #t (lambda () (error 'cocoa-trace "unavailable Racket binding: ~a" name))))))

; install-cocoa-observer : -> (values procedure? procedure?)
;   Observes run-loop phases in common modes without adding sources, wakeups, or dispatch hooks.
(define (install-cocoa-observer)
  (unless (eq? (system-type 'os) 'macosx) (error 'cocoa-trace "requires macOS"))
  (define main? (get-ffi-obj "pthread_main_np" #f (_fun -> _int)))
  (unless (= (main?) 1) (error 'cocoa-trace "requires the main OS thread"))
  ;; Private names are version-dependent. A missing binding is reported, never treated as #f.
  (define frame-read (private-reader 'mred/private/wx/cocoa/frame))
  (define queue-read (private-reader 'mred/private/wx/cocoa/queue))
  (define cf (ffi-lib "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"))
  (define main-loop (get-ffi-obj "CFRunLoopGetMain" cf (_fun -> _pointer)))
  (define common-modes (get-ffi-obj "kCFRunLoopCommonModes" cf _pointer))
  (define add (get-ffi-obj "CFRunLoopAddObserver" cf (_fun _pointer _pointer _pointer -> _void)))
  (define remove (get-ffi-obj "CFRunLoopRemoveObserver" cf
                            (_fun _pointer _pointer _pointer -> _void)))
  (define release (get-ffi-obj "CFRelease" cf (_fun _pointer -> _void)))
  (define keep-callback (box #f))
  (define create
    (get-ffi-obj "CFRunLoopObserverCreate" cf
                 (_fun _pointer _ulong _uint8 _long
                       (_fun #:atomic? #t #:async-apply (lambda (f) (f)) #:keep keep-callback
                             _pointer _ulong _pointer -> _void)
                       _pointer -> _pointer)))
  (define counts (make-hasheq))
  (define sequence 0)
  (define last-activity #f)
  (define last-time #f)
  (define callback-error #f)
  (define (observe observer activity context)
    ;; Do not call user code, read GUI namespaces, or log from the native callback.
    (with-handlers ([exn:fail? (lambda (e) (set! callback-error (exn-message e)))])
      (hash-set! counts activity (add1 (hash-ref counts activity 0)))
      (set! sequence (add1 sequence))
      (set! last-activity activity)
      (set! last-time (current-inexact-monotonic-milliseconds))))
  (define observer (create #f #xE7 1 0 observe #f))
  (unless observer (error 'cocoa-trace "could not create run-loop observer"))
  (define loop (main-loop))
  (add loop observer common-modes)
  (values
   (lambda (window)
     (define suspended (frame-read 'global-suspend-at))
     (hasheq 'racket_version (version)
             'flush_suspended (and suspended #t)
             'flush_suspended_for_window (and suspended window (ptr-equal? suspended window))
             'racket_sleeping (queue-read 'sleeping?)
             'racket_events_suspended (queue-read 'events-suspended?)
             'racket_run_loop_exited (queue-read 'already-exited?)
             'run_loop_events sequence
             'run_loop_entry (hash-ref counts #x1 0)
             'run_loop_before_timers (hash-ref counts #x2 0)
             'run_loop_before_sources (hash-ref counts #x4 0)
             'run_loop_before_waiting (hash-ref counts #x20 0)
             'run_loop_after_waiting (hash-ref counts #x40 0)
             'run_loop_exit (hash-ref counts #x80 0)
             'run_loop_last_activity last-activity
             'run_loop_last_age_ms
             (and last-time (- (current-inexact-monotonic-milliseconds) last-time))
             'run_loop_callback_error callback-error))
   (lambda ()
     (remove loop observer common-modes)
     (release observer)
     (set-box! keep-callback #f))))

(module+ test-support
  (provide current-metal-cocoa-trace-enabled))
