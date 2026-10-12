#lang racket/base

(require racket/runtime-path scribble/eval skia "waves.rkt" "../support/figures.rkt")
(provide shaders-interaction shaders-racketblock+eval
         shader-pict bands-pict waves-pict wave-scene-pict wave-animation-strip wave-variants
         frequency-variants phase-pair hue-pair glow-pair origin-pair)

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

(define (bands-pict)
  (shader-pict bands-source (hash 'extent '(320 180) 'frequency 5)))

(define (waves-pict #:frequency [frequency 5]
                    #:bend [bend 0.30]
                    #:phase [phase 0]
                    #:hue [hue 0.08])
  (render-pict 480 210
               (lambda (canvas)
                 (draw-wave-panel canvas effect 0 0 480 210
                                  #:frequency frequency
                                  #:bend bend
                                  #:phase phase
                                  #:hue hue))
               #:background "#070D21"))

(define (wave-scene-pict seconds #:scale [scale 0.75] #:hue [hue 0.08])
  (render-pict scene-width scene-height
               (lambda (canvas)
                 (draw-wave-scene canvas effect seconds scene-width scene-height
                                  #:hue hue))
               #:scale scale))

(define (wave-animation-strip)
  (apply figure-row
         (for/list ([seconds '(0.0 0.75 1.5)])
           (captioned-pict
            (format "time = ~a seconds" seconds)
            (wave-scene-pict seconds #:scale 0.30)))))

(define (wave-variants)
  (apply figure-row
         (for/list ([bend '(0 0.15 0.35)])
           (captioned-pict
            (format "bend = ~a" bend)
            (render-pict 204 152
                         (lambda (canvas)
                           (draw-wave-panel canvas effect 0 0 204 152 #:bend bend))
                         #:background "#070D21")))))

(define (frequency-variants)
  (apply figure-row
         (for/list ([frequency '(3 5 8)])
           (captioned-pict
            (format "frequency = ~a / bend = 0" frequency)
            (render-pict 204 152
                         (lambda (canvas)
                           (draw-wave-panel canvas effect 0 0 204 152
                                            #:frequency frequency
                                            #:bend 0))
                         #:background "#070D21")))))

(define (phase-pair)
  (apply figure-row
         (for/list ([phase '(0 1)])
           (captioned-pict
            (format "phase = ~a / bend = 0.30" phase)
            (render-pict 300 164
                         (lambda (canvas)
                           (draw-wave-panel canvas effect 0 0 300 164 #:phase phase))
                         #:background "#070D21")))))

(define (hue-pair)
  (figure-row
   (captioned-pict
    "hue = 0.08"
    (render-pict 300 164
                 (lambda (canvas)
                   (draw-wave-panel canvas effect 0 0 300 164 #:hue 0.08))
                 #:background "#070D21"))
   (captioned-pict
    "hue = 0.58"
    (render-pict 300 164
                 (lambda (canvas)
                   (draw-wave-panel canvas effect 0 0 300 164 #:hue 0.58))
                 #:background "#070D21"))))

(define (glow-pair)
  (apply figure-row
         (for/list ([strength '(0 1)])
           (captioned-pict
            (format "glow = ~a" strength)
            (render-pict 300 164
                         (lambda (canvas)
                           (draw-wave-panel canvas effect 0 0 300 164
                                            #:glow strength))
                         #:background "#070D21")))))

(define (origin-pair)
  (define (one local-origin?)
    (render-pict 300 208
                 (lambda (canvas)
                   (define ink (make-paint #:color "#203653"))
                   (define font (make-font #:size 13))
                   (define shader (make-wave-shader effect 224 136))
                   (define paint (make-paint #:shader shader))
                   (draw-simple-text canvas "Same rectangle at (48, 32)" 16 20 font ink)
                   (if local-origin?
                       (draw-wave-panel canvas effect 48 32 224 136)
                       (draw-rounded-rect canvas 48 32 224 136 20 20 paint)))))
  (figure-row
   (captioned-pict "Rectangle moved; origin unchanged" (one #f))
   (captioned-pict "Origin moved with the rectangle" (one #t))))

(define-syntax-rule (shaders-interaction expression ...)
  (interaction #:eval shaders-eval expression ...))
(define-syntax-rule (shaders-racketblock+eval expression ...)
  (racketblock+eval #:eval shaders-eval expression ...))
