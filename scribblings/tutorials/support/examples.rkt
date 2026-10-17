#lang racket/base

;;;
;;; Examples
;;;

;; Copies a catalog-selected example source set into a new directory safely.
;; This module supports documentation assembly and shared examples rather than the public Skia
;; API.


;; Copy only the explicit source set. This module does not load Skia or a GUI.
;;;
;;; Imports and Exports
;;;

(require racket/file racket/list racket/path racket/string "catalog.rkt")
(provide copy-tutorial-example)

;;;
;;; Documentation Data and Helpers
;;;

; check-source : path-string? string? -> path?
;;   Resolves a source file and rejects missing files or paths outside the repository.
(define (check-source root relative)
  (define source (tutorial-source-path relative root))
  (define normalized-root (simplify-path (path->complete-path root) #f))
  (define normalized-source (simplify-path (path->complete-path source) #f))
  (define within-root (find-relative-path (path->directory-path normalized-root)
                                          normalized-source))
  (for/fold ([path normalized-root]) ([part (in-list (explode-path within-root))])
    (define next (build-path path part))
    (when (link-exists? next)
      (raise-arguments-error 'copy-tutorial-example "source contains a symbolic link"
                             "path" next))
    next)
  (unless (file-exists? source)
    (raise-arguments-error 'copy-tutorial-example "example source is missing"
                           "path" source))
  source)

; copy-tutorial-example : string? path-string? #:root [path-string?] -> path?
;;   Copies the complete catalog source set into a new destination without overwriting it.
(define (copy-tutorial-example id destination #:root [root repository-root])
  (define entry (tutorial-by-id id))
  (define files (hash-ref entry 'files))
  ;; Validate every source before creating the staging directory.
  (define sources (map (lambda (relative) (check-source root relative)) files))
  (define target (simplify-path (path->complete-path destination) #f))
  (when (or (file-exists? target) (directory-exists? target) (link-exists? target))
    (raise-arguments-error 'copy-tutorial-example "destination already exists; nothing replaced"
                           "destination" target))
  (define parent (path-only target))
  (unless (and parent (directory-exists? parent))
    (raise-arguments-error 'copy-tutorial-example "destination parent must already exist"
                           "destination" target))
  (define staging (make-temporary-file "skia-example~a" 'directory parent))
  (define installed? #f)
  (dynamic-wind
    void
    (lambda ()
      (for ([relative (in-list files)] [source (in-list sources)])
        (define output (apply build-path staging (string-split relative "/")))
        (make-directory* (path-only output))
        (copy-file source output #f))
      (call-with-output-file (build-path staging "README.txt")
        (lambda (out)
          (displayln (hash-ref entry 'title) out)
          (newline out)
          (displayln "Keep this directory structure, including any support or fixtures folder." out)
          (displayln "Run these commands from this directory after installing Skia:" out)
          (for ([command (in-list (hash-ref entry 'commands))])
            (displayln command out))
          (newline out)
          (displayln (tutorial-requirements entry) out)
          (displayln "Native libraries and system fonts are not included in this copy." out)))
      ;; Refuse a destination created by another process while the copy was staged.
      (rename-file-or-directory staging target #f)
      (set! installed? #t)
      target)
    (lambda ()
      (unless installed?
        (when (directory-exists? staging)
          (delete-directory/files staging))))))
