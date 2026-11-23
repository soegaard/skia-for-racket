#lang racket/base

;;;
;;; Tutorial Example Export
;;;

;; Copies cataloged complete tutorial programs into a selected destination or lists the planned
;; files.
;; This command prepares runnable examples without requiring readers to extract Scribble snippets.

;;;
;;; Imports and Exports
;;;

(require racket/cmdline racket/string raco/command-name
         "../scribblings/tutorials/support/catalog.rkt"
         "../scribblings/tutorials/support/examples.rkt")


;;;
;;; Tutorial Selection and Source Export
;;;

; list-only? : boolean?
;   Selects catalog listing without copying tutorial programs.
(define list-only? #f)

; arguments : (listof string?)
;   Stores positional command-line arguments used to select a tutorial and output destination.
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
