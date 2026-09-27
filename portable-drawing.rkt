#lang racket/base
(require racket/list racket/vector
         "color.rkt" "private/core.rkt" "private/check.rkt"
         "private/geometry-util.rkt" "private/portable-util.rkt"
         "geometry-primitives.rkt" "matrix.rkt" "private/path-matrix.rkt")
(provide draw-markers
         image-grid-cell? image-grid-cell-row image-grid-cell-column
         image-grid-cell-kind image-grid-cell-source image-grid-cell-destination
         image-grid-cell-color image-nine-plan image-lattice-plan image-grid-plan->jsexpr
         draw-image-nine/portable draw-image-lattice/portable draw-atlas/portable)

;; Explicit lowering, before recording or serialization. Existing native batch
;; operations are unchanged. No raw SVG injection and no backend masquerading.
(define (draw-markers c points size paint #:shape [shape 'circle])
  (define who 'draw-markers)
  (define boxes (portable-marker-boxes who points size shape))
  (paint-color paint) ; validate a live, creator-thread paint, even for an empty batch
  (canvas-save-count c)
  ;; Paint style remains meaningful here. Marker size is geometry, not stroke
  ;; width, and markers overlap in input order rather than being path-unioned.
  (for ([b (in-list boxes)])
    (apply (if (eq? shape 'circle) draw-oval draw-rect)
           c (append (vector->list b) (list paint))))
  (void))

(define (image-lattice-plan image-width image-height lattice x y width height)
  (define who 'image-lattice-plan)
  (unless (image-lattice? lattice) (raise-argument-error who "image-lattice?" lattice))
  (portable-lattice-plan
   who image-width image-height
   (image-lattice-x-divisions lattice) (image-lattice-y-divisions lattice)
   (or (image-lattice-bounds lattice) (vector-immutable 0 0 image-width image-height))
   (image-lattice-cell-types lattice) (image-lattice-colors lattice)
   (list x y width height)))

(define (nonempty-box? b)
  (and (positive? (vector-ref b 2)) (positive? (vector-ref b 3))))
(define (visible-cell? cell)
  (and (not (eq? (image-grid-cell-kind cell) 'transparent))
       (nonempty-box? (image-grid-cell-source cell))
       (nonempty-box? (image-grid-cell-destination cell))))
(define (checked-image-canvas c im)
  (image-color-type im) ; validate lifetime/thread even if the plan paints nothing
  (canvas-save-count c))

(define (call-with-slices im boxes proc)
  ;; Reuse a native subset for repeated source rectangles (not one newly
  ;; encoded image per atlas occurrence). No input pixels are resampled here.
  (define table (make-hash))
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       void
       (lambda ()
         (for ([box (in-list boxes)])
           (unless (hash-has-key? table box)
             ;; Do not allow a break between resource creation and registration.
             (parameterize-break #f
               (define part (apply image-subset im (vector->list box)))
               (hash-set! table box part))))
         (proc table))
       (lambda () (for ([part (in-hash-values table)]) (skia-close! part)))))))

(define (color-with-alpha color alpha)
  (define v (color->rgba color))
  (rgba (rgba-red v) (rgba-green v) (rgba-blue v)
        (quotient (+ (* (rgba-alpha v) alpha) 127) 255)))

(define (draw-grid c im plan filter alpha)
  (checked-image-canvas c im)
  (define cells (filter-visible plan))
  (call-with-slices
   im (for/list ([cell (in-list cells)] #:when (eq? (image-grid-cell-kind cell) 'default))
        (image-grid-cell-source cell))
   (lambda (slices)
     (with-skia ([image-paint (make-paint #:color (rgba 0 0 0 alpha) #:antialias? #f)]
                 [color-paint (make-paint #:antialias? #f)])
       (for ([cell (in-list cells)])
         (define b (image-grid-cell-destination cell))
         (cond
           [(eq? (image-grid-cell-kind cell) 'default)
            (draw-image-rect c (hash-ref slices (image-grid-cell-source cell))
                             (vector-ref b 0) (vector-ref b 1) (vector-ref b 2) (vector-ref b 3)
                             #:sampling filter #:paint image-paint)]
           [else
            (paint-set-color! color-paint (color-with-alpha (image-grid-cell-color cell) alpha))
            (apply draw-rect c (append (vector->list b) (list color-paint)))])))))
  (void))
(define (filter-visible plan) (filter visible-cell? plan))

(define (draw-image-nine/portable c im center x y width height
                                  #:sampling [filter 'linear] #:alpha [alpha 255])
  (portable-filter 'draw-image-nine/portable filter)
  (portable-alpha 'draw-image-nine/portable alpha)
  (define plan (image-nine-plan (image-width im) (image-height im) center x y width height))
  (draw-grid c im plan filter alpha))
(define (draw-image-lattice/portable c im lattice x y width height
                                     #:sampling [filter 'linear] #:alpha [alpha 255])
  (portable-filter 'draw-image-lattice/portable filter)
  (portable-alpha 'draw-image-lattice/portable alpha)
  (define plan (image-lattice-plan (image-width im) (image-height im) lattice x y width height))
  (draw-grid c im plan filter alpha))

(define (draw-atlas/portable c im transforms sources
                             #:sampling [filter 'linear] #:alpha [alpha 255])
  (define who 'draw-atlas/portable)
  (portable-filter who filter)
  (portable-alpha who alpha)
  (define ts (geometry-list who transforms))
  (define bs (geometry-list who sources))
  (define n (length ts))
  (geometry-budget who n (* n 48))
  (unless (= n (length bs))
    (raise-arguments-error who "sprite transform/source counts must match"
                           "transforms" n "sources" (length bs)))
  (define boxes
    (for/list ([box (in-list bs)])
      ;; Integer crops avoid silently rounding a fractional atlas region or
      ;; bleeding a neighbor's texels into the exported standalone crop.
      (geometry-source-bounds who (geometry-irect who box) (image-width im) (image-height im))))
  (define matrices
    (for/list ([t (in-list ts)])
      (unless (atlas-transform? t) (raise-argument-error who "atlas-transform?" t))
      (define v (atlas-transform-coefficients t))
      (define sc (vector-ref v 0)) (define ss (vector-ref v 1))
      (make-matrix sc ss (- ss) sc (vector-ref v 2) (vector-ref v 3))))
  (checked-image-canvas c im)
  (call-with-slices
   im boxes
   (lambda (slices)
     (with-skia ([paint (make-paint #:color (rgba 0 0 0 alpha))])
       (for ([box (in-list boxes)] [m (in-list matrices)])
         (unless (and (zero? (matrix-xx m)) (zero? (matrix-yx m)))
           (with-canvas-state c
             (canvas-concat! c m)
             (draw-image-rect c (hash-ref slices box) 0 0 (vector-ref box 2) (vector-ref box 3)
                              #:sampling filter #:paint paint)))))))
  (void))
