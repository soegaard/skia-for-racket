#lang racket/base
(require racket/cmdline racket/file racket/path racket/list rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-output.rkt"
         "../private/audit-trace.rkt" "../private/gpu-io-trace.rkt"
         "../tests/gpu-output-native-test.rkt" "../tests/gpu-output-fixtures.rkt"
         "gpu-test-host.rkt" "gpu-report.rkt")
(provide gpu-output-doctor!)

(define (gpu-output-doctor! prefix #:backend [backend 'opengl] #:host [host-mode 'gui]
                            #:egl-platform [platform 'surfaceless] #:egl-device-index [index 0]
                            #:egl-surface [binding-surface 'surfaceless]
                            #:required? [required? #t] #:require-hardware? [hardware? #f])
  (define context #f) (define other #f) (define started? #f)
  (define initial #f) (define host-info #f) (define failures #f)
  (define pending '()) (define documents '())
  (define (path suffix) (string->path (string-append prefix suffix)))
  (define (base p) (path->string (file-name-from-path p)))
  (define (report status message)
    (hasheq 'schema_version 1 'stage "0.44" 'kind "gpu-output"
            'status status 'message message 'backend (symbol->string backend)
            'required required? 'require_hardware hardware?
            'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
            'racket_version (version) 'validation_run (or (getenv "SKIA_GPU_VALIDATION_RUN") #f)
            'initial_context initial 'host host-info
            'native_test_cases gpu-output-native-test-count 'native_test_failures failures
            'documents (reverse documents) 'performance_measured #f))
  (define (publish status message)
    (write-gpu-json (path ".diagnostic.json") (report status message)))
  (define (with-host proc)
    (call-with-gpu-backend-host backend proc #:host host-mode #:egl-platform platform
                              #:egl-device-index index #:egl-surface binding-surface))
  (define (build! name variant format executor)
    (define file (path (format-name name variant format)))
    (define document
      (if (eq? format 'pdf) (make-pdf-document)
          (make-svg-document output-document-width output-document-height)))
    ;; Register immediately: callbacks, audit vetoes and finalization failures
    ;; leave no untracked open document in this diagnostic.
    (define entry (vector document format file #f))
    (set! pending (cons entry pending))
    (define calls (box 0)) (define group #f) (define ledger (box '()))
    (define-values (_ audit)
      (call-with-audit-collector format 'error #f 1
        (lambda ()
          (parameterize ([current-text-output-mode 'outline] [current-gpu-io-ledger ledger])
            (define (draw c) (set! group (draw-output-document c name executor calls)))
            (if (eq? format 'pdf)
                (with-document-page (c document output-document-width output-document-height) (draw c))
                (draw (svg-document-canvas document)))))))
    (vector-set! entry 3
      (hasheq 'name (symbol->string name) 'variant (symbol->string variant)
              'format (symbol->string format) 'file (base file)
              'page_size (list output-document-width output-document-height)
              'expected_image_size '(210 144) 'authoring_calls (unbox calls)
              'group (output-group-report->jsexpr group)
              'audit (output-audit-report->jsexpr audit)
              'io_events (reverse (unbox ledger)))))
  (define (close-documents!)
    (define first-error #f)
    (for ([entry (in-list pending)])
      (with-handlers ([exn:fail? (lambda (e) (unless first-error (set! first-error e)))])
        (skia-close! (vector-ref entry 0))))
    (set! pending '())
    (when first-error (raise first-error)))
  (with-handlers
      ([exn:fail:gpu:unavailable?
        (lambda (e)
          (publish (if started? "error" "unavailable") (exn-message e))
          (eprintf "GPU output unavailable/error: ~a\n" (exn-message e))
          (if (and (not started?) (not required?)) 0 1))]
       [exn:fail? (lambda (e) (publish "error" (exn-message e))
                    (eprintf "GPU output ERROR: ~a\n" (exn-message e)) 1)])
    (make-directory* (or (path-only (path ".diagnostic.json")) (current-directory)))
    (dynamic-wind void
      (lambda ()
        (with-host
         (lambda (make-context host)
           (set! host-info host)
           (with-host
            (lambda (make-other other-host)
              (dynamic-wind void
                (lambda ()
                  (parameterize-break #f (set! context (make-context)))
                  (set! started? #t)
                  (parameterize-break #f (set! other (make-other)))
                  (set! initial (gpu-context-info context))
                  (when (and hardware? (not (equal? (hash-ref initial 'renderer_class) "hardware-reported")))
                    (error 'gpu-output-doctor "hardware-reported renderer required"))
                  (set! failures (run-tests (make-gpu-output-native-tests context other)))
                  (unless (zero? failures) (error 'gpu-output-doctor "GPU output suite failed: ~a" failures))
                  (define executor (make-gpu-raster-executor context))
                  (for* ([name (in-list output-probe-names)]
                         [variant '(cpu gpu)] [format '(pdf svg)])
                    (build! name variant format (if (eq? variant 'cpu) 'cpu executor))))
                (lambda () (close-gpu-contexts! (list other context) gpu-context-close!)))))))
        ;; All documents remain OPEN while both GPU contexts have been closed.
        ;; Finishing and serializing here exercises native document retention of
        ;; detached image references, not merely copying already-encoded bytes.
        (define closed (gpu-context-info context)) (define other-closed (gpu-context-info other))
        (check-gpu-teardown! closed) (check-gpu-teardown! other-closed)
        (for ([entry (in-list (reverse pending))])
          (define document (vector-ref entry 0))
          (define format (vector-ref entry 1))
          (define bytes
            (if (eq? format 'pdf)
                (begin (document-finish! document) (document->pdf-bytes document))
                (begin (svg-document-finish! document) (svg-document->bytes document))))
          (call-with-output-file (vector-ref entry 2)
            (lambda (out) (write-bytes bytes out)) #:exists 'truncate)
          (set! documents (cons (hash-set (vector-ref entry 3) 'serialized_after_gpu_teardown #t) documents)))
        (write-gpu-json (path ".diagnostic.json")
          (hash-set* (report "passed" #f) 'closed_context closed 'other_closed_context other-closed
                     'documents_serialized_after_gpu_teardown #t))
        (displayln "GPU output tests passed; PDF/SVG documents serialized after GPU teardown. Inspect actual document bytes and embedded PNGs next.")
        0)
      close-documents!)))
(define (format-name name variant format)
  (string-append "." (symbol->string name) "." (symbol->string variant) "." (symbol->string format)))

(module+ main
  (define prefix "output/gpu-output-0.44") (define backend 'opengl) (define host-mode 'gui)
  (define platform 'surfaceless) (define index 0) (define binding-surface 'surfaceless)
  (define required? #t) (define hardware? #f)
  (command-line #:once-each
    [("--prefix") p "Artifact prefix" (set! prefix p)]
    [("--backend") b "opengl or metal" (set! backend (string->symbol b))]
    [("--host") h "gui or egl" (set! host-mode (string->symbol h))]
    [("--egl-platform") p "surfaceless or device" (set! platform (string->symbol p))]
    [("--egl-device-index") i "Explicit device index" (set! index (string->number i))]
    [("--egl-surface") s "surfaceless or pbuffer" (set! binding-surface (string->symbol s))]
    [("--optional") "Permit initial GPU unavailability only" (set! required? #f)]
    [("--require-hardware") "Require hardware-reported renderer" (set! hardware? #t)]
    #:args () (void))
  (exit (gpu-output-doctor! prefix #:backend backend #:host host-mode #:egl-platform platform
                           #:egl-device-index index #:egl-surface binding-surface
                           #:required? required? #:require-hardware? hardware?)))
