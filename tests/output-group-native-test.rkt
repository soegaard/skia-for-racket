#lang racket/base
(require rackunit racket/list racket/file json
         "../main.rkt")
(define (blue c)
  (with-skia ([paint (make-paint #:color 'blue)]) (draw-rect c 0 0 30 20 paint)))
(define (runtime-red c)
  (with-skia ([e (make-runtime-effect "half4 main(float2 p) { return half4(1,0,0,1); }")]
              [s (runtime-effect->shader e)] [p (make-paint #:shader s)])
    (draw-rect c 0 0 30 20 p)))
(define (text c)
  (with-skia ([font (make-font #f #:size 12)] [p (make-paint #:color 'black)])
    (draw-simple-text c "TEXT" 0 15 font p)))
(define (export-group draw #:format [format 'svg] #:policy [policy 'prefer-vector]
                      #:audit [audit 'error] #:scale [scale 2] #:padding [padding 0]
                      #:mode [mode 'auto])
  (define report #f)
  (define calls 0)
  (define page (make-output-page 100 80
    (lambda (c)
      (set! report
        (draw-output-group c 10 15 40 30
          (lambda (g) (set! calls (add1 calls)) (draw g))
          #:policy policy #:padding padding #:scale scale #:label "test")))))
  (define-values (bs ar) (output->bytes/audit page format #:policy audit #:text-mode mode))
  (values bs report calls ar))
(define (g-error thunk)
  (with-handlers ([exn:fail:output-group? exn:fail:output-group-report])
    (call-with-values thunk (lambda ignored #f))))
(define (with-loaded proc)
  (with-skia ([p (call-with-picture 30 20 blue)]
              [loaded (picture-from-bytes (picture->bytes p) #:trusted? #t)])
    (proc loaded)))

(provide output-group-native-tests)
(define output-group-native-tests
  (test-suite "Bounded output groups: native backends"
    (test-case "plain SVG group runs once and stays vector"
      (define-values (bs r calls ar) (export-group blue))
      (check-equal? calls 1) (check-eq? (output-group-report-strategy r) 'native)
      (check-false (regexp-match? #rx"<image" bs)) (check-true (output-audit-report-vector-only? ar)))
    (test-case "plain PDF group runs once"
      (define-values (bs r calls ar) (export-group blue #:format 'pdf)) (check-equal? calls 1) (check-eq? (output-group-report-strategy r) 'native) (check-true (regexp-match? #rx#"^%PDF" bs)))
    (test-case "SVG runtime chooses bounded fallback"
      (define-values (bs r calls ar) (export-group runtime-red)) (check-equal? calls 1) (check-eq? (output-group-report-strategy r) 'raster) (check-equal? (output-group-report-pixel-size r) '#(80 60)) (check-true (regexp-match? #rx"<image" bs)) (check-false (output-audit-report-blocking? ar)))
    (test-case "PDF runtime also chooses explicit fallback"
      (define-values (bs r calls ar) (export-group runtime-red #:format 'pdf)) (check-eq? (output-group-report-strategy r) 'raster) (check-false (output-audit-report-blocking? ar)))
    (test-case "padding contributes to real pixel dimensions"
      (define-values (bs r calls ar) (export-group runtime-red #:padding '(2 3 4 5))) (check-equal? (output-group-report-padded-bounds r) '#(8.0 12.0 46.0 38.0)) (check-equal? (output-group-report-pixel-size r) '#(92 76)))
    (test-case "rational scale report is JSON serializable"
      (define-values (bs r calls ar) (export-group blue #:scale 3/2)) (check-not-exn (lambda () (jsexpr->string (output-group-report->jsexpr r)))))
    (test-case "require vector rejects runtime"
      (define r (g-error (lambda () (export-group runtime-red #:policy 'require-vector)))) (check-eq? (output-group-report-reason r) 'vector-required))
    (test-case "explicit raster on vector content"
      (define-values (bs r calls ar) (export-group blue #:policy 'raster)) (check-eq? (output-group-report-reason r) 'explicit-raster) (check-true (regexp-match? #rx"<image" bs)))
    (test-case "outer vector-only policy vetoes local fallback"
      (check-exn exn:fail:output-audit? (lambda () (export-group runtime-red #:audit 'vector-only))))
    (test-case "a URL is retained in native SVG replay"
      (define-values (bs r calls ar)
        (export-group (lambda (c) (blue c) (canvas-annotate-url! c 0 0 30 20 "https://example.org/?a=1&b=2"))))
      (check-eq? (output-group-report-strategy r) 'native)
      (check-true (regexp-match? #rx"example.org" bs)) (check-false (output-audit-report-blocking? ar)))
    (test-case "URL plus effect refuses semantic loss"
      (define r (g-error (lambda () (export-group (lambda (c) (runtime-red c) (canvas-annotate-url! c 0 0 30 20 "https://example.org/")))))) (check-eq? (output-group-report-reason r) 'annotation-would-be-lost))
    (test-case "named destination belongs on the outer canvas"
      (check-exn exn:fail? (lambda () (export-group (lambda (c) (canvas-define-destination! c "target" 0 0))))))
    (test-case "native PDF text with effects is not silently rasterized"
      (define r (g-error (lambda () (export-group (lambda (c) (text c) (runtime-red c)) #:format 'pdf)))) (check-eq? (output-group-report-reason r) 'native-text-would-be-lost))
    (test-case "explicitly outlined text permits fallback"
      (define-values (bs r calls ar) (export-group (lambda (c) (text c) (runtime-red c)) #:format 'pdf #:mode 'outline)) (check-eq? (output-group-report-strategy r) 'raster))
    (test-case "plain native text stays searchable in PDF path"
      (define-values (bs r calls ar) (export-group text #:format 'pdf)) (check-eq? (output-group-report-strategy r) 'native) (check-not-false (memq 'native-text (output-group-report-features r))))
    (test-case "opaque loaded picture is rejected"
      (with-loaded (lambda (p) (define r (g-error (lambda () (export-group (lambda (c) (draw-picture c p)))))) (check-eq? (output-group-report-reason r) 'unknown-provenance))))
    (test-case "forced raster does not certify an opaque picture"
      (with-loaded (lambda (p) (define r (g-error (lambda () (export-group (lambda (c) (draw-picture c p)) #:policy 'raster)))) (check-eq? (output-group-report-reason r) 'unknown-provenance))))
    (test-case "manual raster inside capture cannot erase unknown history"
      (with-loaded (lambda (p) (define r (g-error (lambda () (export-group (lambda (c) (draw-rasterized c 0 0 30 20 (lambda (r) (draw-picture r p)))))))) (check-eq? (output-group-report-reason r) 'unknown-provenance))))
    (test-case "manual raster cannot erase lost links"
      (define r (g-error (lambda () (export-group (lambda (c) (draw-rasterized c 0 0 30 20 (lambda (r) (canvas-annotate-url! r 0 0 20 10 "https://example.org/")))))))) (check-eq? (output-group-report-reason r) 'discarded-semantics))
    (test-case "lost link survives ordinary recording outside a group"
      (with-skia ([p (call-with-picture 30 20 (lambda (c)
                         (draw-rasterized c 0 0 30 20
                           (lambda (r) (canvas-annotate-url! r 0 0 20 10 "https://example.org/")))))])
        (define r (g-error (lambda () (export-group (lambda (c) (draw-picture c p))))))
        (check-eq? (output-group-report-reason r) 'discarded-semantics)))
    (test-case "nested groups capture each callback once"
      (define inner-count 0)
      (define-values (bs r calls ar) (export-group (lambda(c)
        (draw-output-group c 0 0 30 20 (lambda(g) (set! inner-count (add1 inner-count)) (runtime-red g))))))
      (check-equal? inner-count 1) (check-equal? calls 1)
      (check-eq? (output-group-report-strategy r) 'native)
      (check-eq? (output-group-report-strategy (car (output-group-report-children r))) 'raster))
    (test-case "outer raster includes nested vector content"
      (define-values (bs r calls ar) (export-group (lambda(c) (draw-output-group c 0 0 30 20 blue)) #:policy 'raster))
      (check-eq? (output-group-report-strategy r) 'raster)
      (check-eq? (output-group-report-strategy (car (output-group-report-children r))) 'native))
    (test-case "independent recorder has no target backend"
      (with-skia ([rec (make-picture-recorder)]) (define c (picture-recorder-begin-recording! rec 0 0 100 100)) (check-exn exn:fail? (lambda () (draw-output-group c 0 0 30 20 blue)))))
    (test-case "unrelated recorder cannot borrow nested backend context"
      (check-exn exn:fail?
        (lambda () (export-group (lambda(g)
          (with-skia ([r (make-picture-recorder)])
            (define c (picture-recorder-begin-recording! r 0 0 20 20))
            (draw-output-group c 0 0 10 10 blue)))))))
    (test-case "closed callback resources are retained in recording"
      (define-values (bs r calls ar) (export-group blue)) (check-true (> (bytes-length bs) 100)) (check-eq? (output-group-report-strategy r) 'native))
    (test-case "captured canvas expires after callback"
      (define saved #f) (define-values (bs r calls ar) (export-group (lambda(c) (set! saved c) (blue c)))) (check-exn exn:fail? (lambda () (blue saved))))
    (test-case "callback failure does not touch destination pixels"
      (with-skia ([s (make-surface 60 40 #:background 'green)])
        (define before (surface->rgba-bytes s))
        (check-exn exn:fail? (lambda () (draw-output-group (surface-canvas s) 0 0 30 20
          (lambda(c) (blue c) (error 'author "failed")))))
        (check-equal? (surface->rgba-bytes s) before)))
    (test-case "continuation escape cleans up before destination commit"
      (with-skia ([s (make-surface 60 40 #:background 'green)])
        (define before (surface->rgba-bytes s))
        ;; Escape continuations are allowed by the existing scoped-resource
        ;; protocol. Dynamic cleanup still runs, and capture never reaches the
        ;; destination-commit step.
        (define result
          (let/ec escape
            (draw-output-group (surface-canvas s) 0 0 30 20
                               (lambda(c) (blue c) (escape 'escaped)))
            'committed))
        (check-eq? result 'escaped)
        (check-equal? (surface->rgba-bytes s) before)))
    (test-case "multiple callback values are discarded"
      (define-values (bs r calls ar) (export-group (lambda(c) (blue c) (values 1 2 3)))) (check-equal? calls 1))
    (test-case "receiver matrix and save count restored"
      (with-skia ([s (make-surface 100 80)])
        (define c (surface-canvas s)) (canvas-translate! c 5 6)
        (define before (canvas-matrix4 c)) (define sc (canvas-save-count c))
        (draw-output-group c 10 12 30 20 blue)
        (check-equal? (canvas-matrix4 c) before) (check-equal? (canvas-save-count c) sc)))
    (test-case "padded local clip is the same for native and raster"
      (with-skia ([a (make-surface 60 40)] [b (make-surface 60 40)])
        (define (draw c) (with-skia ([p (make-paint #:color 'blue)]) (draw-rect c -100 -100 500 500 p)))
        (draw-output-group (surface-canvas a) 10 10 20 10 draw #:padding 2 #:scale 1)
        (draw-output-group (surface-canvas b) 10 10 20 10 draw #:padding 2 #:scale 1 #:policy 'raster)
        (check-equal? (surface->rgba-bytes a) (surface->rgba-bytes b))))
    (test-case "isolated clear does not erase the receiving backdrop"
      (with-skia ([s (make-surface 60 40 #:background 'green)])
        (define report (draw-output-group (surface-canvas s) 10 10 30 20
                          (lambda(c) (blue c) (canvas-clear! c 'transparent))))
        (check-eq? (output-group-report-reason report) 'isolated-compositing)
        (check-equal? (surface-pixel s 20 20) (rgba 0 128 0 255))))
    (test-case "isolated src blend matches forced raster on raster target"
      (with-skia ([a (make-surface 60 40 #:background 'green)] [b (make-surface 60 40 #:background 'green)])
        (define (draw c) (with-skia ([p (make-paint #:color (rgba 255 0 0 128) #:blend-mode 'src)])
                          (draw-rect c 0 0 30 20 p)))
        (define report (draw-output-group (surface-canvas a) 10 10 30 20 draw #:scale 1))
        (draw-output-group (surface-canvas b) 10 10 30 20 draw #:scale 1 #:policy 'raster)
        (check-eq? (output-group-report-strategy report) 'raster)
        (check-equal? (surface->rgba-bytes a) (surface->rgba-bytes b))))
    (test-case "raster allocation is bounded before receiver commit"
      (with-skia ([s (make-surface 60 40)])
        (define before (surface->rgba-bytes s))
        (parameterize ([current-skia-byte-limit 64])
          (check-exn exn:fail? (lambda () (draw-output-group (surface-canvas s) 0 0 30 20 blue #:policy 'raster))))
        (check-equal? (surface->rgba-bytes s) before)))
    (test-case "outer perspective is refused before callback"
      (define calls 0)
      (check-exn exn:fail? (lambda () (output->bytes (make-output-page 100 80
        (lambda(c) (canvas-concat-matrix3! c (matrix3-perspective 0.001 0))
          (draw-output-group c 0 0 30 20 (lambda(g) (set! calls (add1 calls)) (blue g))))) 'svg)))
      (check-equal? calls 0))
    (test-case "perspective inside callback is handled by fallback"
      (define-values (bs r calls ar) (export-group (lambda(c) (canvas-concat-matrix3! c (matrix3-perspective 0.001 0)) (blue c)))) (check-eq? (output-group-report-strategy r) 'raster))
    (test-case "device-coordinate region clips are explicitly refused"
      (define r (g-error (lambda () (export-group (lambda(c)
        (with-skia ([region (make-region '((0 0 30 20)))]) (canvas-clip-region! c region) (blue c)))))))
      (check-eq? (output-group-report-reason r) 'device-space-clip))
    (test-case "closed destination rejected before callback"
      (define s (make-surface 10 10)) (define c (surface-canvas s)) (skia-close! s) (define calls 0) (check-exn exn:fail? (lambda () (draw-output-group c 0 0 5 5 (lambda(_) (set! calls (add1 calls)))))) (check-equal? calls 0))
    (test-case "cross-thread destination rejects"
      (with-skia ([s (make-surface 10 10)])
        (define ch (make-channel))
        (thread (lambda () (channel-put ch (with-handlers ([exn:fail? (lambda(_) 'rejected)])
                             (draw-output-group (surface-canvas s) 0 0 5 5 blue) 'accepted))))
        (check-eq? (channel-get ch) 'rejected)))
    (test-case "report is detached immutable data"
      (define-values (bs r calls ar) (export-group blue)) (check-true (immutable? (output-group-report-bounds r))) (check-true (immutable? (output-group-report-label r))) (check-not-exn (lambda () (jsexpr->string (output-group-report->jsexpr r)))))
    (test-case "preflight runs callback once without exposing captured native hazards"
      (define calls 0)
      (define report (analyze-output-page (make-output-page 100 80 (lambda(c)
        (draw-output-group c 0 0 40 30 (lambda(g) (set! calls (add1 calls)) (runtime-red g))))) 'svg))
      (check-equal? calls 1) (check-false (output-audit-report-blocking? report)))
    (test-case "strict rejected export preserves existing file"
      (define path (make-temporary-file "group-~a.svg"))
      (dynamic-wind void
        (lambda ()
          (call-with-output-file path (lambda(o) (write-bytes #"sentinel" o)) #:exists 'truncate)
          (check-exn exn:fail:output-group? (lambda ()
            (save-output/audit (make-output-page 100 80 (lambda(c)
              (draw-output-group c 0 0 30 20 runtime-red #:policy 'require-vector)))
              path 'svg #:exists 'replace)))
          (check-equal? (file->bytes path) #"sentinel"))
        (lambda () (delete-file path))))
    (test-case "outer clip and translation remain effective after replay"
      (with-skia ([s (make-surface 60 40)])
        (define c (surface-canvas s))
        (canvas-clip-rect! c 20 10 10 10 #:antialias? #f)
        (draw-output-group c 10 10 30 20 blue)
        (check-equal? (surface-pixel s 22 12) (rgba 0 0 255 255))
        (check-equal? (rgba-alpha (surface-pixel s 12 12)) 0)))
    (test-case "explicit raster containing known effects stays nonblocking after re-record"
      (with-skia ([p (call-with-picture 30 20 (lambda(c)
                        (draw-rasterized c 0 0 30 20 runtime-red)))])
        (define-values (bs r calls ar) (export-group (lambda(c) (draw-picture c p))))
        (check-eq? (output-group-report-strategy r) 'native)
        (check-false (output-audit-report-blocking? ar))))
))
