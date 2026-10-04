#lang racket/base
;; Actual native documents. Receipt completion is written only after ALL
;; authoring, byte generation, file writes and resource cleanup succeed.
(require racket/class racket/cmdline racket/file racket/list json
         (prefix-in sk: "../main.rkt") "../dc-output.rkt"
         "../tests/dc-output-fixtures.rkt")
(provide generate-dc-output-evidence)
(define (generate-dc-output-evidence directory token)
  (unless (and (string? token) (positive? (string-length token)))
    (raise-argument-error 'dc-output-doctor "nonempty run token" token))
  (when (directory-exists? directory) (error 'dc-output-doctor "evidence directory must be new"))
  (make-directory* directory)
  (sk:skia-check!) (sk:harfbuzz-check!)
  (define entries '())
  (define (emit id kind fmt draws width height
                #:text-mode [mode (if (eq? fmt 'svg) 'outline 'native)]
                #:unit [unit 'pt] #:margins [margins 0] #:raster-counter [counter #f])
    (define calls 0) (define reports '()) (define layout (hash))
    (define pages
      (for/list ([draw (in-list draws)])
        (make-dc-output-page width height
          (lambda (dc)
            (set! calls (add1 calls))
            (define value (draw dc))
            (when (hash? value) (set! layout value)))
          #:unit unit #:margins margins #:background 'white
          #:on-report (lambda (r) (set! reports (cons r reports))))))
    (define-values (content audit)
      (sk:output->bytes/audit pages fmt #:policy 'error #:text-mode mode
        #:title (string-append "Skia DC 0.63 / " id) #:raster-dpi 144))
    (unless (and (= calls (length pages)) (andmap (lambda (r) (hash-ref r 'dc_expired)) reports))
      (error 'dc-output-doctor "authoring count or lifetime mismatch"))
    (define file (string-append id "." (symbol->string fmt)))
    (call-with-output-file (build-path directory file)
      (lambda (out) (write-bytes content out)) #:mode 'binary #:exists 'error)
    (define-values (pw ph) (sk:output-page-size-in-points (car pages)))
    (set! entries
      (cons (hasheq 'id id 'file file 'kind kind 'format (symbol->string fmt)
                    'text_mode (symbol->string mode) 'pages (length pages)
                    'width_points pw 'height_points ph 'authoring_calls calls
                    'layout layout 'dc_reports (reverse reports)
                    'raster_callback_calls (if counter (unbox counter) 0)
                    'audit_policy "error"
                    'audit (sk:output-audit-report->jsexpr audit)) entries)))
  (for* ([fmt '(pdf svg)] [mode '(native outline)])
    (emit (format "vector-~a-~a" fmt mode) "vector" fmt (list draw-output-vector-scene)
          160 120 #:text-mode mode))
  (for ([fmt '(pdf svg)])
    (define counter (box 0))
    (emit (format "mixed-~a" fmt) "mixed" fmt
      (list (lambda (dc) (draw-output-mixed-scene dc (lambda (_) (set-box! counter (add1 (unbox counter)))))))
      200 160 #:raster-counter counter)
    (emit (format "styles-~a" fmt) "styles" fmt (list draw-output-style-scene) 80 64)
    (emit (format "units-~a" fmt) "units" fmt
      (list (lambda (dc) (output-fill dc "red" 0 0 5 3) (hash)))
      25.4 12.7 #:unit 'mm #:margins 1)
    (define (link-page dc)
      (output-fill dc "red" 8 8 24 18)
      (output-label dc)
      (dc-annotate-url! dc 8 8 24 18 "https://example.org/skia-063")
      (dc-link-destination! dc 8 40 80 16 "second")
      (when (eq? fmt 'svg) (dc-define-destination! dc "second" 100 80))
      (hash))
    (emit (format "links-~a" fmt) "links" fmt
      (if (eq? fmt 'pdf)
          (list link-page (lambda (dc) (dc-define-destination! dc "second" 10 10)
                           (output-fill dc "blue" 8 8 24 18) (hash)))
          (list link-page)) 160 120))
  (for* ([consumer (in-list (make-output-consumers))] [fmt '(pdf svg)])
    (emit (format "~a-~a-~a" (car consumer) (cadr consumer) fmt)
          (car consumer) fmt (list (caddr consumer)) 320 240))
  (define receipt
    (hasheq 'schema 1 'stage "0.63" 'status "passed" 'run_token token
            'identity (hasheq 'version (version) 'os (symbol->string (system-type 'os))
                              'architecture (symbol->string (system-type 'arch))
                              'vm (symbol->string (system-type 'vm)))
            'physical_display_verified #f 'pdfa_certified #f 'color_fidelity_certified #f
            'documents (reverse entries)))
  (call-with-output-file (build-path directory "documents.json")
    (lambda (out) (write-json receipt out) (newline out)) #:exists 'error)
  (printf "dc-output-documents: ~a documents; passed.\n" (length entries))
  receipt)
(module+ main
  (define directory #f) (define token #f)
  (command-line #:once-each
    [("--directory") value "new evidence directory" (set! directory value)]
    [("--run-token") value "caller-supplied receipt identity" (set! token value)]
    #:args () (void))
  (unless (and directory token) (error 'dc-output-doctor "--directory and --run-token are required"))
  (void (generate-dc-output-evidence directory token)))
