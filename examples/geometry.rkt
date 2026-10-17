#lang racket/base

;;;
;;; Geometry Example
;;;

;; Runs the geometry document generator with an explicitly chosen output directory.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; The worker uses only public authoring APIs. No GUI window or implicit GPU.
;;;
;;; Imports and Exports
;;;

(require racket/cmdline "../tools/geometry-completion-doctor.rkt")
;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; directory : string?
  ;   Selects the destination used by this example's output.
  (define directory "output/geometry-example")
  (command-line #:once-each [("--directory") path "New output directory" (set! directory path)]
    #:args () (void))
  (generate-geometry-documents directory "interactive-example"))
