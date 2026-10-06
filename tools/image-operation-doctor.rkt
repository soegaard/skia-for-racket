#lang racket/base
(require racket/cmdline racket/file racket/list json
         "../main.rkt" "../tests/image-operation-fixtures.rkt")
(provide generate-image-operation-documents)
(define (write-data path data)
  (call-with-output-file path (lambda (out) (write-bytes data out)) #:exists 'error))
(define (generate-image-operation-documents directory token)
  (when (directory-exists? directory) (error 'image-operation-doctor "output directory already exists"))
  (make-directory* directory)
  (define rows
    (append*
     (for/list ([scene (in-list operation-scenes)])
       (define-values (image offset metadata raw) (make-operation-scene-image scene))
       (with-skia ([im image])
         (define prefix (symbol->string scene))
         (when raw (write-data (build-path directory "scale.f32") raw))
         (define count 0)
         (define page
           (make-output-page operation-width operation-height
             (lambda (c)
               (set! count (add1 count))
               (with-skia ([marker (make-paint #:color (rgb 0 255 0) #:antialias? #f)])
                 (draw-rect c 2 2 5 5 marker))
               (draw-image c im (+ 24 (vector-ref offset 0)) (+ 20 (vector-ref offset 1)) #:sampling 'nearest)
               (canvas-annotate-url! c 2 2 5 5 (string-append "https://example.invalid/image-operations/" prefix)))
             #:background 'white))
         (for/list ([kind '(pdf svg)])
           (define stem (string-append prefix "-" (symbol->string kind)))
           (with-skia ([reference (output-page->image page #:dpi 72)])
             (define pixels (image->rgba-bytes reference #:premultiplied? #t))
             (operation-check-pixels scene pixels)
             (write-data (build-path directory (string-append stem ".rgba")) pixels))
           (set! count 0)
           ;; The image is intentional raster content; vector-only would reject
           ;; the very operation under test. Blocking fallbacks still reject.
           (define-values (data audit) (output->bytes/audit page kind #:policy 'error))
           (unless (and (= count 1) (not (output-audit-report-blocking? audit))
                        (not (output-audit-report-vector-only? audit)))
             (error 'image-operation-doctor "incomplete image export audit"))
           (write-data (build-path directory (format "~a.~a" stem kind)) data)
           (hasheq 'scene prefix 'format (symbol->string kind) 'file (format "~a.~a" stem kind)
                   'rgba (string-append stem ".rgba") 'callback_count count
                   'image_dimensions (list (image-width im) (image-height im))
                   'placement (list (+ 24 (vector-ref offset 0)) (+ 20 (vector-ref offset 1)))
                   'metadata metadata 'raw (if raw "scale.f32" #f)
                   'audit_policy "error" 'audit (output-audit-report->jsexpr audit)))))))
  (call-with-output-file (build-path directory "documents.json")
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.72" 'run_token token 'status "passed"
                          'documents rows 'rendering_executed #t 'gpu_executed #f 'gui_executed #f
                          'byte_order (if (system-big-endian?) "big-endian" "little-endian")) out)) #:exists 'error)
  (printf "Direct image operations: ~a native documents; independent inspection required.\n" (length rows)))
(module+ main
  (define directory #f) (define token #f)
  (command-line #:once-each
    [("--directory") value "New output directory" (set! directory value)]
    [("--token") value "Invocation identity" (set! token value)] #:args () (void))
  (unless (and directory token) (error 'image-operation-doctor "--directory and --token required"))
  (generate-image-operation-documents directory token))
