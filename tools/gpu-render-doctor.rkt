#lang racket/base

;;;
;;; One-Shot GPU Render Diagnostic
;;;

;; Runs the native one-shot rendering suite and writes a result receipt.
;; This command validates the public render convenience API on a selected GPU backend.

;;;
;;; Imports and Exports
;;;

(require racket/cmdline
         rackunit/text-ui
         "../tests/gpu-render-native-test.rkt")

;;;
;;; One-Shot Rendering Check
;;;

;; No fallback and no successful skip: an unavailable selected backend fails.

(module+ main

  ;;;
  ;;; Command-Line Run
  ;;;

  ; backend : (or/c symbol? #f)
  ;   Selects the explicitly requested GPU backend for this command-line run.
  (define backend #f)

  ; adapter : (or/c symbol? #f)
  ;   Selects Direct3D adapter policy when that backend is requested.
  (define adapter #f)
  (command-line
   #:program "gpu-render-doctor.rkt"
   #:once-each
   [("--backend") name "Required: metal or direct3d"
                    (set! backend (string->symbol name))]
   [("--adapter") name "Direct3D only: hardware or warp"
                    (set! adapter (string->symbol name))]
   #:args () (void))
  (unless (memq backend '(metal direct3d))
    (raise-user-error 'gpu-render-doctor "select --backend metal or --backend direct3d"))
  (unless (or (not adapter)
              (and (eq? backend 'direct3d) (memq adapter '(hardware warp))))
    (raise-user-error 'gpu-render-doctor "--adapter hardware/warp requires Direct3D"))

  ; failures : exact-nonnegative-integer?
  ;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures
    (run-tests (make-gpu-render-native-tests #:backend backend #:adapter adapter)))
  (unless (zero? failures)
    (exit 1))
  (printf "One-shot GPU rendering: passed on ~a (~a).\n"
          backend (or adapter 'default)))
