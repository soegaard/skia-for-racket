#lang racket/base
;; Run by the presenter doctor on its eventspace handler. Window creation and
;; event pumping are injected so this module does not initialize racket/gui.
(require rackunit racket/class racket/list
         "../main.rkt" "../gpu.rkt" "../private/gpu-io-trace.rkt" "gpu-fixtures.rkt")
(provide make-gpu-presenter-native-tests gpu-presenter-native-test-count)
(define gpu-presenter-native-test-count 28)
(define (make-gpu-presenter-native-tests backend make-window settle)
  (define (fixture body [render void])
    (define w (make-window render #f))
    (dynamic-wind
      void
      (lambda ()
        (send w show #t) (settle)
        (define p (send w get-gpu-presenter))
        (body w p (gpu-presenter-context p)))
      (lambda () (send w close-gpu))))
  (define (draw p)
    ;; Nil drawable acquisition is an explicit skip; it is not allowed to
    ;; satisfy a live acceptance test. Retry briefly for window-system setup.
    (let loop ([remaining 8])
      (define result (gpu-presenter-render! p))
      (cond [(eq? result 'present-requested) result]
            [(and (eq? result 'skipped) (positive? remaining)) (settle) (loop (sub1 remaining))]
            [else (error 'presentation-test "no submitted frame: ~a" result)])))
  (define (clean p)
    (define info (gpu-presenter-info p))
    (define adapter (hash-ref info 'adapter))
    (define context (hash-ref adapter 'context))
    (check-equal? (hash-ref context 'live_children) 0)
    (check-equal? (hash-ref context 'pending_releases) 0)
    (check-equal? (hash-ref context 'failed_releases) 0)
    (check-equal? (hash-ref adapter 'live_drawables) 0))
  (test-suite
   "Live shared presenter/frame API (submission, not visible-pixel certification)"
   (test-case "presenter exposes the selected execution context"
     (fixture (lambda (w p context)
       (check-true (gpu-presenter? p))
       (check-eq? (gpu-presenter-backend p) backend)
       (check-eq? (gpu-context-backend context) backend))))
   (test-case "ordinary canvas draws through the frame"
     (fixture (lambda (w p context) (draw p) (clean p))
       (lambda (f)
         (check-true (canvas? (gpu-frame-canvas f)))
         (check-eq? (canvas-execution-backend (gpu-frame-canvas f)) backend)
         (with-skia ([paint (make-paint #:color 'red)])
           (draw-circle (gpu-frame-canvas f) 40 40 20 paint)))))
   (test-case "frame geometry agrees with target dimensions and context"
     (fixture (lambda (w p context) (draw p))
       (lambda (f)
         (define info (gpu-frame-info f)) (define target (hash-ref info 'target))
         (check-equal? (gpu-frame-width f) (hash-ref target 'width))
         (check-equal? (gpu-frame-height f) (hash-ref target 'height))
         (check-true (hash-ref target 'context_matches))
         (check-true (positive? (gpu-frame-logical-width f)))
         (check-true (positive? (gpu-frame-scale-x f))))))
   (test-case "both the frame and its raw borrowed canvas expire"
     (define saved #f) (define raw #f)
     (fixture (lambda (w p context)
       (draw p)
       (check-true (gpu-frame-expired? saved)) (check-true (skia-closed? raw))
       (check-exn #rx"expired" (lambda () (gpu-frame-canvas saved)))
       (check-exn exn:fail? (lambda () (canvas-clear! raw 'red))))
       (lambda (f) (set! saved f) (set! raw (gpu-frame-canvas f)))))
   (test-case "expired frame context accessor is rejected"
     (define saved #f)
     (fixture (lambda (w p context)
       (draw p) (check-exn #rx"expired" (lambda () (gpu-frame-context saved))))
       (lambda (f) (set! saved f))))
   (test-case "later frames never revive an earlier canvas"
     (define old #f)
     (fixture (lambda (w p context) (draw p) (draw p))
       (lambda (f)
         (when old
           (check-true (skia-closed? old))
           (check-exn exn:fail? (lambda () (canvas-clear! old 'red))))
         (set! old (gpu-frame-canvas f)))))
   (test-case "six sequential frames leave no native target references"
     (fixture (lambda (w p context)
       (for ([i (in-range 6)]) (draw p) (clean p)))))
   (test-case "resize advances target generation"
     (fixture (lambda (w p context)
       (draw p)
       (define before (hash-ref (gpu-presenter-info p) 'target_generation))
       (send w resize 520 390) (settle) (draw p)
       (check-true (> (hash-ref (gpu-presenter-info p) 'target_generation) before)))))
   (test-case "stable extent keeps generation while frame index advances"
     (fixture (lambda (w p context)
       (draw p) (define before (gpu-presenter-info p)) (draw p)
       (define after (gpu-presenter-info p))
       (check-equal? (hash-ref before 'target_generation) (hash-ref after 'target_generation))
       (check-equal? (add1 (hash-ref before 'frames_acquired)) (hash-ref after 'frames_acquired)))))
   (test-case "hidden window skips target acquisition and can resume"
     (fixture (lambda (w p context)
       (draw p) (send w show #f) (settle)
       (define before (hash-ref (gpu-presenter-info p) 'frames_acquired))
       (check-eq? (gpu-presenter-render! p) 'skipped)
       (check-equal? (hash-ref (gpu-presenter-info p) 'frames_acquired) before)
       (send w show #t) (settle) (draw p) (clean p))))
   (test-case "minimized window skips and restoration resumes presentation"
     (fixture (lambda (w p context)
       (draw p)
       (send w iconize #t) (settle)
       (check-true (send w is-iconized?))
       (define before (hash-ref (gpu-presenter-info p) 'frames_acquired))
       (check-eq? (gpu-presenter-render! p) 'skipped)
       (check-equal? (hash-ref (gpu-presenter-info p) 'frames_acquired) before)
       (send w iconize #f) (settle) (draw p) (clean p))))
   (test-case "resize during a yielded callback cancels the old target and redraws"
     (define window #f) (define resized? #f)
     (fixture (lambda (w p context)
       (set! window w)
       (check-eq? (gpu-presenter-render! p) 'cancelled)
       (check-equal? (hash-ref (gpu-presenter-info p) 'presents_requested) 0)
       (clean p) (settle)
       (check-equal? (hash-ref (gpu-presenter-info p) 'presents_requested) 1)
       (clean p))
       (lambda (f)
         (unless resized?
           (set! resized? #t)
           (send window resize 540 400) (settle)))))
   (test-case "close cancels queued redraws"
     (fixture (lambda (w p context)
       (for ([i (in-range 6)]) (gpu-presenter-request-render! p))
       (send w close-gpu) (settle)
       (check-eq? (gpu-presenter-state p) 'closed)
       (check-equal? (hash-ref (gpu-presenter-info p) 'presents_requested) 0))))
   (test-case "close during rendering cancels presentation after drawing unwinds"
     (define target #f)
     (fixture (lambda (w p context)
       (set! target p)
       (check-eq? (gpu-presenter-render! p) 'cancelled)
       (check-eq? (gpu-presenter-state p) 'closed)
       (check-equal? (hash-ref (gpu-presenter-info p) 'presents_requested) 0)
       (clean p))
       (lambda (f) (gpu-presenter-close! target))))
   (test-case "callback exception retires the target without presenting"
     (fixture (lambda (w p context)
       (check-exn #rx"callback" (lambda () (gpu-presenter-render! p)))
       (check-equal? (hash-ref (gpu-presenter-info p) 'presents_requested) 0)
       (check-eq? (gpu-presenter-state p) 'ready) (clean p))
       (lambda (f) (error 'callback "deliberate"))))
   (test-case "normal frames have submit then present and no CPU transfers"
     (fixture (lambda (w p context)
       (define ledger (box '()))
       (parameterize ([current-gpu-io-ledger ledger]) (draw p))
       (define events (reverse (unbox ledger)))
       (check-equal? (map (lambda (e) (hash-ref e 'kind)) events)
                     '("flush" "submit" "present-request"))
       (for ([e (in-list events)]) (check-false (hash-ref e 'wait_requested #f))))))
   (test-case "redraw bursts coalesce into one submitted frame"
     (fixture (lambda (w p context)
       (for ([i (in-range 20)]) (gpu-presenter-request-render! p))
       (settle)
       (check-equal? (hash-ref (gpu-presenter-info p) 'presents_requested) 1)
       (clean p))))
   (test-case "redraw inside render is queued as one later frame"
     (define target #f) (define n 0)
     (fixture (lambda (w p context)
       (set! target p) (draw p) (check-equal? n 1) (settle)
       (check-equal? n 2) (clean p))
       (lambda (f) (set! n (add1 n))
         (when (= n 1) (gpu-presenter-request-render! target)))))
   (test-case "wrong-thread presenter methods fail before native work"
     (fixture (lambda (w p context)
       (check-true (exn:fail? (in-worker (lambda () (gpu-presenter-render! p)))))
       (check-true (exn:fail? (in-worker (lambda () (gpu-presenter-close! p)))))
       (check-eq? (gpu-presenter-state p) 'ready))))
   (test-case "nested immediate presentation rejects"
     (define target #f)
     (fixture (lambda (w p context) (set! target p) (draw p))
       (lambda (f) (check-exn #rx"nested" (lambda () (gpu-presenter-render! target))))))
   (test-case "an ordinary active GPU scope cannot contain a presenter render"
     (fixture (lambda (w p context)
       (call-with-gpu-context context
         (lambda () (check-exn #rx"nested" (lambda () (gpu-presenter-render! p)))))
       (draw p))))
   (test-case "unbalanced canvas state fails before native submission"
     (fixture (lambda (w p context)
       (check-exn #rx"unbalanced" (lambda () (gpu-presenter-render! p)))
       (check-equal? (hash-ref (gpu-presenter-info p) 'presents_requested) 0)
       (clean p))
       (lambda (f) (canvas-save! (gpu-frame-canvas f)))))
   (test-case "application images block context closure until explicitly retired"
     (define image #f)
     (fixture (lambda (w p context)
       (dynamic-wind void
         (lambda ()
           (set! image
             (call-with-gpu-context context
               (lambda () (with-skia ([s (make-gpu-surface context 4 4)]) (gpu-surface-snapshot s)))))
           (check-exn #rx"live GPU children" (lambda () (gpu-presenter-close! p)))
           (check-eq? (gpu-presenter-state p) 'closing)
           (skia-close! image) (set! image #f)
           (gpu-presenter-close! p) (check-eq? (gpu-presenter-state p) 'closed) (clean p))
         (lambda () (when image (skia-close! image)))))))
   (test-case "two windows use distinct contexts and close independently"
     (fixture (lambda (w p context)
       (fixture (lambda (w2 p2 context2)
         (check-false (eq? context context2))
         (draw p) (draw p2) (send w close-gpu)
         (check-eq? (gpu-presenter-state p) 'closed)
         (draw p2) (clean p2))))))
   (test-case "a GPU image from another window is rejected"
     (define image #f)
     (fixture (lambda (w p context)
       (dynamic-wind void
         (lambda ()
           (set! image (call-with-gpu-context context
             (lambda () (with-skia ([s (make-gpu-surface context 4 4)]) (gpu-surface-snapshot s)))))
           (fixture (lambda (w2 p2 context2) (draw p2) (clean p2))
             (lambda (f) (check-exn exn:fail?
               (lambda () (draw-image (gpu-frame-canvas f) image 0 0))))))
         (lambda () (when image (skia-close! image)))))))
   (test-case "closing another window inside drawing defers native teardown"
     (fixture (lambda (w p context)
       (fixture (lambda (w2 p2 context2)
         (gpu-presenter-set-render! p (lambda (f) (gpu-presenter-close! p2)))
         (draw p) (settle)
         (check-eq? (gpu-presenter-state p2) 'closed) (clean p))))))
   (test-case "closing twice is safe and subsequent rendering rejects"
     (fixture (lambda (w p context)
       (draw p) (gpu-presenter-close! p) (gpu-presenter-close! p)
       (check-exn exn:fail? (lambda () (gpu-presenter-render! p)))
       (clean p))))
   (test-case "GUI paint/show callbacks schedule drawing on the owning handler"
     (define callbacks 0)
     (define w (make-window (lambda (f) (set! callbacks (add1 callbacks))) #t))
     (dynamic-wind void
       (lambda ()
         (send w show #t)
         (let loop ([n 12])
           (when (and (zero? callbacks) (positive? n)) (settle) (loop (sub1 n))))
         (check-true (positive? callbacks))
         (define p (send w get-gpu-presenter)) (clean p))
       (lambda () (send w close-gpu))))))
