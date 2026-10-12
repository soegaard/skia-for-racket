#lang racket

(require racket/cmdline racket/runtime-path skia "atlas.rkt" "model.rkt" "scene.rkt")
(provide open-squadron-window)
(define-runtime-path host "../support/sprite-window.rkt")

(define (open-squadron-window renderer #:smoke? [smoke? #f])
  (define open-window (dynamic-require (list 'submod host 'gui) 'open-sprite-window))
  (open-window "Skia / Star Squadron" scene-width scene-height
               make-game-atlas make-game step-game! draw-game
               #:renderer renderer #:smoke? smoke?
               #:instructions "Move: arrows or A/D   Fire: Space   Pause: P   Restart: R"))

(module+ main
  (define renderer 'gpu)
  (define snapshot #f)
  (define smoke? #f)
  (command-line
   #:program "squadron.rkt" #:once-each
   [("--renderer") name "gpu or raster" (set! renderer (string->symbol name))]
   [("--snapshot") path "Save an illustrated state without a GUI" (set! snapshot path)]
   [("--smoke") "Exercise a window, then close automatically" (set! smoke? #t)]
   #:args () (void))
  (unless (memq renderer '(raster gpu)) (error 'squadron "expected gpu or raster"))
  (cond
    [snapshot
     (with-skia ([atlas (make-game-atlas)] [surface (make-surface scene-width scene-height)])
       (draw-game (surface-canvas surface) atlas (demonstration-game))
       (save-png surface snapshot #:exists 'replace))]
    [else
     (define queue (dynamic-require 'racket/gui/base 'queue-callback))
     (queue (lambda () (open-squadron-window renderer #:smoke? smoke?)) #f)]))
