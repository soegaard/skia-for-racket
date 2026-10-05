#lang racket/base
;; The worker uses only public authoring APIs. No GUI window or implicit GPU.
(require racket/cmdline "../tools/geometry-completion-doctor.rkt")
(module+ main
  (define directory "output/geometry-example")
  (command-line #:once-each [("--directory") path "New output directory" (set! directory path)] #:args () (void))
  (generate-geometry-documents directory "interactive-example"))
