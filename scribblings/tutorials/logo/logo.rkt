#lang racket

;;;
;;; Logo
;;;

;; Builds a logo from path commands and saves raster and vector versions.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require skia)

;;;
;;; Drawing Data and Helpers
;;;

; size : exact-integer?
;   Specifies size in the drawing's local coordinate units.
(define size 500)

; background-color : string?
;   Specifies the background color color used by this drawing.
(define background-color "#F4F0E7")

; fill-color : string?
;   Specifies the fill color color used by this drawing.
(define fill-color "#246B5A")

; outline-color : string?
;   Specifies the outline color color used by this drawing.
(define outline-color "#173B35")

; logo-commands : list?
;   Orders the path segments forming the logo's closed outline.
(define logo-commands
  '((move 250 50)
    (cubic 405 85 440 280 250 440)
    (cubic 60 280 95 85 250 50)
    (close)
    (move 165 310)
    (cubic 210 250 280 195 350 145)
    (cubic 315 220 270 305 205 355)
    (cubic 190 340 177 325 165 310)
    (close)))

; make-logo-path : -> path?
;   Constructs logo path for the example's drawing pipeline.
(define (make-logo-path)
  (make-path logo-commands #:fill-rule 'even-odd))

; draw-logo : canvas? -> void?
;   Draws the logo component in the current canvas coordinate system.
(define (draw-logo canvas)
  (define path (make-logo-path))
  (define fill (make-paint #:color fill-color))
  (define outline (make-paint #:color outline-color
    #:style 'stroke
    #:stroke-width 5
    #:join 'round))
  (draw-path canvas path fill)
  (draw-path canvas path outline))

; save-raster : path-string? -> void?
;   Renders the raster example to the selected output destination.
(define (save-raster filename)
  (define surface (make-surface size size
    #:background background-color))
  (draw-logo (surface-canvas surface))
  (save-png surface filename #:exists 'replace))

; save-vector : path-string? -> void?
;   Exports the drawing through the output-page API to a vector document.
(define (save-vector filename)
  (define page
    (make-output-page size size draw-logo
                      #:unit 'px
                      #:background background-color))
  (save-output page filename 'svg #:exists 'replace))

;;;
;;; Command-Line Entry Point
;;;

(module+ main
  (save-raster "logo.png")
  (save-vector "logo.svg"))
