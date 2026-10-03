#lang racket/base
;; The only production renderer for skia/dc: existing CPU Skia operations.
;; There is no Cairo rendering adapter and no GPU or GUI initialization.
(require (prefix-in sk: "../main.rkt") "dc-support.rkt" "dc-bitmap.rkt"
         "dc-geometry.rkt" "dc-native-util.rkt" "dc-text.rkt")
(provide skia-dc-renderer)
(define (draw! surface command)
  (define c (sk:surface-canvas surface))
  (define ink (dc-draw-ink command))
  (sk:call-with-canvas-state c
    (lambda ()
      (install-clip! c (dc-draw-clip command))
      (set-matrix! c (dc-draw-matrix command))
      (call-with-path (dc-draw-commands command) (dc-draw-rule command)
        (lambda (p)
          (sk:with-skia ([paint (sk:make-paint #:color (native-color (dc-ink-rgba ink))
                                             #:style (if (dc-ink-stroke? ink) 'stroke 'fill)
                                             #:stroke-width (dc-ink-width ink)
                                             #:antialias? (dc-draw-antialias? command))])
            (sk:paint-set-cap! paint (dc-ink-cap ink))
            (sk:paint-set-join! paint (dc-ink-join ink))
            ;; Racket/Cairo uses a miter limit of 10, not Skia's default of 4.
            (sk:paint-set-miter-limit! paint 10)
            (if (pair? (dc-ink-dashes ink))
                (sk:with-skia ([effect (sk:make-dash-path-effect (dc-ink-dashes ink))])
                  (sk:paint-set-path-effect! paint effect)
                  (sk:draw-path c p paint))
                (sk:draw-path c p paint))))))))
(define (clear! surface clip rgba erase?)
  (define c (sk:surface-canvas surface))
  (sk:call-with-canvas-state c
    (lambda ()
      (install-clip! c clip)
      (sk:with-skia ([paint (sk:make-paint #:color (native-color rgba)
                                         #:blend-mode (if erase? 'clear 'src-over)
                                         #:antialias? #f)])
        (sk:draw-paint c paint)))))
(define (bitmap! surface data rect matrix clip opacity sampling)
  (define c (sk:surface-canvas surface))
  (sk:with-skia ([image (sk:rgba-bytes->image
                        (dc-bitmap-data-width data) (dc-bitmap-data-height data)
                        (dc-bitmap-data-pixels data) #:premultiplied? #t)]
                [paint (sk:make-paint #:color (native-color (vector 255 255 255 opacity)))])
    (sk:call-with-canvas-state c
      (lambda ()
        (install-clip! c clip)
        (set-matrix! c matrix)
        (sk:draw-image-subrect c image
          (vector-ref rect 0) (vector-ref rect 1) (vector-ref rect 2) (vector-ref rect 3)
          (vector-ref rect 4) (vector-ref rect 5) (vector-ref rect 6) (vector-ref rect 7)
          #:sampling sampling #:paint paint))))
  (void))
(define (copy! surface matrix clip x y width height x2 y2)
  ;; Immutable native snapshot prevents overlap feedback. Both source and
  ;; destination are in the same DC coordinate system, hence their physical
  ;; displacement is the linear part of that system applied to (x2-x,y2-y).
  (define dest (dc-clip-points matrix x2 y2 width height))
  (define dx (dc-real 'copy (+ (* (vector-ref matrix 0) (- x2 x))
                              (* (vector-ref matrix 2) (- y2 y)))))
  (define dy (dc-real 'copy (+ (* (vector-ref matrix 1) (- x2 x))
                              (* (vector-ref matrix 3) (- y2 y)))))
  (define c (sk:surface-canvas surface))
  (sk:with-skia ([image (sk:surface-snapshot surface)]
                [shader (sk:make-image-shader image #:tile-x 'decal #:tile-y 'decal
                                               #:sampling 'nearest)]
                [paint (sk:make-paint #:shader shader #:blend-mode 'src #:antialias? #f)])
    (sk:call-with-canvas-state c
      (lambda ()
        (install-clip! c clip)
        (call-with-path dest 'winding (lambda (p) (sk:canvas-clip-path! c p #:antialias? #f)))
        (sk:canvas-translate! c dx dy)
        (sk:draw-paint c paint))))
  (void))
(define (composite! parent child clip opacity)
  ;; The completed child is sampled in physical coordinates. The current DC
  ;; transform and per-draw alpha must not be applied a second time.
  (define c (sk:surface-canvas parent))
  (sk:with-skia ([image (sk:surface-snapshot child)]
                [paint (sk:make-paint #:color (native-color (vector 255 255 255 opacity))
                                       #:blend-mode 'src-over #:antialias? #f)])
    (sk:call-with-canvas-state c
      (lambda ()
        (install-clip! c clip)
        (sk:draw-image c image 0 0 #:paint paint))))
  (void))
(define skia-dc-renderer
  (dc-renderer/alpha
   (lambda (w h) (sk:make-surface w h #:background 'transparent))
   sk:skia-close! draw! clear! sk:surface-snapshot
   (lambda (s p?) (sk:surface->rgba-bytes s #:premultiplied? p?))
   sk:surface->png-bytes
   dc-measure-text dc-render-text! dc-glyph-exists? bitmap! copy! composite!))
