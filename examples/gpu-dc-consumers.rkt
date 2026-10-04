#lang racket/base
;; Interactive review, not a timing benchmark or an automated screen oracle.
(require racket/class racket/cmdline (prefix-in gui: racket/gui/base)
         "../gpu-canvas.rkt" "../tests/gpu-dc-consumer-fixtures.rkt")
(define backend (make-parameter 'auto))
(define (make-window)
  (define workloads (make-consumer-workloads))
  (define selected 0)
  (define canvas #f)
  (define window%
    (class gui:frame%
      (super-new)
      (define/augment (on-close)
        (when canvas (send canvas close-skia)) (send this show #f))))
  (define window (new window% [label "Skia 0.60: GPU DC consumers"] [width 720] [height 560]))
  (define panel (new gui:vertical-panel% [parent window]))
  (new gui:choice% [parent panel] [label "Consumer / execution"]
       [choices (for/list ([workload (in-list workloads)])
                  (string-append (consumer-workload-scene workload) " / " (consumer-workload-mode workload)))]
       [callback (lambda (choice _event) (set! selected (send choice get-selection))
                    (when canvas (send canvas refresh)))])
  (set! canvas
    (new skia-gpu-canvas% [parent panel] [backend (backend)] [min-width 320] [min-height 240]
         [paint-callback (lambda (_canvas dc) (exercise-consumer! (list-ref workloads selected) dc))]))
  (send window show #t)
  (void))
(module+ main
  (command-line #:once-each
    [("--backend") name "auto, opengl, metal or direct3d" (backend (string->symbol name))]
    #:args () (void))
  (gui:queue-callback make-window))
