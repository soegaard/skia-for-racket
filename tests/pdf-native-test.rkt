#lang racket/base
(require rackunit racket/file racket/path
         "../main.rkt")
(provide pdf-native-tests)

;; Deliberately lightweight smoke checks, not a replacement for a PDF parser.
(define (check-pdf bs pages)
  (check-true (bytes? bs))
  (check-true (regexp-match? #rx#"^%PDF-" bs))
  (check-true (regexp-match? #rx#"%%EOF[ \t\r\n]*$" bs))
  (check-equal? (length (regexp-match* #rx#"/Type[ \t\r\n]*/Page[ \t\r\n/>]" bs)) pages))

(define (blank-page d [w 200] [h 100])
  (call-with-document-page d w h (lambda (_) (void))))

(define (with-temp-dir proc)
  (define d (make-temporary-file "skia-pdf-native-~a" 'directory))
  (dynamic-wind void (lambda () (proc d)) (lambda () (delete-directory/files d))))

(define pdf-native-tests
  (test-suite
   "PDF documents and borrowed page canvases"
   (test-case "multi-page documents expose the existing canvas API"
     (with-skia ([d (make-pdf-document #:title "PDF test")]
                 [p (make-paint #:color 'red)])
       (check-true (skia-resource? d))
       (check-eq? (document-state d) 'open)
       (define c (document-begin-page! d 200.5 100.25))
       (check-true (canvas? c))
       (check-false (skia-resource? c))
       (check-eq? (document-state d) 'page)
       (draw-circle c 50 50 20 p)
       (document-end-page! d)
       (blank-page d 300 200)
       (check-equal? (document-page-count d) 2)
       (document-finish! d)
       (check-eq? (document-state d) 'finished)
       (check-pdf (document->pdf-bytes d) 2)))
   (test-case "old page canvases remain invalid when later pages begin"
     (with-skia ([d (make-pdf-document)])
       (define old (document-begin-page! d 100 100))
       (document-end-page! d)
       (check-true (skia-closed? old))
       (define next (document-begin-page! d 100 100))
       (check-exn #rx"closed" (lambda () (canvas-clear! old 'red)))
       (check-exn #rx"closed" (lambda () (canvas-save! old)))
       (check-false (skia-closed? next))
       (canvas-clear! next 'blue)
       (document-end-page! d)
       (document-finish! d)))
   (test-case "state machine rejects nesting, missing pages, and premature finish"
     (with-skia ([d (make-pdf-document)])
       (check-exn exn:fail? (lambda () (document-end-page! d)))
       (check-exn exn:fail? (lambda () (document-finish! d)))
       (check-exn exn:fail? (lambda () (document->pdf-bytes d)))
       (void (document-begin-page! d 100 100))
       (check-exn exn:fail? (lambda () (document-begin-page! d 200 100)))
       (check-exn exn:fail? (lambda () (document-finish! d)))
       (document-end-page! d)
       (document-finish! d)
       (check-exn exn:fail? (lambda () (document-begin-page! d 100 100)))))
   (test-case "finish is idempotent and byte results are independent copies"
     (define result
       (with-skia ([d (make-pdf-document)])
         (blank-page d)
         (document-finish! d)
         (define a (document->pdf-bytes d))
         (document-finish! d)
         (define b (document->pdf-bytes d))
         (check-equal? a b)
         (bytes-set! a 0 0)
         (check-equal? (bytes-ref b 0) (char->integer #\%))
         b))
     (check-pdf result 1))
   (test-case "abort releases native state and invalidates the current page"
     (with-skia ([d (make-pdf-document)])
       (define c (document-begin-page! d 100 100))
       (document-abort! d)
       (document-abort! d)
       (check-eq? (document-state d) 'aborted)
       (check-true (skia-closed? d))
       (check-true (skia-closed? c))
       (check-exn #rx"closed" (lambda () (canvas-clear! c 'white)))
       (check-exn #rx"closed" (lambda () (document->pdf-bytes d)))))
   (test-case "generic close aborts unfinished output and cannot close a borrowed canvas"
     (define d (make-pdf-document))
     (define c (document-begin-page! d 100 100))
     (check-exn exn:fail:contract? (lambda () (skia-close! c)))
     (skia-close! d)
     (skia-close! d)
     (check-eq? (document-state d) 'closed)
     (check-true (skia-closed? c))
     (check-exn #rx"closed" (lambda () (canvas-save-count c))))
   (test-case "page helper ends on success and preserves multiple return values"
     (with-skia ([d (make-pdf-document)])
       (define saved #f)
       (define-values (a b)
         (with-document-page (c d 100 100)
           (set! saved c)
           (values 'a 'b)))
       (check-equal? (list a b) '(a b))
       (check-true (skia-closed? saved))
       (check-equal? (document-page-count d) 1)
       (document-finish! d)))
   (test-case "page helper aborts for arbitrary raised values"
     (with-skia ([d (make-pdf-document)])
       (define c #f)
       (define result
         (with-handlers ([(lambda (e) (eq? e 'stop)) (lambda (e) e)])
           (with-document-page (page d 100 100)
             (set! c page)
             (raise 'stop))))
       (check-eq? result 'stop)
       (check-eq? (document-state d) 'aborted)
       (check-true (skia-closed? c))))
   (test-case "continuation escape aborts a partially drawn document"
     (with-skia ([d (make-pdf-document)])
       (check-eq?
        (let/ec escape
          (with-document-page (c d 100 100) (escape 'escaped)))
        'escaped)
       (check-eq? (document-state d) 'aborted)))
   (test-case "continuations cannot reenter an expired page scope"
     (with-skia ([d (make-pdf-document)])
       (define saved #f)
       (with-document-page (c d 100 100)
         (call/cc (lambda (k) (set! saved k) (void))))
       (check-exn exn:fail? (lambda () (saved (void))))
       (document-finish! d)))
   (test-case "scoped pages and nested canvas scopes cannot be manually ended"
     (with-skia ([d (make-pdf-document)])
       (with-document-page (c d 100 100)
         (check-exn #rx"protected" (lambda () (document-end-page! d)))
         (with-canvas-state c
           (canvas-translate! c 10 20)
           (check-exn #rx"protected" (lambda () (document-end-page! d)))
           (check-exn exn:fail? (lambda () (document-finish! d)))))
       (define c (document-begin-page! d 100 100))
       (define base (canvas-save-count c))
       (with-canvas-state c
         (canvas-save! c)
         (check-exn #rx"protected" (lambda () (document-end-page! d))))
       (check-equal? (canvas-save-count c) base)
       (document-end-page! d)
       (document-finish! d)))
   (test-case "canvas state cleanup is safe after the document is explicitly closed"
     (with-skia ([d (make-pdf-document)])
       (define c (document-begin-page! d 100 100))
       (with-canvas-state c (skia-close! d))
       (check-true (skia-closed? c))))
   (test-case "PDF retains draw dependencies after their wrappers are closed"
     (with-skia ([d (make-pdf-document)])
       (with-document-page (c d 300 200)
         (with-skia ([gradient (make-linear-gradient-shader 0 0 100 0 '(red blue))]
                     [p (make-paint #:shader gradient)]
                     [path (make-path '((move 10 10) (line 150 50) (line 10 90) (close)))]
                     [s (make-surface 8 8 #:background 'red)]
                     [im (surface-snapshot s)]
                     [font (make-font #:size 16)]
                     [ink (make-paint #:color 'black)])
           (draw-path c path p)
           (draw-image-rect c im 170 10 100 100)
           (draw-simple-text c "PDF resource retention" 10 150 font ink)))
       (collect-garbage)
       (document-finish! d)
       (define bs (document->pdf-bytes d))
       (check-pdf bs 1)
       (check-true (regexp-match? #rx#"/Font" bs))
       (check-true (regexp-match? #rx#"/Image" bs))))
   (test-case "byte limit rejects oversize finalized output and closes native resources"
     (with-skia ([d (make-pdf-document)])
       (blank-page d)
       (parameterize ([current-skia-byte-limit 16])
         (check-exn #rx"byte-limit" (lambda () (document-finish! d))))
       (check-eq? (document-state d) 'aborted)
       (check-true (skia-closed? d))))
   (test-case "lowering the byte limit checks each copy without corrupting finished output"
     (with-skia ([d (make-pdf-document)])
       (blank-page d)
       (document-finish! d)
       (parameterize ([current-skia-byte-limit 16])
         (check-exn #rx"byte-limit" (lambda () (document->pdf-bytes d))))
       (check-eq? (document-state d) 'finished)
       (check-pdf (document->pdf-bytes d) 1)))
   (test-case "large vector pages do not require a full RGBA raster budget"
     (with-skia ([d (make-pdf-document)])
       (parameterize ([current-skia-byte-limit 16]) (blank-page d 10000 10000))
       (document-finish! d)
       (check-pdf (document->pdf-bytes d) 1)))
   (test-case "file helper preserves destinations when drawing fails"
     (with-temp-dir
      (lambda (dir)
        (define file (build-path dir "test.pdf"))
        (call-with-output-file file (lambda (p) (write-bytes #"original" p)))
        (define called? #f)
        (check-exn exn:fail?
                   (lambda () (call-with-pdf-file file (lambda (_) (set! called? #t)))))
        (check-false called?)
        (check-exn #rx"drawing failed"
                   (lambda ()
                     (call-with-pdf-file file
                       (lambda (d) (blank-page d) (error 'test "drawing failed"))
                       #:exists 'replace)))
        (check-equal? (file->bytes file) #"original")
        (call-with-pdf-file file (lambda (d) (blank-page d)) #:exists 'replace)
        (check-pdf (file->bytes file) 1)
        (check-equal? (length (directory-list dir)) 1))))
   (test-case "save-pdf requires finish and writes independent complete files"
     (with-temp-dir
      (lambda (dir)
        (define file (build-path dir "saved.pdf"))
        (with-skia ([d (make-pdf-document)])
          (blank-page d)
          (check-exn exn:fail? (lambda () (save-pdf d file)))
          (check-false (file-exists? file))
          (document-finish! d)
          (save-pdf d file)
          (check-equal? (file->bytes file) (document->pdf-bytes d)))
        (check-pdf (file->bytes file) 1))))
   (test-case "native document operations are thread-confined"
     (with-skia ([d (make-pdf-document)])
       (define ch (make-channel))
       (thread
        (lambda ()
          (channel-put ch
            (with-handlers ([exn:fail? exn-message])
              (document-begin-page! d 100 100) "unexpected success"))))
       (check-true (regexp-match? #rx"another Racket thread" (channel-get ch)))
       (blank-page d)
       (document-finish! d)))
   (test-case "byte helper closes the document and rejects an unended manual page"
     (define saved #f)
     (define bs
       (call-with-pdf-bytes
        (lambda (d) (set! saved d) (blank-page d) (values 1 2 3))))
     (check-true (skia-closed? saved))
     (check-pdf bs 1)
     (check-exn exn:fail?
                (lambda () (call-with-pdf-bytes
                             (lambda (d) (set! saved d) (document-begin-page! d 100 100)))))
     (check-true (skia-closed? saved)))
   (test-case "metadata is copied from UTF-8 strings and explicit dates"
     (define bs
       (call-with-pdf-bytes
        (lambda (d) (blank-page d))
        #:title "PDF metadata probe" #:author "Søgaard" #:subject "Vector output"
        #:keywords "Racket, Skia" #:creator "PDF test" #:producer "Skia PDF test"
        #:creation-date (seconds->date 0 #f) #:modified-date (seconds->date 86400 #f)
        #:raster-dpi 72 #:encoding-quality 101))
     (check-pdf bs 1)
     (check-true (regexp-match? #rx#"/Title" bs))
     (check-true (regexp-match? #rx#"PDF metadata probe" bs))
     (check-true (regexp-match? #rx#"D:19700101" bs))
     (check-true (regexp-match? #rx#"D:19700102" bs)))))

(module+ test
  (require rackunit/text-ui)
  (define failures (run-tests pdf-native-tests))
  (unless (zero? failures) (error 'pdf-native-test "~a failures" failures)))
