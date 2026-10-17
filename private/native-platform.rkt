#lang racket/base

;;;
;;; Native Platform Identification
;;;

;; Maps the host platform to the expected native library package and filename.
;; Supplies platform naming shared by native loading and diagnostics.

(provide native-rid native-library-name)
;; Pure selection; a recognized RID is not an assertion of GPU support.
; native-rid : symbol? symbol? -> (or/c #f string?)
;;   Maps supported host OS/architecture pairs to installed native-package directory names.
(define (native-rid os arch)
  (case os
    [(macosx) "osx"]
    [(unix) (case arch [(x86_64) "linux-x64"] [(aarch64) "linux-arm64"] [else #f])]
    [(windows) (case arch [(x86_64) "win-x64"] [else #f])]
    [else #f]))
; native-library-name : symbol? symbol? -> string?
;;   Combines SkiaSharp or HarfBuzzSharp's base name with the platform shared-library suffix.
(define (native-library-name kind os)
  (unless (memq kind '(skia harfbuzz))
    (raise-argument-error 'native-library-name "'skia or 'harfbuzz" kind))
  (string-append (if (eq? kind 'skia) "libSkiaSharp" "libHarfBuzzSharp")
                 (case os [(macosx) ".dylib"] [(windows) ".dll"] [else ".so"])))
