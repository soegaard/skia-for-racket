#lang racket/base

(require racket/runtime-path scribble/eval skia "badge.rkt" "../support/figures.rkt")
(provide paths-interaction paths-racketblock+eval badge-pict shape-pict operands-pict simplify-pict
         trim-pair difference-pair backgrounds-pict xor-comparison)
(define-runtime-path program-source "badge.rkt")
(define-runtime-path program-directory ".")
(define paths-eval (make-base-eval))
(paths-eval `(current-directory ,(path->string program-directory)))
(paths-eval '(require racket skia))
(paths-eval `(require (file ,(path->string program-source))))
(define parts (make-badge-parts))

(define (shape-pict key #:scale [scale 0.9])
  (render-pict 320 320
               (lambda (canvas)
                 (draw-checker canvas 320 320)
                 (draw-shape canvas (hash-ref parts key)))
               #:scale scale))

(define (badge-pict)
  (render-pict 720 468 (lambda (canvas) (draw-badge-sheet canvas parts)) #:scale 0.9))

(define (operands-pict)
  (figure-row (captioned-pict "Disk" (shape-pict 'disk #:scale 0.65))
              (captioned-pict "Cross: two overlapping contours" (shape-pict 'cross #:scale 0.65))))

(define (simplify-pict)
  (define source (cross-path))
  (define simplified (path-simplify source))
  (define (one path)
    (render-pict 320 320 (lambda (canvas) (draw-shape canvas path)) #:scale 0.7))
  (figure-row (captioned-pict "Original contour boundaries" (one source))
              (captioned-pict "Simplified filled region, then stroked" (one simplified))))

(define (trim-pair)
  (define operands
    (render-pict 320 320
                 (lambda (canvas)
                   (define boundary
                     (make-paint #:color "#B36230" #:style 'stroke #:stroke-width 2))
                   (draw-checker canvas 320 320)
                   (draw-shape canvas (hash-ref parts 'joined))
                   (draw-path canvas (hash-ref parts 'boundary) boundary))
                 #:scale 0.8))
  (figure-row (captioned-pict "Joined shape + circular limit" operands)
              (captioned-pict "Intersection: only the overlap"
                              (shape-pict 'trimmed #:scale 0.8))))

(define (difference-pair)
  (with-skia ([reverse (path-difference (hash-ref parts 'hole) (hash-ref parts 'trimmed))])
    (figure-row
     (captioned-pict "Body minus hole"
                     (shape-pict 'cutout #:scale 0.8))
     (captioned-pict
      "Hole minus body: empty"
      (render-pict 320 320
                   (lambda (canvas)
                     (draw-checker canvas 320 320)
                     (draw-shape canvas reverse))
                   #:scale 0.8)))))

(define (xor-comparison)
  (with-skia ([left (make-path)] [right (make-path)])
    (path-add-circle! left 80 100 62)
    (path-add-circle! right 140 100 62)
    (with-skia ([difference (path-difference left right)]
                [exclusive (path-xor left right)])
      (define (one path)
        (render-pict 220 200
                     (lambda (canvas)
                       (draw-checker canvas 220 200)
                       (draw-shape canvas path))))
      (define inputs
        (render-pict 220 200
                     (lambda (canvas)
                       (define outline
                         (make-paint #:color "#153E3C" #:style 'stroke #:stroke-width 2))
                       (define fill (make-paint #:color "#23796F"))
                       (define ink (make-paint #:color "#F8F3E9"))
                       (define font (make-font #:size 17))
                       (draw-checker canvas 220 200)
                       (draw-path canvas left fill)
                       (draw-path canvas right fill)
                       (draw-path canvas left outline)
                       (draw-path canvas right outline)
                       (draw-simple-text canvas "A" 40 106 font ink)
                       (draw-simple-text canvas "B" 168 106 font ink))))
      (figure-row (captioned-pict "Overlapping inputs A and B" inputs)
                  (captioned-pict "A minus B: one side" (one difference))
                  (captioned-pict "A XOR B: both outer sides" (one exclusive))))))

(define (backgrounds-pict)
  (define badge (hash-ref parts 'badge))
  (define (one kind)
    (render-pict 320 320
                 (lambda (canvas)
                   (case kind
                     [(gradient)
                      (define shader
                        (make-linear-gradient-shader 0 0 320 320 '("#234A78" "#F5D887")))
                      (define paint (make-paint #:shader shader))
                      (draw-rect canvas 0 0 320 320 paint)]
                     [(stripes)
                      (define dark (make-paint #:color "#BBCEDF"))
                      (canvas-clear! canvas "#FFFFFF")
                      (for ([y (in-range 0 320 32)])
                        (draw-rect canvas 0 y 320 16 dark))])
                   (draw-shape canvas badge))
                 #:scale 0.8))
  (figure-row (captioned-pict "Same badge over a gradient" (one 'gradient))
              (captioned-pict "Same badge over stripes" (one 'stripes))))

(define-syntax-rule (paths-interaction expression ...)
  (interaction #:eval paths-eval expression ...))
(define-syntax-rule (paths-racketblock+eval expression ...)
  (racketblock+eval #:eval paths-eval expression ...))
