#lang racket/base
(require rackunit racket/class racket/list racket/math
         (prefix-in rd: racket/draw) (prefix-in sk: "../main.rkt") "../dc.rkt")
(provide dc-native-tests dc-native-test-count)
(define (using-dc proc [w 24] [h 20] [backing 1])
  (define dc (new skia-dc% [width w] [height h] [backing-scale backing]))
  (dynamic-wind void (lambda () (proc dc)) (lambda () (send dc close))))
(define (pixel dc x y)
  (define-values (w h) (send dc get-pixel-size))
  (define bs (send dc get-rgba-bytes #:premultiplied? #t))
  (for/list ([i (in-range (* 4 (+ x (* w y))) (+ 4 (* 4 (+ x (* w y)))))]) (bytes-ref bs i)))
(define (fill-mode dc [color "red"])
  (send dc set-pen "black" 1 'transparent) (send dc set-brush color 'solid))
(define (argb->rgba b)
  (define out (make-bytes (bytes-length b)))
  (for ([i (in-range 0 (bytes-length b) 4)])
    (bytes-set! out i (bytes-ref b (+ i 1))) (bytes-set! out (+ i 1) (bytes-ref b (+ i 2)))
    (bytes-set! out (+ i 2) (bytes-ref b (+ i 3))) (bytes-set! out (+ i 3) (bytes-ref b i))) out)
(define (compare-with-racket draw [tolerance 0])
  (define bm (rd:make-bitmap 24 20 #t))
  (define reference (new rd:bitmap-dc% [bitmap bm]))
  (send reference erase) (draw reference) (send reference set-bitmap #f)
  (define bytes (make-bytes (* 4 24 20))) (send bm get-argb-pixels 0 0 24 20 bytes #f #t)
  (define expected (argb->rgba bytes))
  (using-dc (lambda (dc)
              (draw dc)
              (define actual (send dc get-rgba-bytes #:premultiplied? #t))
              (check-equal? (bytes-length actual) (bytes-length expected))
              (for ([a (in-bytes actual)] [e (in-bytes expected)] [i (in-naturals)])
                (check-true (<= (abs (- a e)) tolerance) (format "byte ~a: Skia ~a, Racket ~a" i a e))))))
(define dc-native-tests
  (test-suite
   "skia-dc persistent CPU raster native tests"
   (test-case "real DC identity and raster snapshot"
     (using-dc (lambda (dc) (check-true (skia-dc? dc)) (check-true (is-a? dc rd:dc<%>))
                 (sk:with-skia ([im (send dc snapshot)])
                   (check-equal? (sk:image-width im) 24) (check-equal? (sk:image-height im) 20)))))
   (test-case "initial pixels are transparent"
     (using-dc (lambda (dc) (check-equal? (pixel dc 4 4) '(0 0 0 0)))))
   (test-case "ordinary fill uses Skia storage"
     (using-dc (lambda (dc) (fill-mode dc) (send dc draw-rectangle 2 3 7 8)
                 (check-equal? (pixel dc 4 5) '(255 0 0 255))
                 (check-equal? (pixel dc 1 1) '(0 0 0 0)))))
   (test-case "backing scale controls physical pixels"
     (using-dc (lambda (dc) (fill-mode dc) (send dc draw-rectangle 2 3 4 5)
                 (check-equal? (pixel dc 4 6) '(255 0 0 255))
                 (check-equal? (pixel dc 3 6) '(0 0 0 0))
                 (check-equal? (bytes-length (send dc get-rgba-bytes)) (* 48 40 4))) 24 20 2))
   (test-case "fractional backing extent rounds up"
     (using-dc (lambda (dc) (check-equal? (call-with-values (lambda () (send dc get-pixel-size)) list) '(47 35))) 31 23 1.5))
   (test-case "clear obeys background and ignores logical transform"
     (using-dc (lambda (dc) (send dc set-origin 100 100) (send dc set-background "blue") (send dc clear)
                 (check-equal? (pixel dc 1 1) '(0 0 255 255)))))
   (test-case "erase removes alpha irrespective of DC opacity"
     (using-dc (lambda (dc) (send dc clear) (send dc set-alpha 0.25) (send dc erase)
                 (check-equal? (pixel dc 1 1) '(0 0 0 0)))))
   (test-case "clear blends with existing pixels"
     (using-dc (lambda (dc) (send dc set-background "blue") (send dc clear)
                 (send dc set-background "red") (send dc set-alpha 0.5) (send dc clear)
                 (define p (pixel dc 1 1))
                 (check-true (<= 127 (first p) 128)) (check-equal? (second p) 0)
                 (check-true (<= 127 (third p) 128)) (check-equal? (fourth p) 255))))
   (test-case "clipping is retained across draws"
     (using-dc (lambda (dc) (send dc set-clipping-rect 2 3 5 6) (send dc set-background "red") (send dc clear)
                 (check-equal? (pixel dc 3 4) '(255 0 0 255)) (check-equal? (pixel dc 1 4) '(0 0 0 0)))))
   (test-case "clipping captures transform at installation"
     (using-dc (lambda (dc) (send dc set-origin 3 4) (send dc set-clipping-rect 1 2 5 6)
                 (send dc set-origin 50 50) (send dc clear)
                 (check-equal? (pixel dc 4 6) '(255 255 255 255)) (check-equal? (pixel dc 1 2) '(0 0 0 0)))))
   (test-case "zero-area clipping is empty"
     (using-dc (lambda (dc) (send dc set-clipping-rect 1 1 0 10) (send dc clear)
                 (check-equal? (pixel dc 1 5) '(0 0 0 0)))))
   (test-case "clipping can be reset and restored"
     (using-dc (lambda (dc) (send dc set-clipping-rect 1 1 5 5)
                 (define old (send dc get-clipping-region))
                 (send dc set-clipping-region #f) (send dc set-background "blue") (send dc clear)
                 (send dc set-clipping-region old) (send dc set-background "red") (send dc clear)
                 (check-equal? (pixel dc 2 2) '(255 0 0 255)) (check-equal? (pixel dc 9 9) '(0 0 255 255)))))
   (test-case "erase respects clipping"
     (using-dc (lambda (dc) (send dc clear) (send dc set-clipping-rect 2 2 4 4) (send dc erase)
                 (check-equal? (pixel dc 3 3) '(0 0 0 0)) (check-equal? (pixel dc 1 1) '(255 255 255 255)))))
   (test-case "scaled translated fill has correct placement"
     (using-dc (lambda (dc) (fill-mode dc) (send dc set-origin 3 4) (send dc set-scale 2 2)
                 (send dc draw-rectangle 1 1 3 3)
                 (check-equal? (pixel dc 5 6) '(255 0 0 255)) (check-equal? (pixel dc 4 6) '(0 0 0 0)))))
   (test-case "smoothed rotation uses counter-clockwise orientation"
     (using-dc (lambda (dc) (fill-mode dc) (send dc set-smoothing 'smoothed)
                 (send dc translate 12 12) (send dc rotate (/ pi 2)) (send dc draw-rectangle 1 1 4 4)
                 (check-equal? (pixel dc 14 9) '(255 0 0 255)) (check-equal? (pixel dc 9 14) '(0 0 0 0)))))
   (test-case "smoothed reflection and shear draw without fallback"
     (using-dc (lambda (dc) (fill-mode dc) (send dc set-smoothing 'smoothed)
                 (send dc set-initial-matrix '#(-1 0 0.5 1 20 0)) (send dc draw-rectangle 2 2 6 6)
                 (check-equal? (pixel dc 18 5) '(255 0 0 255)))))
   (test-case "odd-even holes differ from winding fills"
     (using-dc (lambda (dc) (fill-mode dc)
                 (define p (new rd:dc-path%)) (send p rectangle 1 1 18 16) (send p rectangle 5 5 6 6)
                 (send dc draw-path p 0 0 'odd-even) (check-equal? (pixel dc 7 7) '(0 0 0 0))
                 (send dc draw-path p 0 0 'winding) (check-equal? (pixel dc 7 7) '(255 0 0 255)))))
   (test-case "round rectangles exclude the extreme corners"
     (using-dc (lambda (dc) (fill-mode dc) (send dc draw-rounded-rectangle 2 2 16 16 5)
                 (check-equal? (pixel dc 2 2) '(0 0 0 0)) (check-equal? (pixel dc 10 10) '(255 0 0 255)))))
   (test-case "ellipse center is filled"
     (using-dc (lambda (dc) (fill-mode dc) (send dc draw-ellipse 2 2 16 12)
                 (check-equal? (pixel dc 10 8) '(255 0 0 255)) (check-equal? (pixel dc 2 2) '(0 0 0 0)))))
   (test-case "arc fill is a wedge while the opposite quadrant stays empty"
     (using-dc (lambda (dc) (fill-mode dc) (send dc draw-arc 2 2 16 16 0 (/ pi 2))
                 (check-equal? (pixel dc 12 7) '(255 0 0 255)) (check-equal? (pixel dc 7 12) '(0 0 0 0)))))
   (test-case "strokes and point pens produce nonempty pixels"
     (using-dc (lambda (dc) (send dc set-brush "white" 'transparent) (send dc set-pen "red" 3 'solid)
                 (send dc draw-line 2 8 20 8) (send dc draw-point 6 15)
                 (check-equal? (pixel dc 10 8) '(255 0 0 255)) (check-equal? (pixel dc 6 15) '(255 0 0 255)))))
   (test-case "dash stroke has ink and gaps"
     (using-dc (lambda (dc) (send dc set-pen "red" 2 'long-dash) (send dc draw-line 1 10 22 10)
                 (define alphas (for/list ([x (in-range 2 21)]) (fourth (pixel dc x 10))))
                 (check-not-false (member 0 alphas)) (check-not-false (member 255 alphas)))))
   (test-case "snapshot survives both mutation and DC close"
     (define image
       (using-dc (lambda (dc) (send dc set-background "red") (send dc clear)
                   (define im (send dc snapshot)) (send dc set-background "blue") (send dc clear) im)))
     (sk:with-skia ([im image])
       (define b (sk:image->rgba-bytes im)) (check-equal? (subbytes b 0 4) (bytes 255 0 0 255))))
   (test-case "PNG export has the PNG signature"
     (using-dc (lambda (dc) (send dc clear)
                 (define bs (send dc get-png-bytes)) (check-equal? (subbytes bs 1 4) #"PNG")
                 (check-true (> (bytes-length bs) 40)))))
   (test-case "repeated independent DCs close cleanly"
     (for ([i (in-range 12)]) (using-dc (lambda (dc) (fill-mode dc) (send dc draw-rectangle 1 2 3 4)
                                                 (check-equal? (pixel dc 2 3) '(255 0 0 255))))))
   (test-case "unsupported method leaves real pixels unchanged"
     (using-dc (lambda (dc) (send dc clear) (define before (send dc get-rgba-bytes))
                 (check-exn exn:fail:skia-dc:unsupported? (lambda () (send dc set-brush "red" 'cross-hatch)))
                 (check-equal? (send dc get-rgba-bytes) before))))
   (test-case "integer rectangles agree with bitmap-dc%"
     (compare-with-racket (lambda (dc) (fill-mode dc) (send dc draw-rectangle 2 3 7 8)) 0))
   (test-case "clip and clear agree with bitmap-dc%"
     (compare-with-racket (lambda (dc) (send dc set-clipping-rect 2 3 7 8) (send dc set-background "red") (send dc clear)) 0))
   (test-case "axis transforms agree with bitmap-dc%"
     (compare-with-racket (lambda (dc) (fill-mode dc) (send dc set-origin 3 4) (send dc set-scale 2 2)
                                      (send dc draw-rectangle 1 1 3 3)) 0))
   (test-case "opacity composition agrees within one channel unit"
     (compare-with-racket (lambda (dc) (send dc clear) (fill-mode dc) (send dc set-alpha 0.5)
                                      (send dc draw-rectangle 2 3 7 8)) 1))
   (test-case "public drawing procedure can replay into a Skia dc"
     ;; Keep the 0.53 replay smoke test strictly on public dc<%> methods.
     ;; Racket's record-dc% closure also sends private local-member methods
     ;; (`do-set-pen!`/`do-set-brush!`), covered by the separate 0.55 suite.
     (define (replay dc)
       (fill-mode dc)
       (send dc draw-rectangle 2 3 7 8))
     (using-dc (lambda (dc) (replay dc) (check-equal? (pixel dc 4 5) '(255 0 0 255)))))))
(define dc-native-test-count 31)
