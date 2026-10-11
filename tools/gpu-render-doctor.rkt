#lang racket/base

(require racket/cmdline
         rackunit/text-ui
         "../tests/gpu-render-native-test.rkt")

;; No fallback and no successful skip: an unavailable selected backend fails.
(module+ main
  (define backend #f)
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
  (define failures
    (run-tests (make-gpu-render-native-tests #:backend backend #:adapter adapter)))
  (unless (zero? failures)
    (exit 1))
  (printf "One-shot GPU rendering: passed on ~a (~a).\n"
          backend (or adapter 'default)))
