#lang racket/base
;; Diagnostic presenter, deliberately not the future public presenter API.
;; All GPU work runs on the creating Racket thread. Event callbacks never draw
;; with this domain and normal Racket DC drawing is never mixed into the GL DC.
(require racket/class (only-in racket/draw gl-config%) racket/cmdline racket/path racket/list
         "../main.rkt" "../gpu.rkt" "../gpu-racket-gl.rkt"
         "../private/gpu-provider.rkt" "../private/gpu-window.rkt"
         "../private/gpu-surface-native.rkt" "../private/gpu-io-trace.rkt"
         "../examples/gpu-scenes.rkt" "gpu-report.rkt")
(provide gpu-window-doctor!)
(define (gpu-window-doctor! prefix #:interactive? [interactive? #f]
                           #:required? [required? #t] #:require-hardware? [hardware? #f])
  (define started? #f)
  (define gpu #f) (define frame #f) (define initial #f)
  (define frames '()) (define ledger (box '()))
  (define (report status message)
    (hasheq 'schema_version 1 'stage "0.39" 'kind "window" 'backend "opengl"
            'status status 'message message 'required required? 'require_hardware hardware?
            'racket_version (version) 'os (symbol->string (system-type 'os))
            'architecture (symbol->string (system-type 'arch))
            'initial_context initial 'frames (reverse frames)
            'io_events (reverse (unbox ledger))
            'performance_measured #f 'interactive interactive?
            'visible_pixels_verified #f 'manual_review_required #t))
  (define (publish data)
    (write-gpu-json (string->path (string-append prefix ".diagnostic.json")) data))
  (with-handlers
      ([exn:fail:gpu:unavailable?
        (lambda (e)
          (define skip? (and (not required?) (not started?)))
          (publish (report (if started? "error" "unavailable") (exn-message e)))
          (eprintf "Window GPU ~a: ~a\n" (if skip? "SKIPPED" "FAILED") (exn-message e))
          (if skip? 0 1))]
       [exn:fail?
        (lambda (e)
          (publish (report "error" (exn-message e)))
          (eprintf "Window GPU ERROR: ~a\n" (exn-message e)) 1)])
    (define-values (frame% canvas% sleep/yield)
      (with-handlers ([exn:fail? (lambda (e) (gpu-unavailable 'gui-initialization "~a" (exn-message e)))])
        (values (dynamic-require 'racket/gui/base 'frame%)
                (dynamic-require 'racket/gui/base 'canvas%)
                (dynamic-require 'racket/gui/base 'sleep/yield))))
    (define config (new gl-config%))
    (send config set-legacy? (eq? (system-type 'os) 'windows))
    (send config set-double-buffered #t) (send config set-stencil-size 8)
    (send config set-hires-mode #t)
    (set! frame (new frame% [label "Skia 0.39 / OpenGL — resize to inspect"] [width 520] [height 350]))
    (define canvas (new canvas% [parent frame] [style '(gl no-autoclear)] [gl-config config]
                        [paint-callback (lambda (_canvas _dc) (void))]))
    (define saved-canvas #f)
    (dynamic-wind
      void
      (lambda ()
        (send frame show #t) (sleep/yield 0.08)
        (define gl (send (send canvas get-dc) get-gl-context))
        (unless (and gl (send gl ok?)) (gpu-unavailable 'racket-gl-host "window GL context unavailable"))
        ;; The native host framebuffer is captured while still untouched by
        ;; Ganesh. Subsequent frame queries use actual drawable pixel sizes.
        (define with-target (send gl call-as-current make-window-gl-access))
        (gpu-surface-native-check! #t)
        (parameterize-break #f (set! gpu (make-gpu-context (make-racket-gl-provider gl))))
        (set! initial (gpu-context-info gpu))
        (when (and hardware?
                   (not (equal? (hash-ref initial 'renderer_class "unclassified") "hardware-reported")))
          (error 'gpu-window-doctor "hardware-reported renderer required"))
        (set! started? #t)
        (define (draw-frame index)
          (define-values (width height) (send canvas get-gl-client-size))
          (define-values (logical-width logical-height) (send canvas get-client-size))
          (when (and (positive? width) (positive? height))
            (define target-info #f)
            (parameterize ([current-gpu-io-ledger ledger])
              (call-with-gpu-context gpu
                (lambda ()
                  (with-skia ([offscreen (make-gpu-surface gpu width height)])
                    (define c (surface-canvas offscreen))
                    (with-canvas-state c
                      (canvas-scale! c (/ width gpu-scene-width) (/ height gpu-scene-height))
                      (draw-gpu-scene c (list-ref gpu-scene-names (modulo index (length gpu-scene-names)))))
                    (with-target width height
                      (lambda (description)
                        (call-with-window-target gpu description
                          (lambda (window)
                            (set! target-info (gpu-surface-info window))
                            (set! saved-canvas (surface-canvas window))
                            ;; Transparent source margins composite over known pixels,
                            ;; never undefined or previous-frame backbuffer contents.
                            (canvas-clear! saved-canvas "#E8EEF2")
                            (draw-gpu-target-to-window! offscreen window)
                            (gpu-flush-and-submit! gpu) ; explicitly NOT a CPU wait
                            (send gl swap-buffers)))))))))
            (unless (skia-closed? saved-canvas) (error 'gpu-window-doctor "frame canvas did not expire"))
            (define info (gpu-context-info gpu))
            (unless (and (zero? (hash-ref info 'live_children))
                         (zero? (hash-ref info 'pending_releases))
                         (zero? (hash-ref info 'failed_releases)))
              (error 'gpu-window-doctor "frame leaked a wrapper/release job"))
            (set! frames
              (cons (hasheq 'index index 'target target-info
                            'logical_width logical-width 'logical_height logical-height
                            'pixel_width width 'pixel_height height
                            'scale_x (/ (exact->inexact width) logical-width)
                            'scale_y (/ (exact->inexact height) logical-height)
                            'swap_requested #t 'expired_canvas #t
                            'live_children (hash-ref info 'live_children)
                            'pending_releases (hash-ref info 'pending_releases)) frames))
            (printf "GL frame ~a: ~ax~a pixels, logical ~ax~a; submitted and swapped without CPU readback\n"
                    index width height logical-width logical-height)))
        ;; Finite validation exercises three actual window sizes. Visual
        ;; confirmation of the swapped pixels remains a separate manual check.
        (for ([size '((520 350) (680 440) (560 380))] [i (in-naturals)])
          (send frame resize (car size) (cadr size)) (sleep/yield 0.10)
          (draw-frame i))
        (when interactive?
          (displayln "Inspect the corner markers, scene detail and resize behavior; close the window to finish.")
          (let loop ([i 3])
            (when (send frame is-shown?)
              (draw-frame i) (sleep/yield 0.25) (loop (add1 i))))))
      (lambda ()
        ;; Close while the native host still exists, even on failure or escape.
        (dynamic-wind void
          (lambda () (when gpu (gpu-context-close! gpu)))
          (lambda () (when frame (send frame show #f))))))
    (define closed (gpu-context-info gpu))
    (check-gpu-teardown! closed)
    (define io (unbox ledger))
    (define reads (count (lambda (e) (equal? (hash-ref e 'kind) "readback")) io))
    (define waits (count (lambda (e) (and (equal? (hash-ref e 'kind) "submit")
                                         (hash-ref e 'wait_requested))) io))
    (unless (and (zero? reads) (zero? waits))
      (error 'gpu-window-doctor "normal frames performed a CPU wait or readback"))
    (unless (>= (length frames) 3) (error 'gpu-window-doctor "fewer than three nonzero drawable frames"))
    (publish (hash-set* (report "passed" #f) 'closed_context closed
                        'frame_readbacks reads 'frame_explicit_cpu_waits waits
                        'surface_symbol_inventory (gpu-surface-native-inventory #t)))
    (displayln "GL window submission/resize checks passed. Visible output still requires human review; no performance claim.")
    0))
(module+ main
  (define prefix "output/gpu-window-0.39")
  (define interactive? #f) (define required? #t) (define hardware? #f)
  (command-line #:program "gpu-window-doctor" #:once-each
    [("--prefix") value "Artifact prefix" (set! prefix value)]
    [("--interactive") "Keep redrawing until the window is closed" (set! interactive? #t)]
    [("--optional") "Allow initialization unavailability to skip" (set! required? #f)]
    [("--require-hardware") "Require a hardware-reported renderer string" (set! hardware? #t)]
    #:args () (void))
  (exit (gpu-window-doctor! prefix #:interactive? interactive? #:required? required?
                           #:require-hardware? hardware?)))
