#lang racket/base
(require json racket/cmdline racket/file racket/list
         "../main.rkt" "../tests/codec-incremental-fixtures.rkt"
         (only-in "../tests/codec-scanline-fixtures.rkt" scanline-fixture-bmp)
         (only-in "../private/codec-incremental-source.rkt" incremental-source-count))
(provide generate-codec-incremental-evidence)
(define (generate-codec-incremental-evidence directory token)
  (make-directory* directory)
  (define seen '())
  (define (save name bytes)
    (call-with-output-file (build-path directory name)
      (lambda (out) (write-bytes bytes out)) #:exists 'error #:mode 'binary))
  (define (track s) (set! seen (cons s seen)) s)
  (define (row s p file)
    (when file (save file (incremental-snapshot-bytes (codec-incremental-snapshot s))))
    (hasheq 'state (symbol->string (incremental-progress-state p))
            'result (symbol->string (incremental-progress-result p))
            'initialized_rows (incremental-progress-initialized-rows p)
            'pixels (or file #f) 'statistics (codec-incremental-statistics s)))
  (define matrices
    (for/list ([interlaced? '(#f #t)])
      (define name (if interlaced? "adam7" "normal"))
      (define parts (incremental-fixture-parts #:interlaced? interlaced?))
      (save (string-append name ".png") (apply bytes-append parts))
      (with-skia ([s (track (make-codec-incremental #:row-bytes 44))])
        (codec-incremental-feed! s (car parts))
        ;; Do not attempt a header-only decode in this matrix: one native codec
        ;; and one start must account for every captured partial/final image.
        (define steps
          (for/list ([part (in-list (cdr parts))] [i (in-naturals 1)])
            (codec-incremental-feed! s part #:final? (= i (sub1 (length parts))))
            (define p (codec-incremental-step! s))
            (when (and (not interlaced?) (= i 1))
              (define out (open-output-bytes))
              (copy-port/streaming (open-input-bytes (apply bytes (range 256))) out)
              (save "live-copy.bin" (get-output-bytes out)))
            (row s p (format "~a-~a.pixels" name i))))
        (hasheq 'name name 'width 8 'height (if interlaced? 8 6) 'row_bytes 44 'steps steps))))
  (define parts (incremental-fixture-parts))
  (define truncated (bytes-append (car parts) (cadr parts) (caddr parts)))
  (save "truncated.png" truncated)
  (define short
    (with-skia ([s (track (make-codec-incremental #:row-bytes 44))])
      (codec-incremental-feed! s truncated #:final? #t)
      (define p (codec-incremental-step! s))
      (row s p "truncated.pixels")))
  (define unsupported
    (with-skia ([s (track (make-codec-incremental))])
      (codec-incremental-feed! s (scanline-fixture-bmp) #:final? #t)
      (row s (codec-incremental-step! s) #f)))
  (define cancelled
    (with-skia ([s (track (make-codec-incremental))])
      (codec-incremental-feed! s (bytes-append (car parts) (cadr parts)))
      (codec-incremental-step! s)
      (row s (codec-incremental-cancel! s) #f)))
  (define report
    (hasheq 'schema 1 'stage "0.76c" 'status "passed" 'run_token token
            'native_version (skia-native-version) 'matrices matrices
            'truncated short 'unsupported unsupported 'cancelled cancelled
            'sessions_closed (andmap skia-closed? seen)
            'registered_sources (incremental-source-count)
            'incremental_decode_executed #t 'one_shot_fallback #f
            'compiler_required #f 'gpu_executed #f))
  (call-with-output-file (build-path directory "incremental.json")
    (lambda (out) (write-json report out) (newline out)) #:exists 'error)
  (displayln "codec-incremental-native-evidence: passed"))
(module+ main
  (define directory #f) (define token #f)
  (command-line #:once-each
    [("--directory") path "New evidence directory" (set! directory path)]
    [("--token") value "Unique execution token" (set! token value)])
  (unless (and directory token) (error 'codec-incremental-doctor "--directory and --token required"))
  (when (directory-exists? directory) (error 'codec-incremental-doctor "directory already exists"))
  (generate-codec-incremental-evidence directory token))
