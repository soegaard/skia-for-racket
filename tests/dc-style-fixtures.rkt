#lang racket/base

;;;
;;; DC Style Fixtures
;;;

;; Provides shared inputs and drawing fixtures for DC brush styles, gradients, stipples, and
;; compatibility queries.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
(require racket/class (prefix-in rd: racket/draw))
(provide color tile mono-tile linear radial fill-with style-oracle)

;;;
;;; Fixtures and Assertions
;;;

; color : byte? byte? byte? [real?] -> color%
;   Builds a Racket Draw color with unit-interval alpha.
(define (color r g b [a 1.0]) (make-object rd:color% r g b a))

; tile : [exact-positive-integer?] -> bitmap%
;   Builds a four-color stipple whose logical 2-by-2 pattern survives backing-scale changes.
(define (tile [backing 1])
  (define bm (rd:make-bitmap 2 2 #t #:backing-scale backing))
  (define w (* 2 backing))
  (define pixels (make-bytes (* w w 4)))
  (for* ([y (in-range w)] [x (in-range w)])
    (define c (list-ref '((255 0 0) (0 255 0) (0 0 255) (255 255 0))
                       (+ (quotient x backing) (* 2 (quotient y backing)))))
    (define i (* 4 (+ x (* y w))))
    (bytes-set! pixels i 255)
    (for ([v (in-list c)] [j '(1 2 3)]) (bytes-set! pixels (+ i j) v)))
  (send bm set-argb-pixels 0 0 w w pixels #f #f #:unscaled? #t)
  bm)

; mono-tile : -> bitmap%
;   Builds a monochrome checkerboard for stipple colorization tests.
(define (mono-tile)
  (define bm (make-object rd:bitmap% 2 2 #t))
  (send bm set-argb-pixels 0 0 2 2 (bytes 255 0 0 0 255 255 255 255
                                             255 255 255 255 255 0 0 0))
  bm)

; linear : [list?] -> linear-gradient%
;   Creates a horizontal 16-unit gradient with the supplied ordered color stops.
(define (linear [stops (list (list 0 (color 255 0 0)) (list 1 (color 0 0 255)))])
  (new rd:linear-gradient% [x0 0] [y0 0] [x1 16] [y1 0] [stops stops]))

; radial : -> radial-gradient%
;   Creates a concentric red-to-blue gradient centered in its comparison tile.
(define (radial)
  (new rd:radial-gradient% [x0 8] [y0 24] [r0 0] [x1 8] [y1 24] [r1 8]
       [stops (list (list 0 (color 255 0 0)) (list 1 (color 0 0 255)))]))

; fill-with : dc<%> brush% real? real? real? real? -> void?
;   Fills a rectangle using the supplied brush and no visible pen.
(define (fill-with dc brush x y w h)
  (send dc set-pen "black" 1 'transparent)
  (send dc set-brush brush)
  (send dc draw-rectangle x y w h))

; style-oracle : dc<%> -> any
;   Draws the common gradient, stipple, and hatch grid used by CPU and document checks.
(define (style-oracle dc)
  (send dc set-smoothing 'unsmoothed)
  (send dc set-background "white") (send dc clear)
  (fill-with dc (rd:make-brush #:gradient (linear)) 0 0 16 16)
  (fill-with dc (rd:make-brush #:stipple (tile)) 16 0 16 16)
  (fill-with dc (rd:make-brush #:color "red" #:style 'horizontal-hatch) 32 0 16 16)
  (fill-with dc (rd:make-brush #:style 'hilite) 48 0 16 16)
  (fill-with dc (rd:make-brush #:gradient (radial)) 0 16 16 16)
  (fill-with dc (rd:make-brush #:color "green" #:style 'xor) 16 16 16 16)
  (fill-with dc (rd:make-brush #:color (color 0 0 255) #:stipple (mono-tile)) 32 16 16 16)
  (send dc set-background (color 255 200 0))
  (fill-with dc (rd:make-brush #:color (color 0 0 255) #:style 'opaque #:stipple (mono-tile)) 48 16
    16 16)
  (fill-with dc (rd:make-brush #:gradient (linear)
                                #:transformation '#(#(1 0 0 1 0 0) 16 32 1 1 0)) 16 32 16 16)
  (send dc start-alpha 0.5)
  (fill-with dc (rd:make-brush #:color "red" #:style 'panel) 32 32 16 16)
  (send dc end-alpha)
  (fill-with dc (rd:make-brush #:stipple (tile 2)) 48 32 16 16)
  (send dc set-pen (rd:make-pen #:width 4 #:cap 'butt #:style 'solid #:stipple (tile)))
  (send dc draw-line 0 56 32 56)
  (void))
