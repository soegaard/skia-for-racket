#lang racket/base

;;;
;;; Package Version Check
;;;

;; Reads package metadata and prints the version expected by validation and release tooling.
;; This small probe connects the Racket package declaration to external build checks.

;;;
;;; Imports and Exports
;;;
;; Use Racket's real predicate, not a SemVer approximation, before compilation.
(require setup/getinfo version/utils racket/runtime-path)

;;;
;;; Diagnostic Operations
;;;

; root : path?
;   Locates .. relative to this module, independent of the invoking directory.
(define-runtime-path root "..")

; info : procedure?
;   Looks up package metadata fields from the repository's info.rkt.
(define info (get-info/full root))
(unless info (error 'package-version "package metadata could not be read"))

; value : (or/c string? #f)
;   Holds the declared version before the command validates and prints it.
(define value (info 'version (lambda () #f)))
(unless (valid-version? value)
  (error 'package-version "invalid Racket package version: ~e" value))
(printf "Racket package version: ~a (valid-version? passed)\n" value)
