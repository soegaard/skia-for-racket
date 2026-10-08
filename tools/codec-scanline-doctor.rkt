#lang racket/base
(require json racket/cmdline racket/file racket/list
         "../main.rkt" "../tests/codec-scanline-fixtures.rkt" "../tests/codec-fixtures.rkt")
(provide generate-scanline-evidence)
(define (generate-scanline-evidence directory token)
  (make-directory* directory)
  (define (save name bytes)
    (call-with-output-file (build-path directory name)
      (lambda (out) (write-bytes bytes out)) #:exists 'error #:mode 'binary))
  (define bottom (scanline-fixture-bmp))
  (define top (scanline-fixture-bmp #:top-down? #t))
  (define short-bottom (scanline-fixture-truncated-bmp))
  (define short-top (scanline-fixture-truncated-bmp #:top-down? #t))
  (define jpeg (scanline-fixture-jpeg))
  (define rotated (jpeg-with-origin jpeg 6))
  (define png (scanline-fixture-png))
  (for ([name '("bottom.bmp" "top.bmp" "short-bottom.bmp" "short-top.bmp" "reference.jpeg" "rotated.jpeg" "unsupported.png")]
        [data (list bottom top short-bottom short-top jpeg rotated png)]) (save name data))
  (define (record name input actions #:scale [scale 1] #:stride [stride #f])
    (with-skia ([s (codec-scanline-from-bytes input #:scale scale)])
      (define info (codec-scanline-info s))
      (define source (codec-scanline-source-info s))
      (define order (codec-scanline-order s))
      (define mappings
        (for/list ([i (in-range (image-info-height info))]) (codec-scanline-output-row s i)))
      (define steps
        (for/list ([action actions] [i (in-naturals)])
          (define op (car action)) (define n (cadr action))
          (define before (codec-scanline-position s))
          (define before-row (codec-scanline-next-row s))
          (define details
            (case op
              [(read)
               (define batch (codec-scanline-read! s n #:row-bytes stride))
               (define file (format "~a-~a.rows" name i))
               (save file (scanline-batch-bytes batch))
               (hasheq 'decoded (scanline-batch-decoded-count batch)
                       'first_row (scanline-batch-first-row batch)
                       'row_bytes (scanline-batch-row-bytes batch)
                       'height (image-info-height (scanline-batch-info batch))
                       'complete (scanline-batch-complete? batch) 'file file)]
              [(skip) (hasheq 'skipped (codec-scanline-skip! s n))]))
          (define state (codec-scanline-state s))
          (hasheq 'op (symbol->string op) 'count n 'before before 'before_row before-row
                  'after (codec-scanline-position s) 'state (symbol->string state)
                  'next_row (if (memq state '(ready complete)) (codec-scanline-next-row s) #f)
                  'result details)))
      (define final-state (codec-scanline-state s))
      (skia-close! s)
      (hasheq 'name name 'width (image-info-width info) 'height (image-info-height info)
              'color_type (symbol->string (image-info-color-type info))
              'alpha_type (symbol->string (image-info-alpha-type info)) 'color_space "srgb"
              'order (symbol->string order)
              'origin (symbol->string (encoded-image-info-origin source)) 'mappings mappings
              'steps steps 'final_state (symbol->string final-state) 'closed (skia-closed? s))))
  (define cases
    (list (record "bottom" bottom '((read 2) (read 1) (read 2)) #:stride 32)
          (record "top" top '((read 2) (read 1) (read 2)))
          (record "skip" bottom '((skip 1) (read 2) (skip 1) (read 1)))
          (record "short-bottom" short-bottom '((read 5)))
          (record "short-top" short-top '((read 5)))
          (record "empty" short-bottom '((read 2) (read 1)))
          (record "skip-failed" short-bottom '((skip 5)))
          (record "jpeg" jpeg '((read 3) (read 4) (read 5)))
          (record "jpeg-half" jpeg '((read 2) (read 1) (read 3)) #:scale 1/2)
          (record "rotated-half" rotated '((read 2) (read 4)) #:scale 1/2)))
  (define unsupported
    (with-handlers ([exn:fail:codec-scanline?
                     (lambda (e) (hasheq 'result (symbol->string (exn:fail:codec-scanline-result e))
                                        'code (exn:fail:codec-scanline-native-code e)))])
      (with-skia ([s (codec-scanline-from-bytes png)]) (error 'scanline-doctor "unexpected PNG scanline support"))))
  (define report
    (hasheq 'schema 1 'stage "0.76b" 'run_token token 'status "passed" 'native_version (skia-native-version)
            'cases cases 'unsupported_png unsupported 'session_scope "owned-private-codec"
            'scaled_scanline_executed #t 'subset_decode_executed #f
            'incremental_decode_executed #f 'live_port_callbacks #f 'gpu_executed #f))
  (call-with-output-file (build-path directory "scanlines.json")
    (lambda (out) (write-json report out) (newline out)) #:exists 'error)
  (displayln "codec-scanline-evidence: passed"))
(module+ main
  (define directory #f) (define token #f)
  (command-line #:once-each
    [("--directory") path "Fresh native evidence directory" (set! directory path)]
    [("--token") value "Unique run token" (set! token value)])
  (unless (and directory token) (error 'scanline-doctor "--directory and --token are required"))
  (when (directory-exists? directory) (error 'scanline-doctor "evidence directory already exists"))
  (generate-scanline-evidence directory token))
