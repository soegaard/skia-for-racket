#lang racket/base
(require racket/cmdline racket/file racket/list json
         "../main.rkt" "../tests/integer-pixel-fixtures.rkt")
(provide generate-integer-pixel-documents)
(define (write-data path data)
  (call-with-output-file path (lambda (out) (write-bytes data out)) #:exists 'error))
(define (generate-integer-pixel-documents directory token)
  (when (directory-exists? directory) (error 'integer-pixel-doctor "output directory already exists"))
  (make-directory* directory)
  (define rows
    (append*
     (for/list ([pixel-format (in-vector integer-pixel-formats)])
       (with-skia ([image (make-integer-fixture-image pixel-format)])
         (for/list ([fmt '(pdf svg)])
           (define count 0)
           (define page
             (make-output-page integer-fixture-width integer-fixture-height
               (lambda (c)
                 (set! count (add1 count))
                 (draw-integer-fixture c image #:scale 1)
                 (canvas-annotate-url! c 2 2 4 4
                   (string-append "https://example.invalid/integer-pixels/" (symbol->string pixel-format))))
               #:background 'white))
           (define stem (format "~a-~a" pixel-format fmt))
           (with-skia ([reference (output-page->image page #:dpi 72)])
             (write-data (build-path directory (string-append stem ".rgba"))
                         (image->rgba-bytes reference #:premultiplied? #t)))
           (set! count 0)
           (define-values (data audit) (output->bytes/audit page fmt #:policy 'error))
           (unless (and (= count 1) (not (output-audit-report-blocking? audit)))
             (error 'integer-pixel-doctor "export was not authored once without a blocking fallback"))
           (write-data (build-path directory (format "~a.~a" stem fmt)) data)
           (hasheq 'source_format (symbol->string pixel-format) 'format (symbol->string fmt)
                   'conversion "explicit-rgba-nearest" 'image_width 64 'image_height 32
                   'file (format "~a.~a" stem fmt) 'rgba (string-append stem ".rgba")
                   'callback_count count 'audit_policy "error"
                   'audit (output-audit-report->jsexpr audit)))))))
  (call-with-output-file (build-path directory "documents.json")
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.70" 'run_token token 'status "passed"
                          'documents rows 'rendering_executed #t 'gpu_executed #f
                          'gui_executed #f) out)) #:exists 'error)
  (printf "Integer pixels: ~a PDF/SVG documents; independent inspection required.\n" (length rows)))
(module+ main
  (define directory #f) (define token #f)
  (command-line #:once-each
    [("--directory") value "New evidence directory" (set! directory value)]
    [("--token") value "Invocation identity" (set! token value)] #:args () (void))
  (unless (and directory token) (error 'integer-pixel-doctor "--directory and --token required"))
  (generate-integer-pixel-documents directory token))
