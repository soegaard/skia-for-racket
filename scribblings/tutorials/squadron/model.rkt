#lang racket

;; Fixed-step game rules: no drawing, native objects, clock reads, or randomness.
(require "../support/sprite-math.rkt")
(provide (struct-out enemy) (struct-out dive) (struct-out shot) (struct-out blast)
         (struct-out game) scene-width scene-height player-y
         make-game formation-position enemy-position dive-point begin-dive!
         swept-hit? fire-player! step-game! demonstration-game)

(define scene-width 640)
(define scene-height 760)
(define player-y 690)
(struct dive (age x y target-x side) #:transparent)
(struct enemy (id kind hp dive) #:transparent)
(struct shot (x y vx vy hostile?) #:transparent)
(struct blast (x y age) #:transparent)
(struct game (ticks player-x lives score wave mode cooldown shield enemies shots blasts countdown)
  #:mutable #:transparent)

(define (make-fleet)
  (for/list ([id (in-range 21)])
    (define kind (if (< id 7) 'guard 'scout))
    (enemy id kind (if (eq? kind 'guard) 2 1) #f)))

(define (make-game)
  (game 0 320.0 3 0 1 'playing 0 0 (make-fleet) '() '() 0))

(define (formation-position id ticks)
  (define seconds (* ticks fixed-step))
  (values (+ 110 (* 70 (modulo id 7)) (* 26 (sin (* 0.8 seconds))))
          (+ 128 (* 58 (quotient id 7)) (* 6 (sin (+ (* 1.2 seconds) (* id 0.3)))))))

(define (cubic a b c d amount)
  (define rest (- 1 amount))
  (+ (* rest rest rest a) (* 3 rest rest amount b)
     (* 3 rest amount amount c) (* amount amount amount d)))

(define (dive-point attack)
  (define amount (min 1 (/ (dive-age attack) 288.0)))
  (define side (dive-side attack))
  (values
   (cubic (dive-x attack)
          (max 32 (min 608 (+ (dive-x attack) (* side 200))))
          (max 32 (min 608 (- (dive-target-x attack) (* side 130))))
          (dive-target-x attack) amount)
   (cubic (dive-y attack) 370 510 820 amount)))

(define (enemy-position sprite ticks)
  (define attack (enemy-dive sprite))
  (cond
    [(not attack) (formation-position (enemy-id sprite) ticks)]
    [(< (dive-age attack) 288) (dive-point attack)]
    [else
     ;; Re-enter from above only after the sprite has gone below the screen.
     (define amount (min 1 (/ (- (dive-age attack) 288) 144.0)))
     (define-values (home-x home-y) (formation-position (enemy-id sprite) ticks))
     (values (cubic (dive-target-x attack) (dive-target-x attack) home-x home-x amount)
             (cubic -60 -20 (- home-y 50) home-y amount))]))

(define (begin-dive! world)
  (define available (filter (lambda (sprite) (not (enemy-dive sprite))) (game-enemies world)))
  (unless (null? available)
    (define selected (list-ref available (modulo (quotient (game-ticks world) 120)
                                               (length available))))
    (define-values (x y) (enemy-position selected (game-ticks world)))
    (define attack (dive 0 x y (game-player-x world) (if (even? (enemy-id selected)) -1 1)))
    (set-game-enemies!
     world
     (map (lambda (sprite)
            (if (= (enemy-id sprite) (enemy-id selected))
                (struct-copy enemy sprite [dive attack]) sprite))
          (game-enemies world)))))

(define (fire-player! world)
  (when (and (eq? (game-mode world) 'playing) (zero? (game-cooldown world)))
    (set-game-shots! world
                    (cons (shot (game-player-x world) (- player-y 24) 0 -540 #f)
                          (game-shots world)))
    (set-game-cooldown! world 18)))

(define (aimed-shot x y target-x speed)
  (define dx (- target-x x))
  (define dy (max 40 (- player-y y)))
  (define distance (sqrt (+ (* dx dx) (* dy dy))))
  (shot x y (* speed (/ dx distance)) (* speed (/ dy distance)) #t))

;; Swept projectile against a circle at the current simulation position.
;; This avoids missing a small target simply because a fast shot crosses it.
(define (swept-hit? x0 y0 x1 y1 center-x center-y radius)
  (define dx (- x1 x0))
  (define dy (- y1 y0))
  (define length-squared (+ (* dx dx) (* dy dy)))
  (define amount
    (if (zero? length-squared) 0
        (max 0 (min 1 (/ (+ (* (- center-x x0) dx) (* (- center-y y0) dy))
                            length-squared)))))
  (<= (+ (sqr (- (+ x0 (* amount dx)) center-x))
         (sqr (- (+ y0 (* amount dy)) center-y)))
      (sqr radius)))

(define (hit-player! world)
  (when (and (eq? (game-mode world) 'playing) (zero? (game-shield world)))
    (set-game-blasts! world
                      (cons (blast (game-player-x world) player-y 0) (game-blasts world)))
    (set-game-lives! world (sub1 (game-lives world)))
    (set-game-player-x! world 320.0)
    (set-game-shield! world 240)
    (when (zero? (game-lives world)) (set-game-mode! world 'game-over))))

(define (damage-enemy! world target)
  (define remaining (sub1 (enemy-hp target)))
  (cond
    [(positive? remaining)
     (set-game-enemies!
      world (map (lambda (sprite)
                   (if (= (enemy-id sprite) (enemy-id target))
                       (struct-copy enemy sprite [hp remaining]) sprite))
                 (game-enemies world)))]
    [else
     (define-values (x y) (enemy-position target (game-ticks world)))
     (set-game-blasts! world (cons (blast x y 0) (game-blasts world)))
     (set-game-score! world (+ (game-score world)
                              (if (eq? (enemy-kind target) 'guard) 200 100)))
     (set-game-enemies! world
                       (filter (lambda (sprite) (not (= (enemy-id sprite) (enemy-id target))))
                               (game-enemies world)))]))

(define (step-shots! world seconds)
  (define survivors
    (for/fold ([result '()]) ([bullet (in-list (game-shots world))])
      (define next-x (+ (shot-x bullet) (* seconds (shot-vx bullet))))
      (define next-y (+ (shot-y bullet) (* seconds (shot-vy bullet))))
      (define (hits? x y radius)
        (swept-hit? (shot-x bullet) (shot-y bullet) next-x next-y x y radius))
      (define target
        (and (not (shot-hostile? bullet))
             (for/first ([sprite (in-list (game-enemies world))]
                         #:when
                         (let-values ([(x y) (enemy-position sprite (game-ticks world))])
                           (hits? x y 19)))
               sprite)))
      (define player-hit?
        (and (shot-hostile? bullet) (hits? (game-player-x world) player-y 16)))
      (cond
        [target (damage-enemy! world target) result]
        [player-hit? (hit-player! world) result]
        [(or (< next-y -30) (> next-y 810) (< next-x -30) (> next-x 670)) result]
        [else (cons (struct-copy shot bullet [x next-x] [y next-y]) result)])))
  (set-game-shots! world (reverse survivors)))

(define (step-enemies! world)
  (set-game-enemies!
   world
   (for/list ([sprite (in-list (game-enemies world))])
     (define attack (enemy-dive sprite))
     (if attack
         (struct-copy enemy sprite
                      [dive (and (< (dive-age attack) 431)
                                 (struct-copy dive attack [age (add1 (dive-age attack))]))])
         sprite)))
  (for ([sprite (in-list (game-enemies world))])
    (define attack (enemy-dive sprite))
    (when (and attack (= (dive-age attack) 100))
      (define-values (x y) (enemy-position sprite (game-ticks world)))
      (set-game-shots!
       world (cons (aimed-shot x y (game-player-x world) (+ 185 (* 8 (min 10 (game-wave world)))))
                   (game-shots world)))))
  (define dive-period (max 95 (- 220 (* 12 (game-wave world)))))
  (when (zero? (modulo (game-ticks world) dive-period)) (begin-dive! world))
  (when (and (pair? (game-enemies world)) (zero? (modulo (game-ticks world) 150)))
    (define fleet (game-enemies world))
    (define shooter (list-ref fleet (modulo (quotient (game-ticks world) 150) (length fleet))))
    (define-values (x y) (enemy-position shooter (game-ticks world)))
    (when (< y 580)
      (set-game-shots! world (cons (aimed-shot x y (game-player-x world) 180)
                                  (game-shots world)))))
  (for ([sprite (in-list (game-enemies world))])
    (define-values (x y) (enemy-position sprite (game-ticks world)))
    (when (<= (+ (sqr (- x (game-player-x world))) (sqr (- y player-y))) (sqr 28))
      (hit-player! world))))

(define (step-game! world seconds held?)
  ;; The shared window always supplies fixed-step; direct callers must do so too.
  (unless (= seconds fixed-step) (error 'step-game! "expected the fixed 1/120-second step"))
  (unless (eq? (game-mode world) 'game-over)
    (set-game-ticks! world (add1 (game-ticks world)))
    (set-game-blasts! world
                      (for/list ([effect (in-list (game-blasts world))]
                                 #:when (< (blast-age effect) 47))
                        (struct-copy blast effect [age (add1 (blast-age effect))]))))
  (case (game-mode world)
    [(playing)
     (set-game-cooldown! world (max 0 (sub1 (game-cooldown world))))
     (set-game-shield! world (max 0 (sub1 (game-shield world))))
     (define direction
       (- (if (or (held? 'right) (held? #\d)) 1 0)
          (if (or (held? 'left) (held? #\a)) 1 0)))
     (set-game-player-x! world (max 28 (min 612 (+ (game-player-x world)
                                                   (* direction 340 seconds)))))
     (when (held? #\space) (fire-player! world))
     (step-enemies! world)
     (step-shots! world seconds)
     (when (and (null? (game-enemies world)) (eq? (game-mode world) 'playing))
       (set-game-mode! world 'wave-clear)
       (set-game-countdown! world 180)
       (set-game-shots! world '()))]
    [(wave-clear)
     (set-game-countdown! world (sub1 (game-countdown world)))
     (when (zero? (game-countdown world))
       (set-game-wave! world (add1 (game-wave world)))
       (set-game-enemies! world (make-fleet))
       (set-game-shield! world 120)
       (set-game-mode! world 'playing))]
    [else (void)]))

;; A reproducible illustrated state, not a claim of a captured play session.
(define (demonstration-game)
  (define world (make-game))
  (set-game-ticks! world 200)
  (set-game-score! world 300)
  (set-game-enemies!
   world
   (for/list ([sprite (in-list (game-enemies world))]
              #:unless (memv (enemy-id sprite) '(8 13 20)))
     (case (enemy-id sprite)
       [(7) (struct-copy enemy sprite [dive (dive 104 130 186 490 1)])]
       [(18) (struct-copy enemy sprite [dive (dive 155 430 244 180 -1)])]
       [else sprite])))
  (set-game-shots! world
                   (list (shot 320 400 0 -540 #f) (shot 320 578 0 -540 #f)
                         (shot 246 536 40 180 #t) (shot 442 394 -40 180 #t)))
  (set-game-blasts! world (list (blast 530 244 19)))
  world)
