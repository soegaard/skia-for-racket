#lang racket/base

;;;
;;; Racket Draw Example
;;;

;; Exercises bitmap interoperability using only the package's public modules.
;; This is an example-suite client of the project's drawing APIs, not library implementation.


;; Public APIs only. Run after installing the pinned Skia library.
;;;
;;; Imports and Exports
;;;

(require racket/class racket/list
         (prefix-in draw: racket/draw)
         "../../main.rkt" "../../racket-draw.rkt")

;;;
;;; Command-Line Entry Point
;;;

(module+ main
  ;; A Draw bitmap becomes a detached CPU image. `#:mask #f` deliberately
  ;; ignores any loaded mask so this demonstration copies literal pixels.
  ; bitmap : (is-a?/c bitmap%)
  ;;   Retains the Racket bitmap used by the interoperability example.
  (define bitmap (draw:make-bitmap 20 10 #t))
  (send bitmap set-argb-pixels 0 0 20 10
        (apply bytes (make-list (* 4 20 10) 255)) #f #t)
  (with-skia ([image (bitmap->image bitmap #:mask #f)]
              [surface (make-surface 40 20 #:background 'white)]
              [paint (make-paint #:antialias? #f)])
    (draw-image (surface-canvas surface) image 10 5 #:paint paint)
    (unless (is-a? (image->bitmap image) draw:bitmap%)
      (error 'racket-draw-example "image export did not make a bitmap")))

  ;; Color copies do not share a mutable color object.
  ; copied-color : rgba?
  ;;   Specifies the copied color color used by this drawing.
  (define copied-color (color%->rgba (make-object draw:color% 10 20 30 0.5)))
  ; mutable-color : (is-a?/c color%)
  ;;   Retains the independent mutable Racket Draw color created from RGBA data.
  (define mutable-color (rgba->color% copied-color))
  (send mutable-color set 200 100 50 0.25)
  (unless (equal? copied-color (rgba 10 20 30 128))
    (error 'racket-draw-example "color copy was changed by Draw mutation"))

  ;; A path round trip returns geometry and the Draw fill style separately.
  ; source-path : (is-a?/c draw:dc-path%)
  ;;   Builds the Racket Draw path used to demonstrate copied Skia path conversion.
  (define source-path (new draw:dc-path%))
  (send source-path rectangle 2 2 12 8)
  (with-skia ([path (dc-path->skia-path source-path #:fill-style 'winding)])
    (define-values (copied-path fill-style) (skia-path->dc-path path))
    (unless (and (is-a? copied-path draw:dc-path%) (eq? fill-style 'winding))
      (error 'racket-draw-example "path round trip changed its fill style")))

  ;; Rational conics need an explicit bounded vector approximation.
  (with-skia ([conic (make-path '((move 0 0) (conic 10 20 20 0 0.5)))])
    (define-values (_path _style)
      (skia-path->dc-path conic #:conic-subdivisions 2))
    (void))
  (displayln "public-racket-draw-example: passed"))
