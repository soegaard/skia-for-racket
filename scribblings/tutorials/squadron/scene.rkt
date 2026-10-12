#lang racket

(require skia "model.rkt" "../support/sprite-math.rkt")
(provide draw-game game-sprites enemy-angle travel-heading)

;; Enemy artwork points down (toward positive y) at zero rotation.
;; Convert the travel direction to a clockwise angle from that orientation.
(define (travel-heading x y next-x next-y)
  (if (and (= x next-x) (= y next-y))
      0
      (- (* (/ 180 pi) (atan (- next-y y) (- next-x x))) 90)))

(define (enemy-angle sprite ticks)
  (define attack (enemy-dive sprite))
  (cond
    [(not attack) 0]
    [else
     (define-values (x y) (enemy-position sprite ticks))
     (define future (struct-copy enemy sprite
                                 [dive (struct-copy dive attack [age (add1 (dive-age attack))])]))
     (define-values (next-x next-y) (enemy-position future (add1 ticks)))
     (travel-heading x y next-x next-y)]))

;; Each entry is (cell x y degrees scale). This render list contains only data.
(define (game-sprites world)
  (define tick (game-ticks world))
  (define frame (modulo (quotient tick 12) 2))
  (append
   (for/list ([sprite (in-list (game-enemies world))])
     (define-values (x y) (enemy-position sprite tick))
     (list (+ (if (eq? (enemy-kind sprite) 'guard) 4 2) frame)
           x y (enemy-angle sprite tick) 1))
   (if (and (positive? (game-lives world))
            (or (zero? (game-shield world)) (even? (quotient tick 8))))
       (list (list frame (game-player-x world) player-y 0 1)) '())
   (for/list ([bullet (in-list (game-shots world))])
     (list (if (shot-hostile? bullet) 7 6) (shot-x bullet) (shot-y bullet) 0 0.65))
   (for/list ([effect (in-list (game-blasts world))])
     (list (+ 8 (min 5 (quotient (blast-age effect) 8)))
           (blast-x effect) (blast-y effect) 0 1.4))))

(define (draw-game canvas atlas world)
  (define sprites (game-sprites world))
  (define (transform sprite)
    (match-define (list cell x y angle scale) sprite)
    (make-atlas-transform x y #:rotation angle #:scale scale #:anchor sprite-anchor))
  (canvas-clear! canvas "#070D21")
  (with-skia ([star (make-paint #:color "#3D6388")]
              [panel (make-paint #:color "#10233A")]
              [ink (make-paint #:color "#E5F8FF")]
              [accent (make-paint #:color "#66DEEC")]
              [warning (make-paint #:color "#FFCD78")]
              [shade (make-paint #:color (rgba 5 12 28 225))]
              [title (make-font #:size 25)]
              [detail (make-font #:size 15)]
              [large (make-font #:size 38)]
              [caption (make-font #:size 12)])
    (for ([index (in-range 70)])
      (define x (+ 8 (modulo (* index 173) 624)))
      (define y (+ 70 (modulo (* index 137) 670)))
      (draw-circle canvas x y (if (zero? (modulo index 5)) 1.4 0.7) star))
    (draw-atlas canvas atlas (map transform sprites)
                (map (lambda (sprite) (sprite-source (first sprite))) sprites)
                #:sampling 'linear)
    ;; HUD is not part of the sprite batch. It cannot be hit by projectiles.
    (draw-rect canvas 0 0 scene-width 70 panel)
    (draw-simple-text canvas "STAR SQUADRON" 22 32 title ink)
    (draw-simple-text canvas (format "SCORE  ~a" (game-score world)) 24 56 detail accent)
    (draw-simple-text canvas (format "WAVE  ~a" (game-wave world)) 318 56 detail accent)
    (draw-simple-text canvas (format "LIVES  ~a" (game-lives world)) 514 56 detail warning)
    (draw-simple-text canvas "MOVE  A/D or arrows     FIRE  Space     PAUSE  P     RESTART  R"
                      25 740 caption ink)
    (unless (eq? (game-mode world) 'playing)
      (define text (if (eq? (game-mode world) 'game-over) "GAME OVER" "WAVE CLEAR"))
      (define x (/ (- scene-width (measure-simple-text large text)) 2))
      (define prompt (if (eq? (game-mode world) 'game-over)
                         "Press R or click Restart" "Incoming squadron..."))
      (define prompt-x (/ (- scene-width (measure-simple-text detail prompt)) 2))
      (draw-rounded-rect canvas 64 328 512 122 18 18 shade)
      (draw-simple-text canvas text x 382 large warning)
      (draw-simple-text canvas prompt prompt-x 418 detail ink))))
