#lang racket/base
(require json racket/cmdline racket/file
         "../main.rkt" "../tests/codec-query-fixtures.rkt" "../tests/codec-fixtures.rkt")
(provide generate-codec-query-evidence)
(define scales '(1 0.5 0.25 0.125 2))
(define (generate-codec-query-evidence directory token)
  (make-directory* directory)
  (define (save name bytes)
    (call-with-output-file (build-path directory name) (lambda (out) (write-bytes bytes out)) #:exists 'error #:mode 'binary))
  (define (pixels c)
    (with-skia ([im (codec->image c #:normalize-origin? #f)]) (image->rgba-bytes im)))
  (define rows
    (for/list ([format '(png jpeg webp)])
      (define name (symbol->string format))
      (define encoded (query-fixture-bytes format))
      (save (string-append name ".encoded") encoded)
      (with-skia ([c (codec-from-bytes encoded)])
        (define before (pixels c))
        (save (string-append name "-before.rgba") before)
        (define sizes
          (for/list ([scale (in-list scales)])
            (define-values (w h) (codec-scaled-dimensions c scale))
            (list scale w h)))
        (define subset (codec-supported-subset c 1 3 6 5))
        (define even (codec-supported-subset c 2 4 6 4))
        (define after (pixels c))
        (unless (bytes=? before after) (error 'codec-query-doctor "query altered subsequent decoding"))
        (save (string-append name "-after.rgba") after)
        (hasheq 'format name 'source_size '(16 12) 'scaled sizes
                'odd_subset (and subset (vector->list subset))
                'even_subset (and even (vector->list even))
                'decode_unchanged #t))))
  (define orientation-size
    (with-skia ([c (codec-from-bytes (jpeg-with-origin (query-fixture-bytes 'jpeg) 6))])
      (call-with-values (lambda () (codec-scaled-dimensions c 0.5)) list)))
  (define report
    (hasheq 'schema 1 'stage "0.76a" 'run_token token 'native_version (skia-native-version)
            'status "passed" 'query_coordinates "encoded-pixels"
            'oriented_jpeg_half orientation-size 'formats rows
            'scaled_decode_executed #f 'subset_decode_executed #f 'gpu_executed #f))
  (call-with-output-file (build-path directory "queries.json")
    (lambda (out) (write-json report out) (newline out)) #:exists 'error)
  (displayln "codec-query-native-evidence: passed"))
(module+ main
  (define directory #f) (define token #f)
  (command-line #:once-each
    [("--directory") path "New evidence directory" (set! directory path)]
    [("--token") text "Unique run token" (set! token text)])
  (unless (and directory token) (error 'codec-query-doctor "--directory and --token are required"))
  (when (directory-exists? directory) (error 'codec-query-doctor "evidence directory must be new"))
  (generate-codec-query-evidence directory token))
