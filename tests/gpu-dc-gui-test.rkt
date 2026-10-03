#lang racket/base
;; Separate, required-when-selected GUI/GPU test process. Display/context
;; initialization failure is fatal; there is no skip or CPU rendering fallback.
(require rackunit racket/class racket/list racket/cmdline
         (prefix-in gui: racket/gui/base) (prefix-in rd: racket/draw)
         "../gpu-canvas.rkt" "../gpu-dc.rkt")
(provide gpu-dc-gui-tests gpu-dc-gui-test-count)
(define backend (make-parameter 'auto))
(define adapter (make-parameter #f))
(define test-custodian (make-custodian))
(define uncaught (box #f))
(define space
  (parameterize ([current-custodian test-custodian]
                 [error-display-handler
                  (lambda (message exception)
                    (unless (unbox uncaught) (set-box! uncaught (cons message exception))))])
    (gui:make-eventspace)))
(define (on-handler thunk)
  (define requested-backend (backend))
  (define requested-adapter (adapter))
  (define ch (make-channel))
  (parameterize ([gui:current-eventspace space])
    (gui:queue-callback
     (lambda ()
       (define result
         (with-handlers ([(lambda (_) #t) (lambda (e) (cons 'exception e))])
           (define previous (unbox uncaught)) (set-box! uncaught #f)
           (when previous
             (if (exn? (cdr previous)) (raise (cdr previous))
                 (error 'gpu-dc-gui "uncaught eventspace error: ~a" (car previous))))
           (cons 'values
             (parameterize ([current-check-around (lambda (check) (check))]
                            [backend requested-backend] [adapter requested-adapter])
               (call-with-values thunk list)))))
       (channel-put ch result)) #f))
  (define result (sync/timeout 20 ch))
  (unless result (error 'gpu-dc-gui "eventspace did not respond within 20 seconds"))
  (if (eq? (car result) 'exception) (raise (cdr result)) (apply values (cdr result))))
(struct window (frame canvas paints dcs ready errors) #:transparent)
(define (make-window paint)
  (on-handler
   (lambda ()
     (define f (new gui:frame% [label "Required Skia GPU DC tests"] [width 260] [height 180]))
     (define paints (box 0)) (define dcs (box '())) (define ready (make-semaphore 0))
     (define errors (box '()))
     (define c
       (new skia-gpu-canvas% [parent f] [backend (backend)] [adapter (adapter)]
            [min-width 40] [min-height 30]
            [on-error (lambda (e) (set-box! errors (cons e (unbox errors))) (semaphore-post ready))]
            [paint-callback
             (lambda (canvas dc)
               (set-box! paints (add1 (unbox paints)))
               (set-box! dcs (cons dc (unbox dcs)))
               (dynamic-wind void
                 (lambda ()
                   (parameterize ([current-check-around (lambda (check) (check))]) (paint canvas dc)))
                 (lambda () (semaphore-post ready))))]))
     (send f show #t)
     (window f c paints dcs ready errors))))
(define (check-errors w)
  (on-handler (lambda ()
    (unless (null? (unbox (window-errors w))) (raise (last (unbox (window-errors w))))))))
(define (await-paint w)
  (unless (sync/timeout 20 (window-ready w))
    (error 'gpu-dc-gui "shown GPU window produced no frame within 20 seconds"))
  (on-handler void) (check-errors w))
(define (drain w) (let loop () (when (sync/timeout 0 (window-ready w)) (loop))))
(define (with-window proc #:paint [paint (lambda (_c _dc) (void))])
  (define w (make-window paint))
  (dynamic-wind void
    (lambda () (await-paint w) (proc w) (on-handler void) (check-errors w))
    (lambda ()
      (on-handler (lambda () (send (window-canvas w) close-skia) (send (window-frame w) show #f))))))
(define (fill dc color)
  (send dc set-pen "black" 1 'transparent) (send dc set-brush color 'solid)
  (send dc draw-rectangle 2 3 10 8))
(define gpu-dc-gui-tests
  (test-suite
   "Real-window GPU DC facade and eventspace lifetime"
   (test-case "GUI check failures propagate to the test process"
     (check-exn exn:test:check? (lambda () (on-handler (lambda () (check-equal? 1 2)))))
     (check-exn exn:test:check?
       (lambda () (with-window void #:paint (lambda (_c _dc) (check-equal? 1 2))))))
   (test-case "paint callback gets an actual DC and widget get-dc is scoped"
     (with-window
       (lambda (w)
         (on-handler (lambda ()
           (check-true (skia-gpu-canvas? (window-canvas w)))
           (check-exn #rx"only during" (lambda () (send (window-canvas w) get-dc)))
           (for ([dc (in-list (unbox (window-dcs w)))]) (check-false (send dc ok?))))))
       #:paint (lambda (c dc)
         (check-true (skia-gpu-dc? dc)) (check-true (is-a? dc rd:dc<%>))
         (check-eq? dc (send c get-dc)) (check-true (send dc ok?)))))
   (test-case "synchronous callback has a fresh DC that expires before refresh-now returns"
     (with-window (lambda (w)
       (on-handler (lambda ()
         (define c (window-canvas w)) (define saved #f) (define calls 0)
         (send c refresh-now (lambda (dc) (set! saved dc) (set! calls (add1 calls)) (fill dc "blue")))
         (check-equal? calls 1) (check-false (send saved ok?))
         (send c refresh-now (lambda (dc)
           (check-false (eq? dc saved)) (check-false (send saved ok?)))))))))
   (test-case "DPR checks use actual physical extents, independently in X and Y"
     (with-window void #:paint (lambda (_c dc)
       (define-values (w h) (send dc get-size))
       (define-values (pw ph) (send dc get-pixel-size))
       (define-values (sx sy) (send dc get-device-scale))
       (check-= (* w sx) pw 1e-6) (check-= (* h sy) ph 1e-6)
       (fill dc "blue")
       ;; Explicit transfer for the oracle, not part of ordinary presentation.
       (define pixels (send dc get-rgba-bytes #:premultiplied? #t))
       (define x (inexact->exact (floor (* 5 sx))))
       (define y (inexact->exact (floor (* 6 sy))))
       (define p (* 4 (+ x (* pw y))))
       (check-equal? (bytes->list (subbytes pixels p (+ p 4))) '(0 0 255 255)))))
   (test-case "refresh requests another frame without permitting persistent GPU access"
     (with-window (lambda (w)
       (on-handler (lambda () (drain w) (send (window-canvas w) refresh)))
       (await-paint w)
       (on-handler (lambda () (check-true (> (unbox (window-paints w)) 1)))))))
   (test-case "resize repaints and old frame DCs stay expired"
     (with-window (lambda (w)
       (define previous (on-handler (lambda () (car (unbox (window-dcs w))))))
       (on-handler (lambda () (drain w) (send (window-frame w) resize 340 230)))
       (await-paint w)
       (on-handler (lambda () (check-false (send previous ok?))
         (send (window-canvas w) refresh-now (lambda (dc)
           (define-values (width height) (send dc get-size))
           (check-true (> width 260)) (check-true (> height 180)))))))))
   (test-case "nested synchronous rendering is rejected but queued refresh is permitted"
     (with-window (lambda (w)
       (on-handler (lambda ()
         (define c (window-canvas w))
         (send c refresh-now (lambda (dc)
           (check-exn #rx"nested" (lambda () (send c refresh-now)))
           (send c refresh) (fill dc "red"))))))))
   (test-case "callback exceptions expire the DC and a later frame recovers"
     (with-window (lambda (w)
       (on-handler (lambda ()
         (define c (window-canvas w)) (define saved #f)
         (check-exn #rx"intentional GPU callback failure"
           (lambda () (send c refresh-now (lambda (dc)
             (set! saved dc) (send dc start-alpha 0.5)
             (error 'test "intentional GPU callback failure")))))
         (check-false (send saved ok?))
         (send c refresh-now (lambda (dc) (fill dc "blue"))))))))
   (test-case "native Skia text and isolated alpha groups render after GUI initialization"
     (with-window void #:paint (lambda (_c dc)
       (send dc set-font (rd:make-font #:family 'swiss #:size 13))
       (define-values (w h _d _l) (send dc get-text-extent "Skia GPU" #f #t))
       (check-true (> w 0)) (check-true (> h 0))
       (send dc draw-text "Skia GPU" 4 4 #t)
       (send dc start-alpha 0.5) (fill dc "red") (send dc end-alpha))))
   (test-case "persistent presentation is explicitly unsupported and close is idempotent"
     (with-window (lambda (w)
       (on-handler (lambda ()
         (define c (window-canvas w))
         (check-exn exn:fail? (lambda () (send c present)))
         (check-exn exn:fail? (lambda () (send c refresh-now #f #:flush? #f)))
         (send c close-skia) (send c close-skia)
         (check-true (send c skia-closed?))
         (check-exn exn:fail? (lambda () (send c refresh-now))))))))))
(define gpu-dc-gui-test-count 10)
(module+ main
  (require rackunit/text-ui)
  (command-line #:once-each
    [("--backend") value "auto, opengl, metal or direct3d" (backend (string->symbol value))]
    [("--adapter") value "hardware or warp (Direct3D)" (adapter (string->symbol value))]
    #:args () (void))
  (define failures
    (dynamic-wind void (lambda () (run-tests gpu-dc-gui-tests))
      (lambda () (custodian-shutdown-all test-custodian))))
  (printf "gpu-dc-gui: ~a cases, ~a failures; real shown GPU windows and eventspace callbacks.\n"
          gpu-dc-gui-test-count failures)
  (exit (if (zero? failures) 0 1)))
