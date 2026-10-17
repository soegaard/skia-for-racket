#lang racket

;;;
;;; Geometry Diagram
;;;

;; Draws a printable geometric construction in millimeter-based page coordinates.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require skia)

(provide page-width
         page-height
         page-margin
         content-width
         draw-construction
         draw-diagram
         make-diagram-page)

;;;
;;; Drawing Data and Helpers
;;;

; page-width : exact-integer?
;;   Specifies page width in the drawing's local coordinate units.
(define page-width 210)
; page-height : exact-integer?
;;   Specifies page height in the drawing's local coordinate units.
(define page-height 297)
; page-margin : exact-integer?
;;   Specifies page margin in the drawing's local coordinate units.
(define page-margin 16)
; content-width : real?
;;   Specifies content width in the drawing's local coordinate units.
(define content-width (- page-width (* 2 page-margin)))

; ink-color : string?
;;   Specifies the ink color color used by this drawing.
(define ink-color "#253B50")
; muted-color : string?
;;   Specifies the muted color color used by this drawing.
(define muted-color "#586A7D")
; accent-color : string?
;;   Specifies the accent color color used by this drawing.
(define accent-color "#187E89")
; rule-color : string?
;;   Specifies the rule color color used by this drawing.
(define rule-color "#D1D9E1")

;; Font measurements should not be snapped to screen pixels before mm scaling.
; make-print-font : real? -> font?
;;   Converts a point size to the millimeter-based coordinates of the printable diagram.
(define (make-print-font size)
  (make-font #:size size
             #:linear-metrics? #t
             #:subpixel? #t
             #:hinting 'none))

; point-a-x : exact-integer?
;;   Specifies point a x in the drawing's local coordinate units.
(define point-a-x 60)
; point-b-x : exact-integer?
;;   Specifies point b x in the drawing's local coordinate units.
(define point-b-x 118)
; point-y : exact-integer?
;;   Specifies point y in the drawing's local coordinate units.
(define point-y 126)
; side-length : real?
;;   Measures the triangle's horizontal base in the diagram's millimeter coordinates.
(define side-length (- point-b-x point-a-x))
; point-c-x : real?
;;   Specifies point c x in the drawing's local coordinate units.
(define point-c-x (/ (+ point-a-x point-b-x) 2))
; point-c-y : real?
;;   Specifies point c y in the drawing's local coordinate units.
(define point-c-y (- point-y (* side-length (/ (sqrt 3) 2))))

; draw-construction : canvas? -> void?
;;   Draws the construction component in the current canvas coordinate system.
(define (draw-construction canvas)
  (define first-circle
    (make-paint #:color "#6CADB2"
                #:style 'stroke
                #:stroke-width 0.5))
  (define second-circle
    (make-paint #:color "#DBA05D"
                #:style 'stroke
                #:stroke-width 0.5))
  (define edge
    (make-paint #:color ink-color
                #:style 'stroke
                #:stroke-width 0.9))
  (define point
    (make-paint #:color ink-color))
  (draw-circle canvas point-a-x point-y side-length first-circle)
  (draw-circle canvas point-b-x point-y side-length second-circle)
  (draw-line canvas point-a-x point-y point-b-x point-y edge)
  (draw-line canvas point-a-x point-y point-c-x point-c-y edge)
  (draw-line canvas point-b-x point-y point-c-x point-c-y edge)
  (for ([position (list (list point-a-x point-y)
                        (list point-b-x point-y)
                        (list point-c-x point-c-y))])
    (draw-circle canvas (first position) (second position) 1.35 point)))

; draw-heading : canvas? -> void?
;;   Draws the heading component in the current canvas coordinate system.
(define (draw-heading canvas)
  (define small-font (make-print-font 3.7))
  (define title-font (make-print-font 8))
  (define subtitle-font (make-print-font 4.2))
  (define ink (make-paint #:color ink-color))
  (define accent (make-paint #:color accent-color))
  (define muted (make-paint #:color muted-color))
  (define rule (make-paint #:color rule-color
                           #:style 'stroke
                           #:stroke-width 0.45))
  (draw-simple-text canvas "SKIA / GEOMETRY STUDY" 0 9 small-font accent)
  (draw-simple-text canvas "An equilateral triangle" 0 27 title-font ink)
  (draw-simple-text canvas "A straightedge-and-compass construction" 0 37
                    subtitle-font muted)
  (draw-line canvas 0 45 content-width 45 rule))

; draw-point-labels : canvas? -> void?
;;   Draws the point labels component in the current canvas coordinate system.
(define (draw-point-labels canvas)
  (define font (make-print-font 5.2))
  (define ink (make-paint #:color ink-color))
  (draw-simple-text canvas "A" 52 134 font ink)
  (draw-simple-text canvas "B" 122 134 font ink)
  (draw-simple-text canvas "C" 94 (- point-c-y 5) font ink))

; draw-caption : canvas? -> void?
;;   Draws the caption component in the current canvas coordinate system.
(define (draw-caption canvas)
  (define tag-font (make-print-font 3.7))
  (define body-font (make-print-font 4.4))
  (define shaper (make-shaper body-font))
  (define ink (make-paint #:color ink-color))
  (define accent (make-paint #:color accent-color))
  (define muted (make-paint #:color muted-color))
  (define rule (make-paint #:color rule-color
                           #:style 'stroke
                           #:stroke-width 0.45))
  (define explanation
    (layout-text
     shaper
     (string-append
      "Both circles have radius AB. Their upper intersection is C. "
      "Since C lies on both circles, AB, AC, and BC have the same length.")
     #:width content-width))
  (draw-line canvas 0 209 content-width 209 rule)
  (draw-simple-text canvas "WHY IT WORKS" 0 221 tag-font accent)
  (draw-text-layout canvas explanation 0 227 ink)
  (draw-simple-text canvas "COMPASS / STRAIGHTEDGE" 0 257 tag-font muted)
  (draw-simple-text canvas "SKIA / 09" 155 257 tag-font muted))

; draw-diagram : canvas? -> void?
;;   Draws the diagram component in the current canvas coordinate system.
(define (draw-diagram canvas)
  (draw-heading canvas)
  (draw-construction canvas)
  (draw-point-labels canvas)
  (draw-caption canvas))

; make-diagram-page : -> output-page?
;;   Constructs diagram page for the example's drawing pipeline.
(define (make-diagram-page)
  (make-output-page page-width page-height draw-diagram
                    #:unit 'mm
                    #:margins page-margin
                    #:background 'white))

;;;
;;; Command-Line Entry Point
;;;

(module+ main
  ; page : output-page?
  ;;   Describes the page drawing and its export dimensions.
  (define page (make-diagram-page))
  ; preview : image?
  ;;   Truncates a text preview for display in the comparison panel.
  (define preview (output-page->image page #:dpi 96))
  (save-output page "equilateral-triangle.pdf" 'pdf #:exists 'replace)
  (save-output page "equilateral-triangle.svg" 'svg #:exists 'replace)
  (save-image preview "equilateral-triangle.png" 'png #:exists 'replace))
