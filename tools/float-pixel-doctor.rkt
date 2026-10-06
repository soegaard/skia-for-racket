#lang racket/base
(require racket/cmdline racket/file racket/list json "../main.rkt" "../tests/float-pixel-fixtures.rkt")
(provide generate-float-pixel-documents)
(define (save-bytes p b) (call-with-output-file p (lambda (o) (write-bytes b o)) #:exists 'error))
(define (generate-float-pixel-documents directory token)
  (when (directory-exists? directory) (error 'float-pixel-doctor "output directory must be new"))
  (make-directory* directory)
  (define rows
    (append*
      (for*/list ([format-name (in-vector float-pixel-formats)] [scene (in-list '(samples linear))])
        (define prefix (format "~a-~a" format-name scene))
        (with-skia ([source (make-float-fixture-buffer format-name scene)]
                    [converted (raster-buffer-convert source (make-image-info 64 32 #:color-space 'srgb))]
                    [im (raster-buffer->image converted)])
          (save-bytes (build-path directory (string-append prefix ".pixels")) (raster-buffer->storage-bytes source))
          ;; Close both buffers; neither pixels nor color-space ownership may be
          ;; borrowed by this immutable, explicitly quantized image.
          (skia-close! source) (skia-close! converted)
          (for/list ([kind (in-list '(pdf svg))])
            (define count 0)
            (define page
              (make-output-page 96 64
                (lambda (c)
                  (set! count (add1 count))
                  (draw-image c im 16 16 #:sampling 'nearest)
                  (with-skia ([p (make-paint #:color (rgb 0 255 0) #:antialias? #f)])
                    (draw-rect c 2 2 4 4 p))
                  (canvas-annotate-url! c 2 2 4 4 (string-append "https://example.invalid/float/" prefix)))
                #:background 'white))
            (define stem (format "~a-~a" prefix kind))
            (with-skia ([reference (output-page->image page #:dpi 72)])
              (save-bytes (build-path directory (string-append stem ".rgba"))
                          (image->rgba-bytes reference #:premultiplied? #t)))
            (set! count 0)
            (define-values (bytes audit) (output->bytes/audit page kind #:policy 'error))
            (when (or (not (= count 1)) (output-audit-report-blocking? audit)
                      (output-audit-report-vector-only? audit))
              (error 'float-pixel-doctor "expected an intentional image and vector surround"))
            (define name (format "~a.~a" stem kind))
            (save-bytes (build-path directory name) bytes)
            (hasheq 'source_format (symbol->string format-name) 'scene (symbol->string scene)
                    'format (symbol->string kind) 'file name 'rgba (string-append stem ".rgba")
                    'raw (string-append prefix ".pixels") 'conversion "explicit-float-to-rgba8888"
                    'image_width 64 'image_height 32 'callback_count count
                    'audit_policy "error" 'audit (output-audit-report->jsexpr audit)))))))
  (call-with-output-file (build-path directory "documents.json")
    (lambda (o) (write-json (hasheq 'schema 1 'stage "0.71" 'status "passed" 'run_token token
                     'byte_order (if (system-big-endian?) "big-endian" "little-endian")
                     'documents rows 'rendering_executed #t 'gpu_executed #f 'hdr_verified #f) o)) #:exists 'error)
  (printf "Float pixels: ~a native documents plus raw pre-quantization pixels; independent inspection required.\n" (length rows)))
(module+ main
  (define directory #f) (define token #f)
  (command-line #:once-each
    [("--directory") d "Fresh evidence directory" (set! directory d)]
    [("--token") t "Invocation identity" (set! token t)] #:args () (void))
  (unless (and directory token) (error 'float-pixel-doctor "--directory and --token required"))
  (generate-float-pixel-documents directory token))
