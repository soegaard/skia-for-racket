#lang racket/base
(require racket/class racket/draw
         "private/gpu-provider.rkt" "private/gpu-gl-system.rkt")
(provide make-racket-gl-provider)
;; This adapter borrows an existing Racket GL host. It owns neither its window
;; nor its event loop, and it does not swap buffers or draw through the host DC.
(define (make-racket-gl-provider gl)
  (unless (is-a? gl gl-context<%>)
    (raise-argument-error 'make-racket-gl-provider "gl-context<%>" gl))
  (unless (send gl ok?) (gpu-unavailable 'racket-gl-host "Racket GL context is unavailable"))
  (define-values (native-key describe resolve) (make-system-gl-tools))
  (define key (send gl call-as-current native-key))
  (unless key (gpu-unavailable 'native-gl-current "Racket host has no current native GL context"))
  (provider-with-resolver
   (make-gpu-provider
    #:name 'racket-gl #:backend 'opengl #:key key
    #:call-as-current (lambda (thunk) (send gl call-as-current thunk never-evt #t))
    #:current? (lambda () (and (send gl ok?) (eq? gl (get-current-gl-context))
                               (equal? key (native-key))))
    #:describe describe)
   resolve))
