#lang racket

;; Retail IK+ floor shadows for the ball bonus.  This is display-only data:
;; neither the fighter masks nor the ball marks take part in collision tests.
;;
;; Fighter rows are copied from the four $C530 pose IDs reachable through the
;; bonus shield table: source/ikplus.asm R65, FighterShadowRows ($483A0).
;; Each string is eight 80-bit rows, encoded as ten bytes per row.  The Amiga
;; prepares the opposite-facing bank by reversing each 80-bit row at startup;
;; `fighter-floor-shadow-runs` does the equivalent reversal directly.

(provide fighter-floor-shadow-runs
         ball-floor-shadow-runs)

(define screen-width 320)
(define shadow-top 192)

(define fighter-shadow-hex
  (hash
   24 '#("ff00000003ff00000000"
         "ff00000007fc00000000"
         "7f0000000ff000000000"
         "3fc000001ff000000000"
         "3fe000003ff000000000"
         "3ff000003ff000000000"
         "1ff800007fe000000000"
         "1ffc0001ffe000000000")
   35 '#("ff00000003ff00000000"
         "ff00000007fc00000000"
         "7f0000000ff000000000"
         "3fc000001ff000000000"
         "3fe000003ff000000000"
         "3ff000003ff000000000"
         "1ff800007fe000000000"
         "1ffc0001ffe000000000")
   34 '#("f3cfc00ff00000000000"
         "7f3fc33fc00000000000"
         "1f3f1b3f800000000000"
         "0f1ffb3fc00000000000"
         "0f0ffb3ff00000000000"
         "0f0fff7ffc0000000000"
         "0f0fff7ffe0000000000"
         "0fbfff7fff0c00000000")
   58 '#("ff00000003fe00000000"
         "ff0000000ffc00000000"
         "ff0000000ff000000000"
         "3fc000001ff000000000"
         "3fe000003ff000000000"
         "3ff000003ff000000000"
         "3ff800007fe000000000"
         "1ffc0001ffe000000000")))

;; $B012..$B700 repeatedly shift these left prefixes and right suffixes.
;; Row 192 is untouched; later rows accumulate outward displacements of
;; 1, 3, 5, 6, 7, 8 and 9 pixels respectively.
(define shadow-filter-widths
  '#(()
     (112)
     (128 64 16)
     (128 96 64 32 16)
     (144 112 80 48 32 16)
     (144 128 96 80 48 32 16)
     (144 128 112 80 64 48 32 16)
     (144 128 112 96 80 64 48 32 16)))

;; $C14C, with the eight preceding zero words supplied by $C13C..$C14B.
;; The retail painter reads an eight-word window beginning at 8-height.
(define ball-shadow-height-words
  '#(#x0000 #x0000 #x0000 #x0000 #x0000 #x0000 #x0000 #x0000
     #x0fc0 #x3ff0 #x7ff8 #xfffc #xfffc #xfffc #xfffc #x7ff8
     #x3ff0 #x0fc0))

(define (hex-digit-value char)
  (cond [(char<=? #\0 char #\9) (- (char->integer char) (char->integer #\0))]
        [(char<=? #\a char #\f) (+ 10 (- (char->integer char) (char->integer #\a)))]
        [(char<=? #\A char #\F) (+ 10 (- (char->integer char) (char->integer #\A)))]
        [else (error 'fighter-floor-shadow-runs "bad shadow hex digit: ~a" char)]))

(define (hex-row-bit? row x)
  (define nibble (hex-digit-value (string-ref row (quotient x 4))))
  (not (zero? (bitwise-and nibble
                            (arithmetic-shift 1 (- 3 (remainder x 4)))))))

(define (word-bit? word x)
  (not (zero? (bitwise-and word (arithmetic-shift 1 (- 15 x))))))

(define (shift-left-prefix! pixels width)
  ;; [a b c d] becomes [b c d d].  Iterating left-to-right deliberately
  ;; preserves the Amiga's in-place ROXL propagation.
  (for ([x (in-range (sub1 width))])
    (vector-set! pixels x (vector-ref pixels (add1 x)))))

(define (shift-right-suffix! pixels width)
  ;; [a b c d] becomes [a a b c].  Work right-to-left for the matching ROXR
  ;; propagation from the central boundary toward the outer edge.
  (define start (- screen-width width))
  (for ([x (in-range (sub1 screen-width) start -1)])
    (vector-set! pixels x (vector-ref pixels (sub1 x)))))

(define (filter-floor-shadow-row! pixels row)
  (for ([width (in-list (vector-ref shadow-filter-widths row))])
    (shift-left-prefix! pixels width))
  (for ([width (in-list (vector-ref shadow-filter-widths row))])
    (shift-right-suffix! pixels width)))

(define (pixels->runs pixels y)
  (let loop ([x 0] [runs '()])
    (cond [(= x screen-width) (reverse runs)]
          [(not (vector-ref pixels x)) (loop (add1 x) runs)]
          [else
           (define end
             (let find-end ([next (add1 x)])
               (if (and (< next screen-width) (vector-ref pixels next))
                   (find-end (add1 next))
                   next)))
           (loop end (cons (list x y (- end x)) runs))])))

(define (fighter-floor-shadow-runs pose mirrored? origin-x)
  (define rows (hash-ref fighter-shadow-hex pose #f))
  (unless rows
    (raise-arguments-error 'fighter-floor-shadow-runs
                           "unsupported bonus-fighter pose"
                           "pose" pose))
  (append*
   (for/list ([row (in-range 8)])
     (define pixels (make-vector screen-width #f))
     (define source-row (vector-ref rows row))
     (for ([source-x (in-range 80)] #:when (hex-row-bit? source-row source-x))
       (define shadow-x (+ origin-x (if mirrored? (- 79 source-x) source-x)))
       (when (<= 0 shadow-x (sub1 screen-width))
         (vector-set! pixels shadow-x #t)))
     (filter-floor-shadow-row! pixels row)
     (pixels->runs pixels (+ shadow-top row)))))

(define (ball-floor-shadow-runs x-integer y-integer)
  ;; $C1F2: ($55 - y) chooses a window only for 0..7.  The source painter
  ;; ignores X's fraction byte, so this uses the coarse integer as well.
  (define height (- #x55 y-integer))
  (cond [(or (< height 0) (>= height 8)
             (< x-integer #x08) (>= x-integer #xb0))
         '()]
        [else
         (define origin-x (- (* 2 x-integer) 32))
         (append*
          (for/list ([row (in-range 8)])
            (define word (vector-ref ball-shadow-height-words (+ (- 8 height) row)))
            (define pixels (make-vector screen-width #f))
            (for ([bit (in-range 16)] #:when (word-bit? word bit))
              (define shadow-x (+ origin-x bit))
              (when (<= 0 shadow-x (sub1 screen-width))
                (vector-set! pixels shadow-x #t)))
            (pixels->runs pixels (+ shadow-top row))))]))

(module+ test
  (require rackunit)
  (check-true (pair? (fighter-floor-shadow-runs 24 #f 112)))
  (check-true (pair? (fighter-floor-shadow-runs 34 #t 112)))
  (check-equal? (length (ball-floor-shadow-runs 72 #x55)) 8)
  (check-equal? (length (ball-floor-shadow-runs 72 #x4e)) 1)
  (check-equal? (ball-floor-shadow-runs 72 #x4d) '()))
