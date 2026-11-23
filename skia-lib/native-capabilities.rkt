#lang racket/base

;;;
;;; Native Capability Catalog
;;;

;; Exposes the package's native capability declarations.
;; This public facade makes the checked native registry available without requiring callers to
;; depend on private ABI implementation paths.

;;;
;;; Imports and Exports
;;;

;; Explicit diagnostic API; importing it remains native-free.
(require (only-in "private/native.rkt" skia-native-capabilities skia-native-symbol-inventory)
         (only-in
          "private/native-abi.rkt"
          native-package-version
          native-abi-catalog
          native-abi-profiles))
(provide skia-native-capabilities skia-native-symbol-inventory
         native-package-version native-abi-catalog native-abi-profiles)
