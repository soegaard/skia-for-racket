#lang racket/base

;;;
;;; GPU DC Consumers Example
;;;

;; Opens an interactive GPU review window for drawing-context consumers.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; Interactive review, not a timing benchmark or an automated screen oracle.
;;;
;;; Imports and Exports
;;;

(require racket/class racket/cmdline (prefix-in gui: racket/gui/base)
         "../gpu-canvas.rkt" "../tests/gpu-dc-consumer-fixtures.rkt")
;;;
;;; Drawing Data and Helpers
;;;

; backend : parameter?
;   Selects backend for the dynamically scoped rendering operation.
(define backend (make-parameter 'auto))

; make-window : -> void?
;   Creates and shows an interactive drawing window with its own resource lifetime.
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
                  (string-append (consumer-workload-scene workload) " / " (consumer-workload-mode
                    workload)))]
       [callback (lambda (choice _event) (set! selected (send choice get-selection))
                    (when canvas (send canvas refresh)))])
  (set! canvas
    (new skia-gpu-canvas% [parent panel] [backend (backend)] [min-width 320] [min-height 240]
         [paint-callback (lambda (_canvas dc) (exercise-consumer! (list-ref workloads selected)
           dc))]))
  (send window show #t)
  (void))
;;;
;;; Command-Line Entry Point
;;;

(module+ main
  (command-line #:once-each
    [("--backend") name "auto, opengl, metal or direct3d" (backend (string->symbol name))]
    #:args () (void))
  (gui:queue-callback make-window))
