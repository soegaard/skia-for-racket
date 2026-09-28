#lang racket/base
(require rackunit racket/list json
         "../main.rkt" "../gpu.rkt" "../gpu-output.rkt"
         "../private/gpu-provider.rkt" "../private/gpu-io-trace.rkt"
         "gpu-output-fixtures.rkt")
(provide make-gpu-output-native-tests gpu-output-native-test-count)
(define gpu-output-native-test-count 42)
(define (blue c)
  (with-skia ([p (make-paint #:color 'blue #:antialias? #f)]) (draw-rect c 0 0 24 16 p)))
(define (effect c)
  (with-skia ([e (make-runtime-effect "half4 main(float2 p) { return half4(1,0,0,1); }")]
              [s (runtime-effect->shader e)] [p (make-paint #:shader s)])
    (draw-rect c 0 0 24 16 p)))
(define (text c)
  (with-skia ([f (make-font #:size 10)] [p (make-paint #:color 'black)])
    (draw-simple-text c "TEXT" 0 12 f p)))
(define (export draw executor #:format [format 'svg] #:policy [policy 'prefer-vector]
                #:audit [audit 'error] #:mode [mode 'auto] #:scale [scale 2]
                #:padding [padding 0] #:width [w 24] #:height [h 16])
  (define result #f) (define calls 0)
  (define-values (bytes audit-report)
    (output->bytes/audit
     (make-output-page 80 60
       (lambda (c)
         (set! result (draw-output-group c 8 10 w h
                        (lambda (g) (set! calls (add1 calls)) (draw g))
                        #:policy policy #:scale scale #:padding padding #:raster-executor executor))))
     format #:policy audit #:text-mode mode))
  (values bytes result calls audit-report))
(define (preview draw executor)
  (with-skia ([s (make-surface 48 36 #:background 'green)])
    (draw-output-group (surface-canvas s) 8 10 24 16 draw #:policy 'raster
                       #:scale 1 #:raster-executor executor)
    (surface->rgba-bytes s)))
(define (group-error thunk)
  (with-handlers ([exn:fail:output-group? exn:fail:output-group-report])
    (call-with-values thunk (lambda _ #f))))
(define (run-with-ledger proc)
  (define ledger (box '()))
  (parameterize ([current-gpu-io-ledger ledger]) (proc))
  (reverse (unbox ledger)))
(define (readbacks events)
  (filter (lambda (e) (equal? (hash-ref e 'kind) "readback")) events))

(define (make-gpu-output-native-tests context other)
  (define executor (make-gpu-raster-executor context))
  (define backend (symbol->string (gpu-context-backend context)))
  (test-suite
   "Bounded GPU document fallbacks with unchanged representation policies"
   (test-case "SVG effect uses the requested GPU and embeds one detached raster"
     (define-values (b r n a) (export effect executor))
     (check-equal? n 1) (check-eq? (output-group-report-strategy r) 'raster)
     (check-equal? (hash-ref (output-group-report-execution r) 'backend) backend)
     (check-true (regexp-match? #rx#"<image" b)) (check-false (output-audit-report-blocking? a)))
   (test-case "PDF effect uses GPU raster rather than backend implicit fallback"
     (define-values (b r n a) (export effect executor #:format 'pdf))
     (check-true (regexp-match? #rx#"^%PDF" b)) (check-equal? n 1)
     (check-equal? (hash-ref (output-group-report-execution r) 'readback_count) 1))
   (test-case "plain vector group does not touch the GPU"
     (define events (run-with-ledger
       (lambda () (define-values (b r n a) (export blue executor))
         (check-eq? (output-group-report-strategy r) 'native)
         (check-false (regexp-match? #rx#"<image" b)))))
     (check-equal? events '()))
   (test-case "vector-only document does not initialize a lazy factory"
     (define creates 0)
     (call-with-gpu-raster-executor
      (lambda () (set! creates (add1 creates)) (gpu-unavailable 'test "no device"))
      (lambda (e) (define-values (b r n a) (export blue e #:audit 'vector-only))
        (check-eq? (output-group-report-strategy r) 'native)))
     (check-equal? creates 0))
   (test-case "require-vector rejects effects before execution"
     (define events (run-with-ledger
       (lambda () (define r (group-error (lambda () (export effect executor #:policy 'require-vector))))
         (check-eq? (output-group-report-reason r) 'vector-required))))
     (check-equal? events '()))
   (test-case "outer vector-only veto precedes lazy context creation"
     (define creates 0)
     (check-exn exn:fail:output-audit?
       (lambda () (call-with-gpu-raster-executor
                    (lambda () (set! creates (add1 creates)) (gpu-unavailable 'test "no device"))
                    (lambda (e) (export effect e #:audit 'vector-only)))))
     (check-equal? creates 0))
   (test-case "native URL metadata remains vector metadata"
     (define-values (b r n a)
       (export (lambda (c) (blue c) (canvas-annotate-url! c 0 0 24 16 "https://example.org/")) executor))
     (check-eq? (output-group-report-strategy r) 'native)
     (check-true (regexp-match? #rx#"example.org" b)))
   (test-case "GPU rasterization cannot discard a URL"
     (define r (group-error (lambda ()
       (export (lambda (c) (effect c) (canvas-annotate-url! c 0 0 24 16 "https://example.org/")) executor))))
     (check-eq? (output-group-report-reason r) 'annotation-would-be-lost))
   (test-case "PDF native text cannot be silently rasterized by a GPU"
     (define r (group-error (lambda () (export (lambda (c) (text c) (effect c)) executor #:format 'pdf))))
     (check-eq? (output-group-report-reason r) 'native-text-would-be-lost))
   (test-case "explicit text outlining permits bounded GPU rasterization"
     (define-values (b r n a) (export (lambda (c) (text c) (effect c)) executor #:format 'pdf #:mode 'outline))
     (check-eq? (output-group-report-strategy r) 'raster))
   (test-case "native PDF text alone remains native"
     (define-values (b r n a) (export text executor #:format 'pdf))
     (check-eq? (output-group-report-strategy r) 'native)
     (check-not-false (memq 'native-text (output-group-report-features r))))
   (test-case "forced GPU rasterization cannot certify imported SKP provenance"
     (with-skia ([p (call-with-picture 24 16 blue)]
                 [opaque (picture-from-bytes (picture->bytes p) #:trusted? #t)])
       (define r (group-error (lambda () (export (lambda (c) (draw-picture c opaque)) executor #:policy 'raster))))
       (check-eq? (output-group-report-reason r) 'unknown-provenance)))
   (test-case "lost links inside an explicit CPU raster remain rejected"
     (define r (group-error (lambda () (export
       (lambda (c) (draw-rasterized c 0 0 24 16
                     (lambda (r) (canvas-annotate-url! r 0 0 24 16 "https://example.org/")))) executor))))
     (check-eq? (output-group-report-reason r) 'discarded-semantics))
   (test-case "fractional bounds and asymmetric padding use ceil pixel extents"
     (define-values (b r n a) (export effect executor #:width 24.25 #:height 16.5
                                      #:padding '(1 2 3 4) #:scale 3/2))
     (check-equal? (output-group-report-pixel-size r) '#(43 34))
     (define target (hash-ref (output-group-report-execution r) 'target))
     (check-equal? (hash-ref target 'width) 43) (check-equal? (hash-ref target 'height) 34))
   (test-case "raster DPI still determines the default group scale"
     (define r #f)
     (define b (output->bytes (make-output-page 80 60
       (lambda (c) (set! r (draw-output-group c 0 0 24 16 effect #:raster-executor executor))))
                              'svg #:raster-dpi 216))
     (check-equal? (output-group-report-scale r) 3)
     (check-equal? (output-group-report-pixel-size r) '#(72 48)))
   (test-case "one GPU fallback performs exactly one explicit readback"
     (define events (run-with-ledger (lambda () (export effect executor))))
     (check-equal? (length (readbacks events)) 1))
   (test-case "transparent clear does not erase the receiving backdrop"
     (define (draw c) (blue c) (canvas-clear! c 'transparent))
     (check-equal? (preview draw executor) (preview draw 'cpu)))
   (test-case "source compositing remains isolated on transparency"
     (define (draw c)
       (with-skia ([p (make-paint #:color (rgba 255 0 0 128) #:blend-mode 'src #:antialias? #f)])
         (draw-rect c 0 0 24 16 p)))
     (check-equal? (preview draw executor) (preview draw 'cpu)))
   (test-case "simple opaque pixels match the CPU fallback exactly"
     (check-equal? (preview blue executor) (preview blue 'cpu)))
   (test-case "authoring failure occurs before lazy GPU creation"
     (define creates 0)
     (check-exn #rx"author failed"
       (lambda () (call-with-gpu-raster-executor
                    (lambda () (set! creates (add1 creates)) (gpu-unavailable 'test "no device"))
                    (lambda (e) (export (lambda (c) (error 'test "author failed")) e)))))
     (check-equal? creates 0))
   (test-case "GPU target limit failure leaves the receiving pixels unchanged"
     (with-skia ([s (make-surface 48 36 #:background 'green)])
       (define before (surface->rgba-bytes s))
       (define limit (hash-ref (gpu-context-info context) 'max_render_target_size))
       (check-exn exn:fail?
         (lambda () (draw-output-group (surface-canvas s) 0 0 (add1 limit) 1 blue
                       #:policy 'raster #:scale 1 #:raster-executor executor)))
       (check-equal? (surface->rgba-bytes s) before)))
   (test-case "byte allocation limit is checked before GPU raster preparation"
     (with-skia ([s (make-surface 48 36)])
       (define before (surface->rgba-bytes s))
       (parameterize ([current-skia-byte-limit 64])
         (check-exn exn:fail? (lambda () (draw-output-group (surface-canvas s) 0 0 24 16 blue
                                          #:policy 'raster #:raster-executor executor))))
       (check-equal? (surface->rgba-bytes s) before)))
   (test-case "nested raster child inherits its exact enclosing executor"
     (define events (run-with-ledger
       (lambda ()
         (define-values (b r n a) (export
           (lambda (c) (draw-output-group c 0 0 24 16 effect)) executor))
         (check-eq? (output-group-report-strategy r) 'native)
         (define child (car (output-group-report-children r)))
         (check-equal? (hash-ref (output-group-report-execution child) 'context_generation)
                       (gpu-context-generation context)))))
     (check-equal? (length (readbacks events)) 1))
   (test-case "nested CPU override does not initialize the outer lazy GPU"
     (define creates 0)
     (call-with-gpu-raster-executor
      (lambda () (set! creates (add1 creates)) (gpu-unavailable 'test "no device"))
      (lambda (e)
        (define-values (b r n a) (export
          (lambda (c) (draw-output-group c 0 0 24 16 effect #:raster-executor 'cpu)) e))
        (check-eq? (output-group-report-strategy r) 'native)))
     (check-equal? creates 0))
   (test-case "unrelated recorder cannot inherit a target or executor"
     (check-exn exn:fail?
       (lambda () (export (lambda (c)
         (with-skia ([recorder (make-picture-recorder)])
           (define rc (picture-recorder-begin-recording! recorder 0 0 24 16))
           (draw-output-group rc 0 0 24 16 effect))) executor))))
   (test-case "unrelated CPU canvas does not inherit the enclosing executor"
     (define events (run-with-ledger
       (lambda () (define-values (b r n a) (export
         (lambda (c)
           (with-skia ([s (make-surface 24 16)])
             (define inner (draw-output-group (surface-canvas s) 0 0 24 16 effect #:policy 'raster))
             (check-equal? (hash-ref (output-group-report-execution inner) 'backend) "raster"))
           (blue c)) executor))
         (check-equal? (output-group-report-children r) '()))))
     (check-equal? events '()))
   (test-case "same active context can execute its bounded output group"
     (call-with-gpu-context context
       (lambda () (define-values (b r n a) (export effect executor))
         (check-equal? (hash-ref (output-group-report-execution r) 'backend) backend))))
   (test-case "foreign active context is never silently substituted"
     (call-with-gpu-context other
       (lambda () (check-exn exn:fail? (lambda () (export effect executor))))))
   (test-case "same-context GPU image is explicitly detached by forced raster"
     (call-with-gpu-context context
       (lambda ()
         (with-skia ([cpu (rgba-bytes->image 1 1 #"\377\0\0\377")]
                     [image (gpu-upload-image context cpu)])
           (define-values (b r n a) (export (lambda (c) (draw-image-rect c image 0 0 24 16))
                                            executor #:policy 'raster))
           (check-equal? (hash-ref (output-group-report-execution r) 'transfer) "gpu-to-cpu")))))
   (test-case "foreign captured GPU graph is rejected before executor activation"
     (call-with-gpu-context other
       (lambda ()
         (with-skia ([cpu (rgba-bytes->image 1 1 #"\377\0\0\377")]
                     [image (gpu-upload-image other cpu)])
           (check-exn #rx"another GPU context"
             (lambda () (export (lambda (c) (draw-image-rect c image 0 0 24 16))
                                 executor #:policy 'raster)))))))
   (test-case "borrowed executor does not close its context"
     (export effect executor)
     (check-eq? (gpu-context-state context) 'ready))
   (test-case "temporary targets and detached images leave no live GPU children"
     (export effect executor)
     (call-with-gpu-context context (lambda () (gpu-drain-releases! context)))
     (define info (gpu-context-info context))
     (check-equal? (hash-ref info 'live_children) 0)
     (check-equal? (hash-ref info 'pending_releases) 0)
     (check-equal? (hash-ref info 'failed_releases) 0))
   (test-case "explicit unavailable fallback records CPU without replaying authoring"
     (define creates 0)
     (call-with-gpu-raster-executor
      (lambda () (set! creates (add1 creates)) (gpu-unavailable 'test "no device"))
      (lambda (e)
        (define-values (b r n a) (export effect e))
        (check-equal? n 1)
        (define execution (output-group-report-execution r))
        (check-equal? (hash-ref execution 'backend) "raster")
        (check-equal? (hash-ref execution 'readback_count) 0)
        (check-equal? (hash-ref (hash-ref execution 'fallback) 'reason) "gpu-unavailable"))
      #:on-unavailable 'cpu)
     (check-equal? creates 1))
   (test-case "default unavailable policy does not produce a CPU document"
     (check-exn exn:fail:gpu:unavailable?
       (lambda () (call-with-gpu-raster-executor
                    (lambda () (gpu-unavailable 'test "no device"))
                    (lambda (e) (export effect e))))))
   (test-case "execution report is detached JSON and audit includes actual transfer"
     (define-values (b r n a) (export effect executor))
     (check-not-exn (lambda () (jsexpr->string (output-group-report->jsexpr r))))
     (define e (findf (lambda (e) (eq? (output-audit-event-operation e) 'execute-output-group))
                      (output-audit-report-events a)))
     (check-not-false e)
     (check-equal? (hash-ref (hash-ref (output-audit-event-details e) 'execution) 'transfer) "gpu-to-cpu"))
   (test-case "explicit raster color space preserves tagged image conversion"
     (with-skia ([linear (make-linear-srgb-color-space)] [srgb (make-srgb-color-space)]
                 [source (rgba-bytes->image 1 1 (bytes 128 128 128 255) #:color-space linear)]
                 [destination (make-surface 32 24 #:color-space srgb)])
       (draw-output-group (surface-canvas destination) 0 0 16 16
         (lambda (c) (draw-image-rect c source 0 0 16 16 #:sampling 'nearest))
         #:policy 'raster #:scale 1 #:color-space srgb #:raster-executor executor)
       (define b (surface->rgba-bytes destination))
       (for ([i '(0 1 2)]) (check-true (<= 186 (bytes-ref b i) 190)))))
   (test-case "destination transform and save stack survive a GPU fallback"
     (with-skia ([s (make-surface 80 60)])
       (define c (surface-canvas s)) (canvas-translate! c 3 4)
       (define before (canvas-matrix4 c)) (define count (canvas-save-count c))
       (define r (draw-output-group c 8 10 24 16 effect #:policy 'raster #:raster-executor executor))
       (check-equal? (hash-ref (output-group-report-execution r) 'transfer) "gpu-to-cpu")
       (check-equal? (canvas-matrix4 c) before) (check-equal? (canvas-save-count c) count)))
   (test-case "nested raster child and forced raster parent each execute once"
     (define child-calls 0)
     (define events (run-with-ledger
       (lambda ()
         (define-values (b r n a)
           (export (lambda (c)
                     (draw-output-group c 0 0 24 16
                       (lambda (g) (set! child-calls (add1 child-calls)) (effect g))))
                   executor #:policy 'raster))
         (check-equal? n 1) (check-equal? (length (output-group-report-children r)) 1))))
     (check-equal? child-calls 1) (check-equal? (length (readbacks events)) 2))
   (test-case "GPU replay features remain visible as rasterized audit events"
     (define-values (b r n a) (export effect executor))
     (define hits (filter (lambda (e) (eq? (output-audit-event-feature e) 'runtime-shader))
                          (output-audit-report-events a)))
     (check-true (pair? hits))
     (for ([e (in-list hits)]) (check-eq? (output-audit-event-status e) 'rasterized)))
   (test-case "preflight still executes temporary GPU rasters and authors only once"
     (define calls 0)
     (define events (run-with-ledger
       (lambda ()
         (define report (analyze-output-page
           (make-output-page 80 60
             (lambda (c) (draw-output-group c 0 0 24 16
                           (lambda (g) (set! calls (add1 calls)) (effect g))
                           #:raster-executor executor))) 'svg))
         (check-false (output-audit-report-blocking? report)))))
     (check-equal? calls 1) (check-equal? (length (readbacks events)) 1))
   (test-case "closed color space is rejected before authoring"
     (define cs (make-srgb-color-space)) (skia-close! cs)
     (define calls 0)
     (with-skia ([s (make-surface 32 24)])
       (check-exn exn:fail? (lambda () (draw-output-group (surface-canvas s) 0 0 24 16
                                        (lambda (c) (set! calls (add1 calls)))
                                        #:color-space cs #:raster-executor executor))))
     (check-equal? calls 0))
   (test-case "CPU fallback remains the default and raw GPU destinations are unchanged"
     (define-values (b r n a) (export effect #f))
     (check-equal? (hash-ref (output-group-report-execution r) 'backend) "raster")
     (call-with-gpu-context context
       (lambda ()
         (with-skia ([s (make-gpu-surface context 32 32)])
           (check-exn exn:fail? (lambda () (draw-output-group (surface-canvas s) 0 0 24 16 blue
                                            #:raster-executor executor)))))))))
