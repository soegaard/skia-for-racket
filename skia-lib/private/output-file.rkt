#lang racket/base

;;;
;;; Completed Output Files
;;;

;; Validates output paths and publishes completed bytes through a temporary file.
;; Shares the file-writing guarantees of image, PDF, SVG, and picture exporters.

(require racket/file racket/path)
(provide output-file-path write-output-file-bytes!)

; output-file-path : symbol? path-string? symbol? [string?] -> path?
;   Checks the destination and replacement policy and fixes its absolute path before encoding.
(define (output-file-path who filename exists [kind "output"])
  (unless (path-string? filename) (raise-argument-error who "path-string?" filename))
  (unless (memq exists '(error replace))
    (raise-argument-error who "'error or 'replace" exists))
  (define target (path->complete-path filename))
  (when (regexp-match? #rx#"\0" (path->bytes target))
    (raise-arguments-error who (string-append kind " path contains NUL") "path" filename))
  (when (directory-exists? target)
    (raise-arguments-error who (string-append kind " destination is a directory") "path" target))
  (unless (directory-exists? (path-only target))
    (raise-arguments-error who (string-append kind " destination directory does not exist")
                           "path" target))
  (when (and (eq? exists 'error) (or (file-exists? target) (link-exists? target)))
    (raise-arguments-error who (string-append kind " destination already exists") "path" target))
  target)

; write-output-file-bytes! : symbol? bytes? path-string? symbol? [string?] -> void?
;   Writes completed bytes beside the destination, then renames them into place; removes the
;   temporary file on failure or escape. Does not promise durability after a system crash.
(define (write-output-file-bytes! who bs filename exists [template ".skia-output-~a.tmp"])
  (unless (bytes? bs) (raise-argument-error who "bytes?" bs))
  (define target (output-file-path who filename exists))
  (define temporary #f)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       (lambda ()
         (parameterize-break #f
           (set! temporary (make-temporary-file template #f (path-only target)))))
       (lambda ()
         (call-with-output-file temporary
           (lambda (out) (write-bytes bs out) (void))
           #:exists 'truncate/replace #:mode 'binary)
         ;; Rename rechecks 'error, including a target created after validation.
         (rename-file-or-directory temporary target (eq? exists 'replace)))
       (lambda ()
         (when (and temporary (file-exists? temporary)) (delete-file temporary))))))
  (void))
