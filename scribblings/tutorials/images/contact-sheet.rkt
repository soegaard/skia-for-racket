#lang racket

;;;
;;; Contact Sheet
;;;

;; Decodes local fixtures and arranges fitted, cropped, and resampled images.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require racket/runtime-path
         skia)

;;;
;;; Drawing Data and Helpers
;;;

; fixture-directory : path?
;;   Locates fixture directory relative to this module rather than the current directory.
(define-runtime-path fixture-directory "fixtures")

; width : exact-integer?
;;   Specifies width in the drawing's local coordinate units.
(define width 900)
; height : exact-integer?
;;   Specifies height in the drawing's local coordinate units.
(define height 600)

; background-color : string?
;;   Specifies the background color color used by this drawing.
(define background-color "#ECE8DF")
; card-color : string?
;;   Specifies the card color color used by this drawing.
(define card-color "#FFFFFF")
; frame-color : string?
;;   Specifies the frame color color used by this drawing.
(define frame-color "#CBD0D4")
; text-color : string?
;;   Specifies the text color color used by this drawing.
(define text-color "#26333D")

; fixture : any/c -> path?
;;   Resolves a local image fixture relative to the tutorial source directory.
(define (fixture name)
  (build-path fixture-directory name))

; draw-image-fit : canvas? image? real? real? real? real? #:sampling [symbol?] -> void?
;;   Fits the whole image inside a destination rectangle without changing its aspect ratio.
(define (draw-image-fit canvas image x y width height
                        #:sampling [sampling 'linear])
  (define scale
    (min (/ width (image-width image))
         (/ height (image-height image))))
  (define draw-width (* scale (image-width image)))
  (define draw-height (* scale (image-height image)))
  (define draw-x (+ x (/ (- width draw-width) 2)))
  (define draw-y (+ y (/ (- height draw-height) 2)))
  (draw-image-rect canvas
                   image
                   draw-x draw-y
                   draw-width draw-height
                   #:sampling sampling))

; draw-cell : canvas? image? any/c real? real? #:sampling [symbol?] -> void?
;;   Draws the cell component in the current canvas coordinate system.
(define (draw-cell canvas image label x y
                   #:sampling [sampling 'linear])
  (define card (make-paint #:color card-color))
  (define frame (make-paint #:color frame-color
    #:style 'stroke
    #:stroke-width 2))
  (define text (make-paint #:color text-color))
  (define font (make-font #:size 16))
  (draw-rounded-rect canvas x y 260 250 14 14 card)
  (draw-rounded-rect canvas x y 260 250 14 14 frame)
  (draw-image-fit canvas image
                  (+ x 15) (+ y 15)
                  230 185
                  #:sampling sampling)
  (draw-simple-text canvas label
                    (+ x 16) (+ y 229)
                    font text))

; draw-contact-sheet : canvas? any/c any/c any/c any/c any/c any/c -> void?
;;   Draws the contact sheet component in the current canvas coordinate system.
(define (draw-contact-sheet canvas
                            mountains flower pattern pixels
                            mountain-crop flower-crop)
  (draw-cell canvas mountains "mountains.jpg" 30 30)
  (draw-cell canvas flower "flower.png" 320 30)
  (draw-cell canvas pattern "pattern.webp" 610 30)
  (draw-cell canvas pixels "pixel-art.png" 30 320
             #:sampling 'nearest)
  (draw-cell canvas mountain-crop "mountain crop" 320 320)
  (draw-cell canvas flower-crop "flower crop" 610 320))

; save-contact-sheet : path-string? -> void?
;;   Renders the contact sheet example to the selected output destination.
(define (save-contact-sheet filename)
  (define mountains (image-from-file (fixture "mountains.jpg")))
  (define flower (image-from-file (fixture "flower.png")))
  (define pattern (image-from-file (fixture "pattern.webp")))
  (define pixels (image-from-file (fixture "pixel-art.png")))
  (define mountain-crop (image-subset mountains 120 45 150 135))
  (define flower-crop (image-subset flower 45 35 150 150))
  (define surface (make-surface width height
    #:background background-color))
  (draw-contact-sheet (surface-canvas surface)
                      mountains flower pattern pixels
                      mountain-crop flower-crop)
  (save-png surface filename #:exists 'replace))

;;;
;;; Command-Line Entry Point
;;;

(module+ main
  (save-contact-sheet "contact-sheet.png"))
