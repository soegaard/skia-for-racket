#lang racket/base

;;;
;;; Registration Test
;;;

;; Checks that registered Scribble manuals agree with the tutorial and collection catalogs.
;; This module guards the documentation's examples and support code against regressions.


;;;
;;; Imports and Exports
;;;

(require rackunit
         racket/file
         racket/list
         racket/runtime-path
         setup/getinfo
         "../support/documentation-catalog.rkt"
         "support/catalog.rkt")

;;;
;;; Repository Fixture
;;;

; repository : path?
;   Locates repository relative to this module rather than the current directory.
(define-runtime-path repository "../..")

;;;
;;; Regression Checks
;;;

(module+ test

  ; info : procedure?
  ;   Reads package registration fields without building the manuals.
  (define info (get-info/full repository))
  (check-not-false info)

  ; documents : list?
  ;   Retains the registered Scribble document entries for comparison with the catalogs.
  (define documents (info 'scribblings (lambda () '())))

  ; sources : list?
  ;   Collects registered manual source paths for duplicate and coverage checks.
  (define sources (map car documents))

  ; names : list?
  ;   Collects registered manual output names for identity and uniqueness checks.
  (define names (map fourth documents))

  ; expected-manual-count : real?
  ;   Counts the collection manuals and individual tutorials expected in registration.
  (define expected-manual-count (+ 2 (length tutorials)))
  (check-equal? (length documents) expected-manual-count)
  (check-equal? (length (remove-duplicates sources)) expected-manual-count)
  (check-equal? (length (remove-duplicates names)) expected-manual-count)
  (check-not-false (member "scribblings/tutorials/index.scrbl" sources))
  (check-not-false (member "scribblings/quick/quick.scrbl" sources))
  (for ([tutorial (in-list tutorials)])
    (check-not-false (member (tutorial-output-directory (hash-ref tutorial 'id)) names)))
  (for ([entry (in-list documents)])
    (check-true (file-exists? (build-path repository (car entry))))
    (check-true (regexp-match? #rx"^skia-" (fourth entry))))
  (for ([dependency '("racket-doc" "draw-doc" "gui-doc")])
    (check-not-false (member dependency (info 'build-deps (lambda () '())))))
  (for ([dependency '("scribble-lib" "racket-index")])
    (check-not-false (member dependency (info 'deps (lambda () '())))))
  ;; File-relative HTML links cannot describe both standalone and installed layouts.
  (for ([source '("scribblings/tutorials/index.scrbl"
                  "scribblings/tutorials/sprites/sprites.scrbl"
                  "scribblings/tutorials/squadron/squadron.scrbl")])
    (check-false
     (regexp-match? #rx"@hyperlink\\[\"\\.\\./"
                    (file->string (build-path repository source))))))
