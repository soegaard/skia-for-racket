#lang racket/base

;;;
;;; Advanced Canvas Doctor
;;;

;; Exercises save layers, native drawables, and specialized canvases and reports native diagnostic
;; evidence.
;; The validation workflow uses this focused probe alongside automated regression suites.

;;;
;;; Imports and Exports
;;;
(require racket/cmdline racket/file racket/path json "../main.rkt"
         "../tests/advanced-canvas-fixtures.rkt")
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
  ; source-file : (or/c path-string? #f)
  ;;   Optionally supplies a GPU RGBA capture to embed in the document evidence instead of drawing a
  ;;   CPU fixture.
  (define source-file #f)
  (command-line #:once-each
    [("--directory") path "Fresh output directory" (set! directory path)]
    [("--token") value "Run token" (set! token value)]
    [("--gpu-layer") path "Explicit RGBA capture from the completed GPU driver"
      (set! source-file path)]
    #:args () (void))
  (unless (and directory token) (error 'advanced-doctor "--directory and --token are required"))
  (make-directory* directory)

  ; image : image?
  ;;   Owns the validated GPU-capture image or CPU-rendered advanced-layer snapshot used by the
  ;;   output fixtures.
  (define image
    (if source-file
        (let ([data (file->bytes source-file)])
          (unless (= (bytes-length data) (* 4 advanced-width advanced-height))
            (error 'advanced-doctor "wrong GPU capture size"))
          (rgba-bytes->image advanced-width advanced-height data #:premultiplied? #t))
        (with-skia ([s (make-surface advanced-width advanced-height #:background 'white)])
          (draw-advanced-layer (surface-canvas s)) (surface-snapshot s))))

  ; rows : (listof hash?)
  ;;   Accumulates document filenames and scene evidence for the output manifest.
  (define rows '())
  (with-skia ([im image] [d (call-with-drawable advanced-width advanced-height draw-advanced-vector)])
    (for* ([mode '(vector layer)] [kind '(pdf svg)])
      (define page
        (make-output-page advanced-width advanced-height
          (lambda (c)
            (if (eq? mode 'vector) (draw-drawable c d) (draw-image c im 0 0 #:sampling 'nearest))
            (with-skia ([marker (make-paint #:color (rgb 0 255 0) #:antialias? #f)])
              (draw-rect c 2 2 4 4 marker))
            (canvas-annotate-url! c 2 2 4 4 advanced-url)) #:background 'white))
      (define-values (data audit)
        (output->bytes/audit page kind #:policy (if (eq? mode 'vector) 'vector-only 'error)))
      (define name (format "~a.~a" mode kind))
      (call-with-output-file (build-path directory name) (lambda (out) (write-bytes data out))
        #:exists 'error)
      (set! rows (cons (hasheq 'mode (symbol->string mode) 'format (symbol->string kind) 'file name
                               'boundary
                         (if (eq? mode 'vector) "native-drawable" "explicit-integer-snapshot")
                               'audit (output-audit-report->jsexpr audit)) rows))))
  (call-with-output-file (build-path directory "documents.json")
    (lambda (out) (write-json (hasheq 'stage "0.74" 'schema 1 'run_token token 'status "passed"
                                     'layer_source (if source-file "gpu-capture" "cpu")
                                     'documents (reverse rows)) out)) #:exists 'error))
