#lang racket/base

;;;
;;; Reference Output Pure Test
;;;

;; Checks page units, margins, output policies, explicit picture trust, and protected page syntax.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Native-free public API checks. No document or picture is allocated.
(require rackunit racket/list skia)

;;;
;;; Page Syntax Expansion
;;;

;; Expand the actual imported macro in this module's namespace. Do not evaluate
;; the supplied form: even the document and dimension expressions may raise.

; expansion-anchor : namespace-anchor?
;   Anchors page-form expansion in the namespace containing this module's imports.
(define-namespace-anchor expansion-anchor)

; expand-page-form : any/c -> syntax?
;   Expands a page-scoping form in the test namespace without generating a native document.
(define (expand-page-form form)
  (parameterize ([current-namespace (namespace-anchor->namespace expansion-anchor)])
    (expand (datum->syntax #f form))))

(module+ test

  ;;;
  ;;; Page Dimensions, Replay, and Export Policies
  ;;;

  (test-case "unit conversion preserves exact arithmetic and uses CSS pixels"
    (check-equal? (unit->points 1 'in) 72)
    (check-equal? (unit->points 127/5 'mm) 72)
    (check-equal? (unit->points 96 'px) 72)
    (check-equal? (unit->points -1 'in) -72)
    (check-exn exn:fail? (lambda () (unit->points 1 'pixels))))

  (test-case "page creation does not run the callback"
    (define calls 0)
    (define page (make-output-page 20 10 (lambda (canvas) (set! calls (add1 calls)))))
    (check-true (output-page? page))
    (check-false (skia-resource? page))
    (check-equal? calls 0)
    (check-equal? (output-page-width page) 20))

  (test-case "margin order is left top right bottom in page units"
    (define page (make-output-page 60 40 void #:unit 'mm #:margins '(2 3 5 7)))
    (check-equal? (output-page-margins page) '(2 3 5 7))
    (check-equal? (call-with-values (lambda () (output-page-content-size page)) list) '(53 30))
    (check-equal? (call-with-values (lambda () (output-page-size-in-points page)) list)
                  (list (* 60 360/127) (* 40 360/127)))
    (check-true (output-page-clip? page)))

  (test-case "page descriptions reject empty content and required callback keywords"
    (check-exn exn:fail? (lambda () (make-output-page 10 10 void #:margins 5)))
    (check-exn exn:fail? (lambda () (make-output-page 10 10 void #:margins #(1 1 1 1))))
    (check-exn exn:fail?
               (lambda () (make-output-page 10 10 (lambda (c #:required value) value))))
    (check-exn exn:fail? (lambda () (make-output-page 14401 1 void))))

  (test-case "format restrictions are checked before callbacks or native allocation"
    (define calls 0)
    (define page (make-output-page 10 10 (lambda (c) (set! calls (add1 calls)))))
    (check-exn exn:fail? (lambda () (output->bytes (list page page) 'svg)))
    (check-exn exn:fail? (lambda () (output->bytes page 'pdf #:id-prefix "svg-only")))
    (check-exn exn:fail? (lambda () (output->bytes page 'svg #:encoding-quality 90)))
    (check-exn exn:fail? (lambda () (output->bytes page 'svg #:pdfa? #t)))
    (check-exn exn:fail? (lambda () (output->bytes '() 'pdf)))
    (check-equal? calls 0))

  (test-case "raster-scale and text-mode parameters validate without native loading"
    (parameterize ([current-text-output-mode 'outline] [current-raster-output-scale 2])
      (check-equal? (current-text-output-mode) 'outline)
      (check-equal? (current-raster-output-scale) 2))
    (check-exn exn:fail? (lambda () (current-text-output-mode 'auto)))
    (check-exn exn:fail? (lambda () (current-raster-output-scale 0)))
    (check-exn exn:fail? (lambda () (current-raster-output-scale 1025))))

  (test-case "SKP loading is refused without explicit boolean trust"
    (check-exn exn:fail? (lambda () (picture-from-bytes (make-bytes 29))))
    (check-exn exn:fail? (lambda () (picture-from-file "not-opened.skp")))
    (check-exn exn:fail? (lambda () (picture-from-bytes #"" #:trusted? 'yes))))

  (test-case "destination IDs are immutable UTF-8 encodings, not registration"
    (check-equal? (destination-id "A") "dest-41")
    (check-equal? (destination-id "é") "dest-c3a9")
    (check-equal? (svg-destination-id "A" #:id-prefix "page") "page-dest-41")
    (check-true (immutable? (destination-id "A")))
    (check-not-equal? (destination-id "A") (destination-id "a"))
    (check-exn exn:fail? (lambda () (destination-id "")))
    (check-exn exn:fail? (lambda () (destination-id "bad\nname")))
    (check-exn exn:fail? (lambda () (svg-destination-id "A" #:id-prefix "1bad"))))

  (test-case "construction settings reject invalid values before native initialization"
    (check-exn exn:fail? (lambda () (make-pdf-document #:raster-dpi 0)))
    (check-exn exn:fail? (lambda () (make-pdf-document #:encoding-quality 102)))
    (check-exn exn:fail? (lambda () (make-pdf-document #:title "bad\0title")))
    (check-exn exn:fail? (lambda () (make-svg-document 0 10)))
    (check-exn exn:fail? (lambda () (make-svg-document 10 10 #:id-prefix "bad prefix"))))

  ;;;
  ;;; Page Macro Expansion
  ;;;

  (test-case "page macro accepts one expression without evaluating any supplied expression"
    (check-not-exn
     (lambda ()
       (expand-page-form
        '(with-pdf-page
           (canvas (error 'expansion-only "document expression ran")
                   (error 'expansion-only "width expression ran")
                   (error 'expansion-only "height expression ran"))
           (error 'expansion-only "body expression ran" canvas))))))

  (test-case "page macro binds its canvas and permits internal definitions and multiple values"
    (check-not-exn
     (lambda ()
       (expand-page-form
        '(with-pdf-page (canvas #f 20 10)
           (define saved canvas)
           (define (results) (values saved 'page-complete))
           (results))))))

  (test-case "page macro rejects empty and definitions-only bodies during expansion"
    (check-exn exn:fail:syntax?
               (lambda () (expand-page-form '(with-pdf-page (canvas #f 20 10)))))
    (check-exn exn:fail:syntax?
               (lambda ()
                 (expand-page-form
                  '(with-pdf-page (canvas #f 20 10) (define saved canvas))))))

  (test-case "page macro requires an identifier in the canvas binding position"
    (check-exn exn:fail:syntax?
               (lambda ()
                 (expand-page-form '(with-pdf-page (42 #f 20 10) (void)))))))
