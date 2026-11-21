#lang racket/base
;; Racket rewrites info.rkt to record package-content-state and, in binary-lib,
;; to move foreign directories. Compare the data-package semantics, not syntax.
(require json setup/getinfo racket/cmdline)
(module+ main
  (command-line #:args (request-file)
    (define rows (call-with-input-file request-file read-json))
    (define fields '(collection version pkg-desc pkg-authors deps license install-platform
                    compile-omit-paths test-omit-paths source-keep-files binary-keep-files
                    binary-lib-keep-files distribution-preference))
    (for ([row (in-list rows)])
      (define a (get-info/full (string->path (hash-ref row 'original))))
      (define b (get-info/full (string->path (hash-ref row 'rebuilt))))
      (unless (and a b) (error 'rebuilt-native-info "metadata missing"))
      (for ([field (in-list fields)])
        (unless (equal? (format "~s" (a field (lambda () 'absent)))
                        (format "~s" (b field (lambda () 'absent))))
          (error 'rebuilt-native-info "~a changed ~a" (hash-ref row 'rebuilt) field)))
      (define copy (a 'copy-foreign-libs (lambda () '())))
      (define rebuilt-copy (b 'copy-foreign-libs (lambda () '())))
      (define moved (b 'move-foreign-libs (lambda () '())))
      (unless (or (and (equal? copy rebuilt-copy) (null? moved))
                  (and (equal? (hash-ref row 'form) "binary-lib")
                       (null? rebuilt-copy) (equal? copy moved)))
        (error 'rebuilt-native-info "unreviewed foreign-directory metadata transformation")))
    (write-json (hasheq 'status "passed" 'packages (length rows)
                        'permitted_rewrites '("package-content-state" "binary-lib copy-to-move-foreign-libs")))
    (newline)))
