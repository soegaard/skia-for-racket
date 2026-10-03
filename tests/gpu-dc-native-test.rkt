#lang racket/base
;; Explicit native gate: a missing backend is a failure, never a skipped pass.
(require rackunit racket/class racket/list racket/cmdline
         (prefix-in rd: racket/draw) (prefix-in sk: "../main.rkt")
         (prefix-in gpu: "../gpu.rkt") "../gpu-egl.rkt" "../gpu-dc.rkt"
         (submod "../private/gpu-presenter.rkt" adapter-internals)
         "../private/gpu-io-trace.rkt")
(provide gpu-dc-native-tests gpu-dc-native-test-count)
(define backend (make-parameter 'auto))
(define adapter (make-parameter 'hardware))
(define (selected-backend)
  (if (eq? (backend) 'auto)
      (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])
      (backend)))
(define (with-context proc)
  (define ctx
    (case (selected-backend)
      [(egl) (make-egl-gpu-context)]
      [(metal) (gpu:make-gpu-context #:backend 'metal)]
      [(direct3d) (gpu:make-gpu-context #:backend 'direct3d #:adapter (adapter))]
      [else (error 'gpu-dc-native "unsupported test backend")]))
  (dynamic-wind void
    (lambda () (gpu:call-with-gpu-context ctx (lambda () (proc ctx))))
    (lambda () (gpu:gpu-context-close! ctx))))
(define (with-surface proc [w 64] [h 48])
  (with-context (lambda (ctx)
    (sk:with-skia ([s (gpu:make-gpu-surface ctx w h)]) (proc ctx s)))))
(define (fill dc color [x 0] [y 0] [w 8] [h 6])
  (send dc set-pen "black" 1 'transparent) (send dc set-brush color 'solid)
  (send dc draw-rectangle x y w h))
(define (pixel bytes width x y)
  (define p (* 4 (+ x (* width y)))) (bytes->list (subbytes bytes p (+ p 4))))
(define (read-pixel s x y)
  (pixel (gpu:gpu-surface->rgba-bytes s #:premultiplied? #t) (sk:surface-width s) x y))
(define (opaque-color? actual rgb)
  (and (for/and ([a (in-list (take actual 3))] [b (in-list rgb)]) (<= (abs (- a b)) 1))
       (= (last actual) 255)))
;; Actual Ganesh target with the existing presenter state machine. The adapter
;; substitutes only window acquisition/presentation, NOT drawing or GPU storage.
(define (with-presenter proc)
  (define ctx
    (case (selected-backend)
      [(egl) (make-egl-gpu-context)]
      [(metal) (gpu:make-gpu-context #:backend 'metal)]
      [(direct3d) (gpu:make-gpu-context #:backend 'direct3d #:adapter (adapter))]))
  (define surface #f) (define presenter #f) (define presents 0) (define saved-frame #f)
  (define metrics (presentation-metrics 64 48 32 16))
  (dynamic-wind
   void
   (lambda ()
     (set! surface (gpu:call-with-gpu-context ctx (lambda () (gpu:make-gpu-surface ctx 64 48))))
     (define raw-backend (gpu:gpu-context-backend ctx))
     (define ad
       (presentation-adapter raw-backend ctx (lambda () metrics)
         (lambda (_m receive)
           (gpu:call-with-gpu-context ctx
             (lambda ()
               (receive (sk:surface-canvas surface)
                        (hasheq 'backend (symbol->string raw-backend) 'target_identity "test-target")
                        (lambda () (gpu:gpu-flush-and-submit! ctx) (set! presents (add1 presents)))))))
         (lambda (_callback) (void)) ; synchronous tests never dispatch a queue
         (lambda () (void))
         (lambda () (hasheq 'fixture "native GPU offscreen target; no GUI or screen certification"))))
     (set! presenter (make-presenter ad void raise))
     (proc ctx surface presenter (lambda () presents)
       (lambda (paint)
         (gpu:gpu-presenter-set-render! presenter
           (lambda (frame) (set! saved-frame frame) (paint frame)))
         (gpu:gpu-presenter-render! presenter))
       (lambda () saved-frame)))
   (lambda ()
     (when presenter (gpu:gpu-presenter-close! presenter))
     (when surface (sk:skia-close! surface))
     (gpu:gpu-context-close! ctx))))
(define gpu-dc-native-tests
  (test-suite
   "Native Ganesh GPU DC: coordinates, residency, transfer and frame lifetime"
   (test-case "borrowed surface is really GPU-backed and stays live after DC expiration"
     (with-surface (lambda (_ctx s)
       (check-true (gpu:gpu-surface? s)) (define saved #f)
       (call-with-gpu-surface-dc s (lambda (dc) (set! saved dc) (fill dc "red")))
       (check-false (send saved ok?))
       (check-equal? (read-pixel s 3 3) '(255 0 0 255))
       (check-true (hash? (gpu:gpu-surface-info s))))))
   (test-case "Retina and asymmetric dimensions sample logical points in physical coordinates"
     (for ([description (in-list '((64 48 64 48) (64 48 32 24) (64 48 32 16) (65 49 32.5 24.5)))])
       (define pw (list-ref description 0)) (define ph (list-ref description 1))
       (define lw (list-ref description 2)) (define lh (list-ref description 3))
       (with-surface (lambda (_ctx s)
         (call-with-gpu-surface-dc s
           (lambda (dc)
             (fill dc "red" 0 0 lw lh)
             (fill dc "blue" 2 3 5 4)
             (check-equal? (call-with-values (lambda () (send dc get-pixel-size)) list) (list pw ph)))
           #:logical-width lw #:logical-height lh)
         (check-equal? (read-pixel s 0 0) '(255 0 0 255))
         (check-equal? (read-pixel s (inexact->exact (floor (* (/ pw lw) 4)))
                                      (inexact->exact (floor (* (/ ph lh) 5)))) '(0 0 255 255))) pw ph)))
   (test-case "logical clipping and transformed geometry use the same device mapping"
     (with-surface (lambda (_ctx s)
       (call-with-gpu-surface-dc s
         (lambda (dc)
           (send dc set-background "white") (send dc clear)
           (send dc set-clipping-rect 3 2 4 4)
           (send dc set-origin 1 1) (fill dc "blue" 0 0 12 10))
         #:logical-width 32 #:logical-height 16)
       (check-equal? (read-pixel s 8 9) '(0 0 255 255))
       (check-equal? (read-pixel s 2 3) '(255 255 255 255)))))
   (test-case "completed alpha groups composite GPU pixels without applying device scale twice"
     (with-surface (lambda (_ctx s)
       (call-with-gpu-surface-dc s
         (lambda (dc)
           (send dc set-background "white") (send dc clear)
           (send dc start-alpha 0.5) (fill dc "red" 2 2 8 6) (send dc end-alpha))
         #:logical-width 32 #:logical-height 16)
       (check-true (opaque-color? (read-pixel s 10 12) '(255 127 127)))
       (check-equal? (read-pixel s 2 2) '(255 255 255 255)))))
   (test-case "unfinished alpha groups are discarded without merging"
     (with-surface (lambda (_ctx s)
       (call-with-gpu-surface-dc s
         (lambda (dc) (fill dc "blue") (send dc start-alpha 0.5) (fill dc "red")))
       (check-equal? (read-pixel s 3 3) '(0 0 255 255)))))
   (test-case "overlapping copy uses a GPU snapshot rather than a CPU readback"
     (with-surface (lambda (_ctx s)
       (define ledger (box '()))
       (parameterize ([current-gpu-io-ledger ledger])
         (call-with-gpu-surface-dc s
           (lambda (dc) (fill dc "red" 0 0 6 6) (fill dc "blue" 6 0 6 6)
             (send dc copy 0 0 12 6 2 0))))
       (check-equal? (read-pixel s 3 3) '(255 0 0 255))
       (check-equal? (read-pixel s 9 3) '(0 0 255 255))
       (check-true (ormap (lambda (e) (equal? (hash-ref e 'kind) "gpu-snapshot")) (unbox ledger)))
       (check-false (ormap (lambda (e) (equal? (hash-ref e 'kind) "readback")) (unbox ledger))))))
   (test-case "public bitmap pixels draw onto GPU storage"
     (with-surface (lambda (_ctx s)
       (define bm (make-object rd:bitmap% 2 2 #f #t))
       (send bm set-argb-pixels 0 0 2 2 (bytes 255 0 255 0 255 0 255 0 255 0 255 0 255 0 255 0))
       (call-with-gpu-surface-dc s (lambda (dc) (send dc draw-bitmap bm 2 2))
         #:logical-width 32 #:logical-height 24)
       (check-equal? (read-pixel s 5 5) '(0 255 0 255)))))
   (test-case "HarfBuzz text measures logically and renders to GPU pixels"
     (with-surface (lambda (_ctx s)
       (call-with-gpu-surface-dc s (lambda (dc)
         (send dc set-background "white") (send dc clear)
         (send dc set-font (rd:make-font #:size 12 #:family 'swiss))
         (define-values (w h _d _l) (send dc get-text-extent "Skia" #f #t))
         (check-true (> w 0)) (check-true (> h 0))
         (send dc set-text-foreground "black") (send dc draw-text "Skia" 2 2 #t)))
       (define pixels (gpu:gpu-surface->rgba-bytes s))
       (check-true (for/or ([i (in-range 0 (bytes-length pixels) 4)]) (< (bytes-ref pixels i) 200))))))
   (test-case "CPU snapshot explicitly detaches and survives GPU context closure"
     (define image #f)
     (with-surface (lambda (_ctx s)
       (call-with-gpu-surface-dc s (lambda (dc) (fill dc "red") (set! image (send dc snapshot))))))
     (dynamic-wind void
       (lambda () (check-false (gpu:gpu-image? image))
         (check-equal? (pixel (sk:image->rgba-bytes image) 64 3 3) '(255 0 0 255)))
       (lambda () (when image (sk:skia-close! image)))))
   (test-case "PNG and RGBA exports are explicit transfers of the root"
     (with-surface (lambda (_ctx s)
       (define ledger (box '()))
       (parameterize ([current-gpu-io-ledger ledger])
         (call-with-gpu-surface-dc s (lambda (dc)
           (fill dc "blue")
           (check-equal? (pixel (send dc get-rgba-bytes) 64 3 3) '(0 0 255 255))
           (check-equal? (subbytes (send dc get-png-bytes) 0 8) #"\211PNG\r\n\032\n"))))
       (check-true (>= (count (lambda (e) (equal? (hash-ref e 'kind) "readback")) (unbox ledger)) 2)))))
   (test-case "CPU targets are rejected instead of becoming an implicit fallback"
     (sk:with-skia ([s (sk:make-surface 8 8)])
       (check-exn exn:fail? (lambda () (call-with-gpu-surface-dc s void)))))
   (test-case "borrowed GPU root requires its active owner and a balanced native stack"
     (with-surface (lambda (_ctx s)
       (sk:call-with-canvas-state (sk:surface-canvas s)
         (lambda () (check-exn #rx"balanced" (lambda () (call-with-gpu-surface-dc s void)))))))
     (define saved #f)
     (with-context (lambda (ctx) (set! saved (gpu:make-gpu-surface ctx 8 8)) (sk:skia-close! saved)))
     (check-exn exn:fail? (lambda () (call-with-gpu-surface-dc saved void))))
   (test-case "presenter commits a GPU-to-GPU frame with no automatic readback"
     (with-presenter (lambda (ctx surface _p presents render frame)
       (define saved #f) (define ledger (box '()))
       (parameterize ([current-gpu-io-ledger ledger])
         (check-eq? (render (lambda (f)
           (call-with-gpu-frame-dc f (lambda (dc) (set! saved dc) (fill dc "blue" 2 3 5 4)))))
           'present-requested))
       (check-equal? (presents) 1)
       (check-false (send saved ok?)) (check-true (gpu:gpu-frame-expired? (frame)))
       (check-exn exn:fail? (lambda () (call-with-gpu-frame-dc (frame) void)))
       (check-false (ormap (lambda (e) (equal? (hash-ref e 'kind) "readback")) (unbox ledger)))
       (gpu:call-with-gpu-context ctx
         (lambda () (check-equal? (read-pixel surface 8 15) '(0 0 255 255))
                    (check-equal? (read-pixel surface 0 0) '(255 255 255 255)))))))
   (test-case "failed callback cancels presentation and the next frame recovers"
     (with-presenter (lambda (_ctx _surface _p presents render _frame)
       (define saved #f)
       (check-exn #rx"deliberate frame failure"
         (lambda () (render (lambda (f)
           (call-with-gpu-frame-dc f (lambda (dc)
             (set! saved dc) (send dc start-alpha 0.5) (error 'probe "deliberate frame failure")))))))
       (check-false (send saved ok?)) (check-equal? (presents) 0)
       (check-eq? (render (lambda (f) (call-with-gpu-frame-dc f (lambda (dc) (fill dc "red")))))
                  'present-requested)
       (check-equal? (presents) 1))))
   (test-case "close requested inside a frame cancels presentation after DC cleanup"
     (with-presenter (lambda (_ctx _surface p presents render _frame)
       (define saved #f)
       (render (lambda (f) (call-with-gpu-frame-dc f
         (lambda (dc) (set! saved dc) (fill dc "red") (gpu:gpu-presenter-close! p)))))
       (check-equal? (presents) 0) (check-false (send saved ok?))
       (check-eq? (gpu:gpu-presenter-state p) 'closed))))))
(define gpu-dc-native-test-count 15)
(module+ main
  (require rackunit/text-ui)
  (command-line #:once-each
    [("--backend") value "auto, egl, metal or direct3d" (backend (string->symbol value))]
    [("--adapter") value "hardware or warp (Direct3D)" (adapter (string->symbol value))]
    #:args () (void))
  (printf "gpu-dc-native backend: ~a\n" (selected-backend))
  (define failures (run-tests gpu-dc-native-tests))
  (printf "gpu-dc-native: ~a cases, ~a failures; native GPU targets and presenter lifecycle, no GUI.\n"
          gpu-dc-native-test-count failures)
  (exit (if (zero? failures) 0 1)))
