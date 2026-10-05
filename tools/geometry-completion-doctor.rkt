#lang racket/base
(require racket/cmdline racket/file racket/list json
         "../main.rkt" "../tests/geometry-completion-fixtures.rkt")
(provide generate-geometry-documents)
(define (write-data path data)
  (call-with-output-file path (lambda (out) (write-bytes data out)) #:exists 'error))
(define (generate-geometry-documents directory token)
  (when (directory-exists? directory) (error 'geometry-doctor "output directory already exists"))
  (make-directory* directory)
  (define rows
    (append*
     (for/list ([name (in-list geometry-scene-names)])
       (define id (symbol->string name))
       (define data (capture-geometry-scene name))
       (check-geometry-pixels name data)
       (write-data (build-path directory (string-append id ".rgba")) data)
       (for/list ([fmt (in-list '(pdf svg))])
         (define count 0) (define group #f)
         (define page
           (make-output-page 96 72
             (lambda (c)
               (with-skia ([marker (make-paint #:color (rgb 0 255 0) #:antialias? #f)])
                 (draw-rect c 2 2 4 4 marker))
               (set! group (draw-output-group c 8 16 64 48
                 (lambda (gc) (set! count (add1 count)) (draw-geometry-scene name gc))
                 #:policy 'require-vector #:label id))
               (canvas-annotate-url! c 2 2 4 4 (string-append "https://example.invalid/geometry/" id)))
             #:background 'white))
         (define-values (bytes audit) (output->bytes/audit page fmt #:policy 'vector-only))
         (unless (and (= count 1) (output-audit-report-vector-only? audit)
                      (eq? (output-group-report-strategy group) 'native))
           (error 'geometry-doctor "native vector authoring contract failed"))
         (define filename (format "~a.~a" name fmt))
         (write-data (build-path directory filename) bytes)
         (hasheq 'name id 'format (symbol->string fmt) 'file filename
                 'rgba (string-append id ".rgba") 'callback_count count
                 'audit_policy "vector-only" 'audit (output-audit-report->jsexpr audit)
                 'group (output-group-report->jsexpr group))))))
  (call-with-output-file (build-path directory "documents.json")
    (lambda (out) (write-json (hasheq 'schema 1 'stage "0.67" 'run_token token 'status "passed"
                                    'documents rows 'rendering_executed #t) out)) #:exists 'error)
  (printf "Geometry: ~a native vector documents generated; independent inspection required.\n" (length rows)))
(module+ main
  (define directory #f) (define token #f)
  (command-line #:once-each
    [("--directory") path "New output directory" (set! directory path)]
    [("--token") value "Run identity" (set! token value)] #:args () (void))
  (unless (and directory token) (error 'geometry-doctor "--directory and --token required"))
  (generate-geometry-documents directory token))
