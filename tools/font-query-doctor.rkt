#lang racket/base

;;;
;;; Font Query Doctor
;;;

;; Exercises font mutation, glyph metrics, and detached outline queries and reports native
;; diagnostic evidence.
;; The validation workflow uses this focused probe alongside automated regression suites.

;;;
;;; Imports and Exports
;;;
(require racket/cmdline racket/file racket/list json
         "../main.rkt" "../tests/font-query-fixtures.rkt")
(provide generate-font-query-documents)

;;;
;;; Diagnostic Operations
;;;

; write-data : path-string? bytes? -> exact-nonnegative-integer?
;   Writes fresh binary evidence, refusing to overwrite an existing capture.
(define (write-data path data)
  (call-with-output-file path (lambda (out) (write-bytes data out)) #:exists 'error))

; generate-font-query-documents : path-string? string? -> void?
;   Exports deterministic font-mutation and outline scenes with tagged document evidence.
(define (generate-font-query-documents directory token)
  (when (or (directory-exists? directory) (file-exists? directory))
    (error 'font-query-doctor "output directory already exists"))
  (make-directory* directory)
  (define rows
    (for*/list ([scene (in-list font-query-scenes)] [fmt '(pdf svg)])
      (define mode (if (eq? fmt 'pdf) 'native 'outline))
      (define calls 0)
      (define page
        (make-output-page font-query-width font-query-height
          (lambda (canvas) (set! calls (add1 calls)) (draw-font-query-scene scene canvas))
          #:background 'white))
      (define stem (format "~a-~a" scene fmt))
      (with-skia ([image (output-page->image page #:dpi 72 #:text-mode mode)])
        (define bytes (image->rgba-bytes image #:premultiplied? #t))
        (check-font-query-pixels scene bytes)
        (write-data (build-path directory (string-append stem ".rgba")) bytes))
      (set! calls 0)
      (define-values (bytes audit)
        (output->bytes/audit page fmt #:text-mode mode #:policy 'vector-only))
      (unless (and (= calls 1) (output-audit-report-vector-only? audit))
        (error 'font-query-doctor "document must be authored once without raster fallback"))
      (define file (format "~a.~a" stem fmt))
      (write-data (build-path directory file) bytes)
      (hasheq 'scene (symbol->string scene) 'format (symbol->string fmt)
              'text_mode (symbol->string mode) 'file file 'rgba (string-append stem ".rgba")
              'callback_count calls 'audit_policy "vector-only"
              'audit (output-audit-report->jsexpr audit))))
  (call-with-output-file (build-path directory "documents.json")
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.68b" 'run_token token 'status "passed"
                          'width font-query-width 'height font-query-height
                          'documents rows 'rendering_executed #t
                          'gui_executed #f 'gpu_executed #f) out)) #:exists 'error)
  (printf "Font queries: ~a documents; independent inspection required.\n" (length rows)))
(module+ main

  ;;;
  ;;; Command-Line Run
  ;;;

  ; directory : (or/c path-string? #f)
  ;   Holds the evidence output directory selected for this run.
  (define directory #f)

  ; token : (or/c string? #f)
  ;   Carries the caller's run identifier into evidence so independent validation can match
  ;   artifacts.
  (define token #f)
  (command-line #:once-each
    [("--directory") value "New output directory" (set! directory value)]
    [("--token") value "Invocation identity" (set! token value)] #:args () (void))
  (unless (and directory token) (error 'font-query-doctor "--directory and --token required"))
  (generate-font-query-documents directory token))
