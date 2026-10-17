#lang racket

;;;
;;; Balls
;;;

;; Starts the bouncing-ball tutorial through the shared sprite window host.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require racket/cmdline racket/runtime-path skia
         "atlas.rkt" "model.rkt" "scene.rkt")
(provide open-balls-window)
;;;
;;; Drawing Data and Helpers
;;;

; host : path?
;   Locates host relative to this module rather than the current directory.
(define-runtime-path host "../support/sprite-window.rkt")

; open-balls-window : symbol? [exact-nonnegative-integer?] #:smoke? [boolean?] -> (is-a?/c frame%)
;   Starts the ball simulation with the selected renderer and requested sprite count.
(define (open-balls-window renderer [count 30] #:smoke? [smoke? #f])
  (define open-window (dynamic-require (list 'submod host 'gui) 'open-sprite-window))
  (open-window "Skia / Bouncing Sprites" scene-width scene-height
               make-ball-atlas (lambda () (make-ball-world count)) step-balls! draw-balls
               #:renderer renderer #:smoke? smoke?))

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; renderer : symbol?
  ;   Selects renderer for the example.
  (define renderer 'gpu)

  ; count : exact-integer?
  ;   Sets the requested number of simulated balls.
  (define count 30)

  ; snapshot : (or/c path-string? #f)
  ;   Optionally names a headless snapshot destination instead of opening the live window.
  (define snapshot #f)

  ; smoke? : boolean?
  ;   Enables the bounded window smoke-run path when explicitly requested.
  (define smoke? #f)
  (command-line
   #:program "balls.rkt" #:once-each
   [("--renderer") name "gpu or raster" (set! renderer (string->symbol name))]
   [("--count") number "1 through 2000 balls" (set! count (string->number number))]
   [("--snapshot") path "Save a CPU still image without opening a GUI" (set! snapshot path)]
   [("--smoke") "Exercise a window, then close automatically" (set! smoke? #t)]
   #:args () (void))
  (unless (memq renderer '(raster gpu)) (error 'balls "expected gpu or raster"))

  ; world : ball-world?
  ;   Keeps the reproducible simulation state used by the sprite example.
  (define world (make-ball-world count)) ; validate before opening any window
  (cond
    [snapshot
     (with-skia ([atlas (make-ball-atlas)] [surface (make-surface scene-width scene-height)])
       (draw-balls (surface-canvas surface) atlas world)
       (save-png surface snapshot #:exists 'replace))]
    [else
     (define queue (dynamic-require 'racket/gui/base 'queue-callback))
     (queue (lambda () (open-balls-window renderer count #:smoke? smoke?)) #f)]))
