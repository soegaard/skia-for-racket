#lang racket/base
;; Public bitmap% pixel bridge. Pixels are copied on every call: bitmap%
;; mutation has no revision counter suitable for a safe immutable-image cache.
(require racket/class racket/list (prefix-in rd: racket/draw)
         (only-in "check.rkt" check-dimensions current-skia-byte-limit)
         "dc-support.rkt")
(provide (struct-out dc-bitmap-data) dc-bitmap-snapshot dc-bitmap-source-rect)
(struct dc-bitmap-data (width height backing logical-width logical-height pixels) #:transparent)
(define (mul255 a b) (quotient (+ (* a b) 127) 255))
(define (color-bytes who c)
  (unless (is-a? c rd:color%) (raise-argument-error who "color% object" c))
  (vector (send c red) (send c green) (send c blue)
          (inexact->exact (round (* 255 (dc-unit who (send c alpha)))))))
(define (physical who bm)
  (define b (dc-real who (send bm get-backing-scale)))
  (unless (> b 0) (raise-arguments-error who "invalid bitmap backing scale" "scale" b))
  (define w (inexact->exact (ceiling (* b (send bm get-width)))))
  (define h (inexact->exact (ceiling (* b (send bm get-height)))))
  (check-dimensions who w h)
  (values w h b))
(define (read-argb bm w h)
  (define bytes (make-bytes (* 4 w h)))
  (send bm get-argb-pixels 0 0 w h bytes #f #f #:unscaled? #t)
  bytes)
(define (dc-bitmap-snapshot who source style color mask background)
  (unless (is-a? source rd:bitmap%) (raise-argument-error who "bitmap% object" source))
  (unless (memq style '(solid opaque xor)) (raise-argument-error who "'solid, 'opaque, or 'xor" style))
  (define foreground (color-bytes who color))
  (define bg (color-bytes who background))
  (unless (or (not mask) (is-a? mask rd:bitmap%)) (raise-argument-error who "bitmap% or #f mask" mask))
  (when mask
    (unless (and (send mask ok?)
                 (= (send mask get-width) (send source get-width))
                 (= (send mask get-height) (send source get-height)))
      (raise-arguments-error who "mask must be valid and match logical source dimensions" "mask" mask)))
  (cond
    [(not (send source ok?)) #f]
    [else
     (define mono? (not (send source is-color?)))
     ;; Racket's legacy xor bitmap mode has the solid semantics, not bitwise XOR.
     (define-values (w h b) (physical who source))
     (define-values (mw mh mb) (if mask (physical who mask) (values 0 0 1.0)))
     ;; Include all temporary pixel buffers in the limit, not just the result.
     (define needed (+ (* 12 w h) (if mask (* 4 mw mh) 0)))
     (when (> needed (current-skia-byte-limit))
       (raise-arguments-error who "bitmap bridge exceeds current-skia-byte-limit"
                              "temporary bytes" needed "limit" (current-skia-byte-limit)))
     (define argb (read-argb source w h))
     (define mask-bytes (and mask (read-argb mask mw mh)))
     (define mask-alpha? (and mask (send mask has-alpha-channel?)))
     (define mask-color? (and mask (send mask is-color?)))
     (define rgba (make-bytes (* w h 4)))
     (for* ([y (in-range h)] [x (in-range w)])
       (define i (* 4 (+ x (* y w))))
       (define r (bytes-ref argb (+ i 1)))
       (define g (bytes-ref argb (+ i 2)))
       (define blue (bytes-ref argb (+ i 3)))
       (define black? (< (+ r g blue) 384))
       (define col (if black? foreground bg))
       (define a
         (cond [mono? (if (or black? (eq? style 'opaque)) (vector-ref col 3) 0)]
               [(send source has-alpha-channel?) (bytes-ref argb i)]
               [else 255]))
       (define mask-a
         (if mask
             (let* ([mx (min (sub1 mw) (inexact->exact (floor (/ (* (+ x 0.5) mb) b))))]
                    [my (min (sub1 mh) (inexact->exact (floor (/ (* (+ y 0.5) mb) b))))]
                    [mi (* 4 (+ mx (* my mw)))])
               (if (and mask-color? mask-alpha?) (bytes-ref mask-bytes mi)
                   (- 255 (quotient (+ (bytes-ref mask-bytes (+ mi 1))
                                      (bytes-ref mask-bytes (+ mi 2))
                                      (bytes-ref mask-bytes (+ mi 3))) 3))))
             255))
       (define final-a (mul255 a mask-a))
       (bytes-set! rgba i (mul255 (if mono? (vector-ref col 0) r) final-a))
       (bytes-set! rgba (+ i 1) (mul255 (if mono? (vector-ref col 1) g) final-a))
       (bytes-set! rgba (+ i 2) (mul255 (if mono? (vector-ref col 2) blue) final-a))
       (bytes-set! rgba (+ i 3) final-a))
     (dc-bitmap-data w h b (send source get-width) (send source get-height)
                     (bytes->immutable-bytes rgba))]))
;; Crop in logical source units. Source and destination change together, so a
;; partially outside section is clipped rather than stretched to fill its box.
(define (dc-bitmap-source-rect who data sx sy sw sh dx dy dw dh)
  (for ([v (in-list (list sx sy dx dy))]) (dc-real who v))
  (for ([v (in-list (list sw sh dw dh))]) (dc-extent who v))
  (define left (max 0.0 sx))
  (define top (max 0.0 sy))
  (define right (min (dc-bitmap-data-logical-width data) (+ sx sw)))
  (define bottom (min (dc-bitmap-data-logical-height data) (+ sy sh)))
  (and (> sw 0) (> sh 0) (> dw 0) (> dh 0) (> right left) (> bottom top)
       (let ([b (dc-bitmap-data-backing data)] [rx (/ dw sw)] [ry (/ dh sh)])
         (vector (* left b) (* top b) (* (- right left) b) (* (- bottom top) b)
                 (+ dx (* (- left sx) rx)) (+ dy (* (- top sy) ry))
                 (* (- right left) rx) (* (- bottom top) ry)))))
