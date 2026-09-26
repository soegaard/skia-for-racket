#lang racket/base
(require rackunit racket/file racket/list "../main.rkt")
(provide output-audit-native-tests)
(define solid "half4 main(float2 p) { return half4(0.1,0.3,0.7,1); }")
(define (plain c)
  (with-skia ([p (make-paint #:color 'blue)]) (draw-rect c 5 5 40 25 p)))
(define (runtime c)
  (with-skia ([e (make-runtime-effect solid)] [s (runtime-effect->shader e)]
              [p (make-paint #:shader s)])
    (draw-rect c 5 5 40 25 p)))
(define (page f) (make-output-page 100 80 f))
(define (contains? r f [s #f])
  (for/or ([e (in-list (output-audit-report-events r))])
    (and (eq? f (output-audit-event-feature e))
         (or (not s) (eq? s (output-audit-event-status e))))))
(define (with-temp proc)
  (define d (make-temporary-file "skia-audit-~a" 'directory))
  (dynamic-wind void (lambda () (proc d)) (lambda () (delete-directory/files d))))

(define output-audit-native-tests
  (test-suite
   "Output capability audit: actual drawing wrappers"
   (test-case "plain SVG output remains vector-only"
     (define-values (bs r) (output->bytes/audit (page plain) 'svg #:policy 'vector-only))
     (check-true (regexp-match? #rx#"<svg" bs))
     (check-true (output-audit-report-vector-only? r)))
   (test-case "linear gradients are traced through their paints"
     (define r (analyze-output-page
                (page (lambda (c)
                        (with-skia ([s (make-linear-gradient-shader 0 0 50 0 '(blue red))]
                                    [p (make-paint #:shader s)]) (draw-rect c 0 0 50 20 p)))) 'svg))
     (check-true (contains? r 'linear-gradient 'vector)))
   (test-case "SVG preflight executes callback once with real backend"
     (define count 0) (define backend #f)
     (define r (analyze-output-page
                (page (lambda (c) (set! count (add1 count))
                        (set! backend (canvas-annotation-backend c)) (runtime c))) 'svg))
     (check-equal? count 1) (check-eq? backend 'svg)
     (check-true (contains? r 'runtime-shader 'needs-raster)))
   (test-case "PDF preflight reports conservative SkSL boundary"
     (check-true (contains? (analyze-output-page (page runtime) 'pdf) 'runtime-shader 'needs-raster)))
   (test-case "explicit group resolves runtime shader and records pixels"
     (define-values (_bs r)
       (output->bytes/audit
        (page (lambda (c) (draw-rasterized c 3 4 50 30 runtime #:scale 2 #:padding 2)))
        'svg #:policy 'error))
     (define group (findf (lambda (e) (eq? 'raster-group (output-audit-event-feature e)))
                         (output-audit-report-events r)))
     (check-true (contains? r 'runtime-shader 'rasterized))
     (check-equal? (hash-ref (output-audit-event-details group) 'pixel_width) 108)
     (check-equal? (hash-ref (output-audit-event-details group) 'pixel_height) 68)
     (check-false (output-audit-report-blocking? r)))
   (test-case "strict exporter rejects direct runtime drawing"
     (check-exn exn:fail:output-audit?
                (lambda () (output->bytes/audit (page runtime) 'svg #:policy 'error))))
   (test-case "strict failure preserves existing file"
     (with-temp
      (lambda (d)
        (define target (build-path d "keep.svg"))
        (call-with-output-file target (lambda (o) (display "keep" o)))
        (check-exn exn:fail:output-audit?
          (lambda () (save-output/audit (page runtime) target 'svg #:exists 'replace)))
        (check-equal? (file->string target) "keep"))))
   (test-case "preflight propagates arbitrary callback failure"
     (check-exn (lambda (x) (eq? x 'probe-stop))
                (lambda () (analyze-output-page (page (lambda (_) (raise 'probe-stop))) 'pdf))))
   (test-case "invalid policy does not execute callback"
     (define n 0)
     (check-exn exn:fail:contract?
       (lambda () (output->bytes/audit (page (lambda (_) (set! n 1))) 'svg #:policy 'silent)))
     (check-equal? n 0))
   (test-case "attached shader survives closure with provenance intact"
     (define e (make-runtime-effect solid)) (define s (runtime-effect->shader e))
     (with-skia ([p (make-paint #:shader s)])
       (skia-close! s) (skia-close! e)
       (check-true (contains? (analyze-output-page (page (lambda (c) (draw-rect c 0 0 10 10 p))) 'svg)
                              'runtime-shader))))
   (test-case "paint copy retains a detached signature"
     (with-skia ([e (make-runtime-effect solid)] [s (runtime-effect->shader e)]
                 [p (make-paint #:shader s)] [q (paint-copy p)])
       (paint-set-shader! p #f)
       (check-true (contains? (analyze-output-page (page (lambda (c) (draw-rect c 0 0 10 10 q))) 'svg)
                              'runtime-shader))))
   (test-case "shader getter preserves its source signature"
     (with-skia ([e (make-runtime-effect solid)] [s (runtime-effect->shader e)]
                 [p (make-paint #:shader s)] [again (paint-shader p)] [q (make-paint #:shader again)])
       (check-true (contains? (analyze-output-page (page (lambda (c) (draw-rect c 0 0 10 10 q))) 'svg)
                              'runtime-shader))))
   (test-case "clearing shader clears warning"
     (with-skia ([e (make-runtime-effect solid)] [s (runtime-effect->shader e)] [p (make-paint #:shader s)])
       (paint-set-shader! p #f)
       (check-false (output-audit-report-blocking?
                     (analyze-output-page (page (lambda (c) (draw-rect c 0 0 10 10 p))) 'svg)))))
   (test-case "blend reset removes custom blender risk"
     (with-skia ([e (make-runtime-effect "half4 main(half4 s,half4 d){return (s+d)*0.5;}" #:kind 'blender)]
                 [b (runtime-effect->blender e)] [p (make-paint)])
       (paint-set-blender! p b) (paint-set-blend-mode! p 'src-over)
       (check-false (contains? (analyze-output-page (page (lambda (c) (draw-rect c 0 0 10 10 p))) 'svg)
                               'runtime-blender))))
   (test-case "PDF image filters are classified as backend expansion"
     (with-skia ([f (make-blur-image-filter 2 2)] [p (make-paint #:image-filter f)])
       (check-true (contains? (analyze-output-page (page (lambda (c) (draw-circle c 20 20 10 p))) 'pdf)
                              'image-filter 'native-expansion))))
   (test-case "SVG image filters require a group"
     (with-skia ([f (make-blur-image-filter 2 2)] [p (make-paint #:image-filter f)])
       (check-true (contains? (analyze-output-page (page (lambda (c) (draw-circle c 20 20 10 p))) 'svg)
                              'image-filter 'needs-raster))))
   (test-case "native text versus automatic outlines"
     (define p (page (lambda (c)
                      (with-skia ([f (make-font #:size 12)] [ink (make-paint)])
                        (draw-simple-text c "abc" 2 20 f ink)))))
     (check-true (contains? (analyze-output-page p 'svg #:text-mode 'native) 'native-text 'viewer-dependent))
     (check-false (contains? (analyze-output-page p 'svg) 'native-text)))
   (test-case "existing image is allowed but not a vector-only result"
     (with-skia ([im (rgba-bytes->image 1 1 (bytes 255 0 0 255))])
       (define p (page (lambda (c) (draw-image c im 0 0))))
       (define-values (_bs r) (output->bytes/audit p 'svg #:policy 'error))
       (check-true (contains? r 'image 'embedded-raster))
       (check-exn exn:fail:output-audit? (lambda () (output->bytes/audit p 'svg #:policy 'vector-only)))))
   (test-case "picture created before audit keeps runtime facts"
     (with-skia ([pic (call-with-picture 100 80 runtime)])
       (check-true (contains? (analyze-output-page (page (lambda (c) (draw-picture c pic))) 'svg)
                              'runtime-shader))))
   (test-case "explicitly rasterized picture is resolved"
     (with-skia ([pic (call-with-picture 100 80 runtime)])
       (define-values (_bs r)
         (output->bytes/audit
          (page (lambda (c) (draw-rasterized c 0 0 100 80 (lambda (rc) (draw-picture rc pic)))))
          'svg #:policy 'error))
       (check-true (contains? r 'runtime-shader 'rasterized))))
   (test-case "raster group annotations report loss"
     (define p (page (lambda (c) (draw-rasterized c 0 0 50 30
                                  (lambda (rc) (plain rc)
                                    (canvas-annotate-url! rc 0 0 10 10 "https://example.org/"))))))
     (check-true (contains? (analyze-output-page p 'svg) 'annotation 'discarded))
     (check-exn exn:fail:output-audit? (lambda () (output->bytes/audit p 'svg #:policy 'error))))
   (test-case "PDF report numbers include empty pages"
     (define r (analyze-output-page (list (page void) (page plain)) 'pdf))
     (check-equal? (output-audit-report-pages r) 2)
     (check-not-false (member 2 (map output-audit-event-page (output-audit-report-events r)))))
   (test-case "repeated preflight reports are deterministic"
     (define p (page plain))
     (check-equal? (output-audit-report->jsexpr (analyze-output-page p 'svg))
                   (output-audit-report->jsexpr (analyze-output-page p 'svg))))
   (test-case "label copied before caller mutation"
     (define label (string-copy "panel"))
     (define p (page (lambda (c) (with-output-label label (plain c)))))
     (define r (analyze-output-page p 'svg))
     (string-set! label 0 #\X)
     (check-not-false (member '("panel") (map output-audit-event-scope (output-audit-report-events r)))))
   (test-case "reused picture recorder does not inherit previous effect"
     (with-skia ([rec (make-picture-recorder)])
       (define first (picture-recorder-begin-recording! rec 0 0 100 80))
       (runtime first)
       (with-skia ([pic1 (picture-recorder-finish-recording! rec)])
         (define second (picture-recorder-begin-recording! rec 0 0 100 80))
         (plain second)
         (with-skia ([pic2 (picture-recorder-finish-recording! rec)])
           (check-false (contains? (analyze-output-page (page (lambda (c) (draw-picture c pic2))) 'svg)
                                   'runtime-shader))))))
   (test-case "source is unchanged by preflight"
     (with-skia ([s (make-surface 2 2 #:background 'red)])
       (define before (surface->rgba-bytes s))
       (define im (surface-snapshot s))
       (dynamic-wind void
         (lambda () (analyze-output-page (page (lambda (c) (draw-image c im 0 0))) 'svg))
         (lambda () (skia-close! im)))
       (check-equal? before (surface->rgba-bytes s))))
   (test-case "difference clip is not certified by a later plain draw"
     (define r (analyze-output-page
                (page (lambda (c) (canvas-clip-rect! c 5 5 10 10 #:operation 'difference) (plain c))) 'svg))
     (check-true (contains? r 'clip-difference 'needs-raster)))
   (test-case "event budget aborts before publication"
     (with-temp
      (lambda (d)
        (define path (build-path d "not-published.svg"))
        (parameterize ([current-output-audit-event-limit 1])
          (check-exn exn:fail? (lambda () (save-output/audit (page plain) path 'svg))))
        (check-false (file-exists? path)))))))
