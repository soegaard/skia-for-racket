#lang racket/base

;;;
;;; Explicit Windows Native Installation
;;;

;; Runs the pinned NuGet installer only when invoked as a command. Compilation
;; and imports do not download inputs or load either native library.

(require racket/runtime-path racket/system)

; python-installer : path?
;   Locates the installed Python acquisition program independently of the current directory.
(define-runtime-path python-installer "install-native-windows.py")

(module+ main
  (unless (eq? (system-type 'os) 'windows)
    (error 'install-windows-natives "this explicit installer requires Windows"))
  (define python
    (or (and (getenv "PYTHON") (find-executable-path (getenv "PYTHON")))
        (find-executable-path "python")
        (error 'install-windows-natives "install Python 3.12 or later, or set PYTHON to its executable")))
  (define racket
    (or (find-executable-path (find-system-path 'exec-file))
        (error 'install-windows-natives "cannot locate the selected Racket executable")))
  (exit (apply system*/exit-code python python-installer "--racket" racket
               (vector->list (current-command-line-arguments)))))
