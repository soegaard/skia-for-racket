#lang racket/base
(require rackunit rackunit/text-ui racket/file racket/path
         "../main.rkt")
(provide svg-native-tests)

(define (rect-svg c)
  (with-skia ([p (make-paint #:color 'blue)])
    (draw-rect c 5 5 30 20 p)))

(define (has? pattern bs) (regexp-match? pattern bs))
(define (in-temp-directory proc)
  (define dir (make-temporary-file "skia-svg-test-~a" 'directory))
  (dynamic-wind void (lambda () (proc dir)) (lambda () (delete-directory/files dir))))

(define (foreign-error thunk)
  (define ch (make-channel))
  (define worker
    (thread (lambda ()
              (with-handlers ([exn? (lambda (e) (channel-put ch e))])
                (thunk)
                (channel-put ch #f)))))
  (define result (channel-get ch))
  (thread-wait worker)
  result)

(define svg-native-tests
  (test-suite
   "SVG native document output"
   (test-case "empty document finishes with fractional viewport dimensions"
     (with-skia ([d (make-svg-document 100.5 60.25)])
       (check-true (svg-document? d))
       (check-true (skia-resource? d))
       (check-false (document? d))
       (check-equal? (svg-document-width d) 100.5)
       (check-equal? (svg-document-height d) 60.25)
       (check-equal? (svg-document-state d) 'open)
       (svg-document-finish! d)
       (check-equal? (svg-document-state d) 'finished)
       (check-true (has? #rx#"viewBox=\"0 0 100.5 60.25\"" (svg-document->bytes d)))
       (check-true (has? #rx#"</svg>" (svg-document->bytes d)))))
   (test-case "canvas uses existing vector drawing operations"
     (define bs
       (call-with-svg-bytes 120 90
         (lambda (c)
           (check-true (canvas? c))
           (check-false (skia-resource? c))
           (with-skia ([p (make-paint #:color 'red)]
                       [curve (make-path '((move 10 10) (cubic 25 70 80 10 110 70)))])
             (draw-circle c 30 30 10 p)
             (draw-path c curve p)))))
     (check-true (has? #rx#"<path" bs))
     (check-false (has? #rx#"data:image/" bs)))
   (test-case "data cannot be read before explicit finalization"
     (with-skia ([d (make-svg-document 40 40)])
       (check-exn #rx"finish" (lambda () (svg-document->bytes d)))
       (check-exn #rx"finish" (lambda () (svg-document->string d)))
       (rect-svg (svg-document-canvas d))
       (svg-document-finish! d)))
   (test-case "finish is idempotent and returned buffers are detached"
     (with-skia ([d (make-svg-document 50 50)])
       (rect-svg (svg-document-canvas d))
       (svg-document-finish! d)
       (define first (svg-document->bytes d))
       (define expected (bytes-copy first))
       (svg-document-finish! d)
       (bytes-set! first 0 0)
       (check-equal? (svg-document->bytes d) expected)
       (check-equal? (string->bytes/utf-8 (svg-document->string d)) expected)))
   (test-case "finished canvas stays invalid across subsequent documents"
     (with-skia ([a (make-svg-document 50 50)] [b (make-svg-document 50 50)])
       (define old (svg-document-canvas a))
       (rect-svg old)
       (svg-document-finish! a)
       (check-true (skia-closed? old))
       (check-false (skia-closed? a))
       (check-exn #rx"closed" (lambda () (canvas-save! old)))
       (check-exn #rx"closed" (lambda () (svg-document-canvas a)))
       (rect-svg (svg-document-canvas b))
       (check-exn #rx"closed" (lambda () (rect-svg old)))
       (svg-document-finish! b)))
   (test-case "generic close invalidates canvas and releases finalized data"
     (define d (make-svg-document 50 50))
     (define c (svg-document-canvas d))
     (rect-svg c)
     (svg-document-finish! d)
     (define bs (svg-document->bytes d))
     (skia-close! d)
     (skia-close! d)
     (check-equal? (svg-document-state d) 'closed)
     (check-true (skia-closed? c))
     (check-exn #rx"closed" (lambda () (svg-document->bytes d)))
     (check-true (has? #rx#"</svg>" bs)))
   (test-case "abort is idempotent and never supplies partial output"
     (define d (make-svg-document 50 50))
     (define c (svg-document-canvas d))
     (rect-svg c)
     (svg-document-abort! d)
     (svg-document-abort! d)
     (check-equal? (svg-document-state d) 'aborted)
     (check-true (skia-closed? c))
     (check-exn #rx"closed" (lambda () (svg-document-finish! d)))
     (check-exn #rx"closed" (lambda () (svg-document->bytes d))))
   (test-case "protected state scopes prevent premature finish"
     (with-skia ([d (make-svg-document 60 60)])
       (define c (svg-document-canvas d))
       (with-canvas-state c
         (canvas-translate! c 3 4)
         (check-exn #rx"protected" (lambda () (svg-document-finish! d)))
         (check-equal? (svg-document-state d) 'open)
         (rect-svg c))
       (check-equal? (canvas-save-count c) 1)
       (svg-document-finish! d)))
   (test-case "explicit close inside a state scope does not touch a dead canvas"
     (define d (make-svg-document 60 60))
     (define c (svg-document-canvas d))
     (with-canvas-state c (skia-close! d))
     (check-true (skia-closed? c)))
   (test-case "exception callback closes every canvas alias"
     (define saved #f)
     (check-exn #rx"intentional"
                (lambda ()
                  (call-with-svg-bytes 60 60
                    (lambda (c) (set! saved c) (error 'test "intentional")))))
     (check-true (skia-closed? saved))
     (check-exn #rx"closed" (lambda () (rect-svg saved))))
   (test-case "arbitrary raised values and multiple callback values are supported"
     (define token (gensym))
     (define saved #f)
     (check-eq?
      (with-handlers ([(lambda (v) (eq? v token)) values])
        (call-with-svg-bytes 60 60 (lambda (c) (set! saved c) (raise token))))
      token)
     (check-true (skia-closed? saved))
     (check-true (bytes? (call-with-svg-bytes 10 10 (lambda (_) (values 1 2 3)))))
     (check-true (bytes? (call-with-svg-bytes 10 10 (lambda (_) (values))))))
   (test-case "continuation escape closes canvas and does not publish"
     (in-temp-directory
      (lambda (dir)
        (define target (build-path dir "escape.svg"))
        (define saved #f)
        (check-eq?
         (let/ec escape
           (call-with-svg-file target 60 60
             (lambda (c) (set! saved c) (escape 'escaped))))
         'escaped)
        (check-true (skia-closed? saved))
        (check-false (file-exists? target))
        (check-equal? (directory-list dir) '()))))
   (test-case "SVG objects remain thread-confined including after close"
     (define d (make-svg-document 50 50))
     (define c (svg-document-canvas d))
     (for ([thunk (in-list (list (lambda () (rect-svg c))
                                 (lambda () (svg-document-canvas d))
                                 (lambda () (svg-document-finish! d))
                                 (lambda () (svg-document-abort! d))))])
       (define e (foreign-error thunk))
       (check-true (exn:fail? e))
       (check-true (regexp-match? #rx"another Racket thread" (exn-message e))))
     (svg-document-finish! d)
     (check-true (exn:fail? (foreign-error (lambda () (svg-document->bytes d)))))
     (skia-close! d)
     (check-true (exn:fail? (foreign-error (lambda () (svg-document-abort! d))))))
   (test-case "output limit failure aborts the document"
     (define d (make-svg-document 50 50))
     (define c (svg-document-canvas d))
     (rect-svg c)
     (parameterize ([current-skia-byte-limit 16])
       (check-exn exn:fail? (lambda () (svg-document-finish! d))))
     (check-equal? (svg-document-state d) 'aborted)
     (check-true (skia-closed? c))
     (skia-close! d))
   (test-case "readback rechecks the current byte limit"
     (with-skia ([d (make-svg-document 30 30)])
       (svg-document-finish! d)
       (parameterize ([current-skia-byte-limit 16])
         (check-exn #rx"byte-limit" (lambda () (svg-document->bytes d))))
       (check-true (bytes? (svg-document->bytes d)))))
   (test-case "title and description are valid escaped UTF-8 metadata"
     (define s (call-with-svg-string 10 10 void
                                     #:title "A < B & C" #:description "Søgaard"))
     (check-true (has? #rx"<title>A &lt; B &amp; C</title>" s))
     (check-true (has? #rx"<desc>Søgaard</desc>" s)))
   (test-case "linear gradients remain vector paint servers"
     (define bs
       (call-with-svg-bytes 120 40
         (lambda (c)
           (with-skia ([sh (make-linear-gradient-shader 0 0 120 0 '(blue red))]
                       [p (make-paint #:shader sh)])
             (draw-rect c 0 0 120 40 p)))))
     (check-true (has? #rx#"<linearGradient" bs))
     (check-true (has? #rx#"<stop" bs))
     (check-false (has? #rx#"data:image/" bs)))
   (test-case "clips and transforms are stable across repeated in-process exports"
     (define (render)
       (call-with-svg-bytes 100 80
         (lambda (c)
           (with-canvas-state c
             (canvas-clip-rect! c 5 5 30 30)
             (canvas-translate! c 4 8)
             (rect-svg c))) #:id-prefix "diagram"))
     (define first (render))
     (check-equal? (render) first)
     (check-true (has? #rx#"<clipPath" first))
     (check-true (has? #rx#"id=\"diagram-0\"" first))
     (check-true (has? #rx#"transform=" first)))
   (test-case "PNG image data is embedded and outlives its source wrappers"
     (define bs
       (call-with-svg-bytes 60 60
         (lambda (c)
           (with-skia ([s (make-surface 2 2 #:background 'red)]
                       [im (surface-snapshot s)])
             (draw-image-rect c im 10 10 40 40)))))
     (check-true (has? #rx#"<image" bs))
     (check-true (has? #rx#"data:image/png;base64," bs))
     (check-true (has? #rx#"<use" bs)))
   (test-case "pictures replay as vectors without flattening the whole output"
     (define bs
       (call-with-svg-bytes 100 80
         (lambda (c)
           (with-skia ([pic (call-with-picture 40 30 rect-svg)])
             (draw-picture c pic #:x 10 #:y 10)
             (draw-picture c pic #:x 50 #:y 40 #:width 20 #:height 15)))))
     (check-true (has? #rx#"<rect" bs))
     (check-false (has? #rx#"data:image/" bs)))
   (test-case "native text output remains text and does not embed font binaries"
     (define bs
       (call-with-svg-bytes 200 60
         (lambda (c)
           (with-skia ([f (make-font #:size 20)] [p (make-paint #:color 'blue)])
             (draw-simple-text c "SVG text" 10 35 f p)))))
     (check-true (has? #rx#"<text" bs))
     (check-true (has? #rx#"font-family=" bs))
     (check-false (has? #rx#"data:font/|@font-face" bs)))
   (test-case "simple-text-path explicitly emits outline geometry"
     (define bs
       (call-with-svg-bytes 200 60
         (lambda (c)
           (with-skia ([f (make-font #:size 20)] [p (make-paint #:color 'blue)]
                       [path (simple-text-path f "SVG" 10 35)])
             (draw-path c path p)))))
     (check-true (has? #rx#"<path" bs))
     (check-false (has? #rx#"<text" bs)))
   (test-case "shaped glyph outlines survive shaper closure and preserve positions"
     (define f (make-font #:size 30))
     (define sh (make-shaper f))
     (define run (shape-text sh "office affinity AV" #:language "en"))
     (define path (shaped-run->path sh run))
     (define empty (shaped-run->path sh (shape-text sh "")))
     (check-equal? (path-point-count empty) 0)
     (skia-close! empty)
     (skia-close! sh)
     (skia-close! f)
     (with-skia ([p path])
       (check-true (> (path-point-count p) 0))
       (define-values (x y w h) (path-bounds p))
       (check-true (> w 0))
       (check-true (> h 0))
       (define bs
         (call-with-svg-bytes 400 60
           (lambda (c)
             (with-skia ([ink (make-paint #:color 'blue)])
               (with-canvas-state c
                 (canvas-translate! c 10 40)
                 (draw-path c p ink))))))
       (check-true (has? #rx#"<path" bs))
       (check-false (has? #rx#"<text" bs))))
   (test-case "explicit rasterized group embeds exactly one image"
     (define calls 0)
     (define saved #f)
     (define bs
       (call-with-svg-bytes 120 90
         (lambda (c)
           (rect-svg c)
           (draw-rasterized
            c 50 10 50 50
            (lambda (rc)
              (set! calls (add1 calls))
              (set! saved rc)
              (with-skia ([blur (make-blur-image-filter 2 2)]
                          [p (make-paint #:color 'blue #:image-filter blur)])
                (draw-circle rc 25 25 10 p)))
            #:scale 2))))
     (check-equal? calls 1)
     (check-true (skia-closed? saved))
     (check-equal? (length (regexp-match* #rx#"<image[ \t\r\n]" bs)) 1)
     (check-true (has? #rx#"<rect" bs)))
   (test-case "explicit file save and early destination conflicts"
     (in-temp-directory
      (lambda (dir)
        (define target (build-path dir "vector.svg"))
        (with-skia ([d (make-svg-document 50 50)])
          (rect-svg (svg-document-canvas d))
          (svg-document-finish! d)
          (save-svg d target)
          (check-equal? (file->bytes target) (svg-document->bytes d)))
        (define called? #f)
        (check-exn exn:fail?
                   (lambda () (call-with-svg-file target 50 50
                                (lambda (_) (set! called? #t)))))
        (check-false called?)
        (check-equal? (length (directory-list dir)) 1))))
   (test-case "callback errors and publication races preserve existing files"
     (in-temp-directory
      (lambda (dir)
        (define target (build-path dir "keep.svg"))
        (call-with-output-file target (lambda (o) (write-bytes #"kept" o)))
        (check-exn #rx"intentional"
                   (lambda () (call-with-svg-file target 50 50
                                (lambda (_) (error 'test "intentional")) #:exists 'replace)))
        (check-equal? (file->bytes target) #"kept")
        (define race (build-path dir "race.svg"))
        (check-exn exn:fail?
                   (lambda ()
                     (call-with-svg-file race 50 50
                       (lambda (_) (call-with-output-file race
                                     (lambda (out) (write-bytes #"racer" out)))))))
        (check-equal? (file->bytes race) #"racer")
        (check-equal? (length (directory-list dir)) 2))))
   (test-case "relative destination is fixed before callback changes directory"
     (in-temp-directory
      (lambda (dir)
        (define elsewhere (build-path dir "elsewhere"))
        (make-directory elsewhere)
        (parameterize ([current-directory dir])
          (call-with-svg-file "fixed.svg" 50 50
            (lambda (c) (current-directory elsewhere) (rect-svg c))))
        (check-true (file-exists? (build-path dir "fixed.svg")))
        (check-false (file-exists? (build-path elsewhere "fixed.svg"))))))))

(module+ test (run-tests svg-native-tests))
