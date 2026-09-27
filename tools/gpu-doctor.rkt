#lang racket/base
(require racket/cmdline racket/file racket/path racket/runtime-path racket/list
         json "../gpu.rkt" "../main.rkt" "../private/gpu-native.rkt"
         "../private/gpu-provider.rkt")
(provide gpu-doctor!)
(define-runtime-path host-module "gpu-gui-host.rkt")
(define-runtime-path metal-module "../private/gpu-metal-probe.rkt")
(define (write-json-atomically path value)
  (make-directory* (or (path-only path) (current-directory)))
  (define temporary (make-temporary-file "gpu-report-~a.tmp" #f (or (path-only path) (current-directory))))
  (dynamic-wind
    void
    (lambda ()
      (call-with-output-file temporary (lambda (out) (write-json value out) (newline out)) #:exists 'truncate)
      (rename-file-or-directory temporary path #t))
    (lambda () (when (file-exists? temporary) (delete-file temporary)))))
(define (gpu-doctor! #:backend [backend 'opengl] #:required? [required? #t]
                     #:require-hardware? [require-hardware? #f] #:cycles [cycles 3]
                     #:prefix [prefix "output/gpu-0.38"])
  (unless (memq backend '(opengl metal)) (error 'gpu-doctor "backend must be opengl or metal"))
  (unless (and (exact-positive-integer? cycles) (<= cycles 100))
    (error 'gpu-doctor "cycles must be an exact integer from 1 through 100"))
  (when (and require-hardware? (eq? backend 'metal))
    (error 'gpu-doctor "the Metal construction probe cannot certify a rendering path"))
  (define steps '())
  (define (step name details)
    (printf "GPU ~a: ~a\n" name details)
    (set! steps (cons (hasheq 'step name 'details details) steps)))
  (define (report status results [message #f])
    (hasheq 'schema_version 1 'stage "0.38" 'backend (symbol->string backend)
            'status status 'required required? 'require_hardware require-hardware?
            'racket_version (version) 'os (symbol->string (system-type 'os))
            'architecture (symbol->string (system-type 'arch))
            'steps (reverse steps) 'cycles results 'message message))
  (define (publish data)
    (write-json-atomically (string->path (string-append prefix ".diagnostic.json")) data))
  (with-handlers
      ([exn:fail:gpu:unavailable?
        (lambda (e)
          (step "unavailable" (hasheq 'at (symbol->string (exn:fail:gpu:unavailable-step e))
                                      'message (exn-message e)))
          (publish (report "unavailable" '() (exn-message e)))
          (printf "GPU ~a: ~a\n" (if required? "REQUIRED CHECK FAILED" "explicitly SKIPPED") (exn-message e))
          (if required? 1 0))]
       [exn:fail?
        (lambda (e)
          (step "error" (exn-message e))
          (publish (report "error" '() (exn-message e)))
          (eprintf "GPU ERROR (not an optional skip): ~a\n" (exn-message e))
          1)])
    (step "native-library" (format "~a" (skia-native-library-path)))
    (define inventory (gpu-native-inventory backend))
    (step "symbol-inventory" inventory)
    (gpu-native-check! backend)
    (make-directory* (or (path-only (string->path prefix)) (current-directory)))
    (define results
      (case backend
        [(metal)
         (define probe (dynamic-require metal-module 'run-metal-construction-probe))
         (for/list ([i (in-range cycles)])
           (define info (probe))
           (step "metal-construction-and-teardown" info)
           (hasheq 'index (add1 i) 'context info 'construction_only #t))]
        [else
         ;; Only GUI initialization failure is classified as unavailability.
         ;; Once rendering starts, a draw/readback/cleanup error MUST fail even
         ;; in optional mode.
         (define with-host
           (with-handlers ([exn:fail?
                            (lambda (e) (gpu-unavailable 'gui-initialization "~a" (exn-message e)))])
             (dynamic-require host-module 'call-with-gpu-test-host)))
         (with-host
          (lambda (provider host)
            (step "host-context" host)
            (for/list ([i (in-range cycles)])
              (define context (make-gpu-context provider))
              (define image-file (format "~a.cycle-~a.png" prefix (add1 i)))
              (define result #f)
              (dynamic-wind
                void
                (lambda ()
                  (define info (gpu-context-info context))
                  (step "ganesh-context" info)
                  (when (and require-hardware?
                             (not (equal? (hash-ref info 'renderer_class "unclassified") "hardware-reported")))
                    (error 'gpu-doctor "required hardware-reported renderer, got ~a"
                           (hash-ref info 'renderer_class "unclassified")))
                  (define smoke (gpu-smoke-test context))
                  ;; This is an explicit CPU detachment after GPU readback.
                  ;; No GPU image or borrowed GPU canvas escapes the probe.
                  (with-skia ([image (rgba-bytes->image 8 8 (hash-ref smoke 'rgba))])
                    (save-image image image-file 'png #:exists 'replace))
                  (set! result
                    (hasheq 'index (add1 i) 'initial_context info
                            'smoke (hash-set smoke 'rgba (bytes->list (hash-ref smoke 'rgba)))
                            'image_file (path->string (file-name-from-path (string->path image-file)))))
                  (step "target-draw-submit-readback" (hash-remove smoke 'rgba)))
                (lambda () (gpu-context-close! context)))
              (define closed (gpu-context-info context))
              (unless (and (equal? (hash-ref closed 'state) "closed")
                           (zero? (hash-ref closed 'live_children))
                           (zero? (hash-ref closed 'pending_releases)))
                (error 'gpu-doctor "context teardown was incomplete"))
              (step "teardown" closed)
              (hash-set result 'closed_context closed))))]))
    (publish (report "passed" results))
    (printf "GPU ~a check passed (~a creation/teardown cycles). No performance claim.\n" backend cycles)
    0))
(module+ main
  (define backend 'opengl)
  (define required? #t)
  (define hardware? #f)
  (define prefix "output/gpu-0.38")
  (define cycles 3)
  (command-line
   #:program "gpu-doctor"
   #:once-each
   [("--backend") name "opengl or metal (no automatic fallback)" (set! backend (string->symbol name))]
   [("--optional") "Unavailable initialization may be reported as an explicit skip" (set! required? #f)]
   [("--require-hardware") "Require a hardware-reported GL renderer; reject software/unknown strings" (set! hardware? #t)]
   [("--prefix") value "Output prefix" (set! prefix value)]
   [("--cycles") value "Context creation/teardown count, 1..100" (set! cycles (string->number value))]
   #:args () (void))
  (exit (gpu-doctor! #:backend backend #:required? required? #:require-hardware? hardware?
                     #:cycles cycles #:prefix prefix)))
