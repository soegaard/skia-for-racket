#lang racket/base

;;;
;;; Native ABI Diagnostic
;;;

;; Prints the active native ABI profile and resolved library information.
;; This diagnostic supplies release and compatibility checks with the actual loaded profile.

(require json "../native-capabilities.rkt")
(module+ main

  ;;;
  ;;; Command-Line Run
  ;;;

  ; report : hash?
  ;   Contains the detected native milestone, symbols, and ABI capability metadata.
  (define report (skia-native-capabilities))
  (unless (and (hash-ref report 'required_cpu_symbols_resolved #f)
               (hash-ref report 'racket_layouts_checked #f))
    (error 'native-abi-doctor "incomplete native ABI preflight"))
  (write-json report)
  (newline))
