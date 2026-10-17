#lang racket

;;;
;;; Badge
;;;

;; Constructs a badge from Boolean combinations of paths and draws the operands.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require skia)
(provide circle-path cross-path make-badge-parts make-badge
         draw-checker draw-shape draw-badge-sheet)

;;;
;;; Drawing Data and Helpers
;;;

; circle-path : real? -> path?
;   Creates the circular path operand with the requested radius.
(define (circle-path radius)
  (define path (make-path))
  (path-add-circle! path 160 160 radius)
  path)

; cross-path : -> path?
;   Creates the cross-shaped operand used in the badge's Boolean path operations.
(define (cross-path)
  (define path (make-path))
  (path-add-rect! path 16 138 288 44)
  (path-add-rect! path 138 16 44 288)
  path)

; make-badge-parts : -> hash?
;   Constructs badge parts for the example's drawing pipeline.
(define (make-badge-parts)
  (define disk (circle-path 92))
  (define cross (cross-path))
  (define boundary (circle-path 118))
  (define hole (circle-path 38))
  (define rim-inside (circle-path 108))
  (define joined (path-union disk cross))
  (define trimmed (path-intersect joined boundary))
  (define cutout (path-difference trimmed hole))
  (define rim (path-xor boundary rim-inside))
  (define badge (path-union cutout rim))
  (hash 'disk disk 'cross cross 'boundary boundary 'hole hole 'rim-inside rim-inside
        'joined joined 'trimmed trimmed 'cutout cutout 'rim rim 'badge badge))

; make-badge : -> path?
;   Constructs badge for the example's drawing pipeline.
(define (make-badge)
  (hash-ref (make-badge-parts) 'badge))

; draw-checker : canvas? real? real? -> void?
;   Draws a checkerboard that makes transparent pixels visible.
(define (draw-checker canvas width height)
  (define light (make-paint #:color "#FAF4E8"))
  (define dark (make-paint #:color "#E4DAC9"))
  (for* ([row (in-range (ceiling (/ height 20)))]
         [column (in-range (ceiling (/ width 20)))])
    (draw-rect canvas (* column 20) (* row 20) 20 20
               (if (even? (+ row column)) light dark))))

; draw-shape : canvas? path? -> void?
;   Draws the shape component in the current canvas coordinate system.
(define (draw-shape canvas path)
  (define fill (make-paint #:color "#23796F"))
  (define outline (make-paint #:color "#153E3C" #:style 'stroke #:stroke-width 2))
  (draw-path canvas path fill)
  (draw-path canvas path outline))

; draw-badge-sheet : canvas? any/c -> void?
;   Draws the badge sheet component in the current canvas coordinate system.
(define (draw-badge-sheet canvas parts)
  (define ink (make-paint #:color "#193F3D"))
  (define faint (make-paint #:color "#AB7C41" #:style 'stroke #:stroke-width 2))
  (define title-font (make-font #:size 28))
  (define font (make-font #:size 15))
  (canvas-clear! canvas "#F8F3E9")
  (draw-simple-text canvas "BUILD A CUTOUT BADGE" 28 48 title-font ink)
  (draw-simple-text canvas "Combine regions, then draw the resulting path." 30 78 font ink)
  (with-canvas-state canvas
    (canvas-translate! canvas 28 98)
    (draw-path canvas (hash-ref parts 'disk) faint)
    (draw-path canvas (hash-ref parts 'cross) faint)
    (draw-path canvas (hash-ref parts 'boundary) faint)
    (draw-path canvas (hash-ref parts 'rim-inside) faint)
    (draw-path canvas (hash-ref parts 'hole) faint))
  (with-canvas-state canvas
    (canvas-translate! canvas 372 98)
    (canvas-clip-rect! canvas 0 0 320 320)
    (draw-checker canvas 320 320)
    (draw-shape canvas (hash-ref parts 'badge)))
  (draw-simple-text canvas "The operands" 104 442 font ink)
  (draw-simple-text canvas "One path, with genuine holes" 404 442 font ink))

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; parts : hash?
  ;   Keeps the named intermediate paths used to explain the badge construction.
  (define parts (make-badge-parts))

  ; surface : surface?
  ;   Owns the raster drawing target used to produce the example's output.
  (define surface (make-surface 720 468))
  (draw-badge-sheet (surface-canvas surface) parts)
  (save-png surface "cutout-badge.png" #:exists 'replace))
