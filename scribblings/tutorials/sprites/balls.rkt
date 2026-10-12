#lang racket

(require racket/cmdline racket/runtime-path skia
         "atlas.rkt" "model.rkt" "scene.rkt")
(provide open-balls-window)
(define-runtime-path host "../support/sprite-window.rkt")

(define (open-balls-window renderer [count 30] #:smoke? [smoke? #f])
  (define open-window (dynamic-require (list 'submod host 'gui) 'open-sprite-window))
  (open-window "Skia / Bouncing Sprites" scene-width scene-height
               make-ball-atlas (lambda () (make-ball-world count)) step-balls! draw-balls
               #:renderer renderer #:smoke? smoke?))

(module+ main
  (define renderer 'gpu)
  (define count 30)
  (define snapshot #f)
  (define smoke? #f)
  (command-line
   #:program "balls.rkt" #:once-each
   [("--renderer") name "gpu or raster" (set! renderer (string->symbol name))]
   [("--count") number "1 through 2000 balls" (set! count (string->number number))]
   [("--snapshot") path "Save a CPU still image without opening a GUI" (set! snapshot path)]
   [("--smoke") "Exercise a window, then close automatically" (set! smoke? #t)]
   #:args () (void))
  (unless (memq renderer '(raster gpu)) (error 'balls "expected gpu or raster"))
  (define world (make-ball-world count)) ; validate before opening any window
  (cond
    [snapshot
     (with-skia ([atlas (make-ball-atlas)] [surface (make-surface scene-width scene-height)])
       (draw-balls (surface-canvas surface) atlas world)
       (save-png surface snapshot #:exists 'replace))]
    [else
     (define queue (dynamic-require 'racket/gui/base 'queue-callback))
     (queue (lambda () (open-balls-window renderer count #:smoke? smoke?)) #f)]))
