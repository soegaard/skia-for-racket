#lang racket/base
(require rackunit rackunit/text-ui racket/file racket/path
         "../main.rkt" "../private/svg-util.rkt")
(provide svg-pure-tests)

(define (envelope bs [title ""] [description ""] [prefix "skia"])
  (define-values (t d) (svg-metadata 'test title description))
  (finish-svg-xml 'test bs 120.5 80.25 t d (svg-id-prefix 'test prefix)))

(define raw-empty #"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"121\" height=\"81\"/>")
(define raw-body #"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"121\" height=\"81\"><rect x=\"7\" width=\"20\" height=\"30\"/></svg>")

(define svg-pure-tests
  (test-suite
   "SVG pure validation and serialization"
   (test-case "fractional dimensions and vector dimensions do not allocate pixels"
     (check-equal? (svg-dimension 'test 120.5) 120.5)
     (check-equal? (svg-dimension 'test 1/1000) 0.001)
     (parameterize ([current-skia-byte-limit 32])
       (check-equal? (svg-dimension 'test 32768) 32768.0)))
   (test-case "invalid dimensions reject before native loading"
     (for ([v (in-list (list 0 -1 1/10000 32769 +inf.0 -inf.0 +nan.0 'bad "100"))])
       (check-exn exn:fail:contract? (lambda () (make-svg-document v 20)))
       (check-exn exn:fail:contract? (lambda () (make-svg-document 20 v)))))
   (test-case "XML character validation"
     (for ([s (in-list (list (string #\nul) (string (integer->char 1))
                             (string (integer->char #xfffe))))])
       (check-exn exn:fail:contract? (lambda () (make-svg-document 20 20 #:title s)))
       (check-exn exn:fail:contract? (lambda () (make-svg-document 20 20 #:description s))))
     (check-exn exn:fail:contract? (lambda () (make-svg-document 20 20 #:title #f))))
   (test-case "metadata escapes XML syntax and retains Unicode"
     (define bs (envelope raw-body "A & B <tag> \"quote\" 'apostrophe'" "Søgaard\n東京"))
     (check-true (regexp-match? #rx#"<title>A &amp; B &lt;tag&gt; &quot;quote&quot; &apos;apostrophe&apos;</title>" bs))
     (check-true (regexp-match? (regexp-quote (string->bytes/utf-8 "Søgaard\n東京")) bs))
     (check-false (regexp-match? #rx#"<tag>" bs)))
   (test-case "empty SVG is finalized as a complete document"
     (define bs (envelope raw-empty "Empty"))
     (check-true (immutable? bs))
     (check-true (regexp-match? #rx#"width=\"120.5\" height=\"80.25\" viewBox=\"0 0 120.5 80.25\"" bs))
     (check-true (regexp-match? #rx#"<title>Empty</title>" bs))
     (check-true (regexp-match? #rx#"</svg>" bs)))
   (test-case "native drawing body is preserved"
     (define bs (envelope raw-body))
     (check-true (regexp-match? #rx#"<rect x=\"7\" width=\"20\" height=\"30\"/>" bs))
     (check-false (regexp-match? #rx#"<title>|<desc>" bs)))
   (test-case "missing roots and unfinished streams are rejected"
     (for ([bs (in-list (list #"" #"not svg" #"<html/>" #"<svg width=\"1\">"))])
       (check-exn exn:fail? (lambda () (envelope bs)))))
   (test-case "IDs and all native attribute reference forms are canonicalized"
     (define a #"<svg width=\"1\"><defs><clipPath id=\"cl_ab12\"/><image id=\"img_0\"/><linearGradient id=\"gradient_0\"/></defs><g clip-path=\"url(#cl_ab12)\"><use xlink:href=\"#img_0\" fill=\"url(#gradient_0)\"/></g><text>url(#cl_ab12) cl_ab12</text></svg>")
     (define b (regexp-replace* #rx#"cl_ab12" a #"cl_ffff"))
     ;; Text is intentionally NOT canonicalized, so keep the label the same.
     (define b-label (regexp-replace #rx#"<text>[^<]*</text>" b #"<text>url(#cl_ab12) cl_ab12</text>"))
     (define out (envelope a "" "" "probe"))
     (check-equal? out (envelope b-label "" "" "probe"))
     (check-true (regexp-match? #rx#"id=\"probe-0\"" out))
     (check-true (regexp-match? #rx#"clip-path=\"url\\(#probe-0\\)\"" out))
     (check-true (regexp-match? #rx#"xlink:href=\"#probe-1\"" out))
     (check-true (regexp-match? #rx#"fill=\"url\\(#probe-2\\)\"" out))
     (check-true (regexp-match? #rx#"<text>url\\(#cl_ab12\\) cl_ab12</text>" out)))
   (test-case "ID validation, duplicate definitions, and broken references"
     (for ([p (in-list (list "" "0bad" "with space" "a:b" "<&>" (make-string 65 #\x) #f))])
       (check-exn exn:fail:contract? (lambda () (make-svg-document 1 1 #:id-prefix p))))
     (check-exn exn:fail? (lambda () (envelope #"<svg width=\"1\"><path id=\"a\"/><path id=\"a\"/></svg>")))
     (check-exn exn:fail? (lambda () (envelope #"<svg width=\"1\"><use href=\"#missing\"/></svg>"))))
   (test-case "metadata and finalized output obey the byte limit"
     (parameterize ([current-skia-byte-limit 4])
       (check-exn exn:fail? (lambda () (svg-metadata 'test "&" ""))))
     (parameterize ([current-skia-byte-limit 64])
       (check-exn exn:fail? (lambda () (envelope #"<svg width=\"1\"/>")))))
   (test-case "drawing callback validation happens before loading"
     (check-exn exn:fail:contract? (lambda () (call-with-svg-bytes 10 10 #f)))
     (check-exn exn:fail:contract? (lambda () (call-with-svg-string 10 10 (lambda () (void)))))
     (check-exn exn:fail:contract? (lambda () (svg-document-canvas #f)))
     (check-exn exn:fail:contract? (lambda () (svg-document->bytes #f))))
   (test-case "rasterized helper validates size, scale, and callback"
     (define-values (w h) (rasterized-dimensions 'test 10.5 20.25 2))
     (check-equal? (list w h) '(21 41))
     (check-exn exn:fail:contract? (lambda () (draw-rasterized #f 0 0 0 10 void)))
     (check-exn exn:fail:contract? (lambda () (draw-rasterized #f 0 0 10 10 void #:scale 0)))
     (check-exn exn:fail:contract? (lambda () (draw-rasterized #f 0 0 10 10 (lambda () 0))))
     (parameterize ([current-skia-byte-limit 100])
       (check-exn exn:fail? (lambda () (rasterized-dimensions 'test 10 10 1)))))
   (test-case "outline helper validates public objects"
     (check-exn exn:fail:contract? (lambda () (shaped-run->path #f #f))))
   (test-case "SVG output paths reject invalid destinations"
     (check-exn exn:fail:contract? (lambda () (svg-output-path 'test #f 'error)))
     (check-exn exn:fail:contract? (lambda () (svg-output-path 'test "x" 'append)))
     (check-exn exn:fail:contract? (lambda () (svg-output-path 'test (current-directory) 'replace))))
   (test-case "completed bytes are safely published without overwriting on error"
     (define dir (make-temporary-file "svg-pure-~a" 'directory))
     (dynamic-wind
       void
       (lambda ()
         (define path (build-path dir "with spaces.svg"))
         (write-svg-file-bytes! 'test #"first" path 'error)
         (check-equal? (file->bytes path) #"first")
         (check-exn exn:fail? (lambda () (write-svg-file-bytes! 'test #"second" path 'error)))
         (check-equal? (file->bytes path) #"first")
         (write-svg-file-bytes! 'test #"second" path 'replace)
         (check-equal? (file->bytes path) #"second")
         (check-equal? (length (directory-list dir)) 1))
       (lambda () (delete-directory/files dir))))
   (test-case "file byte-limit rejection leaves the destination unchanged"
     (define dir (make-temporary-file "svg-limit-~a" 'directory))
     (dynamic-wind
       void
       (lambda ()
         (define path (build-path dir "kept.svg"))
         (write-svg-file-bytes! 'test #"kept" path 'error)
         (parameterize ([current-skia-byte-limit 4])
           (check-exn exn:fail?
                      (lambda () (write-svg-file-bytes! 'test #"too large" path 'replace))))
         (check-equal? (file->bytes path) #"kept")
         (check-equal? (length (directory-list dir)) 1))
       (lambda () (delete-directory/files dir))))))

(module+ test (run-tests svg-pure-tests))
