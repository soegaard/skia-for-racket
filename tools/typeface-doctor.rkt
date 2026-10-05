#lang racket/base
(require racket/cmdline racket/file racket/list json
         "../main.rkt" "../tests/typeface-fixtures.rkt")
(provide generate-typeface-documents)
(define (write-data path data)
  (call-with-output-file path (lambda (out) (write-bytes data out)) #:exists 'error))
(define (generate-typeface-documents directory token)
  (when (directory-exists? directory) (error 'typeface-doctor "output directory already exists"))
  (make-directory* directory)
  (define metadata '())
  (define rows
    (append*
     (for/list ([bold? '(#f #t)])
       (define id (if bold? "bold" "regular"))
       (define source (fixture-font-bytes #:bold? bold?))
       (with-skia ([face (typeface-from-bytes source)]
                   [font (make-font face #:size 48 #:hinting 'none #:edging 'alias)]
                   [ink (make-paint #:color (rgb 24 64 192) #:antialias? #f)])
         (bytes-fill! source 0)
         (define-values (raw index) (typeface->font-bytes face))
         (define kern (typeface-kerning-pair-adjustments face '(2 3)))
         (set! metadata
           (cons (hasheq 'face id 'postscript_name (typeface-postscript-name face)
                         'glyph_count (typeface-glyph-count face) 'units_per_em (typeface-units-per-em face)
                         'fixed_pitch (typeface-fixed-pitch? face)
                         'table_tags (vector->list (typeface-table-tags face))
                         'font_data_bytes (bytes-length raw) 'font_data_index index
                         'kerning_available (and kern #t) 'kerning (and kern (vector->list kern))) metadata))
         ;; Fonts retain their own native typeface reference.
         (skia-close! face)
         (for/list ([spec '((pdf native) (pdf outline) (svg outline))])
           (define fmt (car spec)) (define mode (cadr spec))
           (define count 0)
           (define page
             (make-output-page 160 100
               (lambda (c)
                 (set! count (add1 count))
                 (with-skia ([marker (make-paint #:color (rgb 0 255 0) #:antialias? #f)])
                   (draw-rect c 2 2 4 4 marker))
                 (draw-simple-text c fixture-text 16 72 font ink)
                 (canvas-annotate-url! c 2 2 4 4 (string-append "https://example.invalid/typeface/" id)))
               #:background 'white))
           (define stem (format "~a-~a-~a" id fmt mode))
           ;; Reference and export are separate explicit authoring invocations.
           (with-skia ([image (output-page->image page #:dpi 72 #:text-mode mode)])
             (write-data (build-path directory (string-append stem ".rgba"))
                         (image->rgba-bytes image #:premultiplied? #t)))
           (set! count 0)
           (define-values (data audit) (output->bytes/audit page fmt #:text-mode mode #:policy 'vector-only))
           (unless (and (= count 1) (output-audit-report-vector-only? audit))
             (error 'typeface-doctor "document was not authored once as vector/text output"))
           (define filename (format "~a.~a" stem fmt))
           (write-data (build-path directory filename) data)
           (hasheq 'face id 'format (symbol->string fmt) 'text_mode (symbol->string mode)
                   'file filename 'rgba (string-append stem ".rgba") 'callback_count count
                   'audit_policy "vector-only" 'audit (output-audit-report->jsexpr audit)))))))
  (call-with-output-file (build-path directory "documents.json")
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.68a" 'run_token token 'status "passed"
                          'documents rows 'typefaces (reverse metadata) 'rendering_executed #t
                          'gui_executed #f 'gpu_executed #f) out)) #:exists 'error)
  (printf "Typeface resources: ~a native documents; independent inspection required.\n" (length rows)))
(module+ main
  (define directory #f) (define token #f)
  (command-line #:once-each
    [("--directory") path "New output directory" (set! directory path)]
    [("--token") value "Run identity" (set! token value)] #:args () (void))
  (unless (and directory token) (error 'typeface-doctor "--directory and --token required"))
  (generate-typeface-documents directory token))
