#lang racket

;; IK+ Amiga playable ball-stage prototype (Stage 28).
;; Retail 50 Hz physics, real fighter poses, shield lookup tables and samples.
;; Original retail 8x8 bitmap lettering; optional debug-only visual overlays.
;; Fixed 320x200 CPU/GPU rendering targets, native nearest-neighbour upscale.

(require racket/class
         racket/cmdline
         racket/file
         racket/format
         racket/gui/base
         racket/list
         racket/runtime-path
         racket/string
         (except-in skia make-font)
         skia/bitmap
         skia/gpu
         skia/gpu-gui
         "gui-event-trace.rkt"
         "background-animations.rkt"
         "ambient-animations.rkt"
         "foam-animations.rkt"
         "water-animations.rkt"
         "physics/ikplus-ball-core.rkt"
         "physics/ikplus-bonus-score.rkt"
         "physics/ikplus-shield.rkt"
         "physics/ikplus-shield-collision.rkt"
         "physics/ikplus-shadows.rkt")

(define-runtime-path atlas-path "assets/balls_and_head_atlas.png")
(define-runtime-path background-path "assets/game_background.png")
(define-runtime-path background-effects-path "assets/background_effects.png")
(define-runtime-path ambient-effects-path "assets/retail_ambient_atlas.png")
(define-runtime-path foam-palette-path "assets/retail_foam_palette.png")
(define-runtime-path water-effects-path "assets/retail_water_atlas.png")
(define-runtime-path font-atlas-path "assets/font/font_atlas_128x32.png")
(define-runtime-path shield-left-path "assets/shields/side_left.png")
(define-runtime-path shield-front-path "assets/shields/front_small_logo.png")
(define-runtime-path shield-right-path "assets/shields/side_right.png")
(define-runtime-path fighter-24-path "assets/fighters/fighter_024.png")
(define-runtime-path fighter-34-path "assets/fighters/fighter_034.png")
(define-runtime-path fighter-35-path "assets/fighters/fighter_035.png")
(define-runtime-path fighter-58-path "assets/fighters/fighter_058.png")
(define-runtime-path sound-directory "assets/sounds")
(define-runtime-path periscope-capture-root "periscope-captures")
(define-runtime-path periscope-viewer-path "periscope-viewer.html")
(define-runtime-path ambient-capture-root "ambient-captures")
(define-runtime-path ambient-viewer-path "ambient-viewer.html")
(define-runtime-path bird-capture-root "bird-captures")
(define-runtime-path bird-viewer-path "bird-viewer.html")
(define-runtime-path pacman-capture-root "pacman-captures")
(define-runtime-path pacman-viewer-path "pacman-viewer.html")
(define-runtime-path leaf-capture-root "leaf-captures")
(define-runtime-path leaf-viewer-path "leaf-viewer.html")

(define scene-width 320)
(define scene-height 200)
(define step-ms 20.0) ; Exactly 50 updates per simulated second.
(define diagnostics-refresh-ms 250.0) ; Four diagnostic refreshes per second.
(define frame-gap-capacity 256) ; Roughly five seconds at the target 50 Hz.
(define max-trail-points 120)
(define periscope-capture-length 512) ; Slowest retail script ends by tick 411.
(define periscope-export-batch 4) ; Batch CPU PNG saves on GUI idle callbacks.
(define ambient-capture-length 1024) ; Longest retail crawler completes at tick 960.
(define pacman-capture-length 256) ; Longest 8-row PAC pass ends at tick 160.
(define leaf-capture-length 768) ; Leaf-crossing site 3 ends at tick 720.
(define ambient-export-batch 2) ; Four 320x200 diagnostic panels per PNG.
(define standard-ambient-panels '(fish-left fish-right spider crawler))
(define bird-ambient-panels '(bird-0 bird-1 bird-2 bird-3))
(define pacman-ambient-panels '(pacman-0 pacman-1 pacman-2 pacman-3))
(define leaf-ambient-panels '(leaf-0 leaf-1 leaf-2 leaf-3))
(define leaf-ambient-sites '(3 6 4 7))
(define variant-labels
  '#("Blue / red" "Red / white" "Red / dark" "Blue / yellow"
     "White / black" "White / gray" "Blue / navy" "Rolling head"))

(struct art-set (atlas background effects water shields fighters font ambient foam))
(struct captured-periscope-frame (views reflection shore) #:transparent)
(struct captured-ambient-frame (panels reflection shore leaf-parts) #:transparent)

;; The retail game uses a 64-slot, six-bit character set, not ASCII.
;; Source: exact 512-byte glyph table at runtime address $8E9E.
(define (retail-character-index char)
  (define code (char->integer (char-upcase char)))
  (cond [(<= 48 code 57) (- code 48)]
        [(<= 65 code 90) (- code 48)]
        [(char=? char #\space) 10]
        [(char=? char #\+) 11]
        [(char=? char #\:) 13]
        [(char=? char #\?) 15]
        [(char=? char #\-) 44]
        [(char=? char #\/) 45]
        [else (error 'draw-retail-text "unsupported retail glyph: ~s" char)]))

(define (draw-retail-text canvas font-atlas str x y)
  ;; One 8x8 atlas tile per character. No antialiasing or font substitution.
  (define glyphs (map retail-character-index (string->list str)))
  (draw-atlas canvas font-atlas
              (for/list ([code (in-list glyphs)] [i (in-naturals)])
                (make-atlas-transform (+ x (* 8 i)) y))
              (for/list ([code (in-list glyphs)])
                (list (* 8 (remainder code 16))
                      (* 8 (quotient code 16)) 8 8))
              #:sampling 'nearest))

(define (raw-fixed-integer fixed)
  ;; Bonus-object shadows consume the integer byte only ($C1EA/$C21E): their
  ;; horizontal position intentionally ignores the visible sprite's half-pixel
  ;; fraction.
  (bitwise-and (arithmetic-shift fixed -8) #xff))

(define (draw-shadow-runs canvas runs paint)
  ;; Each run is an exact one-pixel-high span from the retail one-bit mask.
  ;; Keeping the output as integer rects preserves nearest-neighbour pixels on
  ;; both the permanent CPU scene and the 320x200 GPU scene.
  (for ([run (in-list runs)])
    (draw-rect canvas (first run) (second run) (third run) 1 paint)))

(define (close-art-set! art)
  (when art
    (skia-close! (art-set-atlas art))
    (skia-close! (art-set-background art))
    (skia-close! (art-set-effects art))
    (skia-close! (art-set-water art))
    (skia-close! (art-set-font art))
    (skia-close! (art-set-ambient art))
    (skia-close! (art-set-foam art))
    (for ([im (in-vector (art-set-shields art))]) (skia-close! im))
    (for ([im (in-hash-values (art-set-fighters art))]) (skia-close! im))))

(define (upload-art-set context art)
  ;; Called once, on the GPU canvas's first frame, within its active context.
  ;; All GPU textures are retained until window shutdown; CPU originals remain
  ;; available to the explicitly selected raster renderer.
  (define uploaded '())
  (define (upload im)
    (define gpu-image (gpu-upload-image context im))
    (set! uploaded (cons gpu-image uploaded))
    gpu-image)
  (with-handlers ([exn:fail?
                   (lambda (e)
                     ;; If one upload fails, its predecessors must not keep
                     ;; the presenter context alive and block safe closure.
                     (for ([im (in-list uploaded)]) (skia-close! im))
                     (raise e))])
    (art-set (upload (art-set-atlas art))
             (upload (art-set-background art))
             (upload (art-set-effects art))
             (upload (art-set-water art))
             (for/vector ([im (in-vector (art-set-shields art))])
               (upload im))
             (for/hash ([(frame im) (in-hash (art-set-fighters art))])
               (values frame (upload im)))
             (upload (art-set-font art))
             (upload (art-set-ambient art))
             (upload (art-set-foam art)))))

(define (launch [renderer 'auto] [backend 'auto] [event-trace-path #f]
                [start-fullscreen? #f] [auto-periscope-capture? #f]
                [initial-ambient #f] [auto-ambient-capture? #f]
                [auto-bird-capture? #f] [auto-pacman-capture? #f]
                [auto-leaf-capture? #f])
  ;; Called on the GUI eventspace thread. Skia resources are GUI-thread-owned.
  (unless (memq renderer '(auto gpu raster))
    (raise-argument-error 'launch "'auto, 'gpu, or 'raster" renderer))
  (unless (memq backend '(auto metal opengl direct3d))
    (raise-argument-error 'launch "'auto, 'metal, 'opengl, or 'direct3d" backend))
  ;; macOS starts on Metal. Other systems default to the portable raster mode;
  ;; explicitly request --renderer gpu for their native GPU presenter.
  (define gpu? (if (eq? renderer 'auto) (eq? (system-type 'os) 'macosx)
                   (eq? renderer 'gpu)))
  (when (and (not gpu?) (not (eq? backend 'auto)))
    (error 'launch "--backend requires the GPU renderer"))
  ;; Trace collection is opt-in.  It begins only after R, so startup and the
  ;; restart's deliberate GC cannot displace the five-second measurement.
  (define trace-state #f)
  (define trace-output-path #f)
  (define trace-auto-save-timer #f)
  (define cpu-art
    (art-set (image-from-file atlas-path)
             (image-from-file background-path)
             (image-from-file background-effects-path)
             (image-from-file water-effects-path)
             (vector (image-from-file shield-left-path)
                     (image-from-file shield-front-path)
                     (image-from-file shield-right-path))
             (hash 24 (image-from-file fighter-24-path)
                   34 (image-from-file fighter-34-path)
                   35 (image-from-file fighter-35-path)
                   58 (image-from-file fighter-58-path))
             (image-from-file font-atlas-path)
             (image-from-file ambient-effects-path)
             (image-from-file foam-palette-path)))
  (define gpu-art #f)
  (define gpu-scene #f) ; 320x200 GPU surface, created in the first frame
  (define raster-scene (and (not gpu?) (make-surface scene-width scene-height)))
  (define raster-present #f) ; cached, window-sized raster surface
  (define raster-present-size #f)
  (define collision-buffers (load-visible-collision-masks))
  (define simulation (make-world #:seed #x1988))
  (define background-state (make-background-world #:seed #x1988))
  (define ambient-state (make-ambient-world #:seed #x1992))
  (define water-state (make-water-world))
  (define foam-state (make-foam-world #:seed #x18f44))
  (define defender (make-shield))
  (define selected-slot 0)
  (define paused? #f)
  (define trails? #f) ; normal play starts without projectile traces
  (define selection-box? #f) ; or an outline around the selected ball
  (define fps-visible? #t) ; game HUD, independently toggled with F
  (define scenery? #t)
  (define background-animations? #t)
  (define collisions? #t)
  (define player-hit? #t)
  (define sounds? #f) ; muted by default, opt in with M or Diagnostics
  (define progress (make-bonus-score))
  (define closed? #f)
  (define failed? #f)
  (define histories (make-vector 4 '()))
  (define last-objects (make-vector 4 #f))
  (define held (make-hasheq))
  (define remainder-ms 0.0)
  (define previous-ms (current-inexact-monotonic-milliseconds))
  (define ticker #f)
  (define view #f)
  (define pause-button #f)
  (define trails-control #f)
  (define selection-box-control #f)
  (define fps-control #f)
  (define background-animation-control #f)
  (define tick-label #f)
  (define ball-label #f)
  (define shield-label #f)
  (define help-label #f)
  (define background-label #f)
  (define periscope-capture-label #f)
  (define periscope-button #f)
  (define ambient-capture-label #f)
  (define ambient-button #f)
  (define bird-button #f)
  (define pacman-button #f)
  (define leaf-button #f)
  (define perf-label #f)
  (define window #f)
  (define debug-window #f)
  (define last-render-ms 0.0)
  (define frame-count 0)
  (define fps-start-ms (current-inexact-monotonic-milliseconds))
  (define callback-rate 0.0)
  (define current-scale 1)
  (define last-diagnostics-refresh-ms -inf.0)
  ;; Preallocated ring: one O(1) write per render, even with Diagnostics hidden.
  ;; Sample statistics are sorted only when the Diagnostics window is refreshed.
  (define frame-gaps (make-vector frame-gap-capacity 0.0))
  (define frame-gap-count 0)
  (define frame-gap-next 0)
  (define last-render-finished-ms #f)
  (define gc-baseline-ms (current-gc-milliseconds))
  (define last-render-gc-ms gc-baseline-ms)
  (define long-gaps-with-gc 0)
  (define max-timer-gap-ms 0.0)
  (define extra-catch-up-ticks 0)
  (define catch-up-bursts 0)
  (define periscope-showcase-state #f)
  (define periscope-recording #f) ; #f, or vector of 512 immutable snapshots.
  (define periscope-recorded-count 0)
  (define periscope-export-directory #f)
  (define periscope-export-index 0)
  (define periscope-export-surface #f)
  (define periscope-export-timer #f)
  (define periscope-capture-status "Periscope capture: idle")
  (define ambient-showcase-state #f)
  (define ambient-recording #f) ; #f or captured 50 Hz snapshots.
  (define ambient-capture-target ambient-capture-length)
  (define ambient-recorded-count 0)
  (define ambient-export-directory #f)
  (define ambient-export-index 0)
  (define ambient-export-surface #f)
  (define ambient-export-timer #f)
  (define ambient-capture-status "Ambient capture: idle")
  (define ambient-panel-order standard-ambient-panels)
  (define leaf-panel-backgrounds #f)

  (define (stop-trace-auto-save!)
    (when trace-auto-save-timer
      (send trace-auto-save-timer stop)
      (set! trace-auto-save-timer #f)))

  (define (next-trace-output-path path)
    ;; A repeated restart must preserve already captured evidence.  Keep the
    ;; requested name for the first capture, then add -2, -3, and so on.
    (define base-path (if (path? path) path (string->path path)))
    (define file-name (path->string (file-name-from-path base-path)))
    (define name-parts (regexp-match #rx"^(.+)(\\.[^.]+)$" file-name))
    (define stem (if name-parts (cadr name-parts) file-name))
    (define extension (if name-parts (caddr name-parts) ""))
    (define directory (or (path-only base-path) (current-directory)))
    (let loop ([index 1])
      (define candidate
        (if (= index 1)
            base-path
            (build-path directory (format "~a-~a~a" stem index extension))))
      (if (file-exists? candidate)
          (loop (add1 index))
          candidate)))

  (define (start-event-trace-session!)
    (when event-trace-path
      ;; Restart replaces an unfinished attempt rather than mixing its events
      ;; with the new round.  No partial CSV is written for the discarded run.
      (stop-trace-auto-save!)
      (when trace-state
        (discard-gui-event-tracer! trace-state)
        (set! trace-state #f))
      (set! trace-output-path (next-trace-output-path event-trace-path))
      (set! trace-state (start-gui-event-tracer trace-output-path))
      (set! trace-auto-save-timer
            (new timer%
                 [notify-callback
                  (lambda ()
                    (set! trace-auto-save-timer #f)
                    (save-event-trace!))]))
      (send trace-auto-save-timer start 5000 #t)
      (eprintf "IK+ event trace started: ~a (auto-save in 5 s)~n"
               trace-output-path)))

  (define (reset-timing-diagnostics!)
    ;; The explicit full GC on R is not an in-gameplay timing outlier.
    (set! frame-gap-count 0)
    (set! frame-gap-next 0)
    (set! last-render-finished-ms #f)
    (set! gc-baseline-ms (current-gc-milliseconds))
    (set! last-render-gc-ms gc-baseline-ms)
    (set! long-gaps-with-gc 0)
    (set! max-timer-gap-ms 0.0)
    (set! extra-catch-up-ticks 0)
    (set! catch-up-bursts 0))

  (define (recent-frame-gap-stats)
    (if (zero? frame-gap-count)
        (values #f #f)
        (let* ([ordered (sort (for/list ([i (in-range frame-gap-count)])
                                (vector-ref frame-gaps i)) <)]
               [p95-index (sub1 (inexact->exact
                                 (ceiling (* 0.95 frame-gap-count))))])
          (values (list-ref ordered p95-index) (last ordered)))))

  (define (format-milliseconds value)
    (if value (real->decimal-string value 1) "n/a"))

  (define (record-render! started)
    (define finished (current-inexact-monotonic-milliseconds))
    (define gc-now (current-gc-milliseconds))
    (when (and (not paused?) last-render-finished-ms)
      (define gap (max 0.0 (- finished last-render-finished-ms)))
      (vector-set! frame-gaps frame-gap-next gap)
      (set! frame-gap-next (modulo (add1 frame-gap-next) frame-gap-capacity))
      (set! frame-gap-count (min frame-gap-capacity (add1 frame-gap-count)))
      ;; A correlation, not proof that GC caused the long callback interval.
      (when (and (> gap 30.0) (> gc-now last-render-gc-ms))
        (set! long-gaps-with-gc (add1 long-gaps-with-gc))))
    ;; Explicit paused/manual frames are not samples of a running game.
    (set! last-render-finished-ms (and (not paused?) finished))
    (set! last-render-gc-ms gc-now)
    (set! last-render-ms (- finished started))
    (set! frame-count (add1 frame-count))
    (define elapsed (- finished fps-start-ms))
    (when (>= elapsed 1000.0)
      (set! callback-rate (/ (* 1000.0 frame-count) elapsed))
      (set! frame-count 0)
      (set! fps-start-ms finished)))

  (define (request-frame!)
    (when (and view (not closed?) (not failed?))
      (when trace-state
        (define moment (current-inexact-milliseconds))
        (trace-gui-span! trace-state 'request-render moment moment))
      (if gpu? (send view request-gpu-render) (send view refresh))))

  (define (reset-clock!)
    (set! remainder-ms 0.0)
    (set! previous-ms (current-inexact-monotonic-milliseconds)))

  (define (play-retail-effect! effect)
    (when sounds?
      ;; $1698-$16B0 varies the Paula period with the number spawned.
      ;; Pre-exported WAV tiers preserve original PCM and approximate pitch.
      (define tier (min 3 (quotient (world-spawned simulation) 20)))
      (define path (build-path sound-directory
                               (format "~a_tier~a.wav" effect tier)))
      (with-handlers ([exn:fail?
                       (lambda (e)
                         (eprintf "IK+ sound unavailable: ~a\n" (exn-message e))
                         (set! sounds? #f))])
        (unless (play-sound path #t)
          (set! sounds? #f)))))

  ;; Some Racket GUI versions reject multiline message% labels. Use one
  ;; native message% per line, updating only those whose text has changed.
  (define (make-diagnostic-lines parent count)
    (for/vector ([_ (in-range count)])
      (new message% [parent parent] [label " "] [auto-resize #t])))

  (define (set-diagnostic-lines! controls content)
    (define lines (string-split content "\n" #:trim? #f))
    (when (> (length lines) (vector-length controls))
      (error 'set-diagnostic-lines! "too many diagnostic lines: ~a" (length lines)))
    (define displayed
      (append lines (make-list (- (vector-length controls) (length lines)) " ")))
    (for ([control (in-vector controls)] [line (in-list displayed)])
      (define visible-line (if (string=? line "") " " line))
      (unless (string=? (send control get-label) visible-line)
        (send control set-label visible-line))))

  (define (diagnostics-visible?)
    (and debug-window (send debug-window is-shown?)))

  (define (refresh-labels!)
    ;; Diagnostic labels share the GUI eventspace with the game. When hidden,
    ;; skip *all* string formatting, message% updates and layout work.
    (when (diagnostics-visible?)
      (set! last-diagnostics-refresh-ms
            (current-inexact-monotonic-milliseconds))
      (when tick-label
      (set-diagnostic-lines! tick-label
            (format "PAL tick: ~a\nElapsed: ~a s\nSpawned: ~a / 64\nLive: ~a / 4\nNext speed (8.8 hex): $~a\nGravity: ~a / 256\nShield deflections: ~a\nBonus score: ~a pts\nAudio: ~a\nMode: ~a"
                    (world-frame simulation)
                    (real->decimal-string (/ (world-frame simulation) 50.0) 2)
                    (world-spawned simulation)
                    (length (world-snapshot simulation))
                    (number->string (world-speed simulation) 16)
                    (world-gravity simulation)
                    (bonus-score-deflections progress)
                    (bonus-score-points progress)
                    (if sounds? "original samples" "OFF")
                    (cond [failed? "rendering failed"]
                          [(world-hit? simulation) "ROUND OVER (HIT) — press R"]
                          [(bonus-score-survival-awarded? progress) "SURVIVED! +5000 points"]
                          [(world-finished? simulation) "FINISHED"]
                          [paused? "PAUSED"] [else "RUNNING"]))))
      (when shield-label
      (set-diagnostic-lines! shield-label
            (format "SHIELD & FIGHTER\nPose: ~a / 6\nShield view: ~a\nShield screen: (~a, ~a)\nFighter frame: ~a\nMirrored: ~a\nPixel collisions: ~a\nFighter hits: ~a"
                    (shield-state defender)
                    (vector-ref '#("left side" "front" "right side")
                                (shield-view-index defender))
                    (shield-screen-x defender)
                    (shield-screen-y defender)
                    (shield-fighter-frame defender)
                    (if (shield-fighter-mirrored? defender) "yes" "no")
                    (if collisions? "on (retail 1-bit model)" "off")
                    (if player-hit? "on (scene masks provisional)" "off"))))
      (when ball-label
      (define b (vector-ref (world-balls simulation) selected-slot))
      (set-diagnostic-lines! ball-label
            (if b
                (format "SLOT ~a\nPosition: (~a, ~a)\nX raw: ~a\nY raw: ~a\nVX raw: ~a\nVY raw: ~a\nVariant: ~a\nPhase: ~a / 8\nFlags (hex): $~a\nBounces: ~a"
                        selected-slot (ball-screen-x b) (ball-screen-y b)
                        (ball-x b) (ball-y b)
                        (ball-vx b) (ball-vy b)
                        (vector-ref variant-labels (ball-sprite b))
                        (ball-phase b)
                        (number->string (ball-flags b) 16)
                        (ball-bounces b))
                (format "SLOT ~a\nEmpty" selected-slot))))
      (when perf-label
        (let-values ([(gap-p95 gap-max) (recent-frame-gap-stats)])
          (set-diagnostic-lines! perf-label
                (format "RENDERER\n~a / ~a\nNative: 320 x 200\nScale: ~ax\nCallback: ~a ms\nCallbacks/s: ~a\nGap samples: ~a / 256\nGap p95: ~a ms\nGap max: ~a ms\nTimer gap max: ~a ms\nCatch-up ticks: ~a (~a bursts)\nGC CPU since R: ~a ms\nLong gaps + GC: ~a"
                        (if gpu? "GPU" "CPU")
                        (if gpu? (send view get-gpu-backend) "raster")
                        current-scale
                        (real->decimal-string last-render-ms 2)
                        (real->decimal-string callback-rate 1)
                        frame-gap-count
                        (format-milliseconds gap-p95)
                        (format-milliseconds gap-max)
                        (format-milliseconds max-timer-gap-ms)
                        extra-catch-up-ticks catch-up-bursts
                        (- (current-gc-milliseconds) gc-baseline-ms)
                        long-gaps-with-gc))))
      (when background-label
        (set-diagnostic-lines!
         background-label
         (format "BACKGROUND (~a)\nFalling: ~a  Settled: ~a / 30\nWorm: ~a\nPeriscope: ~a\nRetail ambient: ~a"
                 (if background-animations? "ON" "OFF")
                 (length (background-world-flying background-state))
                 (length (background-world-grounded background-state))
                 (if (background-world-worm-x background-state) "ACTIVE" "idle")
                 (if periscope-showcase-state
                     "8 RETAIL SCRIPTS"
                     (or (background-periscope-frame background-state)
                         "idle"))
                 (let ([view (ambient-current-view ambient-state)])
                   (if view (format "~a / site ~a / pose ~a"
                                    (ambient-view-kind view)
                                    (ambient-view-location view)
                                    (ambient-view-frame view))
                       "idle")))))
      (when periscope-capture-label
        (set-diagnostic-lines! periscope-capture-label
                               periscope-capture-status))
      (when ambient-capture-label
        (set-diagnostic-lines! ambient-capture-label
                               ambient-capture-status))))

  (define (maybe-refresh-labels!)
    ;; The 50 Hz timer calls this, but GUI diagnostics only update at 4 Hz.
    ;; Explicit user actions still refresh immediately when the window is open.
    (when (and (diagnostics-visible?)
               (>= (- (current-inexact-monotonic-milliseconds)
                      last-diagnostics-refresh-ms)
                   diagnostics-refresh-ms))
      (define began (and trace-state (current-inexact-milliseconds)))
      (when periscope-showcase-state
        (set! periscope-capture-status
              (format "Recording: ~a / ~a (50 Hz)"
                      periscope-recorded-count periscope-capture-length)))
      (when ambient-showcase-state
        (set! ambient-capture-status
              (format "Ambient recording: ~a / ~a (50 Hz)"
                      ambient-recorded-count ambient-capture-target)))
      (refresh-labels!)
      (when trace-state
        (trace-gui-span! trace-state 'diagnostics-refresh
                         began (current-inexact-milliseconds)))))

  (define (remember-positions!)
    (for ([slot (in-range 4)])
      (define b (vector-ref (world-balls simulation) slot))
      ;; A slot may be freed and immediately reused by a different ball.
      ;; Compare object identity to avoid drawing a false connecting segment.
      (define previous-points
        (if (eq? b (vector-ref last-objects slot))
            (vector-ref histories slot)
            '()))
      (vector-set! histories slot
                   (if b
                       (take (cons (cons (ball-screen-x b) (ball-screen-y b))
                                   previous-points)
                             (min max-trail-points (add1 (length previous-points))))
                       '()))
      (vector-set! last-objects slot b)))

  (define (single-step!)
    (unless (or failed? closed?)
      ;; Scenery continues after a round ends, just as the fixed backdrop
      ;; remains on screen. It never touches the projectile RNG/state.
      (background-step! background-state)
      ;; Original type-3 cleanup restores five original-backdrop rows over
      ;; the LAST crawler pose; those pixels of landed leaves do not return.
      (let ([previous-ambient-view (ambient-current-view ambient-state)])
        (when (and previous-ambient-view
                   (eq? (ambient-view-kind previous-ambient-view) 'crawler))
          (background-erase-crawler-trail!
           background-state
           (ambient-view-x previous-ambient-view)
           (ambient-view-y previous-ambient-view))))
      (ambient-step! ambient-state)
      (water-step! water-state)
      (foam-step! foam-state water-state)
      ;; Sample EACH logical 50 Hz tick, not GPU callbacks. A skipped or
      ;; coalesced render therefore cannot omit poses from the diagnostic.
      (when periscope-showcase-state
        (periscope-showcase-step! periscope-showcase-state)
        (vector-set!
         periscope-recording periscope-recorded-count
         (captured-periscope-frame
          (periscope-showcase-views periscope-showcase-state)
          (for/vector ([row (in-range 21)])
            (water-reflection-frame water-state row))
          (for/vector ([point (in-range 18)])
            (water-shore-frame water-state point))))
        (set! periscope-recorded-count (add1 periscope-recorded-count))
        (when (= periscope-recorded-count periscope-capture-length)
          (set! periscope-showcase-state #f)
          (begin-periscope-export!)))
      (when ambient-showcase-state
        (when leaf-panel-backgrounds
          ;; Erase yesterday's crawler footprint, before its next pose.
          ;; Capture each panel's independent leaf pixels without affecting
          ;; normal scenery, the other ambient captures or the ball game.
          (for ([panel (in-list leaf-ambient-panels)]
                [bg (in-vector leaf-panel-backgrounds)])
            (for ([view (in-list (ambient-showcase-views ambient-showcase-state panel))])
              (background-erase-crawler-trail!
               bg (ambient-view-x view) (ambient-view-y view)))))
        (ambient-showcase-step! ambient-showcase-state)
        (vector-set!
         ambient-recording ambient-recorded-count
         (captured-ambient-frame
          (for/list ([panel (in-list ambient-panel-order)])
            (ambient-showcase-views ambient-showcase-state panel))
          (for/vector ([row (in-range 21)])
            (water-reflection-frame water-state row))
          (for/vector ([point (in-range 18)])
            (water-shore-frame water-state point))
          (and leaf-panel-backgrounds
               (for/list ([bg (in-vector leaf-panel-backgrounds)])
                 (append*
                  (for/list ([leaf (in-list (background-world-grounded bg))])
                    (grounded-leaf-visible-parts leaf)))))))
        (set! ambient-recorded-count (add1 ambient-recorded-count))
        (when (= ambient-recorded-count ambient-capture-target)
          (set! ambient-showcase-state #f)
          (begin-ambient-export!)))
      (unless (world-finished? simulation)
      (shield-step! defender
                    (joystick-nibble (hash-ref held 'left #f)
                                     (hash-ref held 'right #f)
                                     (hash-ref held 'up #f)
                                     (hash-ref held 'down #f)))
      ;; Retail $1BDBA intersects 12 projectile rows against independent
      ;; one-bit fighter and shield buffers, then prioritizes shield D1.
      ;; Source-visible sprite alpha approximates the uncaptured live RAM.
      (when collisions?
        (for ([event (in-list (apply-retail-buffer-collisions!
                               simulation defender collision-buffers
                               #:player-hit? player-hit?))])
          (case (car event)
            [(shield)
             (bonus-score-deflection! progress)
             (let ([b (vector-ref (world-balls simulation) (cadr event))])
               (play-retail-effect!
                (if (and b (= (ball-sprite b) 7)) 'head 'deflect)))]
            [(player) (play-retail-effect! 'hit)]
            [else (void)])))
      (world-step! simulation)
      (bonus-score-update-end! progress simulation)
      (remember-positions!))))

  (define (toggle-pause!)
    (set! paused? (not paused?))
    ;; Do not treat an intentional pause as a missed render callback.
    (set! last-render-finished-ms #f)
    (reset-clock!)
    (when pause-button
      (send pause-button set-label (if paused? "Resume" "Pause")))
    (refresh-labels!)
    (request-frame!))

  (define (advance-one!)
    (unless paused? (toggle-pause!))
    (single-step!)
    (refresh-labels!)
    (request-frame!))

  (define (next-spawn!)
    (unless paused? (toggle-pause!))
    (define previous-count (world-spawned simulation))
    (let loop ([remaining 2000])
      (when (and (positive? remaining)
                 (= previous-count (world-spawned simulation))
                 (not (world-finished? simulation)))
        (single-step!)
        (loop (sub1 remaining))))
    (refresh-labels!)
    (request-frame!))

  (define (restart!)
    (cancel-periscope-capture!)
    (cancel-ambient-capture!)
    (set! simulation (make-world #:seed #x1988))
    (set! background-state (make-background-world #:seed #x1988))
    (set! ambient-state (make-ambient-world #:seed #x1992))
    (set! water-state (make-water-world))
    (set! foam-state (make-foam-world #:seed #x18f44))
    (set! defender (make-shield))
    (set! histories (make-vector 4 '()))
    (set! last-objects (make-vector 4 #f))
    (set! progress (make-bonus-score))
    (set! selected-slot 0)
    ;; All per-round data from the old simulation is now unreachable.
    ;; Reclaim it between rounds, never during a 50 Hz gameplay update.
    ;; GPU textures and persistent rendering surfaces remain in use.
    (collect-garbage)
    (reset-timing-diagnostics!)
    (set! frame-count 0)
    (set! callback-rate 0.0)
    (set! fps-start-ms (current-inexact-monotonic-milliseconds))
    ;; Discard the GC pause instead of counting it as time to catch up.
    (reset-clock!)
    (start-event-trace-session!)
    (when trace-state
      (define moment (current-inexact-milliseconds))
      (trace-gui-span! trace-state 'game-restart moment moment))
    (refresh-labels!)
    (request-frame!))

  (define (deflect-selected!)
    ;; Deliberately an injected debug action, NOT a simulated shield collision.
    (when (vector-ref (world-balls simulation) selected-slot)
      (world-deflect! simulation selected-slot)
      (refresh-labels!)
      (request-frame!)))

  (define (toggle-collisions!)
    (set! collisions? (not collisions?))
    (refresh-labels!)
    (request-frame!))

  (define (toggle-player-hit!)
    (set! player-hit? (not player-hit?))
    (refresh-labels!)
    (request-frame!))

  (define (toggle-sounds!)
    (set! sounds? (not sounds?))
    (refresh-labels!))

  (define (set-trails! enabled?)
    (set! trails? enabled?)
    (when trails-control (send trails-control set-value trails?))
    (request-frame!))

  (define (set-selection-box! enabled?)
    (set! selection-box? enabled?)
    (when selection-box-control
      (send selection-box-control set-value selection-box?))
    (request-frame!))

  (define (toggle-trails!) (set-trails! (not trails?)))
  (define (toggle-selection-box!) (set-selection-box! (not selection-box?)))

  (define (set-fps-visible! enabled?)
    (set! fps-visible? enabled?)
    (when fps-control (send fps-control set-value fps-visible?))
    (request-frame!))

  (define (toggle-fps-visible!) (set-fps-visible! (not fps-visible?)))

  (define (set-background-animations! enabled?)
    (set! background-animations? enabled?)
    (when background-animation-control
      (send background-animation-control set-value background-animations?))
    (refresh-labels!)
    (request-frame!))

  (define (set-periscope-capture-status! message)
    (set! periscope-capture-status message)
    (refresh-labels!))

  (define (stop-periscope-export!)
    (when periscope-export-timer
      (send periscope-export-timer stop)
      (set! periscope-export-timer #f))
    (when periscope-export-surface
      (skia-close! periscope-export-surface)
      (set! periscope-export-surface #f)))

  (define (cancel-periscope-capture!)
    (define busy? (or periscope-recording periscope-export-timer))
    (define exporting? (or periscope-export-timer periscope-export-surface))
    (stop-periscope-export!)
    (set! periscope-showcase-state #f)
    (set! periscope-recording #f)
    (set! periscope-recorded-count 0)
    (set! periscope-export-index 0)
    (when periscope-button (send periscope-button enable #t))
    (when ambient-button (send ambient-button enable #t))
    (when bird-button (send bird-button enable #t))
    (when pacman-button (send pacman-button enable #t))
    (when exporting?
      (reset-clock!)
      (when (and ticker (not closed?)) (send ticker start 16)))
    (when busy?
      ;; Preserve any already written frames: never remove partial captures.
      (set-periscope-capture-status! "Periscope capture: canceled")))

  (define (next-periscope-output-directory)
    (make-directory* periscope-capture-root)
    (let loop ([serial 1])
      (define directory
        (build-path periscope-capture-root
                    (format "periscopes-~a"
                            (~r serial #:min-width 3 #:pad-string "0"))))
      (if (or (directory-exists? directory) (file-exists? directory))
          (loop (add1 serial))
          directory)))

  (define (write-periscope-csv! directory)
    (call-with-output-file (build-path directory "frames.csv")
      (lambda (out)
        (displayln "frame,tick,location,script,draw_x,draw_y,pose,wake" out)
        (for ([i (in-range periscope-capture-length)])
          (define frame (vector-ref periscope-recording i))
          (define poses
            (for/hash ([p (in-list (captured-periscope-frame-views frame))])
              (values (periscope-view-location-index p) p)))
          (for ([location (in-range 8)])
            (define p (hash-ref poses location #f))
            (fprintf out "~a,~a,~a,~a,~a,~a,~a,~a\n"
                     (add1 i) (add1 i) location location
                     (if p (- (periscope-view-x p) 32) "")
                     (if p (periscope-view-y p) "")
                     (cond [(not p) "END"]
                           [(= (periscope-view-frame p) #xfe) "FE"]
                           [else (periscope-view-frame p)])
                     (if p (periscope-view-wake p) "")))))
      #:exists 'error))

  (define (draw-captured-periscope-frame! frame)
    ;; Replay the exact same pre-masked Skia atlas rectangles and recorded
    ;; shoreline/sun variants, onto the 320x200 CPU surface. There is NO
    ;; GPU readback, video timing dependency, or re-simulation of the scripts.
    ;; Hide the fighter and projectiles to expose all eight water positions.
    (define canvas (surface-canvas periscope-export-surface))
    (canvas-clear! canvas "#111822")
    (draw-image-rect canvas (art-set-background cpu-art)
                     0 0 scene-width scene-height #:sampling 'nearest)
    (draw-water-effects canvas cpu-art frame)
    (draw-periscope-views canvas (art-set-effects cpu-art)
                          (captured-periscope-frame-views frame))
    (draw-periscope-location-numbers
     canvas (art-set-font cpu-art)
     (captured-periscope-frame-views frame)))

  (define (finish-periscope-export! [failure #f])
    (define destination periscope-export-directory)
    (stop-periscope-export!)
    (set! periscope-showcase-state #f)
    (set! periscope-recording #f)
    (when periscope-button (send periscope-button enable #t))
    (when ambient-button (send ambient-button enable #t))
    (when bird-button (send bird-button enable #t))
    (when pacman-button (send pacman-button enable #t))
    (unless auto-periscope-capture?
      (reset-clock!)
      (when (and ticker (not closed?)) (send ticker start 16)))
    (if failure
        (begin
          (set-periscope-capture-status! "Capture export FAILED; see terminal")
          (eprintf "IK+ periscope capture incomplete in ~a: ~a\n"
                   destination (exn-message failure)))
        (begin
          (set-periscope-capture-status! "Saved 512 PNGs, frames.csv and view.html")
          (eprintf "IK+ periscope capture ready: ~a\n" destination)))
    (if auto-periscope-capture?
        (begin
          (close-window!)
          (exit (if failure 1 0)))
        (request-frame!)))

  (define (export-periscope-batch!)
    (with-handlers ([exn:fail? (lambda (error)
                                 (finish-periscope-export! error))])
      (for ([_ (in-range periscope-export-batch)]
            #:break (= periscope-export-index periscope-capture-length))
        (define frame
          (vector-ref periscope-recording periscope-export-index))
        (define file
          (build-path periscope-export-directory
                      (format "frame-~a.png"
                              (~r (add1 periscope-export-index)
                                  #:min-width 4 #:pad-string "0"))))
        (draw-captured-periscope-frame! frame)
        (unless (send (surface->bitmap periscope-export-surface)
                      save-file file 'png)
          (error 'periscope-capture "could not write ~a" file))
        (set! periscope-export-index (add1 periscope-export-index)))
      (when (or (= periscope-export-index periscope-capture-length)
                (zero? (modulo periscope-export-index 16)))
        (set-periscope-capture-status!
         (format "Exporting PNGs: ~a / ~a"
                 periscope-export-index periscope-capture-length)))
      (when (= periscope-export-index periscope-capture-length)
        (finish-periscope-export!))))

  (define (begin-periscope-export!)
    ;; Freeze the 50 Hz timer during deferred PNG encoding, then restore it.
    ;; GUI export works in four-frame batches to keep the window responsive.
    (when ticker (send ticker stop))
    (with-handlers ([exn:fail? (lambda (error)
                                 (finish-periscope-export! error))])
      (make-directory periscope-export-directory)
      (write-periscope-csv! periscope-export-directory)
      (copy-file periscope-viewer-path
                 (build-path periscope-export-directory "view.html"))
      (set! periscope-export-surface
            (make-surface scene-width scene-height))
      (set-periscope-capture-status! "Exporting PNGs: 0 / 512")
      (set! periscope-export-timer
            (new timer% [notify-callback export-periscope-batch!]))
      (send periscope-export-timer start 10)))

  (define (preview-periscope!)
    (unless (or periscope-recording periscope-export-timer
                ambient-recording ambient-export-timer)
      (with-handlers ([exn:fail?
                       (lambda (error)
                         (set-periscope-capture-status!
                          "Could not start capture; see terminal")
                         (eprintf "IK+ periscope capture: ~a\n"
                                  (exn-message error))
                         (when auto-periscope-capture?
                           (close-window!)
                           (exit 1)))])
        (set! periscope-export-directory (next-periscope-output-directory))
        (set! periscope-recording (make-vector periscope-capture-length #f))
        (set! periscope-recorded-count 0)
        (set! periscope-export-index 0)
        (set! periscope-showcase-state (make-periscope-showcase))
        (set! scenery? #t)
        (set-background-animations! #t)
        (when paused? (toggle-pause!))
        (when periscope-button (send periscope-button enable #f))
        (when ambient-button (send ambient-button enable #f))
        (when bird-button (send bird-button enable #f))
        (when pacman-button (send pacman-button enable #f))
        (set-periscope-capture-status! "Recording: 0 / 512 (50 Hz)")
        (eprintf "IK+ periscope capture started: 512 ticks (10.24 s) -> ~a\n"
                 periscope-export-directory)
        (request-frame!))))

  (define (set-ambient-capture-status! message)
    (set! ambient-capture-status message)
    (refresh-labels!))

  (define (stop-ambient-export!)
    (when ambient-export-timer
      (send ambient-export-timer stop)
      (set! ambient-export-timer #f))
    (when ambient-export-surface
      (skia-close! ambient-export-surface)
      (set! ambient-export-surface #f)))

  (define (cancel-ambient-capture!)
    (define busy? (or ambient-recording ambient-export-timer))
    (define exporting? (or ambient-export-timer ambient-export-surface))
    (stop-ambient-export!)
    (set! ambient-showcase-state #f)
    (set! ambient-recording #f)
    (set! ambient-recorded-count 0)
    (set! ambient-export-index 0)
    (when ambient-button (send ambient-button enable #t))
    (when bird-button (send bird-button enable #t))
    (when pacman-button (send pacman-button enable #t))
    (when leaf-button (send leaf-button enable #t))
    (when periscope-button (send periscope-button enable #t))
    (set! leaf-panel-backgrounds #f)
    (when exporting?
      (reset-clock!)
      (when (and ticker (not closed?)) (send ticker start 16)))
    (when busy?
      ;; A canceled export never overwrites or deletes its partial files.
      (set-ambient-capture-status! "Ambient capture: canceled")))

  (define (next-ambient-output-directory)
    (define birds? (eq? (car ambient-panel-order) 'bird-0))
    (define pacman? (eq? (car ambient-panel-order) 'pacman-0))
    (define leaf? (eq? (car ambient-panel-order) 'leaf-0))
    (define root (cond [birds? bird-capture-root]
                       [pacman? pacman-capture-root]
                       [leaf? leaf-capture-root]
                       [else ambient-capture-root]))
    (make-directory* root)
    (let loop ([serial 1])
      (define directory
        (build-path root
                    (format "~a-~a"
                            (cond [birds? "birds"]
                                  [pacman? "pacman"]
                                  [leaf? "leaf-eater"]
                                  [else "ambient"])
                            (~r serial #:min-width 3 #:pad-string "0"))))
      (if (or (directory-exists? directory) (file-exists? directory))
          (loop (add1 serial))
          directory)))

  (define (write-ambient-csv! directory)
    (call-with-output-file (build-path directory "frames.csv")
      (lambda (out)
        (displayln
         "frame,tick,panel,location,kind,direction,draw_x,draw_y,pose,cycle,thread_x,thread_start_y,thread_end_y_exclusive"
         out)
        (for ([tick (in-range ambient-capture-target)])
          (define frame (vector-ref ambient-recording tick))
          (for ([panel (in-list ambient-panel-order)]
                [views (in-list (captured-ambient-frame-panels frame))])
            (define locations
              (cond [(memq panel '(fish-left fish-right)) 16]
                    [(memq panel pacman-ambient-panels) 4]
                    [(memq panel leaf-ambient-panels) 1]
                    [else 8]))
            (define poses
              (for/hash ([view (in-list views)])
                (values (ambient-view-location view) view)))
            (for ([location (in-list
                             (if (memq panel leaf-ambient-panels)
                                 (list (list-ref leaf-ambient-sites
                                                 (index-of leaf-ambient-panels panel)))
                                 (range locations)))])
              (define view (hash-ref poses location #f))
              (define silk (and view (ambient-spider-thread view)))
              (fprintf out "~a,~a,~a,~a,~a,~a,~a,~a,~a,~a,~a,~a,~a\n"
                       (add1 tick) (add1 tick) panel location
                       (if view (ambient-view-kind view) "END")
                       (if view (ambient-view-direction view) "")
                       (if view (ambient-view-x view) "")
                       (if view (ambient-view-y view) "")
                       (if view (ambient-view-frame view) "END")
                       (if view (ambient-view-cycle view) "")
                       (if silk (first silk) "")
                       (if silk (second silk) "")
                       (if silk (third silk) ""))))))
      #:exists 'error))

  (define (draw-captured-ambient-frame! frame)
    ;; Four independent 320x200 panels for fish/spiders/crawlers, bird
    ;; silhouettes, or the four retail Pac-Man travel phases.
    (define canvas (surface-canvas ambient-export-surface))
    (canvas-clear! canvas "#111822")
    (for ([panel (in-list ambient-panel-order)]
          [views (in-list (captured-ambient-frame-panels frame))]
          [i (in-naturals)])
      (with-canvas-state canvas
        (canvas-translate! canvas (* scene-width (remainder i 2))
                           (* scene-height (quotient i 2)))
        (canvas-clip-rect! canvas 0 0 scene-width scene-height)
        (draw-image-rect canvas (art-set-background cpu-art)
                         0 0 scene-width scene-height #:sampling 'nearest)
        (draw-water-effects canvas cpu-art frame)
        (when (captured-ambient-frame-leaf-parts frame)
          (draw-leaf-parts canvas (art-set-effects cpu-art)
                           (list-ref (captured-ambient-frame-leaf-parts frame) i)))
        (draw-ambient-views canvas cpu-art views)
        (draw-ambient-location-numbers canvas (art-set-font cpu-art) views)
        (draw-retail-text canvas (art-set-font cpu-art)
                          (case panel
                            [(fish-left) "FISH LEFT"]
                            [(fish-right) "FISH RIGHT"]
                            [(spider) "SPIDERS"]
                            [(crawler) "CRAWLERS"]
                            [(bird-0) "BIRD VARIANT 0"]
                            [(bird-1) "BIRD VARIANT 1"]
                            [(bird-2) "BIRD VARIANT 2"]
                            [(bird-3) "BIRD VARIANT 3"]
                            [(pacman-0) "PAC PATH 0"]
                            [(pacman-1) "PAC PATH 1"]
                            [(pacman-2) "PAC PATH 2"]
                            [(pacman-3) "PAC PATH 3"]
                            [(leaf-0) "LEAF EATER SITE 3"]
                            [(leaf-1) "LEAF EATER SITE 6"]
                            [(leaf-2) "CONTROL SITE 4"]
                            [(leaf-3) "CONTROL SITE 7"])
                          4 2))))

  (define (finish-ambient-export! [failure #f])
    (define destination ambient-export-directory)
    (stop-ambient-export!)
    (set! ambient-showcase-state #f)
    (set! ambient-recording #f)
    (when ambient-button (send ambient-button enable #t))
    (when bird-button (send bird-button enable #t))
    (when pacman-button (send pacman-button enable #t))
    (when leaf-button (send leaf-button enable #t))
    (when periscope-button (send periscope-button enable #t))
    (set! leaf-panel-backgrounds #f)
    (unless auto-ambient-capture?
      (reset-clock!)
      (when (and ticker (not closed?)) (send ticker start 16)))
    (if failure
        (begin
          (set-ambient-capture-status! "Ambient export FAILED; see terminal")
          (eprintf "IK+ ambient capture incomplete in ~a: ~a\n"
                   destination (exn-message failure)))
        (begin
          (set-ambient-capture-status!
           (format "Saved ~a four-panel PNGs, frames.csv and view.html"
                   ambient-capture-target))
          (eprintf "IK+ ambient capture ready: ~a\n" destination)))
    (if auto-ambient-capture?
        (begin (close-window!) (exit (if failure 1 0)))
        (request-frame!)))

  (define (export-ambient-batch!)
    (with-handlers ([exn:fail? (lambda (error)
                                 (finish-ambient-export! error))])
      (for ([_ (in-range ambient-export-batch)]
            #:break (= ambient-export-index ambient-capture-target))
        (define frame (vector-ref ambient-recording ambient-export-index))
        (define file
          (build-path ambient-export-directory
                      (format "frame-~a.png"
                              (~r (add1 ambient-export-index)
                                  #:min-width 4 #:pad-string "0"))))
        (draw-captured-ambient-frame! frame)
        (unless (send (surface->bitmap ambient-export-surface)
                      save-file file 'png)
          (error 'ambient-capture "could not write ~a" file))
        (set! ambient-export-index (add1 ambient-export-index)))
      (when (or (= ambient-export-index ambient-capture-target)
                (zero? (modulo ambient-export-index 16)))
        (set-ambient-capture-status!
         (format "Exporting PNGs: ~a / ~a"
                 ambient-export-index ambient-capture-target)))
      (when (= ambient-export-index ambient-capture-target)
        (finish-ambient-export!))))

  (define (begin-ambient-export!)
    (when ticker (send ticker stop))
    (with-handlers ([exn:fail? (lambda (error)
                                 (finish-ambient-export! error))])
      (make-directory ambient-export-directory)
      (write-ambient-csv! ambient-export-directory)
      (copy-file (case (car ambient-panel-order)
                   [(bird-0) bird-viewer-path]
                   [(pacman-0) pacman-viewer-path]
                   [(leaf-0) leaf-viewer-path]
                   [else ambient-viewer-path])
                 (build-path ambient-export-directory "view.html"))
      (set! ambient-export-surface
            (make-surface (* 2 scene-width) (* 2 scene-height)))
      (set-ambient-capture-status!
       (format "Exporting PNGs: 0 / ~a" ambient-capture-target))
      (set! ambient-export-timer
            (new timer% [notify-callback export-ambient-batch!]))
      (send ambient-export-timer start 10)))

  (define (preview-ambient! [birds? #f] [pacman? #f] [leaf? #f])
    (unless (or ambient-recording ambient-export-timer
                periscope-recording periscope-export-timer)
      (with-handlers ([exn:fail?
                       (lambda (error)
                         (set-ambient-capture-status!
                          "Could not start ambient capture; see terminal")
                         (eprintf "IK+ ambient capture: ~a\n"
                                  (exn-message error))
                         (when auto-ambient-capture?
                           (close-window!)
                           (exit 1)))])
        (set! ambient-panel-order
              (cond [birds? bird-ambient-panels]
                    [pacman? pacman-ambient-panels]
                    [leaf? leaf-ambient-panels]
                    [else standard-ambient-panels]))
        (set! ambient-capture-target
              (cond [pacman? pacman-capture-length]
                    [leaf? leaf-capture-length]
                    [else ambient-capture-length]))
        (set! ambient-export-directory (next-ambient-output-directory))
        (set! ambient-recording (make-vector ambient-capture-target #f))
        (set! ambient-recorded-count 0)
        (set! ambient-export-index 0)
        (set! ambient-showcase-state
              (cond [birds? (make-bird-showcase)]
                    [pacman? (make-pacman-showcase)]
                    [leaf? (make-leaf-crawler-showcase)]
                    [else (make-ambient-showcase)]))
        (set! leaf-panel-backgrounds
              (and leaf?
                   (for/vector ([i (in-range 4)])
                     (define bg (make-background-world #:seed (+ #x1988 i)))
                     (background-force-leaf-pile! bg)
                     bg)))
        (set! scenery? #t)
        (set-background-animations! #t)
        (when paused? (toggle-pause!))
        (when ambient-button (send ambient-button enable #f))
        (when bird-button (send bird-button enable #f))
        (when pacman-button (send pacman-button enable #f))
        (when leaf-button (send leaf-button enable #f))
        (when periscope-button (send periscope-button enable #f))
        (set-ambient-capture-status!
         (format "Recording: 0 / ~a (50 Hz)" ambient-capture-target))
        (eprintf
         "IK+ ~a capture: ~a ticks (~a s) -> ~a\n"
         (cond [birds? "bird (all sites/variants)"]
               [pacman? "Pac-Man (all four travel phases)"]
               [leaf? "leaf-eating crawler (sites 3/6; controls 4/7)"]
               [else "fish/spider/crawler"])
         ambient-capture-target (/ ambient-capture-target 50.0)
         ambient-export-directory)
        (request-frame!))))

  (define (preview-worm!)
    (background-force-worm! background-state)
    (refresh-labels!)
    (request-frame!))

  (define (preview-retail-leaf-eater!)
    (background-force-leaf-pile! background-state)
    (ambient-force-crawler! ambient-state 3)
    (set-background-animations! #t)
    (refresh-labels!)
    (request-frame!))

  (define (save-event-trace!)
    (stop-trace-auto-save!)
    (when trace-state
      (define active-trace trace-state)
      (set! trace-state #f)
      (set! trace-output-path #f)
      (with-handlers ([exn:fail?
                       (lambda (exn)
                         (eprintf "IK+ could not save GUI trace: ~a\n"
                                  (exn-message exn)))])
        (finish-gui-event-tracer! active-trace))))

  (define (close-window!)
    (unless closed?
      (set! closed? #t)
      (when ticker (send ticker stop))
      (cancel-periscope-capture!)
      (cancel-ambient-capture!)
      ;; Retire GPU context children *before* closing the GPU presenter.
      (when gpu-scene (skia-close! gpu-scene) (set! gpu-scene #f))
      (when gpu-art (close-art-set! gpu-art) (set! gpu-art #f))
      (when raster-present (skia-close! raster-present) (set! raster-present #f))
      (when raster-scene (skia-close! raster-scene) (set! raster-scene #f))
      (close-art-set! cpu-art)
      (when (and gpu? view) (send view close))
      (when debug-window (send debug-window show #f))
      (when window (send window show #f))
      (save-event-trace!)))

  (define (render-error error)
    (unless failed?
      (set! failed? #t)
      (when ticker (send ticker stop))
      (eprintf "IK+ renderer: ~a\n"
               (if (exn? error) (exn-message error) error))
      (refresh-labels!)
      (when (or auto-periscope-capture? auto-ambient-capture?)
        (close-window!)
        (exit 1))))

  (define (viewport width height)
    (define scale (max 1 (inexact->exact
                          (floor (min (/ width scene-width)
                                      (/ height scene-height))))))
    (values scale
            (/ (- width (* scale scene-width)) 2)
            (/ (- height (* scale scene-height)) 2)))

  (define (draw-periscope-views canvas effects views)
    ;; One common blit path for live GPU/raster rendering and the frame
    ;; exporter. Source atlas rows are 30 masked cells per retail location.
    (unless (null? views)
      (define (masked-rect slot height)
        (list (* 16 (modulo slot 20))
              (+ 200 (* 9 (quotient slot 20)))
              16 height))
      (draw-atlas
       canvas effects
       (for*/list ([p (in-list views)] [wake? (in-list '(#f #t))])
         (make-atlas-transform (- (periscope-view-x p) 32)
                               (+ (periscope-view-y p)
                                  (if wake? 7 0))))
       (for*/list ([p (in-list views)] [wake? (in-list '(#f #t))])
         (define base (* (periscope-view-location-index p) 30))
         (define pose (periscope-view-frame p))
         (if wake?
             (masked-rect (+ base 23 (periscope-view-wake p)) 4)
             (masked-rect (+ base (if (= pose #xfe) 22 pose))
                          (if (= pose #xfe) 1 9))))
       #:sampling 'nearest)))

  (define (draw-periscope-location-numbers canvas font views)
    ;; Only the diagnostic annotates the eight locations / script IDs.
    (for ([p (in-list views)])
      (draw-retail-text canvas font
                        (number->string (periscope-view-location-index p))
                        (- (periscope-view-x p) 32)
                        (- (periscope-view-y p) 12))))

  (define (draw-leaf-parts canvas effects parts)
    (unless (null? parts)
      (draw-atlas canvas effects
                  (for/list ([part (in-list parts)])
                    (make-atlas-transform (first part) (second part)))
                  (for/list ([part (in-list parts)])
                    (drop part 2))
                  #:sampling 'nearest)))

  (define (draw-background-effects canvas art)
    (define effects (art-set-effects art))
    (define leaf-parts
      (append
       (for/list ([leaf (in-list (background-world-flying background-state))])
         (list (- (flying-leaf-x leaf) 32)
               (inexact->exact (round (flying-leaf-y leaf)))
               128 162 16 2))
       (append*
        (for/list ([leaf (in-list (background-world-grounded background-state))])
          (grounded-leaf-visible-parts leaf)))))
    ;; Source cell is two 16-pixel rows. Landed leaves retain the exact
    ;; missing-pixel mask left behind by the crawler's retail eraser.
    (draw-leaf-parts canvas effects leaf-parts)
    (define periscope-frame (background-periscope-frame background-state))
    (define views
      (cond [periscope-showcase-state
             (periscope-showcase-views periscope-showcase-state)]
            [periscope-frame
             (let ([destination
                    (background-periscope-position background-state)])
               (list (periscope-view
                      (background-periscope-location-index background-state)
                      (car destination) (cdr destination) periscope-frame
                      (background-periscope-wake-frame background-state))))]
            [else '()]))
    (draw-periscope-views canvas effects views)
    (when periscope-showcase-state
      (draw-periscope-location-numbers canvas (art-set-font art) views))
    (when (background-world-worm-x background-state)
      ;; A temporary pixel-sized caterpillar until its retail artwork is
      ;; positively identified. It clears leaves behind it as it moves left.
      (define wx (inexact->exact (round (background-world-worm-x background-state))))
      (define step (quotient (background-world-worm-age background-state) 5))
      (with-skia ([shade (make-paint #:color "#4A2410" #:style 'fill)]
                  [body (make-paint #:color "#CCAA66" #:style 'fill)]
                  [eye (make-paint #:color "#151515" #:style 'fill)])
        (for ([i (in-range 9)])
          (define xx (+ wx (* i 2)))
          (define yy (- 179 (if (< (modulo (+ step i) 8) 4) 2 0)))
          (draw-rect canvas xx (add1 yy) 3 3 shade)
          (draw-rect canvas xx yy 2 2 body))
        (draw-rect canvas (add1 wx) 176 1 1 eye))))

  (define (draw-ambient-views canvas art views)
    ;; Original sprite masks/colors are prebaked in the atlas. The spider's
    ;; descending silk is different: the original blitter retains one pixel
    ;; per previous top row instead of redrawing only its current 7x16 cell.
    ;; Replay those vertical pixels from the exact scanline Copper LUT.
    (define silk-pixels
      (append*
       (for/list ([view (in-list views)])
         (define thread (ambient-spider-thread view))
         (if thread
             (for/list ([y (in-range (second thread) (third thread))])
               (list (first thread) y (fourth thread)))
             '()))))
    (unless (null? silk-pixels)
      (draw-atlas canvas (art-set-foam art)
                  (for/list ([pixel (in-list silk-pixels)])
                    (make-atlas-transform (first pixel) (second pixel)))
                  (for/list ([pixel (in-list silk-pixels)])
                    (list (third pixel) (second pixel) 1 1))
                  #:sampling 'nearest))
    (unless (null? views)
      (draw-atlas canvas (art-set-ambient art)
                  (for/list ([view (in-list views)])
                    (make-atlas-transform (ambient-view-x view)
                                          (ambient-view-y view)))
                  (for/list ([view (in-list views)])
                    (ambient-source-rect view))
                  #:sampling 'nearest)))

  (define (draw-retail-ambient canvas art)
    (define views
      (if ambient-showcase-state
          (append*
           (for/list ([panel (in-list ambient-panel-order)])
             (ambient-showcase-views ambient-showcase-state panel)))
          (let ([view (ambient-current-view ambient-state)])
            (if view (list view) '()))))
    (draw-ambient-views canvas art views))

  (define (draw-ambient-location-numbers canvas font views)
    (for ([view (in-list views)])
      (draw-retail-text canvas font
                        (number->string (ambient-view-location view))
                        (+ 14 (ambient-view-x view))
                        (- (ambient-view-y view) 9))))

  (define (recorded-water-reflection frame)
    (if (captured-periscope-frame? frame)
        (captured-periscope-frame-reflection frame)
        (captured-ambient-frame-reflection frame)))

  (define (recorded-water-shore frame)
    (if (captured-periscope-frame? frame)
        (captured-periscope-frame-shore frame)
        (captured-ambient-frame-shore frame)))

  (define (draw-water-effects canvas art [recorded-frame #f])
    (define water (art-set-water art))
    ;; $18DC2 executes first: eighteen independent 8x1 shoreline tiles.
    ;; The tile family (low/high bit mask) is already baked into the atlas.
    (draw-atlas canvas water
                (for/list ([point (in-range 18)])
                  (define-values (x y) (water-shore-position point))
                  (make-atlas-transform x y))
                (for/list ([point (in-range 18)])
                  (list (* 8 (if recorded-frame
                                 (vector-ref
                                   (recorded-water-shore recorded-frame)
                                  point)
                                 (water-shore-frame water-state point)))
                        (+ 21 point) 8 1))
                #:sampling 'nearest)
    ;; $18CE2 is an animated reflection of the sun: 21 independently
    ;; selected 64-pixel-wide rows, not a single scrolling bitmap.
    (draw-atlas canvas water
                (for/list ([row (in-range 21)])
                  (make-atlas-transform water-sun-x (+ water-sun-y row)))
                (for/list ([row (in-range 21)])
                  (list (* 64 (if recorded-frame
                                  (vector-ref
                                   (recorded-water-reflection recorded-frame) row)
                                  (water-reflection-frame water-state row)))
                        row 64 1))
                #:sampling 'nearest))

  (define (draw-foam-effects canvas art)
    ;; Retail $18F44 alters the least-significant bitplane byte at twelve
    ;; moving water addresses. A 16x200 palette-LUT texture supplies exact
    ;; raster colors for those bits while leaving the shoreline's two moving
    ;; bitplanes intact. This is a single batched GPU atlas draw, not 96
    ;; uploads or on-the-fly shader compilation.
    (define points
      (for*/list ([p (in-list (foam-current-patches foam-state))]
                  [dx (in-range 8)])
        (define x (+ (foam-patch-x p) dx))
        (define y (foam-patch-y p))
        (define bit (if (zero? (bitwise-and (foam-patch-value p)
                                            (arithmetic-shift #x80 (- dx)))) 0 1))
        (list x y (foam-pixel-index water-state x y bit))))
    (draw-atlas canvas (art-set-foam art)
                (for/list ([point (in-list points)])
                  (make-atlas-transform (first point) (second point)))
                (for/list ([point (in-list points)])
                  (list (third point) (second point) 1 1))
                #:sampling 'nearest))

  (define (draw-scene canvas art)
    ;; Every scene is rendered at the Amiga's native 320x200 resolution.
    ;; Scaling and letterboxing belong only to present-scene below.
    (define atlas (art-set-atlas art))
    (define background (art-set-background art))
    (define font-atlas (art-set-font art))
    (define shield-images (art-set-shields art))
    (define fighter-images (art-set-fighters art))
    (define active (world-snapshot simulation))
    (define selected (vector-ref (world-balls simulation) selected-slot))
    (define fighter-image
      (hash-ref fighter-images (shield-fighter-frame defender)))
    (define fighter-x (shield-fighter-screen-x defender))
    (define fighter-y (shield-fighter-screen-y defender))
    (canvas-clear! canvas "#111822")
    (with-skia ([floor-pen (make-paint #:color "#D7A15C"
                                        #:style 'stroke #:stroke-width 0.6)]
                [trail-0 (make-paint #:color "#F6DB67" #:style 'stroke #:stroke-width 0.7)]
                [trail-1 (make-paint #:color "#8FE8F8" #:style 'stroke #:stroke-width 0.7)]
                [trail-2 (make-paint #:color "#F68F92" #:style 'stroke #:stroke-width 0.7)]
                [trail-3 (make-paint #:color "#AFF7A8" #:style 'stroke #:stroke-width 0.7)]
                ;; Retail shadows set bitplane 0 rather than using alpha.  The
                ;; indexed floor palette is not retained by the RGBA backdrop,
                ;; so this is its stable dark-floor counterpart; the geometry,
                ;; height selection and one-bit edge filter remain exact.
                [shadow (make-paint #:color "#59564D")]
                [outline (make-paint #:color "#FFED91"
                                     #:style 'stroke #:stroke-width 0.8)])
      (with-canvas-state canvas
        (canvas-clip-rect! canvas 0 0 scene-width scene-height)
        (if scenery?
            (draw-image-rect canvas background 0 0 scene-width scene-height
                             #:sampling 'nearest)
            (void))
        (when (and scenery? background-animations?)
          (draw-water-effects canvas art))
        (when (and scenery? background-animations?)
          (draw-foam-effects canvas art))
        ;; The floor is y-coarse 85 + the renderer's screen offset 96.
        (draw-line canvas 0 181 320 181 floor-pen)
        (when (and scenery? background-animations?)
          (draw-background-effects canvas art))
        (when (and scenery? background-animations?)
          (draw-retail-ambient canvas art))
        ;; $AF7E/$B00A: paint the current pose's eight one-bit floor rows,
        ;; then apply the original outward lower-edge deformation.  $C164
        ;; separately projects each live ball onto those same ground rows.
        ;; A complete Skia frame is redrawn from scratch, so unlike the Amiga
        ;; bitplane path there is no previous-shadow restoration step here.
        (draw-shadow-runs
         canvas
         (fighter-floor-shadow-runs (shield-fighter-frame defender)
                                    (shield-fighter-mirrored? defender)
                                    fighter-x)
         shadow)
        (for ([ball (in-vector (world-balls simulation))] #:when ball)
          (draw-shadow-runs
           canvas
           (ball-floor-shadow-runs (raw-fixed-integer (ball-x ball))
                                   (raw-fixed-integer (ball-y ball)))
           shadow))
        ;; The original $C530 table chooses the man's fighter pose; $C51B
        ;; and $683 select x origin and mirrored/normal drawing respectively.
        ;; The screen-x helper includes the original blitter's -4-byte
        ;; (-32-pixel) destination correction. Keeping full 80x100 PNGs
        ;; preserves the local transparent padding in both orientations.
        (if (shield-fighter-mirrored? defender)
            (with-canvas-state canvas
              (canvas-translate! canvas (+ fighter-x 80) fighter-y)
              (canvas-scale! canvas -1 1)
              (draw-image-rect canvas fighter-image 0 0 80 100
                               #:sampling 'nearest))
            (draw-image-rect canvas fighter-image fighter-x fighter-y 80 100
                             #:sampling 'nearest))
        (when trails?
          (define trail-pens (vector trail-0 trail-1 trail-2 trail-3))
          (for ([slot (in-range 4)])
            (define points (vector-ref histories slot))
            (for ([a (in-list points)] [b (in-list (if (null? points) '() (cdr points)))])
              (draw-line canvas (car a) (+ (cdr a) 5)
                         (car b) (+ (cdr b) 5) (vector-ref trail-pens slot)))))
        (unless (null? active)
          (draw-atlas canvas atlas
                      (for/list ([item (in-list active)])
                        (make-atlas-transform (hash-ref item 'x) (hash-ref item 'y)))
                      (for/list ([item (in-list active)])
                        (list (* 16 (hash-ref item 'phase))
                              (* 11 (hash-ref item 'sprite)) 16 11))
                      #:sampling 'nearest))
        (draw-image-rect canvas
                         (vector-ref shield-images (shield-view-index defender))
                         (shield-screen-x defender) (shield-screen-y defender)
                         (if (= (shield-view-index defender) 1) 28 4)
                         23 #:sampling 'nearest)
        (when (and selection-box? selected)
          (draw-rect canvas (- (ball-screen-x selected) 2)
                     (- (ball-screen-y selected) 2) 20 15 outline))
        ;; The black HUD strip holds round status, rounded callback FPS and
        ;; score in non-overlapping 8x8 character regions.
        (draw-retail-text
         canvas font-atlas
         (cond [(world-hit? simulation) "BONUS OVER - R"]
               [(bonus-score-survival-awarded? progress)
                "SURVIVED +5000"]
               [else "IK+"])
         8 4)
        (when fps-visible?
          (draw-retail-text canvas font-atlas
                            (format "FPS ~a" (inexact->exact (round callback-rate)))
                            160 4))
        (draw-retail-text canvas font-atlas
                          (format "SCORE ~a" (bonus-score-points progress))
                          232 4))))

  (define (present-scene canvas snapshot width height backing-x backing-y)
    ;; A single nearest-neighbour upscale makes one game pixel a uniform
    ;; rectangle on both CPU and GPU. GPU sizes are *physical* pixels: use
    ;; logical viewport dimensions plus the supplied Retina backing scales.
    (define-values (scale ox oy) (viewport width height))
    (set! current-scale scale)
    (canvas-clear! canvas "#111822")
    (draw-image-rect canvas snapshot
                     (* ox backing-x) (* oy backing-y)
                     (* scene-width scale backing-x)
                     (* scene-height scale backing-y)
                     #:sampling 'nearest))

  (define (paint-raster widget dc)
    (with-handlers ([exn:fail? render-error])
      (unless (or closed? failed?)
        (define-values (width height) (send widget get-client-size))
        (when (and (positive? width) (positive? height))
          (define trace-start (and trace-state (current-inexact-milliseconds)))
          (define started (current-inexact-monotonic-milliseconds))
          ;; The scene surface is permanent and never scales on resize. The
          ;; presentation surface is recycled unless the window size changes.
          (unless (equal? raster-present-size (cons width height))
            (when raster-present (skia-close! raster-present))
            (set! raster-present (make-surface width height))
            (set! raster-present-size (cons width height)))
          (draw-scene (surface-canvas raster-scene) cpu-art)
          (with-skia ([snap (surface-snapshot raster-scene)])
            (present-scene (surface-canvas raster-present) snap
                           width height 1 1))
          (send dc draw-bitmap (surface->bitmap raster-present) 0 0)
          (record-render! started)
          (when trace-state
            (trace-gui-span! trace-state 'render-raster
                             trace-start (current-inexact-milliseconds)))))))

  (define (render-gpu frame)
    ;; This callback runs with the presenter's GPU context active. Nothing
    ;; ever reads GPU pixels back to the CPU during normal gameplay.
    (unless (or closed? failed?)
      (define trace-start (and trace-state (current-inexact-milliseconds)))
      (define started (current-inexact-monotonic-milliseconds))
      (unless gpu-art (set! gpu-art (upload-art-set (gpu-frame-context frame) cpu-art)))
      (unless gpu-scene
        (set! gpu-scene (make-gpu-surface (gpu-frame-context frame)
                                         scene-width scene-height)))
      (draw-scene (surface-canvas gpu-scene) gpu-art)
      (with-skia ([snap (gpu-surface-snapshot gpu-scene)])
        (present-scene (gpu-frame-canvas frame) snap
                       (gpu-frame-logical-width frame)
                       (gpu-frame-logical-height frame)
                       (gpu-frame-scale-x frame)
                       (gpu-frame-scale-y frame)))
      (record-render! started)
      (when trace-state
        (trace-gui-span! trace-state 'render-gpu
                         trace-start (current-inexact-milliseconds)))))

  (define window%
    (class frame%
      (super-new)
      (define/augment (on-close) (close-window!))))
  (define debug-window%
    (class frame%
      (super-new)
      ;; Closing diagnostics must not close the game or its GPU context.
      ;; The F1 key in the game canvas reopens this window.
      (define/augment (on-close) (send this show #f))))
  (define (input-canvas-mixin base%)
    ;; One identical input handler for the Racket raster and Skia GPU widgets.
    ;; Keyboard bindings and game logic are deliberately unchanged.
    (class base%
      (super-new)
      (define/override (on-focus focused?)
        (unless focused? (hash-clear! held)))
      (define/override (on-char event)
        (define released? (eq? (send event get-key-code) 'release))
        (define raw (if released?
                        (send event get-key-release-code)
                        (send event get-key-code)))
        (define key (if (char? raw) (char-downcase raw) raw))
        (cond
          [released? (hash-remove! held key)]
          [(not (hash-ref held key #f))
           (hash-set! held key #t)
           (case key
             [(#\p #\space) (toggle-pause!)]
             [(#\n) (advance-one!)]
             [(#\s) (next-spawn!)]
             [(#\r) (restart!)]
             [(#\t) (toggle-trails!)]
             [(#\o) (toggle-selection-box!)]
             [(#\f) (toggle-fps-visible!)]
             [(#\b) (set! scenery? (not scenery?)) (request-frame!)]
             [(#\c) (toggle-collisions!)]
             [(#\h) (toggle-player-hit!)]
             [(#\m) (toggle-sounds!)]
             [(#\d) (deflect-selected!)]
             [(#\l) (save-event-trace!)]
             [(f1) (when debug-window
                     (let ([reopen? (not (send debug-window is-shown?))])
                       (send debug-window show reopen?)
                       (when reopen? (refresh-labels!))))]
             [(#\0 #\1 #\2 #\3)
              (set! selected-slot (- (char->integer key) (char->integer #\0)))
              (refresh-labels!) (request-frame!)]
             [else (void)])]))
      (define/override (on-event event)
        (when (send event button-down? 'left)
          (send this focus)
          (let-values ([(width height) (send this get-client-size)])
            (let-values ([(scale ox oy) (viewport width height)])
              (define gx (/ (- (send event get-x) ox) scale))
              (define gy (/ (- (send event get-y) oy) scale))
              (define near
                (for/fold ([best #f]) ([slot (in-range 4)])
                  (define b (vector-ref (world-balls simulation) slot))
                  (if b
                      (let ([distance (+ (sqr (- gx (+ (ball-screen-x b) 8)))
                                         (sqr (- gy (+ (ball-screen-y b) 5))))])
                        (if (and (< distance (* 22 22))
                                 (or (not best) (< distance (cdr best))))
                            (cons slot distance) best))
                      best)))
              (when near
                (set! selected-slot (car near))
                (refresh-labels!)
                (request-frame!))))))))

  (define raster-input-canvas% (input-canvas-mixin canvas%))
  (define gpu-input-canvas% (input-canvas-mixin gpu-canvas%))

  (set! window (new window%
                    [label (format "IK+ — Amiga bonus round, Stage 28 (~a)"
                                   (if gpu? "GPU" "CPU"))]
                    [width 980] [height 660]))
  (set! view
        (if gpu?
            (new gpu-input-canvas%
                 [parent window] [backend backend] [render render-gpu]
                 [on-error render-error] [background 'black]
                 [min-width 320] [min-height 200])
            (new raster-input-canvas%
                 [parent window] [style '(no-autoclear)]
                 [min-width 320] [min-height 200]
                 [paint-callback paint-raster])))
  (set! debug-window (new debug-window%
                          [label "IK+ — Diagnostics and controls"]
                          [width 390] [height 850]))
  (define side (new vertical-panel% [parent debug-window]
                    [style '(vscroll)]
                    [alignment '(center top)]))
  (set! pause-button
        (new button% [parent side] [label "Pause"]
             [callback (lambda (_button _event) (toggle-pause!))]))
  (new button% [parent side] [label "Step one 50 Hz tick (N)"]
       [callback (lambda (_button _event) (advance-one!))])
  (new button% [parent side] [label "Advance to next spawn (S)"]
       [callback (lambda (_button _event) (next-spawn!))])
  (new button% [parent side] [label "Restart (R)"]
       [callback (lambda (_button _event) (restart!))])
  (set! trails-control
        (new check-box% [parent side]
             [label "Projectile traces (T)"] [value trails?]
             [callback (lambda (box _event)
                         (set-trails! (send box get-value)))]))
  (set! selection-box-control
        (new check-box% [parent side]
             [label "Selected ball outline (O)"] [value selection-box?]
             [callback (lambda (box _event)
                         (set-selection-box! (send box get-value)))]))
  (set! fps-control
        (new check-box% [parent side]
             [label "Show FPS counter (F)"] [value fps-visible?]
             [callback (lambda (box _event)
                         (set-fps-visible! (send box get-value)))]))
  (set! background-animation-control
        (new check-box% [parent side]
             [label "Background animations (experimental)"]
             [value background-animations?]
             [callback (lambda (box _event)
                         (set-background-animations! (send box get-value)))]))
  (set! periscope-button
        (new button% [parent side]
             [label "Show all periscopes + record 512 frames"]
             [callback (lambda (_button _event) (preview-periscope!))]))
  (set! ambient-button
        (new button% [parent side]
             [label "Show all fish/spiders/crawlers + record 1024 frames"]
             [callback (lambda (_button _event) (preview-ambient!))]))
  (set! bird-button
        (new button% [parent side]
             [label "Show all retail birds + record 1024 frames"]
             [callback (lambda (_button _event) (preview-ambient! #t))]))
  (set! pacman-button
        (new button% [parent side]
             [label "Show all retail Pac-Man paths + record 256 frames"]
             [callback (lambda (_button _event) (preview-ambient! #f #t))]))
  (set! leaf-button
        (new button% [parent side]
             [label "Leaf-eating crawler + record 768 frames"]
             [callback (lambda (_button _event) (preview-ambient! #f #f #t))]))
  (new button% [parent side] [label "Retail crawler eating a leaf pile (site 3)"]
       [callback (lambda (_button _event) (preview-retail-leaf-eater!))])
  (new button% [parent side] [label "Legacy larger caterpillar hypothesis (unverified)"]
       [callback (lambda (_button _event) (preview-worm!))])
  (new button% [parent side] [label "Retail jumping fish (20 poses)"]
       [callback (lambda (_button _event)
                   (ambient-force-fish! ambient-state)
                   (set-background-animations! #t)
                   (request-frame!))])
  (new button% [parent side] [label "Retail lowering spider (raster masks)"]
       [callback (lambda (_button _event)
                   (ambient-force-spider! ambient-state)
                   (set-background-animations! #t)
                   (request-frame!))])
  (new button% [parent side] [label "Retail tiny crawler (12 poses)"]
       [callback (lambda (_button _event)
                   (ambient-force-crawler! ambient-state)
                   (set-background-animations! #t)
                   (request-frame!))])
  (new button% [parent side] [label "Retail flying bird (5-row masks)"]
       [callback (lambda (_button _event)
                   (ambient-force-bird! ambient-state)
                   (set-background-animations! #t)
                   (request-frame!))])
  (new button% [parent side] [label "Retail Pac-Man (8-row sprite)"]
       [callback (lambda (_button _event)
                   (ambient-force-pacman! ambient-state)
                   (set-background-animations! #t)
                   (request-frame!))])
  (new button% [parent side] [label "Toggle scenery (B)"]
       [callback (lambda (_button _event) (set! scenery? (not scenery?)) (request-frame!))])
  (new button% [parent side] [label "Toggle retail bitplane collisions (C)"]
       [callback (lambda (_button _event) (toggle-collisions!))])
  (new button% [parent side] [label "Toggle fighter hit detection (H)"]
       [callback (lambda (_button _event) (toggle-player-hit!))])
  (new button% [parent side] [label "Toggle original audio (M)"]
       [callback (lambda (_button _event) (toggle-sounds!))])
  (new button% [parent side] [label "Inject deflection — DEBUG (D)"]
       [callback (lambda (_button _event) (deflect-selected!))])
  (when event-trace-path
    (new button% [parent side] [label "Save active event trace (L)"]
         [callback (lambda (_button _event) (save-event-trace!))]))
  (new button% [parent side] [label "Close"]
       [callback (lambda (_button _event) (close-window!))])
  (set! tick-label (make-diagnostic-lines side 10))
  (set! shield-label (make-diagnostic-lines side 8))
  (set! ball-label (make-diagnostic-lines side 10))
  (set! perf-label (make-diagnostic-lines side 13))
  (set! background-label (make-diagnostic-lines side 5))
  (set! periscope-capture-label (make-diagnostic-lines side 1))
  (set! ambient-capture-label (make-diagnostic-lines side 1))
  (set! help-label (make-diagnostic-lines side 9))
  (set-diagnostic-lines!
   help-label
   "ARROWS: move shield\n0–3: select ball; click to inspect\nP/Space: pause  N: tick  S: spawn\nT: traces  O: ball outline  F: FPS\nF1: show/hide diagnostics\nC: collisions  H: fighter hits\nM: audio  D: debug deflection\nR: new 5 s trace; L: save early\nOriginal art; scenery timing provisional")

  (set! ticker
        (new timer% [notify-callback
                     (lambda ()
                       (define trace-start
                         (and trace-state (current-inexact-milliseconds)))
                       (define now (current-inexact-monotonic-milliseconds))
                       (define tick-gap (- now previous-ms))
                       (unless (or paused? failed? closed?)
                         ;; Bound catch-up after a stalled UI thread.
                         (set! max-timer-gap-ms
                               (max max-timer-gap-ms (max 0.0 tick-gap)))
                         (set! remainder-ms (+ remainder-ms (min 100.0 (max 0.0 tick-gap))))
                         (let ([steps (min 5 (inexact->exact (floor (/ remainder-ms step-ms))))])
                           (set! remainder-ms (- remainder-ms (* steps step-ms)))
                           (when (> steps 1)
                             (set! extra-catch-up-ticks
                                   (+ extra-catch-up-ticks (sub1 steps)))
                             (set! catch-up-bursts (add1 catch-up-bursts)))
                           (when (positive? steps)
                             (for ([_ (in-range steps)]) (single-step!))
                             (maybe-refresh-labels!)
                             (request-frame!))))
                       (set! previous-ms now)
                       (when trace-state
                         (trace-gui-span! trace-state 'timer-notify
                                          trace-start
                                          (current-inexact-milliseconds))))]))
  ;; Diagnostics are opt-in so their label/layout work cannot perturb the
  ;; default pacing measurement. F1 reopens this window when needed.
  (send debug-window show #f)
  (refresh-labels!)
  (send window show #t)
  (when start-fullscreen? (send window fullscreen #t))
  (send view focus)
  (reset-clock!)
  (send ticker start 16)
  (when initial-ambient
    ;; Useful for repeatable visual checks without opening Diagnostics.
    (case initial-ambient
      [(fish) (ambient-force-fish! ambient-state 4 0)]
      [(spider) (ambient-force-spider! ambient-state 1)]
      [(crawler) (ambient-force-crawler! ambient-state 3)]
      [(leaf-eater) (preview-retail-leaf-eater!)]
      [(bird) (ambient-force-bird! ambient-state 3 2)]
      [(pacman) (ambient-force-pacman! ambient-state 2)]))
  (when auto-periscope-capture? (preview-periscope!))
  (when auto-ambient-capture?
    (preview-ambient! auto-bird-capture? auto-pacman-capture?
                      auto-leaf-capture?))
  window)

(module+ main
  (define selected-renderer 'auto)
  (define selected-backend 'auto)
  (define selected-trace-path #f)
  (define selected-fullscreen? #f)
  (define selected-auto-periscope-capture? #f)
  (define selected-auto-ambient-capture? #f)
  (define selected-auto-bird-capture? #f)
  (define selected-auto-pacman-capture? #f)
  (define selected-auto-leaf-capture? #f)
  (define selected-auto-regular-ambient-capture? #f)
  (define selected-ambient #f)
  (command-line
   #:once-each
   [("--renderer") mode "auto, raster, or gpu (auto chooses Metal on macOS)"
    (set! selected-renderer (string->symbol mode))]
   [("--backend") mode "auto, metal, opengl, or direct3d (GPU only)"
    (set! selected-backend (string->symbol mode))]
   [("--gui-events") path "Save a bounded GUI event trace to the given new CSV file on game exit"
    (set! selected-trace-path path)]
   [("--fullscreen") "Start the game window in native fullscreen mode"
    (set! selected-fullscreen? #t)]
   [("--periscope-capture")
    "Show all eight periscope scripts, capture 512 animation frames, then exit"
    (set! selected-auto-periscope-capture? #t)]
   [("--ambient-capture")
    "Capture 1024 frames of every fish, spider and crawler location, then exit"
    (set! selected-auto-ambient-capture? #t)
    (set! selected-auto-regular-ambient-capture? #t)]
   [("--bird-capture")
    "Capture 1024 frames of all eight retail bird sites and four variants, then exit"
    (set! selected-auto-ambient-capture? #t)
    (set! selected-auto-bird-capture? #t)]
   [("--pacman-capture")
    "Capture 256 frames of all four original Pac-Man passes, then exit"
    (set! selected-auto-ambient-capture? #t)
    (set! selected-auto-pacman-capture? #t)]
   [("--leaf-eater-capture")
    "Capture 768 frames of retail crawler leaf erasure and control paths, then exit"
    (set! selected-auto-ambient-capture? #t)
    (set! selected-auto-leaf-capture? #t)]
   [("--ambient") kind "Begin with fish, spider, crawler, leaf-eater, bird or pacman"
    (unless (member kind '("fish" "spider" "crawler" "leaf-eater" "bird" "pacman"))
      (raise-user-error 'ikplus "--ambient must be fish, spider, crawler, leaf-eater, bird or pacman"))
    (set! selected-ambient (string->symbol kind))]
   #:args () (void))
  (when (or (and selected-auto-periscope-capture?
                 selected-auto-ambient-capture?)
            (> (length (filter values
                               (list selected-auto-regular-ambient-capture?
                                     selected-auto-bird-capture?
                                     selected-auto-pacman-capture?
                                     selected-auto-leaf-capture?))) 1))
    (raise-user-error 'ikplus
                      "choose only one capture: periscope, ambient, bird, pacman or leaf-eater"))
  (queue-callback
   (lambda ()
     (launch (if (and (or selected-auto-periscope-capture?
                          selected-auto-ambient-capture?)
                      (eq? selected-renderer 'auto))
                 'raster selected-renderer)
             selected-backend selected-trace-path selected-fullscreen?
             selected-auto-periscope-capture? selected-ambient
             selected-auto-ambient-capture? selected-auto-bird-capture?
             selected-auto-pacman-capture? selected-auto-leaf-capture?))
   #f))
