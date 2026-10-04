#lang racket/base
;; Shared native Skia drawing operations. The default renderer stays CPU-only;
;; the private factory also accepts explicitly supplied same-context GPU storage.
;; Merely requiring this module initializes neither GPU nor GUI facilities.
(require (prefix-in sk: "../main.rkt") "dc-support.rkt" "dc-bitmap.rkt"
         "dc-geometry.rkt" "dc-native-util.rkt" "dc-text.rkt"
         "dc-style-render.rkt" "dc-path-bounds.rkt")
(provide skia-dc-renderer make-surface-dc-renderer)
;; Private canvas entry points let document recording reuse native geometry
;; and bitmap handling. Existing surface callbacks and GPU copies are unchanged.
(module* canvas-internals #f
  (provide draw-on-canvas! bitmap-on-canvas!))
(define (draw! surface command)
  (draw-on-canvas! (sk:surface-canvas surface) command))
(define (draw-on-canvas! c command)
  (define ink (dc-draw-ink command))
  (sk:call-with-canvas-state c
    (lambda ()
      (install-clip! c (dc-draw-clip command))
      (set-matrix! c (dc-draw-matrix command))
      (call-with-path (dc-draw-commands command) (dc-draw-rule command)
        (lambda (p)
          (call-with-dc-paint ink (dc-draw-antialias? command)
            (lambda (paint) (sk:draw-path c p paint))))))))
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
  (bitmap-on-canvas! (sk:surface-canvas surface) data rect matrix clip opacity sampling))
(define (bitmap-on-canvas! c data rect matrix clip opacity sampling)
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
(define (copy! snapshot surface matrix clip x y width height x2 y2)
  ;; Immutable native snapshot prevents overlap feedback. Both source and
  ;; destination are in the same DC coordinate system, hence their physical
  ;; displacement is the linear part of that system applied to (x2-x,y2-y).
  (define dest (dc-clip-points matrix x2 y2 width height))
  (define dx (dc-real 'copy (+ (* (vector-ref matrix 0) (- x2 x))
                              (* (vector-ref matrix 2) (- y2 y)))))
  (define dy (dc-real 'copy (+ (* (vector-ref matrix 1) (- x2 x))
                              (* (vector-ref matrix 3) (- y2 y)))))
  (define c (sk:surface-canvas surface))
  (sk:with-skia ([image (snapshot surface)]
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
(define (composite! snapshot parent child clip opacity)
  ;; The completed child is sampled in physical coordinates. The current DC
  ;; transform and per-draw alpha must not be applied a second time.
  (define c (sk:surface-canvas parent))
  (sk:with-skia ([image (snapshot child)]
                [paint (sk:make-paint #:color (native-color (vector 255 255 255 opacity))
                                       #:blend-mode 'src-over #:antialias? #f)])
    (sk:call-with-canvas-state c
      (lambda ()
        (install-clip! c clip)
        (sk:draw-image c image 0 0 #:paint paint))))
  (void))
(define (make-surface-dc-renderer create close snapshot rgba png
                                  #:internal-snapshot [internal-snapshot snapshot])
  ;; Internal copies and alpha composition must retain native residency.
  ;; The public snapshot callback may instead perform an explicit CPU transfer.
  (dc-renderer/styles
   create close draw! clear! snapshot rgba png
   dc-measure-text dc-render-text! dc-glyph-exists? bitmap!
   (lambda args (apply copy! internal-snapshot args))
   (lambda args (apply composite! internal-snapshot args))
   dc-path-ink-bounds))
(define skia-dc-renderer
  (make-surface-dc-renderer
   (lambda (w h) (sk:make-surface w h #:background 'transparent))
   sk:skia-close! sk:surface-snapshot
   (lambda (s p?) (sk:surface->rgba-bytes s #:premultiplied? p?))
   sk:surface->png-bytes))
