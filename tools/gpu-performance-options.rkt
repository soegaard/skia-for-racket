#lang racket/base
(require racket/cmdline racket/runtime-path racket/file file/sha1 "../private/gpu-performance-util.rkt")
(provide read-performance-options clear-performance-results! performance-source-fingerprints)
(define-runtime-path source-root "..")
(define (clear-performance-results! prefix)
  (for ([suffix '(".inspection.json" ".review.html" ".samples.csv")])
    (define p (string->path (string-append prefix suffix)))
    (when (file-exists? p) (delete-file p))))
;; Keep these as repository-relative names, but assemble the extension so the
;; static local-require checker does not mistake data paths for module requires.
(define (rkt-source path) (string-append path ".rkt"))
(define source-paths
  (map rkt-source
       '("examples/gpu-scenes" "examples/gpu-presentation-scene"
         "private/gpu-performance-util" "private/gpu-cache"
         "tools/gpu-performance-options" "tools/gpu-performance-work"
         "tools/gpu-performance-doctor" "tools/gpu-redraw-doctor")))
(define (performance-source-fingerprints)
  ;; File bytes only, including in headless mode: never import a GUI module.
  ;; SHA1 here is a reproducibility fingerprint, not a security attestation.
  (for/list ([p (in-list source-paths)])
    (hasheq 'path p 'sha1 (call-with-input-file (build-path source-root p) sha1))))
(define (read-performance-options default-prefix)
  (define prefix default-prefix) (define backend 'opengl) (define host 'gui)
  (define platform 'surfaceless) (define index 0) (define surface 'surfaceless)
  (define required? #t) (define hardware? #f)
  (define (environment key fallback) (string->number (or (getenv key) (number->string fallback))))
  (define samples (environment "GPU_BENCH_SAMPLES" 12))
  (define warmup (environment "GPU_BENCH_WARMUP" 3))
  (define frames (environment "GPU_STRESS_FRAMES" 180))
  (define cycles (environment "GPU_STRESS_CYCLES" 3))
  (define width (environment "GPU_BENCH_WIDTH" 640)) (define height (environment "GPU_BENCH_HEIGHT" 400))
  (define sample-count (environment "GPU_BENCH_SAMPLE_COUNT" 0))
  (command-line #:once-each
    [("--prefix") p "Artifact prefix" (set! prefix p)]
    [("--backend") b "opengl or metal" (set! backend (string->symbol b))]
    [("--host") h "gui or egl" (set! host (string->symbol h))]
    [("--egl-platform") p "surfaceless or device" (set! platform (string->symbol p))]
    [("--egl-device-index") i "Explicit EGL device index" (set! index (string->number i))]
    [("--egl-surface") s "surfaceless or pbuffer" (set! surface (string->symbol s))]
    [("--samples") n "Measured samples (3..500)" (set! samples (string->number n))]
    [("--warmup") n "Excluded warmup iterations (1..100)" (set! warmup (string->number n))]
    [("--frames") n "Stress frames per cycle, multiple of 30 (60..9990)" (set! frames (string->number n))]
    [("--cycles") n "Recreated contexts/window pairs (3..50)" (set! cycles (string->number n))]
    [("--width") n "Benchmark target width" (set! width (string->number n))]
    [("--height") n "Benchmark target height" (set! height (string->number n))]
    [("--sample-count") n "Requested offscreen sampling" (set! sample-count (string->number n))]
    [("--optional") "Permit initial backend unavailability only" (set! required? #f)]
    [("--require-hardware") "Require hardware-reported renderer" (set! hardware? #t)]
    #:args () (void))
  (unless (memq backend '(opengl metal)) (error 'gpu-performance "invalid backend"))
  (unless (memq host '(gui egl)) (error 'gpu-performance "invalid host"))
  (hasheq 'prefix prefix 'backend backend 'host host 'egl_platform platform 'egl_index index
          'egl_surface surface 'required required? 'hardware hardware?
          'config (performance-config #:samples samples #:warmup warmup #:frames frames #:cycles cycles
                                      #:width width #:height height #:sample-count sample-count)))
