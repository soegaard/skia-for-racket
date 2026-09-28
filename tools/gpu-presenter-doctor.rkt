#lang racket/base
(require racket/class racket/cmdline racket/file racket/path racket/list
         rackunit/text-ui "../main.rkt" "../gpu.rkt"
         "../private/gpu-io-trace.rkt" "../tests/gpu-presenter-native-test.rkt"
         "../examples/gpu-presentation-scene.rkt"
         "gpu-report.rkt" "gpu-presentation-host.rkt")
(provide gpu-presenter-doctor!)
(define (gpu-presenter-doctor! prefix backend #:required? [required? #t]
                               #:require-hardware? [hardware? #f])
  (unless (memq backend '(opengl metal))
    (raise-argument-error 'gpu-presenter-doctor! "'opengl or 'metal" backend))
  (define validation-run
    (or (getenv "SKIA_GPU_VALIDATION_RUN")
        (format "presentation-standalone-~a" (current-inexact-milliseconds))))
  (define started? #f) (define handler-checked? #f) (define failures #f) (define windows '())
  (define (report status message)
    (hasheq 'schema_version 1 'stage "0.42" 'kind "presentation"
            'backend (symbol->string backend) 'status status 'message message
            'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
            'racket_version (version) 'validation_run validation-run
            'required required? 'require_hardware hardware? 'eventspace_handler_checked handler-checked?
            'native_test_cases gpu-presenter-native-test-count 'native_test_failures failures
            'windows (reverse windows) 'visible_pixels_verified #f
            'manual_review_required #t 'performance_measured #f))
  (define (publish status message)
    (write-gpu-json (string->path (string-append prefix ".diagnostic.json")) (report status message)))
  (with-handlers
      ([exn:fail:gpu:unavailable?
        (lambda (e)
          (publish (if started? "error" "unavailable") (exn-message e))
          (eprintf "Presentation ~a: ~a\n" backend (exn-message e))
          (if (and (not required?) (not started?)) 0 1))]
       [exn:fail? (lambda (e) (publish "error" (exn-message e))
                    (eprintf "Presentation ERROR: ~a\n" (exn-message e)) 1)])
    (call-on-presentation-handler
     (lambda (gpu-window% settle)
       (set! handler-checked? #t)
       (define (make-window render automatic?)
         (new gpu-window% [label (format "Skia 0.42 / ~a" backend)]
              [width 420] [height 310] [backend backend] [render render]
              [automatic? automatic?]))
       ;; Establish initialization separately from RackUnit so --optional can
       ;; skip a genuinely unavailable backend, never a failed live test.
       (define probe (make-window void #f))
       (dynamic-wind void
         (lambda ()
           (send probe show #t) (settle)
           (define p (send probe get-gpu-presenter))
           (set! started? #t)
           (define ctx (gpu-context-info (gpu-presenter-context p)))
           (when (and hardware? (not (equal? (hash-ref ctx 'renderer_class "unclassified") "hardware-reported")))
             (error 'gpu-presenter-doctor "hardware-reported renderer required")))
         (lambda () (send probe close-gpu)))
       (set! failures (run-tests (make-gpu-presenter-native-tests backend make-window settle)))
       (unless (zero? failures) (error 'gpu-presenter-doctor "presenter native suite failed: ~a" failures))
       ;; Two windows coexist, with separate contexts and independent closure.
       ;; Record every successful submission without a diagnostic readback.
       (define saved-frames (make-vector 2 #f))
       (define saved-canvases (make-vector 2 #f))
       (define hosts
         (for/list ([i (in-range 2)])
           (define w (make-window
             (lambda (f)
               (vector-set! saved-frames i f)
               (vector-set! saved-canvases i (gpu-frame-canvas f))
               (draw-presentation-scene f)) #f))
           (send w move (+ 40 (* i 550)) (+ 60 (* i 50)))
           w))
       (dynamic-wind void
         (lambda ()
           (for ([w (in-list hosts)]) (send w show #t)) (settle)
           (define ps (map (lambda (w) (send w get-gpu-presenter)) hosts))
           (define generations (map (lambda (p) (gpu-context-generation (gpu-presenter-context p))) ps))
           (unless (= (length (remove-duplicates generations)) 2)
             (error 'gpu-presenter-doctor "window contexts unexpectedly share a generation"))
           (for ([w (in-list hosts)] [p (in-list ps)] [i (in-naturals)])
             (define initial (gpu-context-info (gpu-presenter-context p)))
             (define frames '())
             (for ([size (in-list '((520 350) (640 410) (560 370)))])
               (send w resize (car size) (cadr size)) (settle)
               (define ledger (box '()))
               (define result
                 (let loop ([n 8])
                   (define r (parameterize ([current-gpu-io-ledger ledger]) (gpu-presenter-render! p)))
                   (cond [(eq? r 'present-requested) r]
                         [(and (eq? r 'skipped) (positive? n)) (settle) (loop (sub1 n))]
                         [else (error 'gpu-presenter-doctor "unable to submit visible-size frame: ~a" r)])))
               (define f (vector-ref saved-frames i))
               (define after (gpu-presenter-info p))
               (set! frames (cons
                 (hasheq 'result (symbol->string result) 'frame (gpu-frame-info f)
                         'frame_expired (gpu-frame-expired? f)
                         'canvas_expired (skia-closed? (vector-ref saved-canvases i))
                         'after_frame after 'io_events (reverse (unbox ledger))) frames))
               (printf "~a window ~a: ~ax~a pixels, generation ~a; submit/present requested\n"
                       backend i (gpu-frame-width f) (gpu-frame-height f) (gpu-frame-generation f)))
             (send w close-gpu)
             (define closed (gpu-presenter-info p))
             (check-gpu-teardown! (hash-ref (hash-ref closed 'adapter) 'context))
             (set! windows (cons (hasheq 'index i 'initial_context initial 'frames (reverse frames)
                                         'closed_presenter closed) windows))))
         (lambda () (close-gpu-contexts! hosts (lambda (w) (send w close-gpu)))))))
    (publish "passed" #f)
    0))
(module+ main
  (define prefix "output/presentation-0.42") (define backend 'opengl)
  (define required? #t) (define hardware? #f)
  (command-line #:once-each
    [("--prefix") p "Artifact prefix" (set! prefix p)]
    [("--backend") b "opengl or metal" (set! backend (string->symbol b))]
    [("--optional") "Allow initial backend unavailability only" (set! required? #f)]
    [("--require-hardware") "Require hardware-reported renderer" (set! hardware? #t)]
    #:args () (void))
  (exit (gpu-presenter-doctor! prefix backend #:required? required? #:require-hardware? hardware?)))
