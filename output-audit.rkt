#lang racket/base

;;;
;;; Document Output Auditing
;;;

;; Analyzes output pages and returns reports alongside encoded or saved document output.
;; This public layer connects page rendering to provenance collection and the configured
;; vector/raster publication policy.

;;;
;;; Imports and Exports
;;;

(require "output-policy.rkt" "output.rkt" "private/audit-trace.rkt"
         "private/pdf-util.rkt" "private/svg-util.rkt")
(provide (all-from-out "output-policy.rkt")
         current-output-audit-event-limit analyze-output-page
         output->bytes/audit save-output/audit
         call-with-output-label with-output-label)

; source-count : symbol? any/c -> exact-positive-integer?
;;   Validates a page or nonempty page list and returns the audit page count.
(define (source-count who source)
  (cond [(output-page? source) 1]
        [(and (list? source) (pair? source) (andmap output-page? source)) (length source)]
        [else
         (raise-argument-error who "output-page? or nonempty list of output-page? values" source)]))
; call-with-output-label : string? (-> any) -> any
;;   Copies a label containing 1 through 200 characters and runs thunk with that label in the audit
;;   scope.
(define (call-with-output-label label thunk)
  (unless (and (string? label) (<= 1 (string-length label) 200))
    (raise-argument-error 'call-with-output-label "string containing 1 through 200 characters" label))
  (unless (and (procedure? thunk) (procedure-arity-includes? thunk 0))
    (raise-argument-error 'call-with-output-label "procedure accepting zero arguments" thunk))
  (parameterize ([audit-labels (cons (string->immutable-string label) (audit-labels))]) (thunk)))
; with-output-label : syntax (label body ...)
;;   Associates the body forms' audit observations with a copied output-scope label.
(define-syntax-rule (with-output-label label body ...)
  (call-with-output-label label (lambda () body ...)))

;; A preflight executes the callback once with the actual target backend.
;; Native resource creation, metrics, and graphics-state changes still happen;
;; target drawing callouts are observed but suppressed. Temporary raster groups
;; do run. This is not static code analysis and does not suppress user side effects.
; analyze-output-page : (or/c output-page? (listof output-page?)) (or/c 'pdf 'svg) [#:title string?]
;   [#:description string?] [#:text-mode (or/c 'auto 'native 'outline)] [#:raster-dpi (real-in 1
;   9600)] [#:id-prefix (or/c string? #f)] [#:encoding-quality (or/c (integer-in 0 101) #f)]
;   [#:pdfa? boolean?] -> output-audit-report?
;;   Executes each page callback once in preflight mode and returns a report without returning or
;;   publishing document bytes.
(define (analyze-output-page source format
                             #:title [title ""] #:description [description ""]
                             #:text-mode [mode 'auto] #:raster-dpi [dpi 144]
                             #:id-prefix [prefix #f] #:encoding-quality [quality #f]
                             #:pdfa? [pdfa? #f])
  (define-values (_bytes report)
    (call-with-audit-collector
     format 'report #t (source-count 'analyze-output-page source)
     (lambda ()
       (output->bytes source format #:title title #:description description
                      #:text-mode mode #:raster-dpi dpi #:id-prefix prefix
                      #:encoding-quality quality #:pdfa? pdfa?))))
  report)

;; The normal exporting variant draws once and returns both results. Policy
;; rejection occurs before the offending native operation, not after publishing.
; output->bytes/audit : (or/c output-page? (listof output-page?)) (or/c 'pdf 'svg) [#:policy (or/c
;   'report 'error 'vector-only)] [#:title string?] [#:description string?] [#:text-mode (or/c 'auto
;   'native 'outline)] [#:raster-dpi (real-in 1 9600)] [#:id-prefix (or/c string? #f)]
;   [#:encoding-quality (or/c (integer-in 0 101) #f)] [#:pdfa? boolean?] -> (values (and/c bytes?
;   (not/c immutable?)) output-audit-report?)
;;   Exports each page once and returns completed mutable document bytes and an immutable report.
(define (output->bytes/audit source format
                             #:policy [policy 'report]
                             #:title [title ""] #:description [description ""]
                             #:text-mode [mode 'auto] #:raster-dpi [dpi 144]
                             #:id-prefix [prefix #f] #:encoding-quality [quality #f]
                             #:pdfa? [pdfa? #f])
  (call-with-audit-collector
   format policy #f (source-count 'output->bytes/audit source)
   (lambda ()
     (output->bytes source format #:title title #:description description
                    #:text-mode mode #:raster-dpi dpi #:id-prefix prefix
                    #:encoding-quality quality #:pdfa? pdfa?))))

; save-output/audit : (or/c output-page? (listof output-page?)) path-string? (or/c 'pdf 'svg)
;   [#:policy (or/c 'report 'error 'vector-only)] [#:exists (or/c 'error 'replace)] [#:title
;   string?] [#:description string?] [#:text-mode (or/c 'auto 'native 'outline)] [#:raster-dpi
;   (real-in 1 9600)] [#:id-prefix (or/c string? #f)] [#:encoding-quality (or/c (integer-in 0 101)
;   #f)] [#:pdfa? boolean?] -> output-audit-report?
;;   Publishes a completed audited document and returns its report.
(define (save-output/audit source filename format
                           #:policy [policy 'error] #:exists [exists 'error]
                           #:title [title ""] #:description [description ""]
                           #:text-mode [mode 'auto] #:raster-dpi [dpi 144]
                           #:id-prefix [prefix #f] #:encoding-quality [quality #f]
                           #:pdfa? [pdfa? #f])
  (unless (memq format '(pdf svg))
    (raise-argument-error 'save-output/audit "'pdf or 'svg" format))
  (define target
    ((if (eq? format 'pdf) pdf-output-path svg-output-path)
     'save-output/audit filename exists))
  (define-values (bytes report)
    (output->bytes/audit source format #:policy policy
                        #:title title #:description description #:text-mode mode
                        #:raster-dpi dpi #:id-prefix prefix
                        #:encoding-quality quality #:pdfa? pdfa?))
  ((if (eq? format 'pdf) write-pdf-file-bytes! write-svg-file-bytes!)
   'save-output/audit bytes target exists)
  report)
