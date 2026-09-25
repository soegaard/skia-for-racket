#lang racket/base
(require rackunit rackunit/text-ui racket/file
         "../main.rkt" "../private/output-util.rkt")
(provide output-pure-tests)

(define (blank-page) (make-output-page 72 72 void))
(define output-pure-tests
  (test-suite
   "Shared vector output: pure contracts"
   (test-case "absolute units preserve exact arithmetic"
     (check-equal? (unit->points 1 'in) 72)
     (check-equal? (unit->points 127/5 'mm) 72)
     (check-equal? (unit->points 127/50 'cm) 72)
     (check-equal? (unit->points 96 'px) 72)
     (check-equal? (unit->points -3/2) -3/2))
   (test-case "unknown units and nonfinite lengths fail"
     (for ([v (in-list (list +nan.0 +inf.0 -inf.0 'bad 1+2i))])
       (check-exn exn:fail:contract? (lambda () (unit->points v))))
     (check-exn exn:fail:contract? (lambda () (unit->points 1 'em))))
   (test-case "a page owns no native resource and stores its chosen units"
     (define p (make-output-page 3 2 void #:unit 'in #:background 'white))
     (check-true (output-page? p))
     (check-false (skia-resource? p))
     (check-equal? (output-page-unit p) 'in)
     (check-equal? (output-page-width p) 3)
     (check-equal? (output-page-height p) 2)
     (check-equal? (output-page-background p) (rgb 255 255 255))
     (check-true (output-page-clip? p))
     (check-equal? (call-with-values (lambda () (output-page-size-in-points p)) list) '(216 144)))
   (test-case "margins use left top right bottom in drawing units"
     (define p (make-output-page 100 80 void #:margins '(1 2 3 4)))
     (check-equal? (output-page-margins p) '(1 2 3 4))
     (check-equal? (call-with-values (lambda () (output-page-content-size p)) list) '(96 74))
     (check-equal? (output-page-margins (make-output-page 40 40 void #:margins 5)) '(5 5 5 5)))
   (test-case "invalid or exhaustive margins are rejected"
     (for ([m (in-list (list -1 '(0 0 -1 0) '(1 2) '(0 +inf.0 0 0) 36 '(72 0 0 0)))])
       (check-exn exn:fail? (lambda () (make-output-page 72 72 void #:margins m)))))
   (test-case "page and content-size accessors reject non-pages"
     (check-exn exn:fail:contract? (lambda () (output-page-size-in-points #f)))
     (check-exn exn:fail:contract? (lambda () (output-page-content-size #f))))
   (test-case "converted page dimensions enforce the shared vector domain"
     (check-true (output-page? (make-output-page 200 200 void #:unit 'in)))
     (for ([size (in-list '(0 -1 1/10000 14401))])
       (check-exn exn:fail:contract? (lambda () (make-output-page size 10 void))))
     (check-exn exn:fail:contract? (lambda () (make-output-page 201 2 void #:unit 'in))))
   (test-case "callbacks must accept a canvas without mandatory keywords"
     (for ([proc (in-list (list #f (lambda () (void)) (lambda (a b) (void))
                               (lambda (#:required r c) (void))))])
       (check-exn exn:fail:contract? (lambda () (make-output-page 10 10 proc)))))
   (test-case "background is validated and snapshotted at page construction"
     (define color (string-copy "#112233"))
     (define p (make-output-page 20 20 void #:background color #:clip? #f))
     (string-set! color 1 #\F)
     (check-equal? (output-page-background p) (rgb 17 34 51))
     (check-false (output-page-clip? p))
     (check-exn exn:fail? (lambda () (make-output-page 10 10 void #:background 'no-such-color)))
     (check-exn exn:fail:contract? (lambda () (make-output-page 10 10 void #:clip? 1))))
   (test-case "drawing parameters validate and restore their scopes"
     (check-eq? (current-text-output-mode) 'native)
     (parameterize ([current-text-output-mode 'outline] [current-raster-output-scale 3/2])
       (check-eq? (current-text-output-mode) 'outline)
       (check-equal? (current-raster-output-scale) 3/2))
     (check-eq? (current-text-output-mode) 'native)
     (check-exn exn:fail:contract? (lambda () (current-text-output-mode 'auto)))
     (check-exn exn:fail:contract? (lambda () (current-raster-output-scale 0))))
   (test-case "wrong output format or page list is rejected before native loading"
     (for ([source (in-list (list '() #f (list (blank-page) #f)))])
       (check-exn exn:fail:contract? (lambda () (output->bytes source 'pdf))))
     (check-exn exn:fail:contract? (lambda () (output->bytes (blank-page) 'png))))
   (test-case "SVG never silently drops extra pages"
     (check-exn #rx"exactly one"
                (lambda () (output->bytes (list (blank-page) (blank-page)) 'svg))))
   (test-case "all output settings are checked before the callback"
     (define ran? #f)
     (define page (make-output-page 20 20 (lambda (_) (set! ran? #t))))
     (check-exn exn:fail? (lambda () (output->bytes page 'pdf #:text-mode 'unknown)))
     (check-exn exn:fail? (lambda () (output->bytes page 'svg #:raster-dpi +nan.0)))
     (check-exn exn:fail? (lambda () (output->bytes page 'pdf #:raster-dpi 0)))
     (check-exn exn:fail? (lambda () (output->bytes page 'svg #:title "bad\0title")))
     (check-exn exn:fail? (lambda () (output->bytes page 'pdf #:description #f)))
     (check-exn exn:fail? (lambda () (output->bytes page 'svg #:id-prefix "space here")))
     (check-false ran?))
   (test-case "format-specific options cannot be silently ignored"
     (check-exn #rx"SVG-only" (lambda () (output->bytes (blank-page) 'pdf #:id-prefix "x")))
     (check-exn #rx"PDF-only" (lambda () (output->bytes (blank-page) 'svg #:encoding-quality 0)))
     (check-exn exn:fail:contract? (lambda () (output->bytes (blank-page) 'pdf #:encoding-quality 102))))
   (test-case "the last page's raster scale is checked before the first callback"
     (define first (make-output-page 72 72 (lambda (_) (error 'test "callback ran"))))
     (define second (make-output-page 1 1 void #:unit 'in))
     (check-exn #rx"raster scale" (lambda () (output->bytes (list first second) 'pdf #:raster-dpi 9600))))
   (test-case "padded raster geometry preserves the content box"
     (check-equal? (call-with-values (lambda () (rasterized-geometry 'test 10 20 2 '(1 2 3 4))) list)
                   '(28 52 1 2 14.0 26.0))
     (check-equal? (call-with-values (lambda () (rasterized-geometry 'test 10.25 4.5 2 0)) list)
                   '(21 9 0 0 10.25 4.5)))
   (test-case "invalid padding and oversized temporary rasters fail before drawing"
     (check-exn exn:fail:contract?
                (lambda () (draw-rasterized #f 0 0 10 10 void #:padding -1)))
     (parameterize ([current-skia-byte-limit 16])
       (check-exn #rx"byte-limit" (lambda () (rasterized-geometry 'test 2 2 1 1))))
     (check-exn exn:fail:contract? (lambda () (text-blob->path #f))))
   (test-case "SVG physical sizing only rewrites the root dimensions"
     (define input #"<?xml version=\"1.0\"?><svg width=\"72\" height=\"36\" viewBox=\"0 0 72 36\"><svg width=\"9\" height=\"8\"/></svg>")
     (define bs (svg-with-point-size 'test input 72 36))
     (check-true (regexp-match? #rx#"width=\"72.0pt\" height=\"36.0pt\" viewBox=\"0 0 72 36\"" bs))
     (check-true (regexp-match? #rx#"<svg width=\"9\" height=\"8\"/>" bs)))
   (test-case "SVG sizing checks output growth and rejects missing size attributes"
     (define input #"<svg width=\"1\" height=\"1\"></svg>")
     (parameterize ([current-skia-byte-limit (bytes-length input)])
       (check-exn #rx"byte-limit" (lambda () (svg-with-point-size 'test input 1 1))))
     (check-exn #rx"root" (lambda () (svg-with-point-size 'test #"bad" 1 1)))
     (check-exn #rx"explicit size" (lambda () (svg-with-point-size 'test #"<svg ></svg>" 1 1))))
   (test-case "existing destinations fail before a callback is invoked"
     (define tmp (make-temporary-file "skia-output-pure-~a"))
     (dynamic-wind
       void
       (lambda ()
         (define ran? #f)
         (check-exn #rx"already exists"
                    (lambda () (save-output (make-output-page 20 20 (lambda (_) (set! ran? #t))) tmp 'svg)))
         (check-false ran?))
       (lambda () (delete-file tmp))))))

(module+ test
  (unless (zero? (run-tests output-pure-tests)) (error 'output-pure-tests "test failures")))
