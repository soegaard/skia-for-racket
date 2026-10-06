#lang racket/base
(require racket/cmdline racket/file racket/list json "../main.rkt" "../tests/text-blob-scenes.rkt")
(provide generate-text-blob-documents)
(define (write-data path data)
  (call-with-output-file path (lambda (out) (write-bytes data out)) #:exists 'error))
(define (generate-text-blob-documents directory token)
  (when (directory-exists? directory) (error 'text-blob-doctor "output directory exists"))
  (make-directory* directory)
  (define rows
    (append*
     (for/list ([scene (in-list text-blob-scene-names)])
       ;; Scene factory has already closed every source font, face and shaper.
       (with-skia ([blob (make-text-blob-scene scene)])
         (for/list ([spec (in-list (if (eq? scene 'multi)
                                       '((pdf native) (pdf outline) (svg outline))
                                       '((pdf outline) (svg outline))))])
           (define fmt (car spec)) (define mode (cadr spec)) (define count 0)
           (define page
             (make-output-page text-blob-scene-width text-blob-scene-height
               (lambda (canvas)
                 (set! count (add1 count))
                 (draw-text-blob-scene canvas blob)
                 (canvas-annotate-url! canvas 2 2 4 4 (format "https://example.invalid/text-blob/~a" scene)))
               #:background 'white))
           (define stem (format "~a-~a-~a" scene fmt mode))
           (with-skia ([image (output-page->image page #:dpi 72 #:text-mode mode)])
             (write-data (build-path directory (string-append stem ".rgba"))
                         (image->rgba-bytes image #:premultiplied? #t)))
           (set! count 0)
           (define-values (data report) (output->bytes/audit page fmt #:text-mode mode #:policy 'vector-only))
           (unless (and (= count 1) (output-audit-report-vector-only? report))
             (error 'text-blob-doctor "document did not preserve vector output in one authoring invocation"))
           (write-data (build-path directory (format "~a.~a" stem fmt)) data)
           (hasheq 'scene (symbol->string scene) 'format (symbol->string fmt) 'text_mode (symbol->string mode)
                   'file (format "~a.~a" stem fmt) 'rgba (string-append stem ".rgba")
                   'callback_count count 'run_count (text-blob-run-count blob)
                   'audit (output-audit-report->jsexpr report)))))))
  (call-with-output-file (build-path directory "documents.json")
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.69" 'status "passed" 'run_token token 'documents rows
                          'source_owners_closed #t 'rendering_executed #t 'gpu_executed #f 'gui_executed #f) out))
    #:exists 'error)
  (printf "Multi-run text: ~a native PDF/SVG documents generated; independent inspection required.\n" (length rows)))
(module+ main
  (define directory #f) (define token #f)
  (command-line #:once-each
    [("--directory") value "Fresh output directory" (set! directory value)]
    [("--token") value "Invocation identity" (set! token value)] #:args () (void))
  (unless (and directory token) (error 'text-blob-doctor "--directory and --token required"))
  (generate-text-blob-documents directory token))
