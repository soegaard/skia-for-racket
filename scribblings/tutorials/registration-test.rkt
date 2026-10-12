#lang racket/base

(require rackunit
         racket/file
         racket/list
         racket/runtime-path
         setup/getinfo)

(define-runtime-path repository "../..")

(module+ test
  (define info (get-info/full repository))
  (check-not-false info)
  (define documents (info 'scribblings (lambda () '())))
  (define sources (map car documents))
  (define names (map fourth documents))
  (check-equal? (length documents) 23)
  (check-equal? (length (remove-duplicates sources)) 23)
  (check-equal? (length (remove-duplicates names)) 23)
  (check-not-false (member "scribblings/tutorials/index.scrbl" sources))
  (check-not-false (member "scribblings/quick/quick.scrbl" sources))
  (for ([entry (in-list documents)])
    (check-true (file-exists? (build-path repository (car entry))))
    (check-true (regexp-match? #rx"^skia-" (fourth entry))))
  (for ([dependency '("scribble-lib" "racket-doc" "draw-doc" "gui-doc")])
    (check-not-false (member dependency (info 'build-deps (lambda () '())))))
  ;; File-relative HTML links cannot describe both standalone and installed layouts.
  (for ([source '("scribblings/tutorials/index.scrbl"
                  "scribblings/tutorials/sprites/sprites.scrbl"
                  "scribblings/tutorials/squadron/squadron.scrbl")])
    (check-false
     (regexp-match? #rx"@hyperlink\\[\"\\.\\./"
                    (file->string (build-path repository source))))))
