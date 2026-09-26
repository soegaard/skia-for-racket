#lang racket/base
(require rackunit rackunit/text-ui racket/list racket/string racket/file "../main.rkt")
(provide annotation-native-tests)

(define uri "https://example.invalid/manual?a=1&b=2")
(define (has? pattern bs) (regexp-match? pattern bs))
(define (svg-anchors bs)
  (regexp-match* #px"<a[^>]*>(?s:.*?)</a>" (bytes->string/utf-8 bs)))
(define (rect-of anchor)
  (define r (car (regexp-match #px"<rect[^>]*>" anchor)))
  (for/list ([key '("x" "y" "width" "height")])
    (define found (regexp-match (regexp (format " ~a=\"([^\"]+)\"" key)) r))
    (if found (string->number (cadr found)) 0)))
(define (check-rect actual expected)
  (for ([a (in-list actual)] [b (in-list expected)]) (check-= a b 0.01)))
(define (pdf-bytes draw)
  (call-with-pdf-bytes (lambda (d) (call-with-document-page d 200 160 draw))))
(define (foreign-error proc)
  (define ch (make-channel))
  (define t (thread (lambda ()
                     (with-handlers ([exn? (lambda (e) (channel-put ch e))])
                       (proc) (channel-put ch #f)))))
  (define e (channel-get ch)) (thread-wait t) e)

(define annotation-native-tests
  (test-suite
   "Document links and destinations: native backends"
   (test-case "PDF URL annotations are emitted"
     (define bs (pdf-bytes (lambda (c) (canvas-annotate-url! c 10 20 30 40 uri))))
     (check-true (has? #rx#"/Annots" bs))
     (check-true (has? #rx#"/URI" bs)))
   (test-case "SVG URL links are root overlays with escaped targets"
     (define bs (call-with-svg-bytes 200 160
                  (lambda (c) (canvas-annotate-url! c 10 20 30 40 uri))))
     (check-equal? (length (svg-anchors bs)) 1)
     (check-true (has? #rx#"a=1&amp;b=2" bs))
     (check-rect (rect-of (car (svg-anchors bs))) '(10 20 30 40)))
   (test-case "SVG native translate and nonuniform scale affect link coordinates"
     (define bs (call-with-svg-bytes 200 160
                  (lambda (c)
                    (canvas-translate! c 10 20)
                    (canvas-scale! c 2 3)
                    (canvas-annotate-url! c 5 7 10 11 uri))))
     (check-rect (rect-of (car (svg-anchors bs))) '(20 41 20 33)))
   (test-case "rotated link uses a native axis-aligned bounding rectangle"
     (define bs (call-with-svg-bytes 200 160
                  (lambda (c)
                    (canvas-translate! c 100 40)
                    (canvas-rotate! c 90)
                    (canvas-annotate-url! c 0 0 30 10 uri))))
     (check-rect (rect-of (car (svg-anchors bs))) '(90 40 10 30)))
   (test-case "SVG clipping works without an intervening drawing operation"
     (define bs (call-with-svg-bytes 200 160
                  (lambda (c)
                    (canvas-clip-rect! c 25 35 10 20)
                    (canvas-annotate-url! c 10 20 50 70 uri))))
     (check-rect (rect-of (car (svg-anchors bs))) '(25 35 10 20)))
   (test-case "restored clip does not leave a link trapped in stale SVG group"
     (define bs (call-with-svg-bytes 200 160
                  (lambda (c)
                    (with-canvas-state c
                      (canvas-clip-rect! c 1 1 4 4)
                      (with-skia ([p (make-paint #:color 'blue)]) (draw-rect c 0 0 20 20 p)))
                    (canvas-annotate-url! c 60 70 20 30 uri))))
     (check-rect (rect-of (car (svg-anchors bs))) '(60 70 20 30))
     (check-true (has? #px#"</g>(?s:.*?)<a " bs)))
   (test-case "fully clipped and zero-area URL links are omitted"
     (define bs (call-with-svg-bytes 200 160
                  (lambda (c)
                    (canvas-annotate-url! c 1 1 0 10 uri)
                    (canvas-clip-rect! c 0 0 10 10)
                    (canvas-annotate-url! c 20 20 5 5 uri))))
     (check-equal? (svg-anchors bs) '()))
   (test-case "PDF destinations resolve forward across pages"
     (define bs (call-with-pdf-bytes
                 (lambda (d)
                   (call-with-document-page d 200 160
                     (lambda (c) (canvas-link-destination! c 10 20 30 40 "next")))
                   (call-with-document-page d 300 180
                     (lambda (c) (canvas-define-destination! c "next" 15 25))))))
     (check-true (has? #rx#"/Dests" bs))
     (check-true (has? #rx#"/Dest" bs)))
   (test-case "SVG named links resolve to transformed prefixed view destinations"
     (define bs (call-with-svg-bytes 200 160
                  (lambda (c)
                    (canvas-link-destination! c 5 5 40 20 "next")
                    (canvas-translate! c 10 20)
                    (canvas-scale! c 2 3)
                    (canvas-define-destination! c "next" 4 5))
                  #:id-prefix "page"))
     (check-true (has? #rx#"viewBox=\"18.0 35.0 200.0 160.0\"" bs))
     (check-true (has? (byte-regexp (string->bytes/utf-8 (string-append "href=\"#" (svg-destination-id "next" #:id-prefix "page") "\""))) bs)))
   (test-case "duplicate destinations fail across PDF pages"
     (check-exn #rx"already defined"
       (lambda ()
         (call-with-pdf-bytes
          (lambda (d)
            (for ([i (in-range 2)])
              (call-with-document-page d 100 100
                (lambda (c) (canvas-define-destination! c "same" 0 0)))))))))
   (test-case "duplicate destinations fail through SVG canvas aliases"
     (with-skia ([d (make-svg-document 100 100)])
       (canvas-define-destination! (svg-document-canvas d) "same" 0 0)
       (check-exn #rx"already defined"
         (lambda () (canvas-define-destination! (svg-document-canvas d) "same" 1 2)))))
   (test-case "undefined PDF destinations fail before finish and can be resolved"
     (with-skia ([d (make-pdf-document)])
       (call-with-document-page d 100 100 (lambda (c) (canvas-link-destination! c 1 1 5 5 "later")))
       (check-exn #rx"undefined" (lambda () (document-finish! d)))
       (check-equal? (document-state d) 'open)
       (call-with-document-page d 100 100 (lambda (c) (canvas-define-destination! c "later" 0 0)))
       (check-not-exn (lambda () (document-finish! d)))))
   (test-case "undefined SVG destinations fail before native canvas destruction"
     (with-skia ([d (make-svg-document 100 100)])
       (define c (svg-document-canvas d))
       (canvas-link-destination! c 1 1 5 5 "later")
       (check-exn #rx"undefined" (lambda () (svg-document-finish! d)))
       (check-equal? (svg-document-state d) 'open)
       (canvas-define-destination! c "later" 0 0)
       (check-not-exn (lambda () (svg-document-finish! d)))))
   (test-case "same destination name can be used in separate exports"
     (for ([i (in-range 2)])
       (check-true
        (bytes? (call-with-svg-bytes 100 100
                  (lambda (c)
                    (canvas-define-destination! c "intro" 0 0)
                    (canvas-link-destination! c 1 1 5 5 "intro")))))))
   (test-case "Unicode destination names use matching portable IDs"
     (define bs (call-with-svg-bytes 100 100
                  (lambda (c)
                    (canvas-link-destination! c 1 1 20 20 "α & β")
                    (canvas-define-destination! c "α & β" 0 0))))
     (check-true (has? (byte-regexp (string->bytes/utf-8 (svg-destination-id "α & β"))) bs)))
   (test-case "raster annotations do not change any pixel"
     (with-skia ([s (make-surface 20 20 #:background 'red)])
       (define c (surface-canvas s))
       (define old (surface->rgba-bytes s))
       (check-equal? (canvas-annotation-backend c) 'raster)
       (canvas-annotate-url! c 1 1 8 8 uri)
       (canvas-define-destination! c "intro" 0 0)
       (canvas-link-destination! c 1 1 8 8 "missing-on-raster")
       (check-equal? (surface->rgba-bytes s) old)))
   (test-case "recorded URLs replay into SVG with destination transform"
     (with-skia ([pic (call-with-picture 40 30
                       (lambda (c)
                         (check-equal? (canvas-annotation-backend c) 'recording)
                         (canvas-annotate-url! c 1 2 10 8 uri)))])
       (define bs (call-with-svg-bytes 200 160
                    (lambda (c) (draw-picture c pic #:x 20 #:y 30 #:width 80 #:height 60))))
       (check-rect (rect-of (car (svg-anchors bs))) '(22 34 20 16))))
   (test-case "recorded URLs replay into PDF"
     (with-skia ([pic (call-with-picture 40 30 (lambda (c) (canvas-annotate-url! c 1 2 10 8 uri)))])
       (check-true (has? #rx#"/URI" (pdf-bytes (lambda (c) (draw-picture c pic)))))))
   (test-case "named picture annotations reject instead of silently disappearing"
     (check-exn #rx"live PDF/SVG"
       (lambda () (call-with-picture 40 30 (lambda (c) (canvas-define-destination! c "n" 0 0)))))
     (check-exn #rx"live PDF/SVG"
       (lambda () (call-with-picture 40 30 (lambda (c) (canvas-link-destination! c 0 0 10 10 "n"))))))
   (test-case "physical-page coordinates include units and margins"
     (define page (make-output-page 100 70
                   (lambda (c) (canvas-annotate-url! c 10 20 30 10 uri))
                   #:unit 'mm #:margins 5))
     (define bs (output->bytes page 'svg))
     (define k (/ 72 25.4))
     (check-rect (rect-of (car (svg-anchors bs))) (map (lambda (x) (* x k)) '(15 25 30 10))))
   (test-case "annotation calls preserve graphics matrix and save count"
     (call-with-svg-bytes 100 100
       (lambda (c)
         (canvas-translate! c 3 4)
         (define m (canvas-transform c)) (define n (canvas-save-count c))
         (canvas-annotate-url! c 1 1 5 5 uri)
         (canvas-define-destination! c "n" 0 0)
         (canvas-link-destination! c 1 1 5 5 "n")
         (check-equal? (canvas-transform c) m)
         (check-equal? (canvas-save-count c) n))))
   (test-case "expired page and finished SVG canvases are rejected"
     (with-skia ([d (make-pdf-document)])
       (define c (document-begin-page! d 100 100))
       (document-end-page! d)
       (check-exn #rx"closed" (lambda () (canvas-annotate-url! c 0 0 5 5 uri))))
     (with-skia ([d (make-svg-document 100 100)])
       (define c (svg-document-canvas d))
       (svg-document-finish! d)
       (check-exn #rx"closed" (lambda () (canvas-define-destination! c "n" 0 0)))))
   (test-case "cross-thread annotation and backend queries reject"
     (with-skia ([d (make-svg-document 100 100)])
       (define c (svg-document-canvas d))
       (check-true (exn:fail? (foreign-error (lambda () (canvas-annotation-backend c)))))
       (check-true (exn:fail? (foreign-error (lambda () (canvas-annotate-url! c 0 0 5 5 uri)))))))
   (test-case "SVG finalized bytes are repeatable detached copies"
     (with-skia ([d (make-svg-document 100 100)])
       (define c (svg-document-canvas d))
       (canvas-define-destination! c "intro" 0 0)
       (canvas-link-destination! c 1 1 5 5 "intro")
       (svg-document-finish! d)
       (define one (svg-document->bytes d))
       (define two (svg-document->bytes d))
       (check-equal? one two)
       (bytes-set! one 0 0)
       (check-equal? (svg-document->bytes d) two)))
   (test-case "undefined references never overwrite existing SVG output"
     (define path (make-temporary-file "skia-link-~a.svg"))
     (dynamic-wind void
       (lambda ()
         (call-with-output-file path (lambda (p) (write-bytes #"keep" p)) #:exists 'replace)
         (check-exn #rx"undefined"
           (lambda () (call-with-svg-file path 100 100
                        (lambda (c) (canvas-link-destination! c 1 1 5 5 "missing")) #:exists 'replace)))
         (check-equal? (file->bytes path) #"keep"))
       (lambda () (delete-file path))))
   (test-case "undefined references never overwrite existing PDF output"
     (define path (make-temporary-file "skia-link-~a.pdf"))
     (dynamic-wind void
       (lambda ()
         (call-with-output-file path (lambda (p) (write-bytes #"keep" p)) #:exists 'replace)
         (check-exn #rx"undefined"
           (lambda () (call-with-pdf-file path
                        (lambda (d) (call-with-document-page d 100 100
                                      (lambda (c) (canvas-link-destination! c 1 1 5 5 "missing"))))
                        #:exists 'replace)))
         (check-equal? (file->bytes path) #"keep"))
       (lambda () (delete-file path))))
   (test-case "PDF/A mode can include URL and named link annotations"
     (define bs (call-with-pdf-bytes
                 (lambda (d) (call-with-document-page d 100 100
                               (lambda (c)
                                 (canvas-annotate-url! c 1 1 20 10 uri)
                                 (canvas-link-destination! c 1 20 20 10 "n")
                                 (canvas-define-destination! c "n" 0 40))))
                 #:pdfa? #t))
     (check-true (has? #rx#"/OutputIntents" bs))
     (check-true (has? #rx#"/Annots" bs)))))
(module+ test (run-tests annotation-native-tests))
