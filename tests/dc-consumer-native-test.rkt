#lang racket/base
(require racket/class racket/list rackunit
         (prefix-in rd: racket/draw) (prefix-in sk: "../main.rkt") "../dc.rkt"
         "dc-consumer-fixtures.rkt")
(provide dc-consumer-native-tests dc-consumer-native-test-count)
(define dc-consumer-native-test-count 16)
(define (using f [backing 1])
  (define dc (new skia-dc% [width consumer-width] [height consumer-height]
                 [backing-scale backing] [smoothing 'smoothed]))
  (dynamic-wind void (lambda () (send dc clear) (f dc)) (lambda () (send dc close))))
(define (pixel dc x y)
  (define data (send dc get-rgba-bytes))
  (define-values (w h) (send dc get-pixel-size))
  (define i (* 4 (+ x (* y w))))
  (bytes->list (subbytes data i (+ i 4))))
(define (near-pixel dc x y expected [tolerance 2])
  (for ([a (in-list (pixel dc x y))] [e (in-list expected)])
    (check-true (<= (abs (- a e)) tolerance))))
(define (pict-ink dc [b 1])
  (near-pixel dc (* b 24) (* b 24) '(255 0 0 255))
  (near-pixel dc (* b 18) (* b 72) '(255 128 128 255))
  ;; The overlap must be faded as a group, not once per overlapping object.
  (near-pixel dc (* b 36) (* b 72) '(128 128 255 255))
  (near-pixel dc (* b 164) (* b 16) '(20 180 60 255)))
(define (blue? r g b) (and (> b 160) (< r 100) (< g 100)))
(define (red? r g b) (and (> r 160) (< g 100) (< b 100)))
(define (plot-ink dc layout [backing 1])
  (define data (send dc get-rgba-bytes))
  (define-values (w h) (send dc get-pixel-size))
  (for ([entry (in-list (list (list -1.5 -0.75 blue?) (list -0.5 -0.25 blue?)
                              (list 0.5 0.25 blue?) (list 1.5 0.75 blue?)
                              (list -1 1 red?) (list 1 -1 red?)))])
    (define-values (lx ly) (plot-probe-position layout (car entry) (cadr entry)))
    (define x (inexact->exact (round (* backing lx))))
    (define y (inexact->exact (round (* backing ly))))
    (define radius (* backing 3))
    (check-true
     (for*/or ([px (in-range (max 0 (- x radius)) (min w (+ x radius 1)))]
               [py (in-range (max 0 (- y radius)) (min h (+ y radius 1)))])
       (define i (* 4 (+ px (* py w))))
       (and (> (bytes-ref data (+ i 3)) 240)
            ((caddr entry) (bytes-ref data i) (bytes-ref data (+ i 1)) (bytes-ref data (+ i 2)))))
     (format "missing plot ink near data coordinate ~a,~a" (car entry) (cadr entry)))))
(define (both-recordings draw)
  (define-values (proc datum _) (record-consumer draw))
  (define a (using (lambda (dc) (proc dc) (send dc get-rgba-bytes #:premultiplied? #t))))
  (define b (using (lambda (dc) (datum dc) (send dc get-rgba-bytes #:premultiplied? #t))))
  (check-equal? (bytes-length a) (bytes-length b))
  (check-true (for/and ([x (in-bytes a)] [y (in-bytes b)]) (<= (abs (- x y)) 2))))
(define (picture) (using make-consumer-pict))
(define (drawing p) (lambda (dc) (draw-consumer-pict dc p)))
(define dc-consumer-native-tests
  (test-suite
   "Direct pict and plot/no-gui consumers on the existing Skia DC subset"
   (test-case "pict draws solids bitmap and group opacity directly"
     (using (lambda (dc) (draw-consumer-pict dc (make-consumer-pict dc)) (pict-ink dc))))
   (test-case "pict draws actual navy text"
     (using (lambda (dc)
       (draw-consumer-pict dc (make-consumer-pict dc))
       (define data (send dc get-rgba-bytes))
       (check-true (>= (for*/sum ([y (in-range 126 172)] [x (in-range 12 165)])
                         (define i (* 4 (+ x (* y consumer-width))))
                         (if (and (< (bytes-ref data i) 160) (< (bytes-ref data (+ i 1)) 160)
                                  (> (bytes-ref data (+ i 2)) (+ 20 (bytes-ref data i)))) 1 0)) 12)))))
   (test-case "pict uses logical coordinates on a 2x backing"
     (using (lambda (dc) (draw-consumer-pict dc (make-consumer-pict dc)) (pict-ink dc 2)) 2))
   (test-case "direct pict restores selected objects and drawing state"
     (using (lambda (dc)
       (define p (make-consumer-pict dc))
       (send dc set-pen (rd:make-pen #:color "purple" #:width 2 #:immutable? #f))
       (send dc set-brush (rd:make-brush #:color "orange" #:immutable? #f))
       (send dc set-alpha 0.7)
       (define before (consumer-state dc))
       (draw-consumer-pict dc p)
       (check-equal? (consumer-state dc) before))))
   (test-case "pict recorded procedure retains actual consumer content"
     (define-values (proc datum _) (record-consumer (drawing (picture))))
     (using (lambda (dc) (proc dc) (pict-ink dc))))
   (test-case "pict recorded datum retains actual consumer content"
     (define-values (proc datum _) (record-consumer (drawing (picture))))
     (using (lambda (dc) (datum dc) (pict-ink dc))))
   (test-case "pict procedure and datum replay agree on the same backend"
     (both-recordings (drawing (picture))))
   (test-case "repeated consumer replay releases selected pen locks"
     (define pen (rd:make-pen #:width 2 #:immutable? #f))
     (define-values (proc datum _) (record-consumer (drawing (picture))))
     (using (lambda (dc)
       (send dc set-pen pen)
       (for ([_ (in-range 3)]) (proc dc) (datum dc))
       (check-eq? pen (send dc get-pen))))
     (check-not-exn (lambda () (send pen set-width 3))))
   (test-case "plot/dc draws a labeled function and point markers directly"
     (using (lambda (dc) (plot-ink dc (draw-consumer-plot dc)))))
   (test-case "plot/dc restores selected objects and drawing state"
     (using (lambda (dc)
       (send dc set-pen (rd:make-pen #:color "purple" #:width 2 #:immutable? #f))
       (send dc set-brush (rd:make-brush #:color "orange" #:immutable? #f))
       (define before (consumer-state dc))
       (draw-consumer-plot dc)
       (check-equal? (consumer-state dc) before))))
   (test-case "plot/dc uses logical coordinates on a 2x backing"
     (using (lambda (dc) (plot-ink dc (draw-consumer-plot dc) 2)) 2))
   (test-case "plot recorded procedure draws the recorder's layout"
     (define-values (proc datum layout) (record-consumer draw-consumer-plot))
     (using (lambda (dc) (proc dc) (plot-ink dc layout))))
   (test-case "plot recorded datum draws the recorder's layout"
     (define-values (proc datum layout) (record-consumer draw-consumer-plot))
     (using (lambda (dc) (datum dc) (plot-ink dc layout))))
   (test-case "plot procedure and datum replay agree without requiring metric parity"
     (both-recordings draw-consumer-plot))
   (test-case "pict respects and restores the destination clipping region"
     (define p (picture))
     (using (lambda (dc)
       (send dc set-clipping-rect 12 12 20 20)
       (define clip (send dc get-clipping-region))
       (draw-consumer-pict dc p)
       (check-eq? (send dc get-clipping-region) clip)
       (near-pixel dc 24 24 '(255 0 0 255))
       (near-pixel dc 44 24 '(255 255 255 255)))))
   (test-case "consumer snapshots encode after the owning DC closes"
     (for ([draw (in-list (list (drawing (picture)) draw-consumer-plot))])
       (define image (using (lambda (dc) (draw dc) (send dc snapshot))))
       (sk:with-skia ([im image])
         (check-equal? (sk:image-width im) consumer-width)
         (check-equal? (sk:image-height im) consumer-height)
         (check-true (> (bytes-length (sk:image->png-bytes im)) 100)))))))
