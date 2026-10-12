#lang racket/base

(require racket/cmdline racket/string raco/command-name
         "../scribblings/tutorials/support/catalog.rkt"
         "../scribblings/tutorials/support/examples.rkt")

(define list-only? #f)
(define arguments
  (command-line
   #:program (short-program+command-name)
   #:once-each
   [("--list") "List available tutorial names" (set! list-only? #t)]
   #:args arguments
   arguments))

(cond
  [list-only?
   (unless (null? arguments)
     (raise-user-error 'skia-examples "--list does not accept a tutorial or destination"))
   (for ([entry (in-list tutorials)])
     (printf "~a: ~a\n" (hash-ref entry 'id) (hash-ref entry 'title)))]
  [else
   (unless (= (length arguments) 2)
     (raise-user-error 'skia-examples "expected a tutorial name and a NEW destination directory"))
   (define target (copy-tutorial-example (car arguments) (cadr arguments)))
   (printf "Copied to ~a\n" target)
   (printf "Keep the subdirectories. Run the commands in README.txt from that directory.\n")])
