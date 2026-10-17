#lang racket/base

;;;
;;; Reader Test
;;;

;; Checks catalog-driven navigation, source access, and safe example copying.
;; This module guards the documentation's examples and support code against regressions.


;;;
;;; Imports and Exports
;;;

(require rackunit racket/file racket/list racket/path racket/string
         scribble/core
         "support/catalog.rkt" "support/examples.rkt" "support/reader.rkt")

;;;
;;; Regression Checks
;;;

(module+ test
  ; root : path?
  ;;   Owns the temporary source root used by the copier regression checks.
  (define root (make-temporary-file "skia-reader-test~a" 'directory))
  ; fixtures : path?
  ;;   Names the temporary fixture subtree used by the copier tests.
  (define fixtures (build-path root "package"))
  ; copies : path?
  ;;   Names the destination subtree used by the copier tests.
  (define copies (build-path root "copies"))
  (make-directory* fixtures)
  (make-directory* copies)
  ; files : list?
  ;;   Collects each catalog source path once for completeness checks.
  (define files (remove-duplicates (append-map (lambda (row) (hash-ref row 'files)) tutorials)))
  (dynamic-wind
    void
    (lambda ()
      ;; Synthetic inputs test the copier, not a rendering or a runnable native example.
      (for ([relative (in-list files)])
        (define source (tutorial-source-path relative fixtures))
        (make-directory* (path-only source))
        (display-to-file (string-append "Synthetic source: " relative "\n") source))
      (test-case "Every tutorial copies exactly its declared file set"
        (for ([row (in-list tutorials)])
          (define id (hash-ref row 'id))
          (define target (copy-tutorial-example id (build-path copies id) #:root fixtures))
          (define expected (sort (cons "README.txt" (hash-ref row 'files)) string<?))
          (define actual
            (sort (for/list ([path (in-directory target)] #:when (file-exists? path))
                    (string-replace (path->string (find-relative-path target path)) "\\" "/"))
                  string<?))
          (check-equal? actual expected id)
          (for ([relative (in-list (hash-ref row 'files))])
            (check-equal?
             (file->bytes (apply build-path target (string-split relative "/")))
             (file->bytes (tutorial-source-path relative fixtures)) id))))
      (test-case "Existing destinations and edits are never replaced"
        (define target (build-path copies "images"))
        (define file (build-path target "images" "contact-sheet.rkt"))
        (display-to-file "My edits\n" file #:exists 'replace)
        (check-exn exn:fail?
                   (lambda () (copy-tutorial-example "images" target #:root fixtures)))
        (check-equal? (file->string file) "My edits\n"))
      (test-case "An unknown tutorial creates nothing"
        (define target (build-path copies "unknown"))
        (check-exn exn:fail?
                   (lambda () (copy-tutorial-example "not-a-tutorial" target #:root fixtures)))
        (check-false (directory-exists? target)))
      (test-case "Missing fixtures fail before publishing a destination"
        (define target (build-path copies "incomplete"))
        (delete-file (tutorial-source-path "images/fixtures/flower.png" fixtures))
        (define before (directory-list copies))
        (check-exn exn:fail?
                   (lambda () (copy-tutorial-example "images" target #:root fixtures)))
        (check-equal? (directory-list copies) before)
        (check-false (directory-exists? target)))
      (test-case "Unsafe source names are rejected"
        (for ([path '("/tmp/x.rkt" "../x.rkt" "images/../x.rkt" "images//x.rkt"
                      "images\\x.rkt" "C:/x.rkt" "./images/x.rkt" "images/x.rkt/")])
          (check-exn exn:fail? (lambda () (tutorial-source-path path fixtures)) path)))
      (test-case "Quick has a different package source prefix"
        (check-equal? (tutorial-source-path "quick/moonlight.rkt" fixtures)
                      (build-path fixtures "scribblings" "quick" "moonlight.rkt")))
      (test-case "Missing destination parents are not created"
        (define target (build-path copies "absent" "quick"))
        (check-exn exn:fail?
                   (lambda () (copy-tutorial-example "quick" target #:root fixtures)))
        (check-false (directory-exists? (build-path copies "absent"))))
      (test-case "Source symlinks are refused"
        (cond
          [(eq? (system-type 'os) 'windows)
           (displayln "SKIP: source-symlink test requires Windows symbolic-link privileges")]
          [else
           (define file (tutorial-source-path "quick/moonlight.rkt" fixtures))
           (define saved (build-path fixtures "original.txt"))
           (rename-file-or-directory file saved)
           (make-file-or-directory-link saved file)
           (check-exn exn:fail?
                      (lambda ()
                        (copy-tutorial-example "quick" (build-path copies "symlink")
                                               #:root fixtures)))]))
      (test-case "Literal command fragments retain ASCII hyphens"
        (for ([text '("--renderer raster" "--renderer gpu" "--count 300"
                       "--snapshot frame.png" "raco skia-examples --list")])
          (check-equal? (content->string (command-text text)) text)))
      (test-case "All reader blocks can be constructed without loading Skia"
        (for ([row (in-list tutorials)])
          (define id (hash-ref row 'id))
          (check-true (element? (tutorial-link id)))
          (check-not-exn (lambda () (tutorial-entry id)))
          (check-not-exn (lambda () (tutorial-next id)))
          (check-not-exn (lambda () (tutorial-sources id))))
        (for ([category (in-list categories)])
          (check-not-exn
           (lambda () (tutorial-category (hash-ref category 'id)))))))
    (lambda () (delete-directory/files root))))
