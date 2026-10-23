#lang racket/base

;;;
;;; Bad Apple!! Vector Player
;;;

;; Run after preparing data with:
;;   python3 tools/prepare-bad-apple.py --download
;;   racket examples/bad-apple.rkt --data output/bad-apple/frames.json.gz

(require racket/cmdline
         (prefix-in gui: racket/gui/base)
         "bad-apple/window.rkt")

(module+ main
  (define data-path "output/bad-apple/frames.json.gz")
  (define renderer 'raster)
  (define backend 'auto)
  (define audio-path #f)
  (define mpv-executable "mpv")
  (define sync-offset-seconds 0.0)
  (command-line
   #:program "bad-apple.rkt"
   #:once-each
   [("--data") path "prepared frames.json.gz path" (set! data-path path)]
   [("--renderer") name "raster or gpu" (set! renderer (string->symbol name))]
   [("--backend") name "auto, opengl, metal, or direct3d" (set! backend (string->symbol name))]
   [("--audio") path "matching MP4 for optional mpv audio" (set! audio-path path)]
   [("--mpv") path "mpv executable for --audio" (set! mpv-executable path)]
   [("--sync-offset") seconds "visual seconds added to mpv time"
    (define value (string->number seconds))
    (unless (real? value) (raise-argument-error '--sync-offset "real number" seconds))
    (set! sync-offset-seconds value)]
   #:args () (void))
  (unless (memq renderer '(raster gpu))
    (raise-argument-error 'bad-apple.rkt "raster or gpu renderer" renderer))
  (unless (memq backend '(auto opengl metal direct3d))
    (raise-argument-error 'bad-apple.rkt "supported GPU backend" backend))
  ;; Native scene construction happens only after this callback reaches the GUI handler thread.
  (gui:queue-callback
   (lambda ()
     (open-bad-apple-window data-path renderer backend audio-path mpv-executable sync-offset-seconds))))
