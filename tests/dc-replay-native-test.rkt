#lang racket/base
(require rackunit racket/class racket/list
         (prefix-in rd: racket/draw) (prefix-in sk: "../main.rkt") "../dc.rkt"
         "../examples/dc-replay.rkt")
(provide dc-replay-native-tests dc-replay-native-test-count)
(define (using proc [w 96] [h 72] [backing 1])
  (define dc (new skia-dc% [width w] [height h] [backing-scale backing] [smoothing 'smoothed]))
  (dynamic-wind void (lambda () (proc dc)) (lambda () (send dc close))))
(define (pixels dc) (send dc get-rgba-bytes #:premultiplied? #t))
(define (pixel dc x y)
  (define-values (w h) (send dc get-pixel-size))
  (bytes->list (subbytes (pixels dc) (* 4 (+ x (* y w))) (* 4 (+ 1 x (* y w))))))
(define (near actual expected [tolerance 1])
  (check-equal? (length actual) (length expected))
  (for ([a actual] [b expected]) (check-true (<= (abs (- a b)) tolerance) (format "~a versus ~a" actual expected))))
(define (fill dc color x y w h)
  (send dc set-pen "black" 1 'transparent) (send dc set-brush color 'solid)
  (send dc draw-rectangle x y w h))
(define (simple dc) (send dc set-smoothing 'smoothed) (fill dc "red" 2 3 8 9))
(define (rich-ink! dc)
  (near (pixel dc 73 14) '(236 64 79 255) 2)
  (define bytes (pixels dc))
  (define-values (width height) (send dc get-pixel-size))
  (define text-ink
    (for*/sum ([y (in-range 38 62)] [x (in-range 9 70)])
      (define i (* 4 (+ x (* y width))))
      (if (and (< (bytes-ref bytes i) 230) (> (bytes-ref bytes (+ i 2)) (bytes-ref bytes i))) 1 0)))
  (check-true (>= text-ink 10) "recorded text must produce real navy ink"))
(define (reference draw [tolerance 2])
  (define bm (rd:make-bitmap 48 32 #t))
  (define rd-dc (new rd:bitmap-dc% [bitmap bm]))
  (send rd-dc erase) (send rd-dc set-smoothing 'smoothed) (draw rd-dc)
  (send rd-dc set-bitmap #f)
  (define argb (make-bytes (* 48 32 4)))
  (send bm get-argb-pixels 0 0 48 32 argb #f #t)
  (using (lambda (dc)
    (draw dc) (define actual (pixels dc))
    (define worst
      (for*/fold ([worst 0]) ([i (in-range 0 (bytes-length argb) 4)] [j (in-range 4)])
        (max worst (abs (- (bytes-ref actual (+ i j))
                          (bytes-ref argb (+ i (if (= j 3) 0 (add1 j)))))))))
    (check-true (<= worst tolerance) (format "maximum channel error ~a (limit ~a)" worst tolerance))) 48 32))
(define dc-replay-native-tests
  (test-suite
   "DC recorded replay and isolated raster alpha groups (native Skia pixels)"
   (test-case "recorded procedure draws geometry"
     (define-values (proc datum) (make-dc-recording simple))
     (using (lambda (dc) (proc dc) (check-equal? (pixel dc 4 5) '(255 0 0 255)))))
   (test-case "recorded datum draws geometry"
     (define-values (proc datum) (make-dc-recording simple))
     (using (lambda (dc) (datum dc) (check-equal? (pixel dc 4 5) '(255 0 0 255)))))
   (test-case "rich recorded procedure includes text bitmap transform clip and nested alpha"
     (define-values (proc datum) (make-dc-recording draw-dc-replay-scene))
     (using (lambda (dc) (proc dc) (rich-ink! dc)
       (check-not-equal? (pixel dc 12 12) '(255 255 255 255)))) )
   (test-case "rich recorded datum includes text bitmap transform clip and nested alpha"
     (define-values (proc datum) (make-dc-recording draw-dc-replay-scene))
     (using (lambda (dc) (datum dc) (rich-ink! dc)
       (check-not-equal? (pixel dc 12 12) '(255 255 255 255)))) )
   (test-case "repeat both replay forms without accumulating selection locks"
     (define-values (proc datum) (make-dc-recording simple))
     (define p (rd:make-pen #:immutable? #f))
     (using (lambda (dc)
       (send dc set-pen p) (for ([_ (in-range 12)]) (proc dc) (datum dc))
       (check-eq? p (send dc get-pen)) (check-equal? (pixel dc 4 5) '(255 0 0 255))))
     (check-not-exn (lambda () (send p set-width 7))))
   (test-case "replay composes destination translation and scale"
     (define-values (proc datum) (make-dc-recording simple))
     (for ([draw (list proc datum)])
       (using (lambda (dc) (send dc set-origin 3 4) (send dc set-scale 2 2) (draw dc)
         (check-equal? (pixel dc 8 11) '(255 0 0 255))
         (check-equal? (pixel dc 4 5) '(0 0 0 0))))))
   (test-case "replay intersects destination clipping"
     (define-values (proc datum) (make-dc-recording simple))
     (for ([draw (list proc datum)])
       (using (lambda (dc) (send dc set-clipping-rect 4 5 2 2) (define region (send dc get-clipping-region))
         (draw dc) (check-eq? region (send dc get-clipping-region))
         (check-equal? (pixel dc 4 5) '(255 0 0 255)) (check-equal? (pixel dc 3 5) '(0 0 0 0))))))
   (test-case "replay respects destination opacity"
     (define-values (proc datum) (make-dc-recording simple))
     (for ([draw (list proc datum)])
       (using (lambda (dc) (send dc set-alpha 0.25) (draw dc)
         (near (pixel dc 4 5) '(64 0 0 64)) (check-= (send dc get-alpha) 0.25 0)))))
   (test-case "replay restores native destination selections by identity"
     (define-values (proc datum) (make-dc-recording simple))
     (using (lambda (dc)
       (define p (rd:make-pen #:color "blue" #:immutable? #f))
       (define b (rd:make-brush #:color "blue" #:immutable? #f))
       (send dc set-pen p) (send dc set-brush b) (proc dc) (datum dc)
       (check-eq? p (send dc get-pen)) (check-eq? b (send dc get-brush)))))
   (test-case "replay restores complete transformation after nested groups"
     (define-values (proc datum) (make-dc-recording draw-dc-replay-scene))
     (using (lambda (dc) (send dc set-origin 2 3) (send dc set-scale 0.5 0.75)
       (define before (send dc get-transformation))
       (proc dc) (check-equal? before (send dc get-transformation))
       (datum dc) (check-equal? before (send dc get-transformation)))))
   (test-case "overlap is faded once not per drawing"
     (using (lambda (dc) (send dc start-alpha 0.5)
       (fill dc "red" 2 2 12 12) (fill dc "red" 8 2 12 12) (send dc end-alpha)
       (near (pixel dc 4 4) '(128 0 0 128)) (near (pixel dc 10 4) '(128 0 0 128)))))
   (test-case "nested groups multiply their final opacity"
     (using (lambda (dc) (send dc start-alpha 0.5) (send dc start-alpha 0.5)
       (fill dc "red" 2 2 10 10) (send dc end-alpha) (send dc end-alpha)
       (near (pixel dc 4 4) '(64 0 0 64)))))
   (test-case "saved destination opacity multiplies group opacity"
     (using (lambda (dc) (send dc set-alpha 0.25) (send dc start-alpha 0.5)
       (fill dc "red" 2 2 10 10) (send dc end-alpha)
       (near (pixel dc 4 4) '(32 0 0 32)) (check-= (send dc get-alpha) 0.25 0))))
   (test-case "per-draw opacity inside a group is independent"
     (using (lambda (dc) (send dc set-alpha 0.25) (send dc start-alpha 1)
       (check-= (send dc get-alpha) 1 0) (send dc set-alpha 0.5)
       (fill dc "red" 2 2 10 10) (send dc end-alpha)
       (near (pixel dc 4 4) '(32 0 0 32)) (check-= (send dc get-alpha) 0.25 0))))
   (test-case "zero group opacity leaves existing pixels intact"
     (using (lambda (dc) (send dc clear) (define before (pixels dc)) (send dc start-alpha 0)
       (fill dc "red" 0 0 30 30) (send dc end-alpha) (check-equal? before (pixels dc)))))
   (test-case "empty group leaves pixels intact"
     (using (lambda (dc) (fill dc "blue" 0 0 30 30) (define before (pixels dc))
       (send dc start-alpha 0.5) (send dc end-alpha) (check-equal? before (pixels dc)))))
   (test-case "root snapshot hides unfinished group and remains independent"
     (using (lambda (dc) (fill dc "blue" 0 0 30 30)
       (send dc start-alpha 0.5) (fill dc "red" 0 0 30 30)
       (check-equal? (pixel dc 4 4) '(0 0 255 255))
       (sk:with-skia ([image (send dc snapshot)])
         (send dc end-alpha)
         (check-equal? (subbytes (sk:image->rgba-bytes image) 0 4) (bytes 0 0 255 255))))))
   (test-case "copy inside group reads group storage rather than parent"
     (using (lambda (dc) (fill dc "blue" 0 0 30 30)
       (send dc start-alpha 1) (fill dc "red" 2 2 4 4) (send dc copy 2 2 4 4 10 2)
       (send dc end-alpha) (check-equal? (pixel dc 11 3) '(255 0 0 255)))))
   (test-case "parent clipping is applied when group merges"
     (using (lambda (dc) (send dc set-clipping-rect 2 2 4 4) (send dc start-alpha 0.5)
       (fill dc "red" 0 0 20 20) (send dc end-alpha)
       (near (pixel dc 3 3) '(128 0 0 128)) (check-equal? (pixel dc 7 3) '(0 0 0 0)))))
   (test-case "nested clip does not replace parent merge boundary"
     (using (lambda (dc) (send dc set-clipping-rect 2 2 5 5) (send dc start-alpha 1)
       (send dc set-clipping-rect 4 2 8 5) (fill dc "red" 0 0 20 20) (send dc end-alpha)
       (check-equal? (pixel dc 5 3) '(255 0 0 255)) (check-equal? (pixel dc 3 3) '(0 0 0 0))
       (check-equal? (pixel dc 8 3) '(0 0 0 0)))))
   (test-case "erase inside alpha clears only the group"
     (using (lambda (dc) (fill dc "blue" 0 0 30 30) (send dc start-alpha 1)
       (fill dc "red" 0 0 30 30) (send dc erase) (send dc end-alpha)
       (check-equal? (pixel dc 4 4) '(0 0 255 255)))))
   (test-case "group merge does not apply current transform twice"
     (using (lambda (dc) (send dc translate 10 8) (send dc start-alpha 1)
       (fill dc "red" 2 2 4 4) (send dc end-alpha)
       (check-equal? (pixel dc 13 11) '(255 0 0 255)) (check-equal? (pixel dc 23 19) '(0 0 0 0)))))
   (test-case "simple overlapping group agrees with bitmap-dc%"
     (reference (lambda (dc) (send dc start-alpha 0.5)
       (fill dc "red" 2 2 12 12) (fill dc "blue" 8 2 12 12) (send dc end-alpha)) 1))
   (test-case "nested oracle agrees with bitmap-dc% within two channel units"
     (reference draw-dc-replay-oracle 2))
   (test-case "memory rejection leaves native pixels unchanged"
     (using (lambda (dc) (fill dc "blue" 0 0 30 30) (define before (pixels dc))
       (parameterize ([sk:current-skia-byte-limit (* 4 96 72)])
         (check-exn exn:fail? (lambda () (send dc start-alpha 0.5))))
       (check-equal? before (pixels dc)))))
   (test-case "close discards group and retained root image survives"
     (define image
       (using (lambda (dc) (fill dc "blue" 0 0 30 30) (send dc start-alpha 1)
         (fill dc "red" 0 0 30 30) (send dc snapshot))))
     (sk:with-skia ([im image]) (check-equal? (subbytes (sk:image->rgba-bytes im) 0 4) (bytes 0 0 255 255))))
   (test-case "backing scale is applied once through alpha group"
     (using (lambda (dc) (send dc start-alpha 1) (fill dc "red" 2 3 4 5) (send dc end-alpha)
       (check-equal? (pixel dc 5 7) '(255 0 0 255)) (check-equal? (pixel dc 3 7) '(0 0 0 0))) 24 20 2))
   (test-case "replay inside existing alpha group leaves that group open"
     (define-values (proc datum) (make-dc-recording simple))
     (for ([draw (list proc datum)])
       (using (lambda (dc) (send dc start-alpha 0.5) (draw dc)
         (check-equal? (pixel dc 4 5) '(0 0 0 0)) (send dc end-alpha)
         (near (pixel dc 4 5) '(128 0 0 128))))))))
(define dc-replay-native-test-count 28)
