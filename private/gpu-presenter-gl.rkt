#lang racket/base
(require racket/class "../gpu.rkt" "../gpu-racket-gl.rkt" "gpu-window.rkt"
         "gpu-io-trace.rkt" "core.rkt" "gpu-provider.rkt"
         (submod "gpu-presenter.rkt" adapter-internals))
(provide make-gl-presentation-adapter)
;; Called on the owning eventspace handler, before Ganesh has touched the host.
(define (make-gl-presentation-adapter gl measure post background)
  (unless (and gl (send gl ok?)) (gpu-unavailable 'presentation-gl "Racket GL host unavailable"))
  (define access (send gl call-as-current make-window-gl-access))
  (define context (make-gpu-context (make-racket-gl-provider gl)))
  (presentation-adapter
   'opengl context measure
   (lambda (metrics receive)
     (call-with-gpu-context context
       (lambda ()
         (access (hash-ref metrics 'pixel_width) (hash-ref metrics 'pixel_height)
           (lambda (description)
             (call-with-window-target context description
               (lambda (surface)
                 (define info (gpu-surface-info surface))
                 (define c (surface-canvas surface))
                 (canvas-clear! c background)
                 (receive c (hash-set* info 'target_identity (hash-ref info 'framebuffer_id)
                                      'presentation_path "host-framebuffer/swap-buffers")
                   (lambda ()
                     (unless (= (canvas-save-count c) 1)
                       (error 'gpu-presenter "render callback left unbalanced canvas saves/layers"))
                     (gpu-flush-and-submit! context)
                     (send gl swap-buffers)
                     (record-gpu-io! (hasheq 'kind "present-request" 'backend "opengl"
                                             'method "swap-buffers" 'wait_requested #f)))))))))))
   post (lambda () (gpu-context-close! context))
   (lambda () (hasheq 'context (gpu-context-info context)
                     'presentation_path "host-framebuffer/swap-buffers"
                     'owns_host_framebuffer #f 'live_drawables 0))))
