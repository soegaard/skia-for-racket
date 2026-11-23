#lang racket/base

;; Only the explicit network-enabled staging subprocess uses this PEM bundle.
;; The bundle comes from Python's verified roots on the same disposable runner.
;; Normal package installation and network-denied validation keep their defaults.

(require openssl pkg/lib racket/file)

(define arguments (vector->list (current-command-line-arguments)))
(unless (>= (length arguments) 3)
  (error 'catalog-raco "expected an absolute cache directory, PEM file or -, and raco arguments"))
(when (getenv "PLT_PKG_SSL_NO_VERIFY")
  (error 'catalog-raco "HTTPS certificate verification must remain enabled"))
(define cache (string->path (car arguments)))
(unless (and (complete-path? cache) (not (link-exists? cache)))
  (error 'catalog-raco "expected an absolute private cache directory"))
(make-directory* cache)
(define roots (and (not (equal? (cadr arguments) "-")) (string->path (cadr arguments))))
(when roots
  (unless (and (complete-path? roots) (file-exists? roots) (not (link-exists? roots))
               (< 0 (file-size roots)) (<= (file-size roots) (* 16 1024 1024)))
    (error 'catalog-raco "missing, unsafe or oversized trusted PEM bundle"))
  ;; Parse eagerly so a malformed bundle fails before any network access.
  (ssl-load-verify-source! (ssl-make-client-context 'auto) roots))

(parameterize ([ssl-default-verify-sources (if roots (list roots) (ssl-default-verify-sources))]
               [current-pkg-download-cache-dir cache]
               [current-command-line-arguments (list->vector (cddr arguments))])
  (dynamic-require 'raco #f))
