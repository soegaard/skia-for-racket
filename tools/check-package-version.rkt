#lang racket/base
;; Use Racket's real predicate, not a SemVer approximation, before compilation.
(require setup/getinfo version/utils racket/runtime-path)
(define-runtime-path root "..")
(define info (get-info/full root))
(unless info (error 'package-version "package metadata could not be read"))
(define value (info 'version (lambda () #f)))
(unless (valid-version? value)
  (error 'package-version "invalid Racket package version: ~e" value))
(printf "Racket package version: ~a (valid-version? passed)\n" value)
