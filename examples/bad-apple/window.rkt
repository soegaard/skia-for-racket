#lang racket/base

;;;
;;; Bad Apple!! Player Window
;;;

;; The GUI owns all native paths, paints, persistent raster surfaces, timers, and GPU frames. Data
;; loading happens on a worker, but the worker communicates only immutable ordinary data back to the
;; eventspace handler.

(require racket/class
         racket/format
         racket/math
         (only-in racket/gui/base
                  button% canvas% frame% horizontal-panel% message% slider% timer%
                  vertical-panel% current-eventspace eventspace-handler-thread queue-callback)
         "../../bitmap.rkt"
         "../../gpu.rkt"
         "../../gpu-gui.rkt"
         "../../main.rkt"
         "audio-mpv.rkt"
         "data.rkt"
         "scene.rkt"
         "transport.rkt")

(provide open-bad-apple-window)

(define (handler-thread! who space)
  (unless (eq? (current-thread) (eventspace-handler-thread space))
    (error who "must be called on the GUI eventspace handler thread (use queue-callback)")))

(define (renderer? value) (memq value '(raster gpu)))
(define (backend? value) (memq value '(auto opengl metal direct3d)))

;; open-bad-apple-window : path-string? symbol? symbol? -> frame%
(define (open-bad-apple-window data-path renderer backend [audio-path #f]
                               [mpv-executable "mpv"] [sync-offset-seconds 0.0])
  (define who 'open-bad-apple-window)
  (define space (current-eventspace))
  (handler-thread! who space)
  (unless (renderer? renderer)
    (raise-argument-error who "'raster or 'gpu" renderer))
  (unless (backend? backend)
    (raise-argument-error who "'auto, 'opengl, 'metal, or 'direct3d" backend))
  (unless (and (real? sync-offset-seconds)
               (not (nan? sync-offset-seconds)) (not (infinite? sync-offset-seconds)))
    (raise-argument-error who "finite real sync offset in seconds" sync-offset-seconds))

  ;; State shared only by callbacks running on `space`.
  (define closed? #f)
  (define loading-generation 0)
  (define preload-queued? #f)
  (define builder #f)
  (define scene #f)
  (define transport #f)
  (define ticker #f)
  (define tick-generation 0)
  (define view #f)
  (define window #f)
  (define status #f)
  (define splash-panel #f)
  (define player-panel #f)
  (define splash-canvas #f)
  (define splash-start-button #f)
  (define splash-dismissed? #f)
  (define splash-progress-text "Loading prepared vector data…")
  (define splash-credit-text
    "Frame data: github.com/jhancock532/bad-console / frames.js")
  (define splash-surface #f)
  (define splash-width 0)
  (define splash-height 0)
  (define play-button #f)
  (define restart-button #f)
  (define scrubber #f)
  (define scrubber-changing? #f)
  (define scrubbing? #f)
  (define resume-after-scrub? #f)
  (define raster-surface #f)
  (define raster-width 0)
  (define raster-height 0)
  (define audio #f)
  ;; The FPS estimate is measured from completed scene paints, not transport ticks. A one-second
  ;; sample window smooths transient resize/expose paints while still keeping the readout live.
  (define fps-window-start #f)
  (define frames-in-fps-window 0)
  (define measured-fps #f)
  (define fps-visible? #t)

  (define (now) (current-inexact-monotonic-milliseconds))
  (define (post thunk)
    (parameterize ([current-eventspace space]) (queue-callback thunk #f)))
  (define (label-text message)
    ;; GUI control labels are single-line strings. Backend exceptions can contain newlines, so
    ;; normalize them before surfacing an error instead of turning an error-reporting path into a
    ;; second GUI exception.
    (define one-line (regexp-replace* #px"[\r\n]+" message " "))
    ;; Native label controls also reject very long strings on some backends.
    (if (> (string-length one-line) 180)
        (string-append (substring one-line 0 179) "…")
        one-line))
  (define (set-splash-progress! message)
    (set! splash-progress-text (label-text message))
    (when (and splash-canvas (not splash-dismissed?)) (send splash-canvas refresh)))
  (define (set-status! message)
    (define label (label-text message))
    (set-splash-progress! label)
    (when status (send status set-label label)))
  (define (set-splash-credit-from-asset! asset)
    (define source (bad-apple-asset-source asset))
    (define repository (hash-ref source 'repository))
    (define path (hash-ref source 'path))
    (define commit (hash-ref source 'commit))
    (set! splash-credit-text
          (format "Frame data: github.com/~a / ~a (pinned commit ~a)"
                  repository path (substring commit 0 (min 12 (string-length commit)))))
    (when (and splash-canvas (not splash-dismissed?)) (send splash-canvas refresh)))
  (define (show-player!)
    (when (ready?)
      (set! splash-dismissed? #t)
      ;; A hidden panel still contributes its minimum size to some GUI layouts. Replace the root's
      ;; child list so the splash cannot reserve vertical space above the actual player.
      (send root-panel change-children (lambda (_children) (list player-panel)))
      (send player-panel show #t)
      (send splash-start-button enable #f)
      (when splash-surface
        (skia-close! splash-surface)
        (set! splash-surface #f))
      (send view focus)
      (play!)))
  (define (ready?) (and scene transport (not closed?)))
  (define (playing?) (and transport (eq? (bad-apple-transport-state transport) 'playing)))

  (define (reset-fps!)
    (set! fps-window-start (now))
    (set! frames-in-fps-window 0)
    (set! measured-fps #f))

  (define (fps-label)
    (cond
      [(not (playing?)) "FPS 0.0"]
      [measured-fps (format "FPS ~a" (real->decimal-string measured-fps 1))]
      [else "FPS …"]))

  (define (toggle-fps!)
    (set! fps-visible? (not fps-visible?))
    (describe-position!))

  (define (record-render!)
    (when (playing?)
      (define timestamp (now))
      (unless fps-window-start (set! fps-window-start timestamp))
      (set! frames-in-fps-window (add1 frames-in-fps-window))
      (define elapsed (- timestamp fps-window-start))
      (when (>= elapsed 1000.0)
        (set! measured-fps (* 1000.0 (/ frames-in-fps-window elapsed)))
        (set! fps-window-start timestamp)
        (set! frames-in-fps-window 0)
        ;; A completed sample is the natural cadence for refreshing the visible readout.
        (describe-position!))))

  (define (audio-snapshot)
    (and audio (mpv-audio-current-snapshot audio)))

  (define (follow-audio-clock!)
    (when (and audio transport (playing?))
      (define snapshot (audio-snapshot))
      (cond
        [(mpv-audio-snapshot-error snapshot)
         ;; Stop rather than silently switching to an unrelated elapsed-time clock. Play remains
         ;; available afterwards as the user's explicit silent-continuation choice.
         (set-status! (format "Audio stopped: ~a. Press Play to continue silently."
                              (mpv-audio-snapshot-error snapshot)))
         (mpv-audio-close! audio)
         (set! audio #f)
         (bad-apple-transport-pause! transport (now))]
        [(real? (mpv-audio-snapshot-media-time snapshot))
         (bad-apple-transport-set-media-time!
          transport (max 0 (+ (mpv-audio-snapshot-media-time snapshot) sync-offset-seconds))
          (now) #:playing? (eq? (mpv-audio-snapshot-state snapshot) 'playing))])))

  (define (set-controls-enabled! enabled?)
    (for ([control (in-list (list play-button restart-button scrubber))] #:when control)
      (send control enable enabled?)))

  (define (describe-position!)
    (when transport
      (define position-label
        (format "Frame ~a" (bad-apple-transport-current-frame transport)))
      (set-status! (if fps-visible?
                       (format "~a - ~a" position-label (fps-label))
                       position-label))))

  (define (sync-scrubber!)
    (when (and scrubber transport (not scrubber-changing?))
      (set! scrubber-changing? #t)
      (send scrubber set-value (bad-apple-transport-current-frame transport))
      (set! scrubber-changing? #f)))

  (define (current-frame!)
    (cond
      [(not transport) 0]
      [(playing?)
       (follow-audio-clock!)
       (if (playing?)
           (bad-apple-transport-select-frame! transport (now))
           (bad-apple-transport-current-frame transport))]
      [else (bad-apple-transport-current-frame transport)]))

  (define (request-render!)
    (when (and view scene (not closed?))
      (if (eq? renderer 'gpu)
          (send view request-gpu-render)
          (send view refresh))))

  (define (cancel-tick!)
    (set! tick-generation (add1 tick-generation))
    (when ticker (send ticker stop)))

  (define (schedule-tick!)
    (when (and (ready?) (playing?))
      (define delay (if audio 16 (bad-apple-transport-next-delay-ms transport (now))))
      (cond
        [(not delay)
         ;; Select once to turn a just-passed endpoint into `ended`.
         (bad-apple-transport-select-frame! transport (now))
         (sync-scrubber!)
         (describe-position!)
         (request-render!)]
        [else
         (define ticket (add1 tick-generation))
         (set! tick-generation ticket)
         ;; Arm through a low-priority GUI callback. The generation check prevents an old queued
         ;; arm from reviving playback after a pause, seek, or close.
         (post
          (lambda ()
            (when (and (not closed?) (= ticket tick-generation) (playing?))
              (send ticker start delay #t))))])))

  (define (tick!)
    (when (and (ready?) (playing?))
      (current-frame!)
      (sync-scrubber!)
      (describe-position!)
      (request-render!)
      (schedule-tick!)))

  (define (pause!)
    (when (ready?)
      (when audio (mpv-audio-pause! audio))
      (bad-apple-transport-pause! transport (now))
      (set! measured-fps #f)
      (cancel-tick!)
      (send play-button set-label "Play")
      (sync-scrubber!)
      (describe-position!)
      (request-render!)))

  (define (play!)
    (when (ready?)
      (when audio (mpv-audio-play! audio))
      (bad-apple-transport-play! transport (now))
      (reset-fps!)
      (send play-button set-label "Pause")
      (describe-position!)
      (request-render!)
      (schedule-tick!)))

  (define (toggle-play!) (if (playing?) (pause!) (play!)))

  (define (seek-frame! frame #:resume? [resume? #f])
    (when (ready?)
      (cancel-tick!)
      (when audio
        (mpv-audio-pause! audio)
        (mpv-audio-seek!
         audio (max 0 (- (/ frame (bad-apple-transport-frame-rate transport)) sync-offset-seconds)))
        (when resume? (mpv-audio-play! audio)))
      (bad-apple-transport-seek-frame! transport frame (now) #:play? resume?)
      (send play-button set-label (if resume? "Pause" "Play"))
      (sync-scrubber!)
      (describe-position!)
      (request-render!)
      (when resume? (schedule-tick!))))

  (define (restart!) (seek-frame! 0 #:resume? #t))

  (define (step! delta)
    (when (ready?)
      (cancel-tick!)
      (bad-apple-transport-step! transport delta (now))
      (send play-button set-label "Play")
      (sync-scrubber!)
      (describe-position!)
      (request-render!)))

  (define (start-scrub!)
    (when (and (ready?) (not scrubbing?))
      (set! scrubbing? #t)
      (set! resume-after-scrub? (playing?))
      (pause!)))

  (define (finish-scrub!)
    (when scrubbing?
      (set! scrubbing? #f)
      (when resume-after-scrub? (play!))
      (set! resume-after-scrub? #f)))

  (define (on-scrubber-change)
    (when (and (ready?) (not scrubber-changing?))
      (seek-frame! (send scrubber get-value) #:resume? #f)))

  (define (handle-key! event)
    (when (ready?)
      (define code (send event get-key-code))
      (unless (eq? code 'release)
        (case code
          [(#\space) (toggle-play!)]
          [(#\r #\R) (restart!)]
          [(#\f #\F) (toggle-fps!)]
          [(left) (step! -1)]
          [(right) (step! 1)]
          [(home) (seek-frame! 0)]
          [(end) (seek-frame! (sub1 (bad-apple-transport-frame-count transport)))]
          [else (void)]))))

  (define (input-canvas% base%)
    (class base%
      (super-new)
      (define/override (on-event event)
        (when (send event button-down? 'left) (send this focus))
        (super on-event event))
      (define/override (on-char event) (handle-key! event))))

  (define (draw-centered-text canvas font text baseline paint width)
    (draw-simple-text canvas text (/ (- width (measure-simple-text font text)) 2) baseline font paint))

  (define (ensure-splash-surface! physical-width physical-height)
    (when (or (not splash-surface) (not (= physical-width splash-width))
              (not (= physical-height splash-height)))
      (when splash-surface (skia-close! splash-surface))
      (set! splash-surface (make-surface physical-width physical-height #:background "#0B0C1A"))
      (set! splash-width physical-width)
      (set! splash-height physical-height)))

  (define (draw-splash canvas width height)
    (define title-size (max 58.0 (min 112.0 (* width 0.125))))
    (define body-size (max 16.0 (min 25.0 (* width 0.026))))
    (define detail-size (max 13.0 (min 18.0 (* width 0.019))))
    (define card-width (min (- width 72.0) 760.0))
    (define card-left (/ (- width card-width) 2))
    (define card-top (* height 0.50))
    (define card-height (min 190.0 (* height 0.34)))
    (with-skia ([background-gradient
                 (make-linear-gradient-shader 0 0 width height
                                              '("#090A19" "#24113D" "#0A1222"))]
                [background (make-paint #:shader background-gradient)]
                [title-gradient
                 (make-linear-gradient-shader (* width 0.24) 0 (* width 0.76) 0
                                              '("#FFDFEA" "#FF5D9E" "#8CF5EE"))]
                [title-paint (make-paint #:shader title-gradient)]
                [body-paint (make-paint #:color "#EEF0FF")]
                [detail-paint (make-paint #:color "#B8BED9")]
                [accent-paint (make-paint #:color "#8CF5EE")]
                [progress-paint (make-paint #:color "#FFD36E")]
                [card-paint (make-paint #:color "#15172C")]
                [card-outline (make-paint #:color "#7651A6" #:style 'stroke #:stroke-width 1.5)]
                [shadow-one (make-paint #:color (rgba 255 93 158 48))]
                [shadow-two (make-paint #:color (rgba 87 236 220 38))]
                [title-face (typeface-from-family "Avenir Next" #:weight 'black)]
                [body-face (typeface-from-family "Avenir Next" #:weight 'medium)]
                [title-font (make-font title-face #:size title-size #:hinting 'none
                                       #:linear-metrics? #t #:subpixel? #t)]
                [body-font (make-font body-face #:size body-size #:hinting 'none
                                      #:linear-metrics? #t #:subpixel? #t)]
                [detail-font (make-font body-face #:size detail-size #:hinting 'none
                                        #:linear-metrics? #t #:subpixel? #t)])
      (draw-rect canvas 0 0 width height background)
      ;; Soft color fields keep the monochrome content from making the opening screen feel flat.
      (draw-circle canvas (* width 0.14) (* height 0.19) (* width 0.19) shadow-one)
      (draw-circle canvas (* width 0.87) (* height 0.77) (* width 0.22) shadow-two)
      (draw-centered-text canvas title-font "Bad Apple" (* height 0.31) title-paint width)
      (draw-centered-text canvas body-font "A monochrome animated music video, reimagined as Skia paths."
                          (* height 0.39) body-paint width)
      (draw-rounded-rect canvas card-left card-top card-width card-height 20 20 card-paint)
      (draw-rounded-rect canvas card-left card-top card-width card-height 20 20 card-outline)
      (draw-centered-text canvas body-font "Famous for its high-contrast silhouette visuals and technical recreations."
                          (+ card-top (* card-height 0.28)) body-paint width)
      (draw-centered-text canvas detail-font "Bad Apple!! and its music are third-party works; this is a technical demo."
                          (+ card-top (* card-height 0.50)) detail-paint width)
      (draw-centered-text canvas detail-font splash-credit-text
                          (+ card-top (* card-height 0.68)) accent-paint width)
      (draw-centered-text canvas detail-font splash-progress-text
                          (+ card-top (* card-height 0.88)) progress-paint width)))

  (define (paint-splash widget dc)
    (define-values (logical-width logical-height) (send widget get-client-size))
    (define-values (physical-width physical-height) (send widget get-scaled-client-size))
    (when (and (not splash-dismissed?) (positive? logical-width) (positive? logical-height)
               (positive? physical-width) (positive? physical-height))
      (ensure-splash-surface! physical-width physical-height)
      (define canvas (surface-canvas splash-surface))
      (with-canvas-state canvas
        (canvas-scale! canvas (/ physical-width logical-width) (/ physical-height logical-height))
        (draw-splash canvas logical-width logical-height))
      (define-values (old-scale-x old-scale-y) (send dc get-scale))
      (dynamic-wind
       (lambda ()
         (send dc set-scale (* old-scale-x (/ logical-width physical-width))
               (* old-scale-y (/ logical-height physical-height))))
       (lambda () (send dc draw-bitmap (surface->bitmap splash-surface) 0 0))
       (lambda () (send dc set-scale old-scale-x old-scale-y)))))

  (define (ensure-raster-surface! physical-width physical-height)
    (when (or (not raster-surface) (not (= physical-width raster-width))
              (not (= physical-height raster-height)))
      (when raster-surface (skia-close! raster-surface))
      (set! raster-surface (make-surface physical-width physical-height #:background 'black))
      (set! raster-width physical-width)
      (set! raster-height physical-height)))

  (define (paint-raster widget dc)
    (define-values (logical-width logical-height) (send widget get-client-size))
    (define-values (physical-width physical-height) (send widget get-scaled-client-size))
    (when (and scene (positive? logical-width) (positive? logical-height)
               (positive? physical-width) (positive? physical-height))
      (ensure-raster-surface! physical-width physical-height)
      (define canvas (surface-canvas raster-surface))
      (with-canvas-state canvas
        (canvas-scale! canvas (/ physical-width logical-width) (/ physical-height logical-height))
        (draw-bad-apple-frame canvas scene (current-frame!) logical-width logical-height))
      ;; `surface->bitmap` produces a physical-resolution, scale-1 detached bitmap. Scale it into
      ;; the logical client rectangle explicitly, rather than relying on any platform bitmap scale.
      ;; `draw-bitmap-section-smooth` is not implemented by the window DC on every supported
      ;; Racket release, so draw through the portable DC scaling API instead.
      (define-values (old-scale-x old-scale-y) (send dc get-scale))
      (dynamic-wind
       (lambda ()
         (send dc set-scale (* old-scale-x (/ logical-width physical-width))
               (* old-scale-y (/ logical-height physical-height))))
       (lambda () (send dc draw-bitmap (surface->bitmap raster-surface) 0 0))
       (lambda () (send dc set-scale old-scale-x old-scale-y)))
      (record-render!)))

  (define (paint-gpu frame)
    (when scene
      (define canvas (gpu-frame-canvas frame))
      (with-canvas-state canvas
        (canvas-scale! canvas (gpu-frame-scale-x frame) (gpu-frame-scale-y frame))
        (draw-bad-apple-frame canvas scene (current-frame!)
                              (gpu-frame-logical-width frame)
                              (gpu-frame-logical-height frame)))
      (record-render!)))

  (define (close-window!)
    (unless closed?
      (set! closed? #t)
      (set! loading-generation (add1 loading-generation))
      (cancel-tick!)
      (when builder (bad-apple-scene-builder-cancel! builder)
            (bad-apple-scene-builder-close! builder)
            (set! builder #f))
      (when scene (bad-apple-scene-close! scene) (set! scene #f))
      (when splash-surface (skia-close! splash-surface) (set! splash-surface #f))
      (when raster-surface (skia-close! raster-surface) (set! raster-surface #f))
      (when audio (mpv-audio-close! audio) (set! audio #f))
      (when (and view (eq? renderer 'gpu)) (send view close))
      (when transport (bad-apple-transport-close! transport))
      (when window (send window show #f))))

  (define window%
    (class frame%
      (super-new)
      (define/augment (on-close) (close-window!))))

  ;; Build the window before loading so an asset error is visible to the user rather than trapped in
  ;; a worker thread or emitted as a terminal-only exception.
  (set! window (new window% [label (format "Bad Apple!! / ~a" renderer)] [width 840] [height 700]))
  (define root-panel (new vertical-panel% [parent window] [alignment '(center top)]))
  (set! splash-panel
        (new vertical-panel% [parent root-panel] [alignment '(center center)] [min-height 620]))
  (set! splash-canvas
        (new canvas% [parent splash-panel] [style '(no-autoclear)]
             [paint-callback paint-splash] [min-width 720] [min-height 540]))
  (set! splash-start-button
        (new button% [parent splash-panel] [label "Preparing…"] [enabled #f]
             [callback (lambda (_button _event) (show-player!))]))

  (set! player-panel (new vertical-panel% [parent root-panel] [alignment '(center top)]))
  (define controls (new horizontal-panel% [parent player-panel] [stretchable-height #f]
                        [horiz-margin 10] [vert-margin 8]))
  (set! play-button
        (new button% [parent controls] [label "Play"]
             [callback (lambda (_button _event) (toggle-play!))]))
  (set! restart-button
        (new button% [parent controls] [label "Restart"]
             [callback (lambda (_button _event) (restart!))]))
  ;; slider%'s range is an initialization-time property on the supported GUI API. Keep a
  ;; dedicated row in the layout, then create the slider after the worker has loaded the asset
  ;; and revealed its real frame count.
  (define scrubber-row
    (new vertical-panel% [parent player-panel] [stretchable-height #f]))
  (set! status (new message% [parent player-panel] [label "Loading prepared Bad Apple!! data…"]
                     [auto-resize #t]))
  (set-controls-enabled! #f)

  (with-handlers ([exn:fail?
                   (lambda (error)
                     (close-window!)
                     (raise error))])
    (set! view
          (if (eq? renderer 'gpu)
              (new (input-canvas% gpu-canvas%)
                   [parent player-panel] [backend backend] [render paint-gpu]
                   [on-error (lambda (error)
                               (set-status! (format "GPU renderer failed: ~a" (exn-message error)))
                               (set-controls-enabled! #f))]
                   [min-width 640] [min-height 480])
              (new (input-canvas% canvas%)
                   [parent player-panel] [style '(border no-autoclear)]
                   [paint-callback paint-raster] [min-width 640] [min-height 480])))
    (send player-panel show #f)
    (send root-panel change-children (lambda (_children) (list splash-panel)))
    (send window show #t))

  (define (continue-preload!)
    (when (and builder (not closed?))
      (with-handlers ([exn:fail?
                       (lambda (error)
                         (set-status! (format "Preparation failed: ~a" (exn-message error)))
                         (set-controls-enabled! #f)
                         (when builder (bad-apple-scene-builder-close! builder) (set! builder #f)))])
        (define result (bad-apple-scene-builder-step! builder #:path-limit 96 #:time-limit-ms 4.0))
        (define-values (paths total frame-index frame-count)
          (bad-apple-scene-builder-progress builder))
        (set-status! (format "Preparing paths: ~a / ~a · frames ~a / ~a"
                             paths total (min frame-index frame-count) frame-count))
        (cond
          [result
           (set! scene result)
           (define asset (bad-apple-scene-builder-asset builder))
           (set-splash-credit-from-asset! asset)
           (set! transport
                 (make-bad-apple-transport (bad-apple-asset-frame-count asset)
                                            (bad-apple-asset-fps-numerator asset)
                                            (bad-apple-asset-fps-denominator asset)
                                            (now)))
           (when audio-path
             (with-handlers ([exn:fail?
                              (lambda (error)
                                (set-status! (format "Audio unavailable: ~a" (exn-message error))))])
               (set! audio (start-mpv-audio audio-path #:executable mpv-executable))))
           (set! builder #f)
           (set! scrubber
                 (new slider% [parent scrubber-row] [label "Frame"] [min-value 0]
                      [max-value (sub1 (bad-apple-transport-frame-count transport))]
                      [init-value 0] [style '(horizontal plain)]
                      [callback (lambda (_slider _event) (on-scrubber-change))]))
           (set-controls-enabled! #t)
           (describe-position!)
           (set-splash-progress! "Ready. Start playback when you are ready.")
           (send splash-start-button set-label "Start playback")
           (send splash-start-button enable #t)]
          [(and builder (not closed?))
           (post continue-preload!)]))))

  (define (start-loading!)
    (define ticket (add1 loading-generation))
    (set! loading-generation ticket)
    (thread
     (lambda ()
       (with-handlers ([exn:fail?
                        (lambda (error)
                          (post
                           (lambda ()
                             (when (and (not closed?) (= ticket loading-generation))
                               (set-status! (format "Could not load data: ~a" (exn-message error)))))))] )
         (define asset (read-bad-apple-asset data-path))
         (post
          (lambda ()
            (when (and (not closed?) (= ticket loading-generation))
              (with-handlers ([exn:fail?
                               (lambda (error)
                                 (set-status! (format "Could not start preparation: ~a"
                                                      (exn-message error))))])
                (set-splash-credit-from-asset! asset)
                (set! builder (make-bad-apple-scene-builder asset))
                (continue-preload!)))))))))

  (set! ticker (new timer% [notify-callback tick!]))
  (start-loading!)
  window)
