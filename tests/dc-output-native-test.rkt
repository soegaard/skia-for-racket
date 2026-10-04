#lang racket/base
(require rackunit racket/class racket/list racket/file
         (prefix-in rd: racket/draw) (prefix-in sk: "../main.rkt")
         "../dc-output.rkt" "../private/dc-support.rkt")
(provide dc-output-native-tests dc-output-native-test-count)
(define (fill dc [color "blue"] [x 2] [y 3] [w 8] [h 6])
  (send dc set-pen "black" 1 'transparent) (send dc set-brush color 'solid)
  (send dc draw-rectangle x y w h))
(define (page draw #:policy [policy 'prefer-vector])
  (make-dc-output-page 80 60 draw #:background 'white #:policy policy))
(define (export draw format #:policy [policy 'prefer-vector])
  (sk:output->bytes (page draw #:policy policy) format))
(define (pixel bytes width x y)
  (define n (* 4 (+ x (* width y)))) (bytes->list (subbytes bytes n (+ n 4))))
(define dc-output-native-tests
  (test-suite
   "Shared authoring on actual PDF, SVG and raster output canvases"
   (test-case "simple PDF has a native PDF header"
     (check-equal? (subbytes (export fill 'pdf) 0 5) #"%PDF-"))
   (test-case "simple SVG keeps geometry without a page image"
     (define xml (export fill 'svg #:policy 'require-vector))
     (check-true (regexp-match? #rx#"<(path|rect)" xml))
     (check-false (regexp-match? #rx#"<image" xml)))
   (test-case "finite clear remains vector geometry on SVG"
     (define xml (export (lambda (dc) (send dc clear) (fill dc)) 'svg #:policy 'require-vector))
     (check-false (regexp-match? #rx#"<image" xml)))
   (test-case "authoring runs once and its DC is expired before report delivery"
     (define calls 0) (define saved #f) (define reported #f)
     (define p (make-dc-output-page 80 60
       (lambda (dc) (set! calls (add1 calls)) (set! saved dc) (fill dc))
       #:on-report (lambda (r) (check-false (send saved ok?)) (set! reported r))))
     (sk:output->bytes p 'svg)
     (check-equal? calls 1) (check-true (hash-ref reported 'dc_expired)))
   (test-case "callback error cannot paint even the beginning of a live raster receiver"
     (sk:with-skia ([s (sk:make-surface 80 60 #:background 'red)])
       (check-exn #rx"deliberate" (lambda ()
         (call-with-output-dc (sk:surface-canvas s) 80 60
           (lambda (dc) (fill dc) (error 'probe "deliberate")))))
       (check-equal? (pixel (sk:surface->rgba-bytes s) 80 4 5) '(255 0 0 255))))
   (test-case "inherited receiver translation survives native DC matrix resets"
     (sk:with-skia ([s (sk:make-surface 80 60 #:background 'white)])
       (define c (sk:surface-canvas s)) (sk:canvas-translate! c 10 8)
       (call-with-output-dc c 20 20 fill)
       (define pixels (sk:surface->rgba-bytes s))
       (check-equal? (pixel pixels 80 14 13) '(0 0 255 255))
       (check-equal? (pixel pixels 80 4 5) '(255 255 255 255))))
   (test-case "explicit output-page preview produces independent CPU pixels"
     (sk:with-skia ([im (sk:output-page->image (page fill) #:dpi 144)])
       (check-equal? (sk:image-width im) 160)
       (check-equal? (pixel (sk:image->rgba-bytes im) 160 10 12) '(0 0 255 255))))
   (test-case "completed group opacity applies once to overlapping content"
     (sk:with-skia ([im (sk:output-page->image
       (page (lambda (dc) (send dc start-alpha 0.5)
         (fill dc "red" 10 10 30 20) (fill dc "blue" 20 10 30 20)
         (send dc end-alpha))) #:dpi 72)])
       (define rgba (pixel (sk:image->rgba-bytes im) 80 25 15))
       (for ([a (in-list rgba)] [e '(128 128 255 255)]) (check-true (<= (abs (- a e)) 2)))))
   (test-case "SVG alpha uses only an isolated bounded subgroup image"
     (define xml (export (lambda (dc)
       (fill dc "green" 2 2 8 8) (send dc start-alpha 0.5)
       (fill dc "red" 10 10 30 20) (fill dc "blue" 20 10 30 20) (send dc end-alpha)) 'svg))
     (check-true (regexp-match? #rx#"<image" xml))
     (check-true (regexp-match? #rx#"<(path|rect)" xml)))
   (test-case "require-vector rejects group fallback rather than dropping opacity"
     (check-exn exn:fail? (lambda () (export (lambda (dc)
       (send dc start-alpha 0.5) (fill dc) (send dc end-alpha)) 'svg #:policy 'require-vector))))
   (test-case "native text inside a raster-needed alpha group is not silently discarded"
     (define p (page (lambda (dc) (send dc start-alpha 0.5)
       (send dc draw-text "KEEP TEXT" 2 2) (send dc end-alpha))))
     (check-exn exn:fail? (lambda () (sk:output->bytes p 'svg #:text-mode 'native))))
   (test-case "identity linear gradient serializes as a gradient not an image"
     (define xml (export (lambda (dc)
       (define g (new rd:linear-gradient% [x0 0] [y0 0] [x1 40] [y1 0]
         [stops (list (list 0 (make-object rd:color% 255 0 0))
                      (list 1 (make-object rd:color% 0 0 255)))]))
       (send dc set-pen "black" 1 'transparent)
       (send dc set-brush (rd:make-brush #:gradient g)) (send dc draw-rectangle 0 0 40 20)) 'svg))
     (check-true (regexp-match? #rx#"linearGradient" xml))
     (check-false (regexp-match? #rx#"<image" xml)))
   (test-case "explicit raster callback can copy pixels and is called only once"
     (define calls 0)
     (define xml (export (lambda (dc)
       (fill dc)
       (draw-dc-raster-group dc 12 12 20 10 (lambda (r)
         (set! calls (add1 calls)) (fill r "red" 0 0 10 10)
         (send r copy 0 0 10 10 5 0)) #:scale 2)) 'svg))
     (check-equal? calls 1) (check-true (regexp-match? #rx#"<image" xml)))
   (test-case "raster group callback has logical dimensions and expires on exit"
     (define saved #f)
     (export (lambda (dc)
       (draw-dc-raster-group dc 0 0 20 10
         (lambda (r)
           (set! saved r)
           (check-equal? (call-with-values (lambda () (send r get-size)) list) '(20.0 10.0))
           (fill r)) #:scale 2)) 'svg)
     (check-false (send saved ok?)))
   (test-case "explicit raster groups reject annotations instead of losing them"
     (check-exn exn:fail:skia-dc:unsupported?
       (lambda () (export (lambda (dc)
         (draw-dc-raster-group dc 0 0 20 10
           (lambda (r) (dc-annotate-url! r 0 0 10 10 "https://example.org")))) 'svg))))
   (test-case "require-vector rejects explicit raster before its callback"
     (define calls 0)
     (check-exn exn:fail? (lambda () (export (lambda (dc)
       (draw-dc-raster-group dc 0 0 10 10 (lambda (_) (set! calls (add1 calls)))))
       'svg #:policy 'require-vector)))
     (check-equal? calls 0))
   (test-case "URL annotations survive the document DC bridge"
     (define xml (export (lambda (dc) (fill dc)
       (dc-annotate-url! dc 1 1 10 10 "https://example.org/skia")) 'svg))
     (check-true (regexp-match? #rx#"https://example.org/skia" xml)))
   (test-case "named SVG destinations use the real live document scope"
     (define xml (export (lambda (dc)
       (dc-link-destination! dc 1 1 20 10 "target")
       (dc-define-destination! dc "target" 10 20)) 'svg))
     (check-true (regexp-match? #rx#"<view" xml)))
   (test-case "cross-page PDF destinations validate after every page"
     (define first (page (lambda (dc) (fill dc) (dc-link-destination! dc 1 1 20 10 "second"))))
     (define second (page (lambda (dc) (fill dc) (dc-define-destination! dc "second" 2 2))))
     (check-equal? (subbytes (sk:output->bytes (list first second) 'pdf) 0 5) #"%PDF-"))
   (test-case "misspelled destination is rejected at document completion"
     (check-exn exn:fail? (lambda () (export (lambda (dc)
       (dc-link-destination! dc 1 1 20 10 "missing")) 'pdf))))
   (test-case "page units and margins provide content-local dimensions"
     (define p (make-dc-output-page 25.4 12.7
       (lambda (dc)
         (define-values (w h) (send dc get-size))
         (check-= w 23.4 1e-5) (check-= h 10.7 1e-5)
         (fill dc "red" 0 0 5 3)) #:unit 'mm #:margins 1))
     (check-true (> (bytes-length (sk:output->bytes p 'pdf)) 100)))
   (test-case "strict audit accepts handled subgroup fallback"
     (define-values (bytes report) (sk:output->bytes/audit
       (page (lambda (dc) (draw-dc-raster-group dc 1 1 20 10 fill))) 'svg #:policy 'error))
     (check-false (sk:output-audit-report-blocking? report))
     (check-true (regexp-match? #rx#"<image" bytes)))))
(define dc-output-native-test-count 22)
(module+ main
  (require rackunit/text-ui)
  (sk:skia-check!)
  (define failures (run-tests dc-output-native-tests))
  (printf "dc-output-native: ~a cases, ~a failures\n" dc-output-native-test-count failures)
  (exit (if (zero? failures) 0 1)))
