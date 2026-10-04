#lang racket/base
;; Shared test/example authoring. All callbacks use dc<%>, not raw Skia
;; canvases, screenshots of GUI widgets, or a replacement pict/plot renderer.
(require racket/class racket/list
         (prefix-in rd: racket/draw)
         "../dc.rkt" "../dc-output.rkt" "dc-consumer-fixtures.rkt"
         (prefix-in styles: "dc-style-fixtures.rkt"))
(provide draw-output-vector-scene draw-output-mixed-scene draw-output-style-scene
         make-output-consumers output-label output-fill)
(define (output-fill dc color x y w h)
  (send dc set-pen "black" 1 'transparent)
  (send dc set-brush color 'solid)
  (send dc draw-rectangle x y w h))
(define (output-label dc [text "SkiaDC063"] [x 8] [y 44])
  (send dc set-font (rd:make-font #:family 'swiss #:size 12 #:size-in-pixels? #t))
  (send dc set-text-foreground "black")
  (send dc draw-text text x y #t))
(define (draw-output-vector-scene dc)
  (send dc set-background "white") (send dc clear)
  (output-fill dc "red" 8 8 24 18)
  (send dc set-brush "blue" 'solid) (send dc draw-ellipse 56 8 28 18)
  (send dc set-clipping-rect 104 8 16 16)
  (output-fill dc (make-object rd:color% 0 255 0) 100 4 40 40)
  (send dc set-clipping-region #f)
  (output-label dc)
  (define gradient
    (new rd:linear-gradient% [x0 8] [y0 80] [x1 56] [y1 80]
         [stops (list (list 0 (make-object rd:color% 255 0 0))
                      (list 1 (make-object rd:color% 0 0 255)))]))
  (send dc set-brush (rd:make-brush #:gradient gradient))
  (send dc draw-rectangle 8 80 48 16)
  (send dc set-origin 100 82)
  (output-fill dc "purple" 0 0 16 12)
  (send dc set-origin 0 0)
  (hash))
(define (draw-output-mixed-scene dc [raster-callback void])
  (send dc set-background "white") (send dc clear)
  (output-fill dc "red" 8 8 24 18)
  (output-fill dc (make-object rd:color% 0 255 0) 130 8 16 16)
  (output-label dc)
  (send dc start-alpha 0.5)
  (output-fill dc "red" 8 68 40 24)
  (output-fill dc "blue" 28 68 40 24)
  (send dc end-alpha)
  (draw-dc-raster-group dc 100 70 64 32
    (lambda (r)
      (raster-callback r)
      (output-fill r "red" 0 0 16 24)
      (output-fill r "blue" 16 0 16 24)
      ;; Include the source/backdrop INSIDE the isolated group. This does not
      ;; copy pixels already emitted elsewhere on the document page.
      (send r copy 0 0 32 24 8 0))
    #:scale 2 #:label "copy-island-64x32")
  (hash))
(define (draw-output-style-scene dc)
  (styles:style-oracle dc)
  (hash))
(define (make-output-consumers)
  (define metric-dc (new skia-dc% [width 320] [height 240] [smoothing 'smoothed]))
  (define picture
    (dynamic-wind void (lambda () (make-consumer-pict metric-dc))
                  (lambda () (send metric-dc close))))
  (define pict-draw (lambda (dc) (draw-consumer-pict dc picture) (hash)))
  (append*
   (for/list ([entry (in-list (list (cons "pict" pict-draw) (cons "plot" draw-consumer-plot)))])
     (define-values (procedure datum layout) (record-consumer (cdr entry)))
     (list (list (car entry) "direct" (cdr entry))
           (list (car entry) "procedure" (lambda (dc) (procedure dc) layout))
           (list (car entry) "datum" (lambda (dc) (datum dc) layout))))))
