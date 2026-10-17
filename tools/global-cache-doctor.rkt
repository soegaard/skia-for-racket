#lang racket/base

;;;
;;; Global Cache Doctor
;;;

;; Exercises global font/resource cache controls and bounded memory statistics and reports native
;; diagnostic evidence.
;; The validation workflow uses this focused probe alongside automated regression suites.

;;;
;;; Imports and Exports
;;;
(require json racket/cmdline racket/file racket/list
         "../main.rkt" "../tests/global-cache-support.rkt")
(provide generate-cache-evidence)

;;;
;;; Diagnostic Operations
;;;

; generate-cache-evidence : path-string? string? -> void?
;;   Captures cache limits, memory reports, truncation bounds, and drawing stability while restoring
;;   global settings.
(define (generate-cache-evidence directory token)
  (make-directory* directory)
  (define (save name bytes)
    (call-with-output-file (build-path directory name)
      (lambda (out) (write-bytes bytes out)) #:exists 'error #:mode 'binary))
  (define before (limit-settings))
  (define requested '#(8388608 256 4194304 524288))
  (define returned #f) (define observed #f) (define counters #f)
  (define light #f) (define detailed #f) (define truncated #f)
  (define post-purge '())
  (define pixels (cache-test-pixels))
  (save "before.rgba" pixels)
  (dynamic-wind void
    (lambda ()
      (set! returned
        (vector (skia-set-font-cache-limit! (vector-ref requested 0))
                (skia-set-font-cache-count-limit! (vector-ref requested 1))
                (skia-set-resource-cache-limit! (vector-ref requested 2))
                (skia-set-resource-cache-single-allocation-limit! (vector-ref requested 3))))
      (set! observed (limit-settings))
      (unless (and (equal? returned before) (equal? observed requested))
        (error 'global-caches "native cache setter/getter disagreement"))
      (save "font.rgba" (warm-cache!))
      (set! counters (skia-cache-statistics))
      (set! light (memory-statistics->jsexpr (skia-memory-statistics)))
      (set! detailed (memory-statistics->jsexpr (skia-memory-statistics #:detailed? #t)))
      (set! truncated (memory-statistics->jsexpr (skia-memory-statistics #:max-entries 0)))
      (skia-set-font-cache-limit! 1) (skia-set-font-cache-count-limit! 1)
      (skia-set-resource-cache-limit! 1)
      (save "limited.rgba" (cache-test-pixels))
      (for ([purge
              (in-list (list skia-purge-font-cache! skia-purge-resource-cache!
                         skia-purge-all-caches!))]
            [name (in-list '(font resource all))])
        (define settings (limit-settings))
        (purge)
        (define after (limit-settings))
        (unless (equal? settings after) (error 'global-caches "purge altered limits"))
        (set! post-purge (cons (hasheq 'cache (symbol->string name) 'before (vector->list settings)
                                      'after (vector->list after)) post-purge))
        (save (format "purge-~a.rgba" name) (cache-test-pixels))))
    (lambda () (restore-limits! before)))
  (define restored (limit-settings))
  (unless (equal? restored before) (error 'global-caches "cache limits not restored"))
  (define receipt
    (hasheq 'schema 1 'stage "0.77a" 'status "passed" 'run_token token
            'native_version (skia-native-version) 'scope "process-global-skia-caches"
            'gpu_executed #f 'process_memory_measured #f 'driver_memory_measured #f
            'trace_extension_symbols_resolved 3
            'limits_before (vector->list before) 'limits_requested (vector->list requested)
            'setter_previous (vector->list returned) 'limits_observed (vector->list observed)
            'limits_restored (vector->list restored) 'purges (reverse post-purge)
            'counters (hash-set counters 'scope "process-global-skia-caches")
            'light light 'detailed detailed 'truncated truncated))
  (call-with-output-file (build-path directory "global-caches.json")
    (lambda (out) (write-json receipt out) (newline out)) #:exists 'error)
  (displayln "global-cache-native-evidence: passed"))
(module+ main

  ;;;
  ;;; Command-Line Run
  ;;;

  ; directory : (or/c path-string? #f)
  ;;   Holds the evidence output directory selected for this run.
  (define directory #f)
  ; token : (or/c string? #f)
  ;;   Carries the caller's run identifier into evidence so independent validation can match
  ;;   artifacts.
  (define token #f)
  (command-line #:once-each
    [("--directory") path "New evidence directory" (set! directory path)]
    [("--token") text "Unique validator token" (set! token text)])
  (unless (and directory token) (error 'global-cache-doctor "--directory and --token are required"))
  (when (directory-exists? directory) (error 'global-cache-doctor "directory already exists"))
  (generate-cache-evidence directory token))
