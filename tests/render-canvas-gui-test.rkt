#lang racket/base
;; Required selected GUI test. No unavailable-backend skip or CPU GPU fallback.
(require rackunit racket/class racket/list racket/cmdline racket/file json
         (prefix-in gui: racket/gui/base) (prefix-in rd: racket/draw)
         "../render-canvas.rkt" "../gpu-dc.rkt"
         "../private/render-canvas-policy.rkt" "../private/gpu-io-trace.rkt"
         "gpu-dc-consumer-fixtures.rkt")
(provide render-canvas-gui-tests render-canvas-gui-test-count)
(define request (make-parameter (list 'raster 'auto #f)))
(define output-directory (make-parameter #f))
(define captures (box '()))
(define test-custodian (make-custodian))
(define uncaught (box #f))
(define space
  (parameterize ([current-custodian test-custodian]
                 [error-display-handler
                  (lambda (message e) (unless (unbox uncaught) (set-box! uncaught (cons message e))))])
    (gui:make-eventspace)))
(define (expected)
  (resolve-render-canvas-policy (car (request)) (cadr (request)) (caddr (request)) #f #f))
(define (gpu-mode?) (eq? (hash-ref (expected) 'renderer) 'gpu))
(define (on-handler thunk)
  (define opts (request))
  (define directory (output-directory))
  (define ch (make-channel))
  (parameterize ([gui:current-eventspace space])
    (gui:queue-callback
     (lambda ()
       (define result
         (with-handlers ([(lambda (_) #t) (lambda (e) (cons 'exception e))])
           (define previous (unbox uncaught)) (set-box! uncaught #f)
           (when previous (raise (cdr previous)))
           (cons 'values
             (parameterize ([request opts] [output-directory directory]
                            [current-check-around (lambda (check) (check))])
               (call-with-values thunk list)))))
       (channel-put ch result)) #f))
  (define result (sync/timeout 30 ch))
  (unless result (error 'render-canvas-gui "eventspace did not respond"))
  (if (eq? (car result) 'exception) (raise (cdr result)) (apply values (cdr result))))
(struct window (frame canvas ready errors seen) #:transparent)
(define (make-window [paint void])
  (on-handler
   (lambda ()
     (define opts (request)) (define directory (output-directory))
     (define f (new gui:frame% [label "Unified render canvas acceptance"] [width 420] [height 340]))
     (define ready (make-semaphore 0)) (define errors (box '())) (define seen (box '()))
     (define c
       (make-skia-render-canvas f #:renderer (car (request)) #:backend (cadr (request))
         #:adapter (caddr (request)) #:min-width 320 #:min-height 240
         #:on-error (lambda (e) (set-box! errors (cons e (unbox errors))) (semaphore-post ready))
         #:paint-callback
         (lambda (canvas dc)
           (set-box! seen (cons dc (unbox seen)))
           (dynamic-wind void
             (lambda ()
               (parameterize ([request opts] [output-directory directory]
                              [current-check-around (lambda (check) (check))])
                 (paint canvas dc)))
             (lambda () (semaphore-post ready))))))
     (send f show #t)
     (window f c ready errors seen))))
(define (check-errors w)
  (on-handler (lambda ()
    (unless (null? (unbox (window-errors w))) (raise (last (unbox (window-errors w))))))))
(define (await-paint w)
  (unless (sync/timeout 30 (window-ready w)) (error 'render-canvas-gui "shown window produced no callback"))
  (on-handler void) (check-errors w))
(define (close-window w)
  (on-handler (lambda () (send (window-canvas w) close) (send (window-frame w) show #f))))
(define (with-window proc #:paint [paint void])
  (define w (make-window paint))
  (dynamic-wind void (lambda () (await-paint w) (proc w) (check-errors w)) (lambda () (close-window w))))
(define (reset-dc dc)
  (send dc set-transformation '#(#(1 0 0 1 0 0) 0 0 1 1 0))
  (send dc set-clipping-region #f) (send dc set-alpha 1)
  (send dc set-background "white") (send dc clear))
(define (fill dc color x y w h)
  (send dc set-pen "black" 1 'transparent) (send dc set-brush color 'solid)
  (send dc draw-rectangle x y w h))
(define (pixel data width x y)
  (define p (* 4 (+ x (* width y)))) (bytes->list (subbytes data p (+ p 4))))
(define (extent dc label)
  (define-values (w h) (send dc get-size))
  (define-values (pw ph) (send dc get-pixel-size))
  (hasheq 'name label 'logical_width w 'logical_height h 'pixel_width pw 'pixel_height ph))
(define (kinds entries) (map (lambda (v) (hash-ref v 'kind)) entries))
(define (readback-count entries) (count (lambda (e) (equal? (hash-ref e 'kind) "readback")) entries))
(define (check-after dc)
  (if (gpu-mode?)
      (begin (check-false (send dc ok?))
             (check-exn exn:fail? (lambda () (send dc get-rgba-bytes))))
      (check-true (send dc ok?))))

(define render-canvas-gui-tests
  (test-suite
   "Unified callback API on real raster and GPU canvas% objects"
   (test-case "checks on the handler thread propagate"
     (check-exn exn:test:check? (lambda () (on-handler (lambda () (check-equal? 1 2))))))
   (test-case "factory returns canvas% implementing the common interface"
     (with-window (lambda (w) (on-handler (lambda ()
       (define c (window-canvas w))
       (check-true (is-a? c gui:canvas%)) (check-true (skia-render-canvas? c))
       (check-eq? (send c get-renderer) (hash-ref (expected) 'renderer))
       (check-eq? (send c get-backend) (hash-ref (expected) 'backend)))))))
   (test-case "callback get-dc is exact and outside-callback access rejects"
     (with-window (lambda (w) (on-handler (lambda ()
       (check-exn #rx"only during" (lambda () (send (window-canvas w) get-dc)))
       (for ([dc (in-list (unbox (window-seen w)))]) (check-after dc)))))
       #:paint (lambda (c dc)
         (check-true (is-a? dc rd:dc<%>)) (check-eq? dc (send c get-dc))
         (check-true (send dc ok?)) (check-equal? (skia-gpu-dc? dc) (gpu-mode?)))))
   (test-case "refresh-now invokes its one-shot callback exactly once"
     (with-window (lambda (w) (on-handler (lambda ()
       (define c (window-canvas w)) (define calls 0) (define saved #f)
       (send c refresh-now (lambda (dc) (set! calls (add1 calls)) (set! saved dc)))
       (check-equal? calls 1) (check-after saved)
       (send c refresh-now (lambda (dc) (check-equal? (eq? dc saved) (not (gpu-mode?))))))))))
   (test-case "callback replacement is explicit and one-shot does not replace it"
     (with-window (lambda (w) (on-handler (lambda ()
       (define c (window-canvas w)) (define seen '())
       (send c set-paint-callback (lambda (_c _d) (set! seen (cons 'regular seen))))
       (check-equal? seen '())
       (send c refresh-now (lambda (_d) (set! seen (cons 'one-shot seen))))
       (send c refresh-now)
       (check-equal? (reverse seen) '(one-shot regular)))))))
   (test-case "nested render, close, present and callback replacement reject"
     (with-window (lambda (w) (on-handler (lambda ()
       (define c (window-canvas w))
       (send c refresh-now (lambda (_dc)
         (for ([thunk (list (lambda () (send c refresh-now)) (lambda () (send c close))
                            (lambda () (send c present)) (lambda () (send c set-paint-callback void)))])
           (check-exn #rx"paint callback" thunk))
         (when (gpu-mode?) (check-exn #rx"paint callback" (lambda () (send c close-gpu))))
         (send c refresh))))))))
   (test-case "synchronous callback errors propagate, unwind and recover"
     (with-window (lambda (w) (on-handler (lambda ()
       (define c (window-canvas w)) (define saved #f)
       (check-exn #rx"intentional-render-error"
         (lambda () (send c refresh-now (lambda (dc)
           (set! saved dc) (send dc start-alpha 0.5) (error 'test "intentional-render-error")))))
       (check-after saved)
       (check-false (hash-ref (hash-ref (send c get-render-info) 'callback) 'painting))
       (check-exn #rx"only during" (lambda () (send c get-dc)))
       (send c refresh-now (lambda (dc) (reset-dc dc) (fill dc "blue" 2 3 10 10)))
       (check-equal? (unbox (window-errors w)) '()))))))
   (test-case "continuation escape does not leave a live callback scope"
     (with-window (lambda (w) (on-handler (lambda ()
       (define c (window-canvas w))
       (check-eq? (let/ec out (send c refresh-now (lambda (_dc) (out 'escaped)))) 'escaped)
       (check-false (hash-ref (hash-ref (send c get-render-info) 'callback) 'painting))
       (send c refresh-now))))))
   (test-case "wrong-thread public operations are rejected"
     (with-window (lambda (w)
       (define c (window-canvas w))
       ;; This test thread is intentionally not the eventspace handler.
       (for ([thunk (list (lambda () (send c get-renderer)) (lambda () (send c get-backend))
                          (lambda () (send c get-render-info)) (lambda () (send c get-dc))
                          (lambda () (send c get-raster-dc)) (lambda () (send c refresh))
                          (lambda () (send c close)))])
         (check-exn #rx"handler thread" thunk)))))
   (test-case "persistent raster access is explicit and never downloads a GPU"
     (with-window (lambda (w) (on-handler (lambda ()
       (define c (window-canvas w)) (define ledger (box '()))
       (parameterize ([current-gpu-io-ledger ledger])
         (if (gpu-mode?)
             (begin (check-exn #rx"unavailable" (lambda () (send c get-raster-dc)))
                    (check-exn #rx"raster-only" (lambda () (send c present))))
             (let ([dc (send c get-raster-dc)])
               (check-eq? dc (send c get-raster-dc))
               (fill dc "red" 2 3 10 10) (send c present))))
       (check-equal? (readback-count (unbox ledger)) 0))))))
   (test-case "logical coordinates sample actual physical backing extents"
     (with-window (lambda (w) (on-handler (lambda ()
       (send (window-canvas w) refresh-now (lambda (dc)
         (reset-dc dc) (fill dc "blue" 2 3 10 8)
         (define e (extent dc "pixels"))
         (define pw (hash-ref e 'pixel_width)) (define ph (hash-ref e 'pixel_height))
         (define x (inexact->exact (floor (* 6 (/ pw (hash-ref e 'logical_width))))))
         (define y (inexact->exact (floor (* 7 (/ ph (hash-ref e 'logical_height))))))
         (define data (send dc get-rgba-bytes #:premultiplied? #t))
         (check-equal? (pixel data pw x y) '(0 0 255 255))
         (check-equal? (pixel data pw 0 0) '(255 255 255 255)))))))))
   (test-case "resize is observed without reviving an expired GPU DC"
     (with-window (lambda (w)
       (define previous (on-handler (lambda () (car (unbox (window-seen w))))))
       (define old (on-handler (lambda ()
         (call-with-values (lambda () (send (window-canvas w) get-client-size)) list))))
       (on-handler (lambda () (send (window-frame w) resize 600 460)))
       ;; A later handler turn lets the native layout event run before reading.
       (on-handler void)
       (on-handler (lambda ()
         (send (window-canvas w) refresh-now (lambda (dc)
           (define-values (w h) (send dc get-size))
           (check-true (> w (car old))) (check-true (> h (cadr old)))
           (when (gpu-mode?) (check-false (send previous ok?))))))))))
   (test-case "paint callback supports zero and multiple return values"
     (with-window (lambda (w) (on-handler (lambda ()
       (send (window-canvas w) refresh-now (lambda (_dc) (values)))
       (send (window-canvas w) refresh-now (lambda (_dc) (values 1 2 3))))))))
   (test-case "portable refresh-now rejects nonpresenting and invalid callbacks"
     (with-window (lambda (w) (on-handler (lambda ()
       (define c (window-canvas w))
       (check-exn exn:fail? (lambda () (send c refresh-now #f #:flush? #f)))
       (check-exn exn:fail? (lambda () (send c refresh-now (lambda (x y) (void)))))
       (check-exn exn:fail? (lambda () (send c set-paint-callback 42)))
       (send c refresh-now))))))
   (test-case "invalid factory options leave the parent's children unchanged"
     (on-handler (lambda ()
       (define f (new gui:frame% [label "Invalid selection test"]))
       (define before (send f get-children))
       (check-exn exn:fail? (lambda () (make-skia-render-canvas f #:renderer 'raster #:backend 'opengl)))
       (check-exn exn:fail? (lambda () (make-skia-render-canvas f #:paint-callback 42)))
       (check-exn exn:fail? (lambda () (make-skia-render-canvas f #:min-width -1)))
       (check-equal? (send f get-children) before))))
   (test-case "capabilities and selection records are detached and immutable"
     (with-window (lambda (w) (on-handler (lambda ()
       (define c (window-canvas w))
       (define info (send c get-render-info))
       (define caps (send c get-render-capabilities))
       (check-true (immutable? info)) (check-true (immutable? caps))
       (check-equal? (hash-ref caps 'persistent_dc) (not (gpu-mode?)))
       (check-equal? (hash-ref (hash-ref info 'selection) 'requested_renderer) (car (request)))
       (check-false (hash-ref (hash-ref info 'selection) 'runtime_fallback))
       (check-false (hash-ref info 'physical_display_verified)))))))
   (test-case "consumer frames have no implicit GPU readback and retain captures"
     (with-window (lambda (w)
       (define workloads (on-handler make-consumer-workloads))
       (for ([size (in-list '(("small" 420 340) ("large" 600 460)))])
         (on-handler (lambda () (send (window-frame w) resize (cadr size) (caddr size))))
         (on-handler void)
         (for ([workload (in-list workloads)])
           (on-handler (lambda ()
             (define c (window-canvas w)) (define normal-dc #f)
             (define normal-io (box '())) (define capture-io (box '()))
             (parameterize ([current-gpu-io-ledger normal-io])
               (send c refresh-now (lambda (dc)
                 (set! normal-dc dc) (reset-dc dc) (exercise-consumer! workload dc))))
             (check-equal? (readback-count (unbox normal-io)) 0)
             (when (gpu-mode?) (check-not-false (member "present-request" (kinds (unbox normal-io)))))
             (check-after normal-dc)
             (define e #f) (define pixels #f) (define layout #f)
             (send c refresh-now (lambda (dc)
               (reset-dc dc)
               (set! e (extent dc (car size)))
               (set! layout (exercise-consumer! workload dc))
               (set! pixels (parameterize ([current-gpu-io-ledger capture-io])
                              (send dc get-rgba-bytes #:premultiplied? #t)))))
             (check-equal? (readback-count (unbox capture-io)) (if (gpu-mode?) 1 0))
             (define id (format "~a-~a-~a" (consumer-workload-scene workload) (consumer-workload-mode workload) (car size)))
             (define file (string-append id ".rgba"))
             (when (output-directory)
               (call-with-output-file (build-path (output-directory) file)
                 (lambda (out) (write-bytes pixels out)) #:exists 'error #:mode 'binary))
             (set-box! captures
               (cons (hasheq 'id id 'scene (consumer-workload-scene workload) 'mode (consumer-workload-mode workload)
                             'extent e 'layout layout 'file file
                             'draw_io (reverse (unbox normal-io)) 'capture_io (reverse (unbox capture-io)))
                     (unbox captures))))))))))
   (test-case "close is idempotent and does not masquerade as a usable renderer"
     (with-window (lambda (w) (on-handler (lambda ()
       (define c (window-canvas w))
       (send c close) (send c close-skia)
       (check-true (send c closed?))
       (check-eq? (hash-ref (send c get-render-info) 'close_status) 'closed)
       (check-not-exn (lambda () (send c refresh)))
       (check-exn #rx"closed" (lambda () (send c refresh-now)))
       (check-exn #rx"closed" (lambda () (send c get-raster-dc)))
       (check-eq? (send c get-backend) (hash-ref (expected) 'backend)))))))
   (test-case "scheduled paint check failures reach on-error and the test process"
     (define w (make-window (lambda (_c _dc) (check-equal? 1 2))))
     (dynamic-wind void
       (lambda () (check-exn exn:test:check? (lambda () (await-paint w))))
       (lambda () (close-window w))))
   (test-case "window convenience class uses the same factory and closes its canvas"
     (define ready (make-semaphore 0)) (define errors (box '()))
     (define frame
       (on-handler (lambda ()
         (define f
           (new skia-render-window% [label "Unified window acceptance"]
                [renderer (car (request))] [backend (cadr (request))] [adapter (caddr (request))]
                [on-error (lambda (e) (set-box! errors (cons e (unbox errors))) (semaphore-post ready))]
                [paint-callback (lambda (_c _dc) (semaphore-post ready))]))
         (send f show #t) f)))
     (dynamic-wind void
       (lambda ()
         (check-not-false (sync/timeout 30 ready))
         (on-handler (lambda ()
           (unless (null? (unbox errors)) (raise (car (unbox errors))))
           (define c (send frame get-render-canvas))
           (check-true (skia-render-canvas? c))
           (check-eq? (send c get-renderer) (hash-ref (expected) 'renderer))
           (send frame close-render) (send frame close-render)
           (check-true (send c closed?)))))
       (lambda () (on-handler (lambda () (send frame close-render))))))
))
(define render-canvas-gui-test-count 20)
(define (json-value value)
  (cond [(symbol? value) (symbol->string value)]
        [(hash? value) (for/hasheq ([(k v) (in-hash value)]) (values k (json-value v)))]
        [(list? value) (map json-value value)]
        [(vector? value) (map json-value (vector->list value))]
        [else value]))
(module+ main
  (require rackunit/text-ui)
  (define renderer 'raster) (define backend 'auto) (define adapter #f)
  (define directory #f) (define token "manual")
  (command-line #:once-each
    [("--renderer") v "raster, gpu or auto" (set! renderer (string->symbol v))]
    [("--backend") v "auto, opengl, metal or direct3d" (set! backend (string->symbol v))]
    [("--adapter") v "hardware or warp (Direct3D)" (set! adapter (string->symbol v))]
    [("--directory") v "New evidence directory" (set! directory v)]
    [("--run-token") v "Validator identity" (set! token v)]
    #:args () (void))
  (when directory (make-directory directory))
  (define failures
    (parameterize ([request (list renderer backend adapter)] [output-directory directory])
      (dynamic-wind void (lambda () (run-tests render-canvas-gui-tests))
        (lambda () (custodian-shutdown-all test-custodian)))))
  (when directory
    (call-with-output-file (build-path directory "result.json")
      (lambda (out)
        (write-json
         (json-value
          (hasheq 'schema 1 'stage "0.61" 'status (if (zero? failures) "passed" "failed")
                  'run_token token 'requested_renderer renderer
                  'selection (resolve-render-canvas-policy renderer backend adapter #f #f)
                  'cases render-canvas-gui-test-count 'failures failures 'physical_display_verified #f
                  'identity (hasheq 'version (version) 'os (system-type 'os)
                                    'architecture (system-type 'arch) 'vm (system-type 'vm))
                  'captures (reverse (unbox captures)))) out)) #:exists 'error))
  (printf "render-canvas-gui: ~a cases, ~a failures; real shown windows and consumer captures.\n"
          render-canvas-gui-test-count failures)
  (exit (if (zero? failures) 0 1)))
