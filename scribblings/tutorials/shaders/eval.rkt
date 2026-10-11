#lang racket/base

(require racket/runtime-path scribble/eval skia "waves.rkt" "../support/figures.rkt")
(provide shaders-interaction shaders-racketblock+eval
         shader-pict waves-pict wave-poster-pict wave-variants)
(define-runtime-path program-source "waves.rkt")
(define-runtime-path program-directory ".")
(define shaders-eval (make-base-eval))
(shaders-eval `(current-directory ,(path->string program-directory)))
(shaders-eval '(require racket skia))
(shaders-eval `(require (file ,(path->string program-source))))
(define effect (make-runtime-effect wave-source))

(define (shader-pict source uniforms)
  (with-skia ([compiled (make-runtime-effect source)]
              [shader (runtime-effect->shader compiled #:uniforms uniforms)]
              [paint (make-paint #:shader shader)])
    (render-pict 320 180 (lambda (canvas) (draw-rect canvas 0 0 320 180 paint)))))

(define (waves-pict #:bend [bend 0.28] #:phase [phase 0])
  (render-pict 480 210
               (lambda (canvas)
                 (draw-wave-panel canvas effect 0 0 480 210 #:bend bend #:phase phase))
               #:background "#0A1527"))

(define (wave-poster-pict)
  (render-pict poster-width poster-height (lambda (canvas) (draw-wave-poster canvas effect))
               #:scale 0.85))

(define (wave-variants)
  (apply figure-row
         (for/list ([bend '(0 0.15 0.35)])
           (captioned-pict
            (format "bend = ~a" bend)
            (render-pict 204 152
                         (lambda (canvas)
                           (draw-wave-panel canvas effect 0 0 204 152 #:bend bend))
                         #:background "#0A1527")))))

(define-syntax-rule (shaders-interaction expression ...)
  (interaction #:eval shaders-eval expression ...))
(define-syntax-rule (shaders-racketblock+eval expression ...)
  (racketblock+eval #:eval shaders-eval expression ...))
