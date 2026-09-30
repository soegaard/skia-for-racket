#lang racket/base
;; Actual HWND/swap-chain tests on the owning Racket GUI eventspace. This is
;; separate from the offscreen WARP gate; passing is not screen certification.
(require json racket/class racket/cmdline racket/file racket/path racket/list
         rackunit/text-ui "../main.rkt" "../gpu.rkt"
         "gpu-presentation-host.rkt" "../private/gpu-io-trace.rkt"
         (submod "../private/gpu-presenter-d3d12.rkt" testing)
         "../tests/gpu-presenter-native-test.rkt")
(provide dxgi-doctor!)
(define (draw-pattern frame)
  (define c (gpu-frame-canvas frame))
  (define w (gpu-frame-width frame)) (define h (gpu-frame-height frame))
  (define x (quotient w 2)) (define y (quotient h 2))
  (with-skia ([red (make-paint #:color 'red #:blend-mode 'src #:antialias? #f)]
              [blue (make-paint #:color 'blue #:blend-mode 'src #:antialias? #f)]
              [black (make-paint #:color 'black #:blend-mode 'src #:antialias? #f)]
              [white (make-paint #:color 'white #:blend-mode 'src #:antialias? #f)]
              [yellow (make-paint #:color 'yellow #:blend-mode 'src #:antialias? #f)])
    (draw-rect c 0 0 x y red)
    (draw-rect c x 0 (- w x) y blue)
    (draw-rect c 0 y x (- h y) black)
    (draw-rect c x y (- w x) (- h y) white)
    (draw-rect c 0 0 1 1 yellow)))
(define (dxgi-doctor! directory selection index)
  (define run-id (path->string (file-name-from-path (simplify-path directory))))
  (define cycles '())
  (define failures #f)
  (define window-created? #f)
  (define counts (hasheq 'presenter gpu-presenter-native-test-count 'presenter_failures #f))
  (define (publish status [message #f])
    (call-with-output-file (build-path directory "dxgi.diagnostic.json")
      (lambda (out)
        (write-json
          (hasheq 'schema 1 'stage "0.49" 'status status 'error message
                  'validation_run run-id 'adapter_selection (symbol->string selection)
                  'adapter_index (if (eq? selection 'warp) #f index)
                  'racket_version (version) 'os (symbol->string (system-type 'os))
                  'architecture (symbol->string (system-type 'arch))
                  'test_counts counts 'cycles (reverse cycles)
                  'window_created window-created? 'presentation_submission_verified (equal? status "passed")
                  'back_buffer_pixels_verified #f ; independent Python checker decides
                  'visible_pixels_verified #f 'hardware_acceleration_verified #f
                  'performance_measured #f) out))
      #:exists 'truncate/replace))
  (publish "running")
  (with-handlers ([exn:fail? (lambda (e) (publish "failed" (exn-message e)) (raise e))])
    (unless (and (eq? (system-type 'os) 'windows) (eq? (system-type 'arch) 'x86_64))
      (error 'dxgi-doctor "requires Windows x64"))
    (call-on-presentation-handler
      (lambda (window-class settle)
        (define (make-window render automatic?)
          (define w (new window-class [backend 'direct3d] [adapter selection] [adapter-index index]
               [sync-interval 1] [label "Skia DXGI validation"] [width 220] [height 160]
               [render render] [automatic? automatic?]))
          (set! window-created? #t) w)
        (set! failures (run-tests (make-gpu-presenter-native-tests 'direct3d make-window settle)))
        (set! counts (hasheq 'presenter gpu-presenter-native-test-count 'presenter_failures failures))
        (unless (zero? failures) (error 'dxgi-doctor "shared presenter native suite failed"))
        (define (draw! p)
          ;; Occlusion and initialization skips never count as submitted frames.
          (let loop ([left 30])
            (define result (gpu-presenter-render! p))
            (cond [(eq? result 'present-requested) (void)]
                  [(and (eq? result 'skipped) (positive? left)) (settle) (loop (sub1 left))]
                  [else (error 'dxgi-doctor "required DXGI frame was not presented: ~a" result)])))
        (define (clean! p)
          (define info (gpu-presenter-info p))
          (define a (hash-ref info 'adapter))
          (define c (hash-ref a 'context))
          (unless (and (zero? (hash-ref a 'live_drawables))
                       (= (hash-ref c 'live_children) 1)
                       (zero? (hash-ref c 'pending_releases))
                       (zero? (hash-ref c 'failed_releases)))
            (error 'dxgi-doctor "unretired per-frame references")))
        (for ([cycle (in-range 3)])
          ;; Two windows coexist; all native operations still use one handler.
          (define windows (list (make-window draw-pattern #f) (make-window draw-pattern #f)))
          (define entries '())
          (dynamic-wind void
            (lambda ()
              (for ([w (in-list windows)] [number (in-naturals)])
                (send w move (+ 24 (* number 340)) 24) (send w show #t))
              (settle)
              (for ([w (in-list windows)] [number (in-naturals)])
                (send w focus) (settle)
                (define p (send w get-gpu-presenter))
                (define initial (gpu-context-info (gpu-presenter-context p)))
                (define captures '())
                (define normal-ledger (box '()))
                (define targets '())
                (for ([size (in-list '((220 160) (286 204) (242 178)))] [ordinal (in-naturals)])
                  (send w resize (car size) (cadr size)) (settle)
                  (define pending #f)
                  (parameterize
                    ([current-dxgi-capture-hook
                       (lambda (pixels record)
                         (when (equal? (hash-ref record 'result) "submitted")
                           (set! pending (cons pixels record))))])
                    (draw! p))
                  (unless pending (error 'dxgi-doctor "successful frame has no back-buffer capture"))
                  (define frame (hash-ref (gpu-presenter-info p) 'last_frame))
                  (set! targets (cons frame targets))
                  ;; Bytes are retained; PNG encoding is after both contexts close.
                  (set! captures (cons (list ordinal (car pending) (cdr pending) frame) captures))
                  (parameterize ([current-gpu-io-ledger normal-ledger]) (draw! p))
                  (clean! p))
                (parameterize ([current-gpu-io-ledger normal-ledger])
                  (for ([frame (in-range 180)])
                    (draw! p)
                    (when (zero? (modulo (add1 frame) 30)) (collect-garbage) (clean! p))))
                (define ready (gpu-presenter-info p))
                (set! entries (cons (list number p initial ready captures (reverse (unbox normal-ledger))) entries))
                (printf "DXGI cycle ~a/window ~a: 180 stress frames, two resizes and three captures completed\n" cycle number)))
            (lambda () (for ([w (in-list windows)]) (send w close-gpu))))
          (define results
            (for/list ([entry (in-list (reverse entries))])
              (define number (list-ref entry 0))
              (define p (list-ref entry 1))
              (define final (gpu-presenter-info p))
              (unless (and (eq? (gpu-presenter-state p) 'closed)
                           (equal? (hash-ref (hash-ref (hash-ref final 'adapter) 'context) 'state) "closed"))
                (error 'dxgi-doctor "context not closed before pixel encoding"))
              (define capture-results
                (for/list ([item (in-list (reverse (list-ref entry 4)))])
                  (define ordinal (list-ref item 0)) (define pixels (list-ref item 1))
                  (define record (list-ref item 2)) (define frame (list-ref item 3))
                  (define filename (format "cycle-~a-window-~a-size-~a.png" cycle number ordinal))
                  (with-skia ([image (rgba-bytes->image (hash-ref record 'width) (hash-ref record 'height) pixels)])
                    (call-with-output-file (build-path directory filename)
                      (lambda (out) (write-bytes (image->png-bytes image) out)) #:exists 'error))
                  (hasheq 'ordinal ordinal 'png filename 'submission record 'frame frame
                          'encoded_after_context_teardown #t)))
              (hasheq 'window number 'initial (list-ref entry 2) 'before_close (list-ref entry 3)
                      'final final 'stress_frames 180 'normal_frames 183
                      'normal_io (list-ref entry 5) 'captures capture-results)))
          (set! cycles (cons (hasheq 'cycle cycle 'windows results) cycles))
          (publish "running"))))
    (publish "passed")
    (void)))
(module+ main
  (define directory #f) (define selection 'warp) (define index 0)
  (command-line #:once-each
    [("--directory") path "fresh evidence directory" (set! directory (path->complete-path path))]
    [("--adapter") name "warp or hardware; no fallback" (set! selection (string->symbol name))]
    [("--adapter-index") n "DXGI hardware index" (set! index (string->number n))]
    #:args () (void))
  (unless directory (error 'dxgi-doctor "--directory is required"))
  (dxgi-doctor! directory selection index))
