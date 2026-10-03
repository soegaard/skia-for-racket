#lang racket/base
;; A fresh process is required for each order: native dynamic-library binding
;; cannot be meaningfully reset inside a shared Racket namespace.
;; Keep draw/GUI/DC modules out of the static imports, so the requested order
;; is established before either renderer executes a text call.
(require racket/class racket/cmdline racket/runtime-path json)
(define-runtime-path dc-module "../dc.rkt")
(define sample "Skia and Racket office 123")
(define (ensure value message)
  (unless value (error 'canvas-text-load-order message)))
(define (has-ink? bytes red-offset)
  (for/or ([i (in-range red-offset (bytes-length bytes) 4)]) (< (bytes-ref bytes i) 240)))
(define (check-skia-text!)
  (define skia-dc% (dynamic-require dc-module 'skia-dc%))
  (define make-font (dynamic-require 'racket/draw 'make-font))
  (define dc (new skia-dc% [width 300] [height 56]))
  (dynamic-wind
   void
   (lambda ()
     (send dc clear)
     (send dc set-font (make-font #:size 16 #:family 'swiss))
     (send dc set-text-foreground "black")
     (define-values (width height _descent _leading) (send dc get-text-extent sample #f #t))
     (ensure (and (> width 0) (> height 0)) "Skia text has empty metrics")
     (send dc draw-text sample 4 4 #t)
     (ensure (has-ink? (send dc get-rgba-bytes #:premultiplied? #t) 0)
             "Skia text produced no raster ink"))
   (lambda () (send dc close))))
(define (check-racket-text!)
  (define make-bitmap (dynamic-require 'racket/draw 'make-bitmap))
  (define bitmap-dc% (dynamic-require 'racket/draw 'bitmap-dc%))
  (define make-font (dynamic-require 'racket/draw 'make-font))
  (define bitmap (make-bitmap 300 56 #t))
  (define dc (new bitmap-dc% [bitmap bitmap]))
  (dynamic-wind
   void
   (lambda ()
     (send dc set-background "white") (send dc clear)
     (send dc set-font (make-font #:size 16 #:family 'swiss))
     (send dc set-text-foreground "black")
     (define-values (width height _descent _leading) (send dc get-text-extent sample #f #t))
     (ensure (and (> width 0) (> height 0)) "Racket/Pango text has empty metrics")
     (send dc draw-text sample 4 4 #t))
   (lambda () (send dc set-bitmap #f)))
  (define argb (make-bytes (* 4 300 56)))
  (send bitmap get-argb-pixels 0 0 300 56 argb #f #t)
  (ensure (has-ink? argb 1) "Racket/Pango text produced no raster ink"))
(module+ main
  (define order
    (command-line #:program "canvas-text-load-order"
                  #:args (order) order))
  (ensure (member order '("gtk-first" "skia-first")) "expected gtk-first or skia-first")
  (cond
    [(equal? order "gtk-first")
     (dynamic-require 'racket/gui/base #f)
     (check-skia-text!)]
    [else
     (check-skia-text!)
     (dynamic-require 'racket/gui/base #f)])
  ;; Repeated Skia and ordinary Racket text must both work after both library
  ;; families have loaded. Pixel ink is checked without font-identity or
  ;; cross-renderer glyph-shape equality assumptions.
  (check-racket-text!)
  (check-skia-text!)
  (check-racket-text!)
  (display "canvas-text-load-order: ")
  (write-json (hasheq 'status "passed" 'load_order order
                     'skia_text_checks 2 'racket_text_checks 2 'gui_initialized #t))
  (newline))
