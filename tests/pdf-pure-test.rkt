#lang racket/base
(require rackunit racket/file racket/path ffi/unsafe
         "../main.rkt" "../private/types.rkt" "../private/pdf-util.rkt")
(provide pdf-pure-tests)

(define (with-temp-dir proc)
  (define d (make-temporary-file "skia-pdf-test-~a" 'directory))
  (dynamic-wind void (lambda () (proc d)) (lambda () (delete-directory/files d))))

(define pdf-pure-tests
  (test-suite
   "PDF pure validation and ABI"
   (test-case "PDF metadata layouts include bool padding and complete timestamps"
     (define p (ctype-sizeof _pointer))
     (check-equal? (ctype-sizeof _sk-pdf-datetime) 10)
     (check-equal? (ctype-sizeof _sk-pdf-metadata) (if (= p 8) 80 44))
     (define md (make-sk-pdf-metadata #f #f #f #f #f #f #f #f 144.0 #t 101))
     (check-equal? (ptr-ref (ptr-add md (* 8 p)) _float) 144.0)
     (check-equal? (ptr-ref (ptr-add md (+ (* 8 p) 4)) _uint8) 1)
     (check-equal? (ptr-ref (ptr-add md (+ (* 8 p) 8)) _int) 101)
     (void/reference-sink md))
   (test-case "PDF dimensions are fractional points, not raster dimensions"
     (check-equal? (pdf-page-dimension 'test 595.25) 595.25)
     (parameterize ([current-skia-byte-limit 1])
       (check-equal? (pdf-page-dimension 'test 14400) 14400.0))
     (for ([v (in-list (list 0 -1 1e-100 14401 +inf.0 +nan.0 1+2i 'bad))])
       (check-exn exn:fail:contract? (lambda () (pdf-page-dimension 'test v)))))
   (test-case "raster DPI validation is finite and bounded"
     (check-equal? (pdf-raster-dpi 'test 300) 300.0)
     (for ([v (in-list (list 0 -1 9601 +inf.0 +nan.0 'bad))])
       (check-exn exn:fail:contract? (lambda () (pdf-raster-dpi 'test v)))))
   (test-case "image encoding quality preserves the native lossless sentinel"
     (for ([n '(0 50 100 101)]) (check-equal? (pdf-encoding-quality 'test n) n))
     (for ([v '(-1 102 50.5 bad)])
       (check-exn exn:fail:contract? (lambda () (pdf-encoding-quality 'test v)))))
   (test-case "metadata uses UTF-8 and rejects NUL, wrong types, and aggregate overflow"
     (check-equal? (pdf-metadata-bytes 'test '("" "Søgaard"))
                   (list #"" (string->bytes/utf-8 "Søgaard")))
     (check-exn exn:fail? (lambda () (pdf-metadata-bytes 'test (list "a\0b"))))
     (check-exn exn:fail:contract? (lambda () (pdf-metadata-bytes 'test '(7))))
     (parameterize ([current-skia-byte-limit 3])
       (check-exn #rx"byte-limit" (lambda () (pdf-metadata-bytes 'test '("ab" "cd"))))))
   (test-case "dates preserve local clock fields and signed minute offsets"
     (check-false (pdf-date-time 'test #f))
     (define d (struct-copy date (seconds->date 0 #f) [time-zone-offset -3600]))
     (define dt (pdf-date-time 'test d))
     (check-equal? (sk-pdf-datetime-year dt) 1970)
     (check-equal? (sk-pdf-datetime-month dt) 1)
     (check-equal? (sk-pdf-datetime-day dt) 1)
     (check-equal? (sk-pdf-datetime-zone-minutes dt) -60))
   (test-case "dates reject invalid calendar days and non-minute offsets"
     (define d (seconds->date 0 #f))
     (check-exn exn:fail? (lambda () (pdf-date-time 'test (struct-copy date d [month 2] [day 30]))))
     (check-exn exn:fail? (lambda () (pdf-date-time 'test (struct-copy date d [time-zone-offset 30]))))
     (check-exn exn:fail:contract? (lambda () (pdf-date-time 'test "today")))
     (check-equal? (sk-pdf-datetime-day
                    (pdf-date-time 'test (struct-copy date d [year 2024] [month 2] [day 29]))) 29))
   (test-case "constructor options fail before native loading"
     (check-exn exn:fail:contract? (lambda () (make-pdf-document #:raster-dpi 0)))
     (check-exn exn:fail:contract? (lambda () (make-pdf-document #:encoding-quality 102)))
     (check-exn exn:fail:contract? (lambda () (make-pdf-document #:title #f)))
     (check-exn exn:fail:contract? (lambda () (make-pdf-document #:creation-date 'now))))
   (test-case "document APIs and callbacks reject invalid arguments"
     (check-false (document? 'not-document))
     (for ([f (in-list (list document-state document-page-count document-end-page!
                             document-finish! document-abort! document->pdf-bytes))])
       (check-exn exn:fail:contract? (lambda () (f 'not-document))))
     (check-exn exn:fail:contract? (lambda () (document-begin-page! 'bad 100 100)))
     (check-exn exn:fail:contract? (lambda () (call-with-pdf-bytes (lambda () (void))))))
   (test-case "file preflight rejects directories, missing parents, and bad exists options"
     (with-temp-dir
      (lambda (dir)
        (define called? #f)
        (define (body _) (set! called? #t))
        (check-exn exn:fail? (lambda () (call-with-pdf-file dir body)))
        (check-exn exn:fail? (lambda () (call-with-pdf-file (build-path dir "missing" "x.pdf") body)))
        (check-exn exn:fail:contract?
                   (lambda () (call-with-pdf-file (build-path dir "x.pdf") body #:exists 'truncate)))
        (check-false called?))))
   (test-case "private file publisher preserves existing files and replaces on request"
     (with-temp-dir
      (lambda (dir)
        (define f (build-path dir "spaces in filename.pdf"))
        (write-pdf-file-bytes! 'test #"old" f 'error)
        (check-exn exn:fail? (lambda () (write-pdf-file-bytes! 'test #"new" f 'error)))
        (check-equal? (file->bytes f) #"old")
        (write-pdf-file-bytes! 'test #"new" f 'replace)
        (check-equal? (file->bytes f) #"new")
        (check-equal? (length (directory-list dir)) 1))))
   (test-case "preflight freezes a complete destination path"
     (with-temp-dir
      (lambda (dir)
        (define p (parameterize ([current-directory dir])
                    (pdf-output-path 'test "new.pdf" 'error)))
        (check-true (complete-path? p))
        (check-equal? p (build-path dir "new.pdf")))))))

(module+ test
  (require rackunit/text-ui)
  (define failures (run-tests pdf-pure-tests))
  (unless (zero? failures) (error 'pdf-pure-test "~a failures" failures)))
