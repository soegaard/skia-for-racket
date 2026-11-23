#lang racket/base

;;;
;;; Bad Apple!! Transport
;;;

;; A clock-independent playback controller. GUI timers request work, but elapsed media time is
;; always selected from a monotonic-clock anchor so late callbacks skip stale visual frames.

(require racket/math)

(provide bad-apple-transport?
         make-bad-apple-transport
         bad-apple-transport-state
         bad-apple-transport-current-frame
         bad-apple-transport-generation
         bad-apple-transport-frame-count
         bad-apple-transport-frame-rate
         bad-apple-transport-duration-seconds
         bad-apple-transport-media-time
         bad-apple-transport-select-frame!
         bad-apple-transport-set-media-time!
         bad-apple-transport-play!
         bad-apple-transport-pause!
         bad-apple-transport-restart!
         bad-apple-transport-seek-frame!
         bad-apple-transport-step!
         bad-apple-transport-close!
         bad-apple-transport-next-delay-ms)

(struct bad-apple-transport (frame-count fps-numerator fps-denominator state current-frame
                                          media-anchor clock-anchor generation)
  #:mutable
  #:transparent)

(define (clock-ms? value) (and (real? value) (not (nan? value)) (not (infinite? value))))

(define (check-clock who value)
  (unless (clock-ms? value) (raise-argument-error who "finite real monotonic milliseconds" value)))

(define (make-bad-apple-transport frame-count fps-numerator fps-denominator now-ms)
  (unless (exact-positive-integer? frame-count)
    (raise-argument-error 'make-bad-apple-transport "exact positive integer" frame-count))
  (unless (exact-positive-integer? fps-numerator)
    (raise-argument-error 'make-bad-apple-transport "exact positive integer" fps-numerator))
  (unless (exact-positive-integer? fps-denominator)
    (raise-argument-error 'make-bad-apple-transport "exact positive integer" fps-denominator))
  (check-clock 'make-bad-apple-transport now-ms)
  (bad-apple-transport frame-count fps-numerator fps-denominator 'paused 0 0 now-ms 0))

(define (bad-apple-transport-frame-rate transport)
  (/ (bad-apple-transport-fps-numerator transport)
     (bad-apple-transport-fps-denominator transport)))

(define (bad-apple-transport-duration-seconds transport)
  (/ (bad-apple-transport-frame-count transport)
     (bad-apple-transport-frame-rate transport)))

(define (clamp value low high) (min high (max low value)))

(define (increment-generation! transport)
  (set-bad-apple-transport-generation! transport
                                       (add1 (bad-apple-transport-generation transport))))

(define (frame->media-time transport frame)
  (/ frame (bad-apple-transport-frame-rate transport)))

;; bad-apple-transport-media-time : transport? finite-real? -> nonnegative-real?
;; Reads the anchored media position without changing state. The position may equal duration only
;; at the ended boundary.
(define (bad-apple-transport-media-time transport now-ms)
  (check-clock 'bad-apple-transport-media-time now-ms)
  (define value
    (if (eq? (bad-apple-transport-state transport) 'playing)
        (+ (bad-apple-transport-media-anchor transport)
           (/ (- now-ms (bad-apple-transport-clock-anchor transport)) 1000.0))
        (bad-apple-transport-media-anchor transport)))
  (clamp value 0 (exact->inexact (bad-apple-transport-duration-seconds transport))))

;; bad-apple-transport-select-frame! : transport? finite-real? -> exact-nonnegative-integer?
;; Updates the selected frame from media time and turns a completed playback into an explicit ended
;; transport state rather than repeatedly scheduling the final boundary.
(define (bad-apple-transport-select-frame! transport now-ms)
  (check-clock 'bad-apple-transport-select-frame! now-ms)
  (unless (memq (bad-apple-transport-state transport) '(closing closed))
    (define time (bad-apple-transport-media-time transport now-ms))
    (define duration (bad-apple-transport-duration-seconds transport))
    (define duration-number (exact->inexact duration))
    (cond
      [(and (eq? (bad-apple-transport-state transport) 'playing) (>= time duration-number))
       (set-bad-apple-transport-state! transport 'ended)
       (set-bad-apple-transport-media-anchor! transport duration)
       (set-bad-apple-transport-clock-anchor! transport now-ms)
       (set-bad-apple-transport-current-frame! transport
                                                (sub1 (bad-apple-transport-frame-count transport)))
       (increment-generation! transport)]
      [else
       ;; Monotonic clocks are inexact milliseconds. A decimal representation of an exact source
       ;; boundary can land a few ulps below its mathematical value, so admit only a tiny boundary
       ;; tolerance before flooring; this never turns an ordinary 30 fps interval into a duplicate.
       (define selected
         (inexact->exact
          (floor (+ (* time (bad-apple-transport-frame-rate transport)) 1e-9))))
       (set-bad-apple-transport-current-frame!
        transport
        (clamp selected 0 (sub1 (bad-apple-transport-frame-count transport))))]))
  (bad-apple-transport-current-frame transport))

;; bad-apple-transport-set-media-time! : transport? nonnegative-real? finite-real? -> frame
;; Applies an externally authoritative media clock (the optional mpv adapter) without creating a
;; competing elapsed-time anchor. The caller decides whether that clock is currently playing.
(define (bad-apple-transport-set-media-time! transport media-time now-ms #:playing? [playing? #t])
  (unless (and (clock-ms? media-time) (>= media-time 0))
    (raise-argument-error 'bad-apple-transport-set-media-time! "nonnegative finite real seconds"
                          media-time))
  (check-clock 'bad-apple-transport-set-media-time! now-ms)
  (unless (memq (bad-apple-transport-state transport) '(closing closed))
    (set-bad-apple-transport-media-anchor!
     transport (clamp media-time 0 (exact->inexact (bad-apple-transport-duration-seconds transport))))
    (set-bad-apple-transport-clock-anchor! transport now-ms)
    (set-bad-apple-transport-state! transport (if playing? 'playing 'paused))
    (bad-apple-transport-select-frame! transport now-ms))
  (bad-apple-transport-current-frame transport))

(define (bad-apple-transport-pause! transport now-ms)
  (check-clock 'bad-apple-transport-pause! now-ms)
  (when (eq? (bad-apple-transport-state transport) 'playing)
    (define time (bad-apple-transport-media-time transport now-ms))
    (set-bad-apple-transport-media-anchor! transport time)
    (set-bad-apple-transport-clock-anchor! transport now-ms)
    (bad-apple-transport-select-frame! transport now-ms)
    (unless (eq? (bad-apple-transport-state transport) 'ended)
      (set-bad-apple-transport-state! transport 'paused))
    (increment-generation! transport))
  (bad-apple-transport-state transport))

(define (bad-apple-transport-play! transport now-ms)
  (check-clock 'bad-apple-transport-play! now-ms)
  (case (bad-apple-transport-state transport)
    [(ended)
     (set-bad-apple-transport-current-frame! transport 0)
     (set-bad-apple-transport-media-anchor! transport 0)
     (set-bad-apple-transport-clock-anchor! transport now-ms)
     (set-bad-apple-transport-state! transport 'playing)
     (increment-generation! transport)]
    [(paused)
     (set-bad-apple-transport-clock-anchor! transport now-ms)
     (set-bad-apple-transport-state! transport 'playing)
     (increment-generation! transport)]
    [else (void)])
  (bad-apple-transport-state transport))

(define (bad-apple-transport-seek-frame! transport frame now-ms #:play? [play? #f])
  (unless (exact-integer? frame)
    (raise-argument-error 'bad-apple-transport-seek-frame! "exact integer" frame))
  (check-clock 'bad-apple-transport-seek-frame! now-ms)
  (unless (memq (bad-apple-transport-state transport) '(closing closed))
    (define selected (clamp frame 0 (sub1 (bad-apple-transport-frame-count transport))))
    (set-bad-apple-transport-current-frame! transport selected)
    (set-bad-apple-transport-media-anchor! transport (frame->media-time transport selected))
    (set-bad-apple-transport-clock-anchor! transport now-ms)
    (set-bad-apple-transport-state! transport (if play? 'playing 'paused))
    (increment-generation! transport))
  (bad-apple-transport-current-frame transport))

(define (bad-apple-transport-restart! transport now-ms #:play? [play? #t])
  (bad-apple-transport-seek-frame! transport 0 now-ms #:play? play?))

(define (bad-apple-transport-step! transport delta now-ms)
  (unless (exact-integer? delta)
    (raise-argument-error 'bad-apple-transport-step! "exact integer" delta))
  (check-clock 'bad-apple-transport-step! now-ms)
  (bad-apple-transport-pause! transport now-ms)
  (bad-apple-transport-seek-frame!
   transport (+ (bad-apple-transport-current-frame transport) delta) now-ms))

(define (bad-apple-transport-close! transport)
  (unless (eq? (bad-apple-transport-state transport) 'closed)
    (set-bad-apple-transport-state! transport 'closed)
    (increment-generation! transport))
  (void))

;; bad-apple-transport-next-delay-ms : transport? finite-real? -> (or/c #f exact-positive-integer?)
;; Returns a one-shot timer delay derived from the next source-frame boundary. It never returns zero,
;; avoiding a busy loop when a callback happens to run exactly on a boundary.
(define (bad-apple-transport-next-delay-ms transport now-ms)
  (check-clock 'bad-apple-transport-next-delay-ms now-ms)
  (cond
    [(not (eq? (bad-apple-transport-state transport) 'playing)) #f]
    [else
     (define media-time (bad-apple-transport-media-time transport now-ms))
     (define rate (bad-apple-transport-frame-rate transport))
     (define duration (bad-apple-transport-duration-seconds transport))
     (if (>= media-time (exact->inexact duration))
         #f
         (let* ([selected (inexact->exact (floor (* media-time rate)))]
                [next-time (/ (add1 selected) rate)]
                [remaining-ms (* 1000 (- next-time media-time))])
           (max 1 (inexact->exact (ceiling remaining-ms)))))]))
