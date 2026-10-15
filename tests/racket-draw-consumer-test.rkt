#lang racket/base

(require rackunit rackunit/text-ui racket/class racket/list
         (prefix-in rd: racket/draw)
         "../main.rkt" "../racket-draw.rkt" "../dc.rkt" "../dc-output.rkt")

(provide racket-draw-consumer-tests)

(define (pixel bytes width x y)
  (define i (* 4 (+ x (* y width))))
  (subbytes bytes i (+ i 4)))

(define racket-draw-consumer-tests
  (test-suite
   "skia/racket-draw ordinary consumer integration"
   (test-case "a Draw bitmap imports into Skia and exports through bitmap%"
     (define source (rd:make-bitmap 4 3 #t))
     (send source set-argb-pixels 0 0 4 3
           (apply bytes (append* (make-list 12 '(255 255 0 0)))) #f #t)
     (with-skia ([image (bitmap->image source #:mask #f)]
                 [surface (make-surface 8 6 #:background 'white)]
                 [paint (make-paint #:antialias? #f)])
       (draw-image (surface-canvas surface) image 2 1 #:paint paint)
       (define copied (surface->bitmap surface))
       (define argb (make-bytes 4))
       (send copied get-argb-pixels 2 1 1 1 argb #f #t)
       (check-equal? argb (bytes 255 255 0 0))))
   (test-case "exported paths and styles work with bitmap, Skia DC, and vector PDF output"
     (with-skia ([source (make-path '((move 2 2) (line 18 2) (line 18 18) (line 2 18) (close)
                                      (move 6 6) (line 14 6) (line 14 14) (line 6 14) (close))
                                    #:fill-rule 'even-odd)])
       (define-values (draw-path fill-style) (skia-path->dc-path source))
       (define bitmap (rd:make-bitmap 22 22 #t))
       (define bitmap-dc (new rd:bitmap-dc% [bitmap bitmap]))
       (send bitmap-dc set-pen "black" 1 'transparent)
       (send bitmap-dc set-brush "red" 'solid)
       (send bitmap-dc draw-path draw-path 0 0 fill-style)
       (send bitmap-dc set-bitmap #f)
       (define center (make-bytes 4))
       (send bitmap get-argb-pixels 10 10 1 1 center #f #t)
       (check-equal? center (bytes 0 0 0 0))
       (define dc (new skia-dc% [width 22] [height 22]))
       (dynamic-wind
         void
         (lambda ()
           (send dc set-pen "black" 1 'transparent)
           (send dc set-brush "red" 'solid)
           (send dc draw-path draw-path 0 0 fill-style)
           (check-equal? (pixel (send dc get-rgba-bytes #:premultiplied? #t) 22 3 3)
                         (bytes 255 0 0 255)))
         (lambda () (send dc close)))
       (define page
         (make-dc-output-page 22 22
           (lambda (dc)
             (send dc set-pen "black" 1 'transparent)
             (send dc set-brush "red" 'solid)
             (send dc draw-path draw-path 0 0 fill-style))
           #:policy 'require-vector))
       (define pdf (output->bytes page 'pdf))
       (define svg (output->bytes page 'svg))
       (check-equal? (subbytes pdf 0 5) #"%PDF-")
       (check-true (regexp-match? #rx#"<(path|rect)" svg))
       (check-false (regexp-match? #rx#"<image" svg))))
   (test-case "Draw-authored paths remain vector geometry when imported and rendered"
     (define draw-source (new rd:dc-path%))
     (send draw-source rectangle 1 1 12 8)
     (with-skia ([path (dc-path->skia-path draw-source #:fill-style 'winding)]
                 [surface (make-surface 20 14)]
                 [paint (make-paint #:color 'blue #:antialias? #f)])
       (draw-path (surface-canvas surface) path paint)
       (check-equal? (pixel (surface->rgba-bytes surface #:premultiplied? #t) 20 4 4)
                     (bytes 0 0 255 255))))))

(module+ test
  (skia-check!)
  (define failures (run-tests racket-draw-consumer-tests))
  (unless (zero? failures) (error 'racket-draw-consumer-test "~a failures" failures)))
