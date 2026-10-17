#lang racket

;;;
;;; Squadron Model Test
;;;

;; Checks Squadron tutorial behavior with focused regression tests.
;; This module guards the documentation's examples and support code against regressions.

;;;
;;; Imports and Exports
;;;

(require rackunit "model.rkt" "../support/sprite-math.rkt")
;;;
;;; Test Data and Helpers
;;;

; none : any/c -> boolean?
;   Models an input state in which no key is held.
(define (none _) #f)

; keys : any/c ... -> procedure?
;   Builds a held-key predicate for deterministic simulation tests.
(define (keys . names) (lambda (name) (and (member name names) #t)))
;;;
;;; Regression Checks
;;;

(module+ test
  (test-case "new game has three lives and two enemy types"
    (define world (make-game))
    (check-equal? (game-lives world) 3)
    (check-equal? (length (game-enemies world)) 21)
    (check-equal? (count (lambda (e) (eq? (enemy-kind e) 'guard)) (game-enemies world)) 7))
  (test-case "ship moves and remains inside the playfield"
    (define world (make-game))
    (for ([_ (in-range 120)]) (step-game! world fixed-step (keys 'right)))
    (check-= (game-player-x world) 612 1e-9))
  (test-case "opposite controls cancel"
    (define world (make-game))
    (step-game! world fixed-step (keys #\a #\d))
    (check-= (game-player-x world) 320 1e-9))
  (test-case "held fire is bounded by a cooldown"
    (define world (make-game))
    (for ([_ (in-range 17)]) (step-game! world fixed-step (keys #\space)))
    (check-equal? (length (game-shots world)) 1)
    (step-game! world fixed-step (keys #\space))
    (step-game! world fixed-step (keys #\space))
    (check-equal? (length (game-shots world)) 2))
  (test-case "stationary projectile containment is defined"
    (check-true (swept-hit? 5 5 5 5 5 5 2))
    (check-false (swept-hit? 0 0 0 0 5 5 2)))
  (test-case "fast projectiles do not skip a circle"
    (check-true (swept-hit? 10 200 10 0 10 100 8))
    (check-false (swept-hit? 40 200 40 0 10 100 8)))
  (test-case "a scout hit scores once and consumes the shot"
    (define world (make-game))
    (define target (enemy 7 'scout 1 #f))
    (define-values (x y) (enemy-position target 1))
    (set-game-enemies! world (list target (enemy 8 'scout 1 #f)))
    (set-game-shots! world (list (shot x (+ y 2) 0 -540 #f)))
    (step-game! world fixed-step none)
    (check-equal? (game-score world) 100)
    (check-equal? (length (game-enemies world)) 1)
    (check-equal? (game-shots world) '()))
  (test-case "guards require two hits"
    (define world (make-game))
    (define target (enemy 0 'guard 2 #f))
    (define-values (x y) (enemy-position target 1))
    (set-game-enemies! world (list target))
    (set-game-shots! world (list (shot x y 0 -540 #f)))
    (step-game! world fixed-step none)
    (check-equal? (enemy-hp (car (game-enemies world))) 1)
    (check-equal? (game-score world) 0))
  (test-case "one shot cannot destroy two overlapping enemies"
    (define world (make-game))
    (define attack (dive 50 300 180 320 1))
    (define target (enemy 7 'scout 1 attack))
    (define next (struct-copy enemy target [dive (struct-copy dive attack [age 51])]))
    (define-values (x y) (enemy-position next 1))
    (set-game-enemies! world (list target (enemy 8 'scout 1 attack)))
    (set-game-shots! world (list (shot x y 0 0 #f)))
    (step-game! world fixed-step none)
    (check-equal? (game-score world) 100)
    (check-equal? (length (game-enemies world)) 1))
  (test-case "several bullets cannot remove several lives in one step"
    (define world (make-game))
    (set-game-shots! world (make-list 5 (shot 320 player-y 0 180 #t)))
    (step-game! world fixed-step none)
    (check-equal? (game-lives world) 2)
    (check-true (positive? (game-shield world))))
  (test-case "game over freezes the simulation"
    (define world (make-game))
    (set-game-lives! world 1)
    (set-game-shots! world (list (shot 320 player-y 0 0 #t)))
    (step-game! world fixed-step none)
    (check-equal? (game-mode world) 'game-over)
    (define before (format "~s" world))
    (for ([_ (in-range 120)]) (step-game! world fixed-step (keys #\space 'left)))
    (check-equal? (format "~s" world) before))
  (test-case "cleared waves keep the score and advance difficulty"
    (define world (make-game))
    (set-game-score! world 2800)
    (set-game-enemies! world '())
    (step-game! world fixed-step none)
    (check-equal? (game-mode world) 'wave-clear)
    (for ([_ (in-range 180)]) (step-game! world fixed-step none))
    (check-equal? (game-wave world) 2)
    (check-equal? (game-score world) 2800)
    (check-equal? (length (game-enemies world)) 21))
  (test-case "a dive starts at the existing formation position"
    (define world (make-game))
    (begin-dive! world)
    (define sprite (findf enemy-dive (game-enemies world)))
    (define-values (x y) (enemy-position sprite 0))
    (define-values (home-x home-y) (formation-position (enemy-id sprite) 0))
    (check-= x home-x 1e-9)
    (check-= y home-y 1e-9))
  (test-case "dive curve exits below the playfield"
    (define-values (x y) (dive-point (dive 288 110 186 320 -1)))
    (check-= x 320 1e-9)
    (check-= y 820 1e-9))
  (test-case "return path rejoins a moving formation slot"
    (define sprite (enemy 8 'scout 1 (dive 432 180 186 320 1)))
    (define-values (x y) (enemy-position sprite 500))
    (define-values (home-x home-y) (formation-position 8 500))
    (check-= x home-x 1e-9)
    (check-= y home-y 1e-9))
  (test-case "arbitrary simulation steps are rejected"
    (check-exn exn:fail? (lambda () (step-game! (make-game) 1 none))))
  (test-case "same key sequence gives identical states"
    (define a (make-game))
    (define b (make-game))
    (for ([tick (in-range 1200)])
      (define held (if (< (modulo tick 240) 120) (keys #\space #\a) (keys #\space #\d)))
      (step-game! a fixed-step held)
      (step-game! b fixed-step held))
    (check-equal? a b)))
