#lang racket/base

;;;
;;; GPU Dxgi Example
;;;

;; Opens a Windows DXGI presenter on a selected software or hardware adapter.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; Run explicitly on a Windows x64 interactive desktop. WARP by default;
;; --adapter hardware selects the requested physical DXGI enumeration index.
;;;
;;; Imports and Exports
;;;

(require racket/class
         (only-in racket/gui/base queue-callback)
         racket/cmdline
         "../main.rkt" "../gpu.rkt" "../gpu-gui.rkt")
;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; selection : symbol?
  ;   Selects selection for the example.
  (define selection 'warp)

  ; index : exact-integer?
  ;   Selects the device or adapter enumeration index requested by the command line.
  (define index 0)
  (command-line #:once-each
    [("--adapter") name "warp or hardware" (set! selection (string->symbol name))]
    [("--adapter-index") n "hardware enumeration index" (set! index (string->number n))]
    #:args () (void))

  ; draw : gpu-frame? -> void?
  ;   Draws the demonstration directly into the currently active presenter frame.
  (define (draw frame)
    (define c (gpu-frame-canvas frame))
    (define w (gpu-frame-width frame)) (define h (gpu-frame-height frame))
    (canvas-clear! c 'white)
    (with-skia ([paint (make-paint #:color "#177C9C")]
                [accent (make-paint #:color "#DD7733")])
      (draw-rect c (* w 0.1) (* h 0.1) (* w 0.8) (* h 0.8) paint)
      (draw-circle c (* w 0.5) (* h 0.5) (* 0.25 (min w h)) accent)))
  (queue-callback
    (lambda ()
      (define w (new gpu-window% [backend 'direct3d] [adapter selection]
                      [adapter-index index] [sync-interval 1]
                      [label "Skia / DXGI"] [width 640] [height 480] [render draw]))
      (send w show #t))))
