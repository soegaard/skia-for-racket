#lang racket/base
;; This is a REQUIRED-GUI suite when selected. Failure to initialize a display,
;; expose a real window, or dispatch an eventspace callback is a test failure.
;; Keep it out of headless run-tests.rkt and package-wide implicit tests.
(require rackunit racket/class racket/list
         (prefix-in gui: racket/gui/base)
         (prefix-in rd: racket/draw)
         "../canvas.rkt" "../dc.rkt")
(provide canvas-gui-tests canvas-gui-test-count)

(define test-custodian (make-custodian))
(define uncaught-eventspace-error (box #f))
(define test-eventspace
  (parameterize ([current-custodian test-custodian]
                 [error-display-handler
                  (lambda (message exception)
                    ;; GUI's event loop reports uncaught callback exceptions
                    ;; here instead of terminating its handler thread. Keep
                    ;; the original exception/continuation marks for RackUnit.
                    (unless (unbox uncaught-eventspace-error)
                      (set-box! uncaught-eventspace-error (cons message exception))))])
    (gui:make-eventspace)))
(define (call-with-check-exceptions thunk)
  ;; A separately created eventspace does not inherit RackUnit's active test
  ;; parameters. Its default check handler prints failures and keeps running.
  ;; Force ordinary exceptions, then transfer them to the test thread below.
  (parameterize ([current-check-around (lambda (check) (check))]) (thunk)))
(define (on-handler thunk)
  (define answer-channel (make-channel))
  (parameterize ([gui:current-eventspace test-eventspace])
    (gui:queue-callback
     (lambda ()
       ;; Read/reset the uncaught error on its writer thread, after previously
       ;; queued normal-priority callbacks. Carry it alongside this callback's
       ;; result, so the barrier cannot consume a printed error as success.
       (define prior-error (unbox uncaught-eventspace-error))
       (set-box! uncaught-eventspace-error #f)
       (define result
         (with-handlers ([(lambda (_) #t) (lambda (e) (cons 'exception e))])
           (cons 'values (call-with-values (lambda () (call-with-check-exceptions thunk)) list))))
       (channel-put answer-channel (cons prior-error result)))
     #f))
  (define answer (sync/timeout 15 answer-channel))
  (unless answer (error 'canvas-gui-test "eventspace handler did not reply within 15 seconds"))
  (when (car answer)
    (define prior-error (car answer))
    (if (exn? (cdr prior-error)) (raise (cdr prior-error))
        (error 'canvas-gui-test "uncaught eventspace callback error: ~a" (car prior-error))))
  (define result (cdr answer))
  (case (car result)
    [(exception) (raise (cdr result))]
    [else (apply values (cdr result))]))
(struct test-window (frame canvas paints ready callback-dcs errors) #:transparent)
(define (make-window #:style [style '()] #:paint [paint (lambda (_canvas _dc) (void))])
  (on-handler
   (lambda ()
     (define frame (new gui:frame% [label "Skia canvas required GUI validation"] [width 220] [height 160]))
     (define paints (box 0)) (define ready (make-semaphore 0)) (define callback-dcs (box '()))
     (define errors (box '()))
     (define canvas
       (new skia-canvas% [parent frame] [style style] [min-width 40] [min-height 30]
            [paint-callback
             (lambda (canvas dc)
               (set-box! paints (add1 (unbox paints)))
               (set-box! callback-dcs (cons dc (unbox callback-dcs)))
               (with-handlers ([(lambda (_) #t) (lambda (e) (set-box! errors (cons e (unbox errors))))])
                 (call-with-check-exceptions (lambda () (paint canvas dc))))
               (semaphore-post ready))]))
     (send frame show #t)
     (test-window frame canvas paints ready callback-dcs errors))))
(define (raise-callback-error! window)
  (unless (null? (unbox (test-window-errors window)))
    (raise (last (unbox (test-window-errors window))))))
(define (await-paint! window)
  (unless (sync/timeout 15 (test-window-ready window))
    (error 'canvas-gui-test "a shown window did not receive a paint callback within 15 seconds"))
  (raise-callback-error! window))
(define (drain-paints! window)
  (let loop () (when (sync/timeout 0 (test-window-ready window)) (loop))))
(define (with-window proc #:style [style '()] #:paint [paint (lambda (_canvas _dc) (void))])
  (define window (make-window #:style style #:paint paint))
  (dynamic-wind
   void
   (lambda ()
     (await-paint! window) (on-handler void) (raise-callback-error! window)
     (proc window)
     (on-handler void) (raise-callback-error! window))
   (lambda ()
     (on-handler (lambda () (send (test-window-canvas window) close-skia)
                            (send (test-window-frame window) show #f))))))
(define (fill dc color [x 0] [y 0] [width 20] [height 12])
  (send dc set-pen "black" 1 'transparent) (send dc set-brush color 'solid)
  (send dc draw-rectangle x y width height))
(define (pixel dc x y)
  (define-values (w h) (send dc get-pixel-size))
  (define bytes (send dc get-rgba-bytes #:premultiplied? #t))
  (bytes->list (subbytes bytes (* 4 (+ x (* w y))) (* 4 (+ 1 x (* w y))))))

(define canvas-gui-tests
  (test-suite
   "Required real-window Skia canvas eventspace, exposure and lifecycle tests"
   (test-case "GUI harness propagates failed synchronous and exposure assertions to RackUnit"
     (check-exn exn:test:check?
       (lambda () (on-handler (lambda () (check-equal? 1 2)))))
     (check-exn exn:test:check?
       (lambda () (with-window void #:paint (lambda (_canvas _dc) (check-equal? 1 2)))))
     (parameterize ([gui:current-eventspace test-eventspace])
       (gui:queue-callback (lambda () (error 'uncaught-gui-probe "deliberate uncaught eventspace failure")) #f))
     (check-exn #rx"deliberate uncaught eventspace failure" (lambda () (on-handler void)))
     (check-not-exn (lambda () (on-handler void))))
   (test-case "shown window receives its Skia DC on the owning eventspace handler"
     (with-window
      (lambda (window)
        (on-handler
         (lambda ()
           (define canvas (test-window-canvas window))
           (define dc (send canvas get-dc))
           (check-true (skia-canvas? canvas)) (check-true (is-a? canvas gui:canvas%))
           (check-true (skia-dc? dc)) (check-true (is-a? dc rd:dc<%>))
           (check-true (positive? (unbox (test-window-paints window))))
           (check-true (andmap (lambda (seen) (eq? seen dc)) (unbox (test-window-callback-dcs window)))))))
      #:paint (lambda (canvas dc)
                (check-eq? (current-thread) (gui:eventspace-handler-thread test-eventspace))
                (check-eq? (send canvas get-dc) dc))))
   (test-case "refresh-now uses the requested synchronous callback and persistent DC"
     (with-window (lambda (window)
       (on-handler (lambda ()
         (define canvas (test-window-canvas window)) (define dc (send canvas get-dc))
         (define ordinary (unbox (test-window-paints window))) (define invoked 0)
         (send canvas refresh-now
           (lambda (given) (set! invoked (add1 invoked)) (check-eq? given dc) (fill given "red"))
           #:flush? #t)
         (check-equal? invoked 1) (check-equal? (unbox (test-window-paints window)) ordinary)
         (check-equal? (pixel dc 3 4) '(255 0 0 255)))))))
   (test-case "real canvas repeatedly measures and draws HarfBuzz text after GTK initialization"
     (with-window
      (lambda (window)
        (on-handler (lambda ()
          (define canvas (test-window-canvas window)) (define dc (send canvas get-dc))
          (send canvas refresh-now) (send canvas refresh-now)
          (check-eq? (send canvas get-dc) dc)
          (define pixels (send dc get-rgba-bytes #:premultiplied? #t))
          (check-true (for/or ([i (in-range 0 (bytes-length pixels) 4)]) (< (bytes-ref pixels i) 240))))))
      #:paint
      (lambda (_canvas dc)
        (send dc set-font (rd:make-font #:size 16 #:family 'swiss))
        (send dc set-text-foreground "black")
        (define-values (width height _descent _leading) (send dc get-text-extent "Skia canvas office 123" #f #t))
        (check-true (> width 0)) (check-true (> height 0))
        (send dc draw-text "Skia canvas office 123" 4 4 #t))))
   (test-case "burst refresh requests coalesce and run after the issuing callback returns"
     (with-window (lambda (window)
       (drain-paints! window)
       (define before
         (on-handler (lambda ()
           (define canvas (test-window-canvas window))
           (define before (unbox (test-window-paints window)))
           (for ([_ (in-range 12)]) (send canvas refresh))
           (check-equal? (unbox (test-window-paints window)) before)
           before)))
       (await-paint! window)
       (define after (on-handler (lambda () (unbox (test-window-paints window)))))
       ;; A toolkit exposure may join the batch, so require coalescing without
       ;; assuming an OS-independent exact event count.
       (check-true (<= 1 (- after before) 11)))))
   (test-case "manual present transfers existing drawing without invoking the paint callback"
     (with-window (lambda (window)
       (on-handler (lambda ()
         (define canvas (test-window-canvas window)) (define dc (send canvas get-dc))
         (define before (unbox (test-window-paints window)))
         (fill dc "blue") (send canvas present)
         (check-equal? (unbox (test-window-paints window)) before)
         (check-equal? (pixel dc 3 4) '(0 0 255 255))
         (define info (send canvas get-skia-info))
         (check-equal? (hash-ref info 'stage) "0.58")
         (check-eq? (hash-ref info 'backend) 'cpu)
         (check-false (hash-ref info 'gpu_execution))
         (check-true (positive? (hash-ref info 'presentation_count))))))))
   (test-case "actual frame resize updates logical and physical size without changing DC or selections"
     (with-window (lambda (window)
       (define retained
         (on-handler (lambda ()
           (define canvas (test-window-canvas window)) (define dc (send canvas get-dc))
           (define pen (rd:make-pen #:color "red" #:width 3 #:immutable? #f))
           (define brush (rd:make-brush #:color "blue" #:immutable? #f))
           (send dc set-pen pen) (send dc set-brush brush)
           (send dc set-origin 3 4) (send dc set-alpha 0.25)
           (send dc set-clipping-rect 1 2 20 20)
           (list dc pen brush (send dc get-clipping-region)
                 (call-with-values (lambda () (send canvas get-client-size)) list)))))
       (drain-paints! window)
       (on-handler (lambda () (send (test-window-frame window) resize 310 230)))
       (await-paint! window)
       (on-handler (lambda ()
         (define canvas (test-window-canvas window)) (define dc (send canvas get-dc))
         (define-values (w h) (send canvas get-client-size))
         (check-eq? dc (first retained)) (check-not-equal? (list w h) (fifth retained))
         (check-equal? (call-with-values (lambda () (send dc get-size)) list)
                       (list (exact->inexact w) (exact->inexact h)))
         (define scale (send dc get-backing-scale))
         (check-equal? (call-with-values (lambda () (send dc get-pixel-size)) list)
                       (list (inexact->exact (ceiling (* w scale))) (inexact->exact (ceiling (* h scale)))))
         (check-eq? (send dc get-pen) (second retained)) (check-eq? (send dc get-brush) (third retained))
         (check-eq? (send dc get-clipping-region) (fourth retained))
         (check-equal? (send dc get-alpha) 0.25)
         (check-equal? (call-with-values (lambda () (send dc get-origin)) list) '(3.0 4.0))
         (check-exn exn:fail? (lambda () (send (second retained) set-width 8)))
         (check-exn exn:fail? (lambda () (send (fourth retained) set-rectangle 0 0 1 1))))))))
   (test-case "hide and show trigger another exposure using the same DC"
     (with-window (lambda (window)
       (define dc (on-handler (lambda () (send (test-window-canvas window) get-dc))))
       (on-handler (lambda () (send (test-window-frame window) show #f)))
       (drain-paints! window)
       (on-handler (lambda () (send (test-window-frame window) show #t)))
       (await-paint! window)
       (on-handler (lambda () (check-eq? (send (test-window-canvas window) get-dc) dc))))))
   (test-case "synchronous paint exception discards an unfinished alpha group and permits recovery"
     (with-window (lambda (window)
       (on-handler (lambda ()
         (define canvas (test-window-canvas window)) (define dc (send canvas get-dc))
         (check-exn #rx"deliberate GUI paint failure"
           (lambda () (send canvas refresh-now
             (lambda (dc) (send dc start-alpha 0.5) (fill dc "red")
               (error 'callback "deliberate GUI paint failure")))))
         (check-equal? (pixel dc 3 4) '(255 255 255 255))
         (send dc end-alpha) (check-equal? (pixel dc 3 4) '(255 255 255 255))
         (send canvas refresh-now (lambda (dc) (fill dc "blue")))
         (check-equal? (pixel dc 3 4) '(0 0 255 255)))))))
   (test-case "automatic clear resets the full backing while retaining user state"
     (with-window (lambda (window)
       (on-handler (lambda ()
         (define canvas (test-window-canvas window)) (define dc (send canvas get-dc))
         (fill dc "red") (send dc set-clipping-rect 2 3 5 4)
         (send dc set-alpha 0.25) (send dc set-origin 100 100)
         (define region (send dc get-clipping-region))
         (send canvas refresh-now void)
         (check-equal? (pixel dc 0 0) '(255 255 255 255))
         (check-equal? (pixel dc 3 4) '(255 255 255 255))
         (check-equal? (send dc get-alpha) 0.25)
         (check-eq? (send dc get-clipping-region) region))))))
   (test-case "changed canvas background retains its alpha and returns a detached color"
     (with-window (lambda (window)
       (on-handler (lambda ()
         (define canvas (test-window-canvas window)) (define dc (send canvas get-dc))
         (send canvas set-canvas-background (make-object rd:color% 120 200 240 0.5))
         (define returned (send canvas get-canvas-background))
         (check-equal? (send returned alpha) 0.5)
         (send returned set 1 2 3)
         (check-equal? (send (send canvas get-canvas-background) red) 120)
         (check-equal? (send (send canvas get-canvas-background) alpha) 0.5)
         (check-equal? (send (send dc get-background) alpha) 0.5)
         (send canvas refresh-now void)
         (for ([actual (in-list (pixel dc 3 4))] [expected '(60 100 120 128)])
           (check-= actual expected 1)))))))
   (test-case "no-autoclear preserves prior pixels across refresh-now"
     (with-window
      (lambda (window)
        (on-handler (lambda ()
          (define canvas (test-window-canvas window)) (define dc (send canvas get-dc))
          (fill dc "red")
          (send canvas refresh-now (lambda (dc) (fill dc "blue" 2 3 5 4)))
          (define scale (send dc get-backing-scale))
          (define (scaled logical) (inexact->exact (floor (* scale logical))))
          (check-equal? (pixel dc 0 0) '(255 0 0 255))
          ;; pixel reads physical backing coordinates while drawing uses
          ;; logical canvas coordinates. Sample well inside the blue rectangle
          ;; on both 1x and HiDPI/Retina backings.
          (check-equal? (pixel dc (scaled 4) (scaled 5)) '(0 0 255 255)))))
      #:style '(no-autoclear)))
   (test-case "nested presentation and close reject without invalidating the active DC"
     (with-window (lambda (window)
       (on-handler (lambda ()
         (define canvas (test-window-canvas window))
         (send canvas refresh-now
           (lambda (dc)
             (check-exn exn:fail? (lambda () (send canvas refresh-now)))
             (check-exn exn:fail? (lambda () (send canvas present)))
             (check-exn exn:fail? (lambda () (send canvas close-skia)))
             (fill dc "red")))
         (check-true (send (send canvas get-dc) ok?)))))))
   (test-case "foreign-thread DC presentation and close access fail before changing the canvas"
     (with-window (lambda (window)
       (define canvas (test-window-canvas window))
       (for ([thunk (list (lambda () (send canvas get-dc)) (lambda () (send canvas present))
                          (lambda () (send canvas refresh-now)) (lambda () (send canvas close-skia)))])
         (check-exn #rx"eventspace handler" thunk))
       (on-handler (lambda () (check-false (send canvas closed?)) (check-true (send (send canvas get-dc) ok?)))))))
   (test-case "close is idempotent invalidates retained DC and makes queued refresh harmless"
     (with-window (lambda (window)
       (define before
         (on-handler (lambda ()
           (define canvas (test-window-canvas window)) (define dc (send canvas get-dc))
           (define pen (rd:make-pen #:immutable? #f)) (send dc set-pen pen)
           (send canvas refresh) (send canvas close-skia) (send canvas close-skia)
           (check-true (send canvas closed?)) (check-false (send dc ok?))
           (check-not-exn (lambda () (send pen set-width 3)))
           (check-exn #rx"closed" (lambda () (send canvas get-dc)))
           (check-exn #rx"closed" (lambda () (send canvas present)))
           (unbox (test-window-paints window)))))
       (on-handler (lambda () (check-equal? (unbox (test-window-paints window)) before))))))))

(define canvas-gui-test-count 15)
(module+ main
  (require rackunit/text-ui)
  (define failures
    (dynamic-wind void (lambda () (run-tests canvas-gui-tests))
                  (lambda () (custodian-shutdown-all test-custodian))))
  (printf "canvas-gui: ~a cases, ~a failures; real shown windows and eventspace callbacks.\n"
          canvas-gui-test-count failures)
  (exit (if (zero? failures) 0 1)))
