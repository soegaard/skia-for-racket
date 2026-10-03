#lang racket/base
(require rackunit racket/class racket/list (prefix-in rd: racket/draw)
         "../private/dc-class.rkt" "../private/dc-support.rkt" "../private/dc-styles.rkt"
         "../private/dc-bitmap.rkt" "../private/dc-style-math.rkt"
         "dc-style-math-test.rkt" "dc-style-fixtures.rkt")
(provide dc-style-pure-tests dc-style-pure-test-count)
(define (with-dc proc)
  (define events (box '()))
  (define renderer (dc-renderer (lambda (w h) #t) void
                                (lambda (s d) (set-box! events (append (unbox events) (list d))))
                                (lambda args (void)) values (lambda args #"") (lambda args #"")))
  (define dc (new (make-skia-dc-class renderer) [width 64] [height 64] [smoothing 'smoothed]))
  (dynamic-wind void (lambda () (proc dc events)) (lambda () (send dc close))))
(define (last-ink events) (dc-draw-ink (last (unbox events))))
(define (draw-brush dc b) (fill-with dc b 0 0 16 16))
(define dc-style-pure-test-count 24)
(define dc-style-pure-tests
  (test-suite "DC style preparation without Skia"
   (test-case "45 production math cases" (check-equal? (run-dc-style-math-tests) 45))
   (test-case "all public pen styles accepted"
     (with-dc (lambda (dc e) (for ([s dc-pen-styles]) (send dc set-pen "red" 2 s)))))
   (test-case "all public brush styles accepted"
     (with-dc (lambda (dc e) (for ([s dc-brush-styles]) (send dc set-brush "red" s)))))
   (test-case "hatch descriptions contain no native objects"
     (with-dc (lambda (dc e)
       (draw-brush dc (rd:make-brush #:color "red" #:style 'cross-hatch))
       (check-eq? (dc-paint-source-kind (dc-ink/style-source (last-ink e))) 'hatch))))
   (test-case "linear gradient is normalized"
     (with-dc (lambda (dc e) (draw-brush dc (rd:make-brush #:gradient (linear)))
       (check-eq? (vector-ref (dc-paint-source-data (dc-ink/style-source (last-ink e))) 0) 'linear))))
   (test-case "radial circles are preserved"
     (with-dc (lambda (dc e) (draw-brush dc (rd:make-brush #:gradient (radial)))
       (check-equal? (vector-ref (dc-paint-source-data (dc-ink/style-source (last-ink e))) 1)
                     '(8.0 24.0 0.0 8.0 24.0 8.0)))))
   (test-case "gradient stops are sorted stably"
     (with-dc (lambda (dc e)
       (draw-brush dc (rd:make-brush #:gradient (linear (list (list 1 (color 0 0 255)) (list 0 (color 255 0 0))))))
       (check-equal? (map car (vector-ref (dc-paint-source-data (dc-ink/style-source (last-ink e))) 2)) '(0.0 1.0)))))
   (test-case "zero stop gradient is supported"
     (check-not-exn (lambda () (dc-check-brush (rd:make-brush #:gradient (linear '()))))))
   (test-case "one stop gradient is supported"
     (check-not-exn (lambda () (dc-check-brush (rd:make-brush #:gradient (linear (list (list 0.2 (color 1 2 3)))))))))
   (test-case "nonfinite gradient geometry is rejected before selection"
     (with-dc (lambda (dc e)
       (define old (send dc get-brush))
       (define g (new rd:linear-gradient% [x0 +nan.0] [y0 0] [x1 10] [y1 0] [stops '()]))
       (check-exn exn:fail? (lambda () (send dc set-brush (rd:make-brush #:gradient g))))
       (check-eq? old (send dc get-brush)))))
   (test-case "singular brush transformation rejected before selection"
     (with-dc (lambda (dc e)
       (define old (send dc get-brush))
       (check-exn exn:fail? (lambda () (send dc set-brush
         (rd:make-brush #:gradient (linear) #:transformation '#(#(0 0 0 1 0 0) 0 0 1 1 0)))))
       (check-eq? old (send dc get-brush)))))
   (test-case "brush transformation replaces rather than composes with DC"
     (with-dc (lambda (dc e)
       (send dc set-origin 8 0) (send dc set-scale 2 2)
       (draw-brush dc (rd:make-brush #:gradient (linear) #:transformation '#(#(1 0 0 1 0 0) 0 0 1 1 0)))
       (check-equal? (dc-paint-source-matrix (dc-ink/style-source (last-ink e))) '#(0.5 0.0 0.0 0.5 -4.0 0.0)))))
   (test-case "stipple uses immutable copied pixels"
     (with-dc (lambda (dc e) (draw-brush dc (rd:make-brush #:stipple (tile)))
       (define data (dc-paint-source-data (dc-ink/style-source (last-ink e))))
       (check-true (immutable? (dc-bitmap-data-pixels data))))))
   (test-case "stipple backing scale is not destination scale"
     (with-dc (lambda (dc e) (draw-brush dc (rd:make-brush #:stipple (tile 2)))
       (check-equal? (dc-paint-source-matrix (dc-ink/style-source (last-ink e))) '#(0.5 0.0 0.0 0.5 0.0 0.0)))))
   (test-case "gradient source wins over stipple"
     (with-dc (lambda (dc e) (draw-brush dc (rd:make-brush #:gradient (linear) #:stipple (tile)))
       (check-eq? (dc-paint-source-kind (dc-ink/style-source (last-ink e))) 'gradient))))
   (test-case "transparent style suppresses drawing"
     (with-dc (lambda (dc e) (draw-brush dc (rd:make-brush #:style 'transparent #:gradient (linear)))
       (check-equal? (unbox e) '()))))
   (test-case "hilite alpha is applied once"
     (with-dc (lambda (dc e) (send dc set-alpha 0.5)
       (draw-brush dc (rd:make-brush #:color "red" #:style 'hilite))
       (check-equal? (dc-ink-rgba (last-ink e)) '#(0 0 0 0.15)))))
   (test-case "stippled dashed pen keeps its pattern and phase"
     (with-dc (lambda (dc e) (send dc set-pen (rd:make-pen #:width 3 #:style 'dot #:stipple (tile)))
       (send dc draw-line 0 4 20 4) (check-equal? (dc-ink-dashes (last-ink e)) '(3.0 6.0)))))
   (test-case "dash phase is retained in command"
     (with-dc (lambda (dc e) (send dc set-pen "red" 2 'dot-dash) (send dc draw-line 0 4 20 4)
       (check-= (dc-ink/style-phase (last-ink e)) 4.0 0))))
   (test-case "mutable pattern pixels are resnapshotted"
     (with-dc (lambda (dc e)
       (define bm (tile)) (define b (rd:make-brush #:stipple bm))
       (draw-brush dc b)
       (define first (dc-bitmap-data-pixels (dc-paint-source-data (dc-ink/style-source (last-ink e)))))
       (send bm set-argb-pixels 0 0 1 1 (bytes 255 12 34 56)) (draw-brush dc b)
       (check-not-equal? first (dc-bitmap-data-pixels (dc-paint-source-data (dc-ink/style-source (last-ink e))))))))
   (test-case "gradient color mutation does not mutate earlier command"
     (with-dc (lambda (dc e)
       (define c (color 255 0 0)) (define b (rd:make-brush #:gradient (linear (list (list 0 c)))))
       (draw-brush dc b) (define first (dc-paint-source-data (dc-ink/style-source (last-ink e))))
       (send c set 0 255 0) (draw-brush dc b)
       (check-not-equal? first (dc-paint-source-data (dc-ink/style-source (last-ink e)))))))
   (test-case "affine unsmoothed geometry is accepted"
     (with-dc (lambda (dc e) (send dc set-smoothing 'unsmoothed)
       (send dc set-initial-matrix '#(-1 0.3 0.2 1 32 0))
       (send dc draw-line 1 2 10 20) (check-equal? (length (unbox e)) 1))))
   (test-case "selected patterned brush retains identity and releases lock"
     (with-dc (lambda (dc e) (define b (rd:make-brush #:stipple (tile) #:immutable? #f))
       (send dc set-brush b) (check-eq? b (send dc get-brush))
       (check-exn exn:fail? (lambda () (send b set-style 'solid)))
       (send dc close) (check-not-exn (lambda () (send b set-style 'solid))))))
   (test-case "monochrome xor pixels equal solid"
     (define bm (mono-tile))
     (define (snapshot s) (dc-bitmap-data-pixels (dc-bitmap-snapshot 'test bm s (color 255 0 0) #f (color 0 0 255))))
     (check-equal? (snapshot 'xor) (snapshot 'solid)))))
