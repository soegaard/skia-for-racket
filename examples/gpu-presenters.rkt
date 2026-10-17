#lang racket/base

;;;
;;; GPU Presenters Example
;;;

;; Opens GPU presenter windows that share the same drawing callback.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; Run this example as a GUI program; each presenter uses the same callback.
;;;
;;; Imports and Exports
;;;

(require racket/class racket/cmdline racket/gui/base
         "../gpu.rkt" "../gpu-gui.rkt" "gpu-presentation-scene.rkt")
;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; requested : symbol?
  ;   Selects requested for the example.
  (define requested (if (eq? (system-type 'os) 'macosx) 'both 'opengl))
  (command-line #:once-each
    [("--backend") b "auto, opengl, metal, or both (macOS)" (set! requested (string->symbol b))]
    #:args () (void))
  (unless (memq requested '(auto opengl metal both))
    (raise-argument-error 'gpu-presenters "auto, opengl, metal, or both" requested))

  ; backends : list?
  ;   Lists the explicitly selected presenters to open for comparison.
  (define backends (if (eq? requested 'both) '(opengl metal) (list requested)))
  (when (and (memq 'metal backends) (not (eq? (system-type 'os) 'macosx)))
    (error 'gpu-presenters "Metal window presentation requires macOS"))
  (queue-callback
   (lambda ()
     (for ([backend (in-list backends)] [i (in-naturals)])
       (define w (new gpu-window%
         [label (format "Skia ~a — resize, minimize, move between displays" backend)]
         [width 540] [height 380] [backend backend] [render draw-presentation-scene]
         [on-error (lambda (e) (eprintf "Presentation failure: ~a\n" (if (exn? e) (exn-message e)
           e)))]))
       (send w move (+ 30 (* 560 i)) (+ 50 (* 60 i)))
       (send w show #t))) #f))
