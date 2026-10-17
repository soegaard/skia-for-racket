#lang racket/base

;;;
;;; Racket Path Conversion
;;;

;; Converts between dc-path% commands and detached Skia path contours.
;; Bridges Racket and Skia geometry while bounding conic approximation work.


;; Checked, detached path preparation for skia/racket-draw.  The destination
;; dc-path% is created only after a complete raw Skia snapshot has passed the
;; topology and expansion checks.

;;;
;;; Imports and Exports
;;;

(require racket/class racket/list racket/match
         (prefix-in rd: racket/draw)
         "check.rkt"
         "core.rkt"
         "dc-geometry.rkt"
         "path-matrix.rkt"
         "../geometry.rkt")

(provide dc-path->skia-path/checked skia-path->dc-path/checked)

;;;
;;; Racket-to-Skia Path Preparation
;;;

; draw-fill-style : symbol? symbol? -> symbol?
;   Accepts the Racket odd-even or winding fill rule before translating it to Skia.
(define (draw-fill-style who value)
  (unless (memq value '(odd-even winding))
    (raise-argument-error who "'odd-even or 'winding" value))
  value)

; path-budget : symbol? exact-nonnegative-integer? -> void?
;   Checks a conservative 64-byte-per-command conversion budget before constructing destination
;   paths.
(define (path-budget who count)
  ;; Detached segment records, generated cubic commands, and their point data
  ;; are charged conservatively before a dc-path% is constructed.
  (define bytes (* 64 count))
  (unless (<= bytes (current-skia-byte-limit))
    (raise-arguments-error who "path bridge exceeds current-skia-byte-limit"
                           "estimated command bytes" bytes
                           "limit" (current-skia-byte-limit))))

; dc-path->skia-path/checked : (is-a?/c dc-path%) symbol? -> path?
;   Snapshots checked Racket path commands into a caller-owned native Skia path with the requested
;   fill rule.
(define (dc-path->skia-path/checked path fill-style)
  (define who 'dc-path->skia-path)
  (draw-fill-style who fill-style)
  (define commands (dc-path-commands who path))
  (path-budget who (length commands))
  (define native-commands
    (for/list ([command (in-list commands)])
      (vector->list command)))
  (make-path native-commands
             #:fill-rule (if (eq? fill-style 'odd-even) 'even-odd 'winding)))

;;;
;;; Raw Contours and Bounded Conic Expansion
;;;

(struct draw-contour (segments closed?) #:transparent)
;; Fields:
;;   segments: ordered detached path-segment list, beginning with 'move and ending with 'close when
;;   closed? is #t. closed?: boolean distinguishing explicitly closed and final open contours.
;;   Only the final contour may remain open. Conversion preserves endpoint order and approximates
;;   non-unit rational conics only with an explicit, bounded subdivision power.


; split-contours : symbol? (listof path-segment?) -> (listof draw-contour?)
;   Validates move/close topology and groups raw segments in order, allowing an open contour only at
;   the end.
(define (split-contours who segments)
  (define current '())
  (define contours '())
  (define (finish-open!)
    (when (pair? current)
      (set! contours (append contours (list (draw-contour current #f))))
      (set! current '())))
  (for ([segment (in-list segments)] [index (in-naturals)])
    (case (path-segment-verb segment)
      [(move)
       (finish-open!)
       (set! current (list segment))]
      [(close)
       (unless (pair? current)
         (raise-arguments-error who "close verb has no current contour"
                                "segment index" index))
       (set! contours (append contours (list (draw-contour (append current (list segment)) #t))))
       (set! current '())]
      [(line quad conic cubic)
       (unless (pair? current)
         (raise-arguments-error who "path segment has no initial move verb"
                                "segment index" index
                                "verb" (path-segment-verb segment)))
       (set! current (append current (list segment)))]
      [else
       (raise-arguments-error who "unsupported native path verb"
                              "segment index" index
                              "verb" (path-segment-verb segment))]))
  (finish-open!)
  (for ([contour (in-list contours)] [index (in-naturals)])
    (when (and (not (draw-contour-closed? contour))
               (< index (sub1 (length contours))))
      (raise-arguments-error who
                             "an open contour cannot be followed by another contour"
                             "contour index" index)))
  contours)

; point-coordinate : symbol? (or/c list? vector?) (or/c 0 1) -> real?
;   Reads and validates one coordinate from a two-element detached point list or vector.
(define (point-coordinate who point index)
  ;; Raw path snapshots use two-element lists; conic->quadratics returns
  ;; immutable two-element vectors. Keep the conversion boundary detached while
  ;; accepting the two checked representations supplied by those helpers.
  (define value
    (cond [(and (list? point) (= (length point) 2)) (list-ref point index)]
          [(and (vector? point) (= (vector-length point) 2)) (vector-ref point index)]
          [else (raise-arguments-error who "two-coordinate point" "point" point)]))
  (scalar who value))

; point-x : symbol? (or/c list? vector?) -> real?
;   Returns a detached point's checked x coordinate for path conversion.
(define (point-x who point) (point-coordinate who point 0))

; point-y : symbol? (or/c list? vector?) -> real?
;   Returns a detached point's checked y coordinate for path conversion.
(define (point-y who point) (point-coordinate who point 1))

; cubic-for-quadratic : symbol? any/c any/c any/c -> (listof real?)
;   Converts start/control/end quadratic points to cubic control1/control2/end coordinates in xy
;   order.
(define (cubic-for-quadratic who p0 q p2)
  (define x0 (point-x who p0)) (define y0 (point-y who p0))
  (define qx (point-x who q)) (define qy (point-y who q))
  (define x2 (point-x who p2)) (define y2 (point-y who p2))
  (list (scalar who (+ x0 (* 2/3 (- qx x0))))
        (scalar who (+ y0 (* 2/3 (- qy y0))))
        (scalar who (+ x2 (* 2/3 (- qx x2))))
        (scalar who (+ y2 (* 2/3 (- qy y2))))
        x2 y2))

; checked-conic-power : symbol? (or/c #f exact-integer?) -> (or/c #f exact-integer?)
;   Accepts no approximation or a subdivision power from zero through five.
(define (checked-conic-power who power)
  (unless (or (not power) (and (exact-integer? power) (<= 0 power 5)))
    (raise-argument-error who "#f or exact integer from 0 through 5" power))
  power)

; predicted-output-count : symbol? (listof draw-contour?) (or/c #f exact-integer?) ->
; exact-nonnegative-integer?
;   Counts commands after conic expansion and rejects non-unit conics without an explicit subdivision
;   power.
(define (predicted-output-count who contours power)
  (for/sum ([contour (in-list contours)])
    (for/sum ([segment (in-list (draw-contour-segments contour))])
      (case (path-segment-verb segment)
        [(conic)
         (define weight (scalar who (path-segment-conic-weight segment)))
         (unless (> weight 0)
           (raise-arguments-error who "conic weight must be positive and finite"
                                  "weight" weight))
         (cond [(= weight 1.0) 1]
               [power (arithmetic-shift 1 power)]
               [else
                (raise-arguments-error
                 who "non-unit conic requires explicit #:conic-subdivisions"
                 "weight" weight)])]
        [(move line quad cubic close) 1]
        [else (raise-arguments-error who "unsupported native path verb"
                                     "verb" (path-segment-verb segment))]))))

; segment->draw-commands : symbol? path-segment? (or/c #f exact-integer?) -> list?
;   Converts one detached segment to Racket move/line/cubic/close commands, approximating conics only
;   when requested.
(define (segment->draw-commands who segment power)
  (define verb (path-segment-verb segment))
  (define points (path-segment-points segment))
  (case verb
    [(move)
     (match points [(list p) (list (list 'move (point-x who p) (point-y who p)))]
       [_ (error who "invalid move segment snapshot")])]
    [(line)
     (match points [(list _ p) (list (list 'line (point-x who p) (point-y who p)))]
       [_ (error who "invalid line segment snapshot")])]
    [(cubic)
     (match points
       [(list _ c1 c2 p)
        (list (list 'cubic (point-x who c1) (point-y who c1)
                    (point-x who c2) (point-y who c2)
                    (point-x who p) (point-y who p)))]
       [_ (error who "invalid cubic segment snapshot")])]
    [(quad)
     (match points
       [(list p0 q p2) (list (cons 'cubic (cubic-for-quadratic who p0 q p2)))]
       [_ (error who "invalid quadratic segment snapshot")])]
    [(conic)
     (match points
       [(list p0 q p2)
        (define weight (scalar who (path-segment-conic-weight segment)))
        (unless (> weight 0)
          (raise-arguments-error who "conic weight must be positive and finite"
                                 "weight" weight))
        (cond [(= weight 1.0) (list (cons 'cubic (cubic-for-quadratic who p0 q p2)))]
              [power
               (append*
                (for/list ([quadratic (in-list (conic->quadratics p0 q p2 weight
                                                                      #:subdivisions power))])
                  (list (cons 'cubic
                              (cubic-for-quadratic who (vector-ref quadratic 0)
                                                   (vector-ref quadratic 1)
                                                   (vector-ref quadratic 2))))))]
              [else
               (raise-arguments-error who "non-unit conic requires explicit #:conic-subdivisions"
                                      "weight" weight)])]
       [_ (error who "invalid conic segment snapshot")])]
    [(close) (list '(close))]
    [else (raise-arguments-error who "unsupported native path verb" "verb" verb)]))

;;;
;;; Skia-to-Racket Path Construction
;;;

; skia-path->dc-path/checked : path? (or/c #f exact-integer?) -> (values (is-a?/c dc-path%) symbol?)
;   Validates a raw Skia snapshot and expansion budget, then returns a detached Racket path and
;   translated fill rule.
(define (skia-path->dc-path/checked path power)
  (define who 'skia-path->dc-path)
  (checked-conic-power who power)
  ;; Both queries take a detached native snapshot while preserving the source's
  ;; ordinary liveness and owner-thread checks.
  (define fill-rule (path-fill-rule path))
  (define contours (split-contours who (path-segments path #:mode 'raw #:force-closed? #f)))
  (path-budget who (predicted-output-count who contours power))
  (define commands
    (append*
     (for/list ([contour (in-list contours)])
       (append*
        (for/list ([segment (in-list (draw-contour-segments contour))])
          (segment->draw-commands who segment power))))))
  (define result (new rd:dc-path%))
  (for ([command (in-list commands)])
    (match command
      [(list 'move x y) (send result move-to x y)]
      [(list 'line x y) (send result line-to x y)]
      [(list 'cubic x1 y1 x2 y2 x y) (send result curve-to x1 y1 x2 y2 x y)]
      [(list 'close) (send result close)]))
  (values result (if (eq? fill-rule 'even-odd) 'odd-even 'winding)))
