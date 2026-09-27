#lang racket/base
;; Loaded only by an explicit live GL probe, never by skia or skia/gpu.
(require racket/class racket/draw "../gpu-racket-gl.rkt"
         "../private/gpu-provider.rkt")
(provide call-with-gpu-test-host)
(define (call-with-gpu-test-host proc)
  ;; Even compiling this module on a CPU-only machine does not require gui-lib.
  (define-values (frame% canvas% sleep/yield)
    (with-handlers ([exn:fail? (lambda (e) (gpu-unavailable 'gui-initialization "~a" (exn-message e)))])
      (values (dynamic-require 'racket/gui/base 'frame%)
              (dynamic-require 'racket/gui/base 'canvas%)
              (dynamic-require 'racket/gui/base 'sleep/yield))))
  (define config (new gl-config%))
  ;; Racket's documented core-profile support is macOS/Linux. Windows uses
  ;; the supported legacy request; the doctor reports the actual GL version.
  (define legacy? (eq? (system-type 'os) 'windows))
  (send config set-legacy? legacy?)
  (send config set-stencil-size 8)
  (send config set-double-buffered #t)
  (send config set-hires-mode #t)
  (define frame (new frame% [label "Skia 0.38: OpenGL backend probe"] [width 160] [height 120]))
  (dynamic-wind
    void
    (lambda ()
      (define canvas (new canvas% [parent frame] [style '(gl no-autoclear)] [gl-config config]))
      (send frame show #t)
      (sleep/yield 0.05)
      (define gl (send (send canvas get-dc) get-gl-context))
      (unless (and gl (send gl ok?))
        (gpu-unavailable 'racket-gl-host "window could not create a usable Racket GL context"))
      (proc (make-racket-gl-provider gl)
            (hasheq 'requested_legacy_profile legacy?
                    'requested_stencil_bits 8 'requested_hires #t
                    'provider "racket/gui GL host"
                    'presentation_tested #f
                    'headless #f)))
    (lambda () (send frame show #f))))
