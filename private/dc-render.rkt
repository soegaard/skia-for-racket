#lang racket/base
;; The only production renderer for skia/dc: existing CPU Skia operations.
;; There is no Cairo rendering adapter and no GPU or GUI initialization.
(require (prefix-in sk: "../main.rkt") "dc-support.rkt")
(provide skia-dc-renderer)
(define (native-color v)
  (sk:rgba (vector-ref v 0) (vector-ref v 1) (vector-ref v 2)
           (inexact->exact (round (* 255 (vector-ref v 3))))))
(define (call-with-path commands rule proc)
  (sk:with-skia ([p (sk:make-path #:fill-rule (if (eq? rule 'odd-even) 'even-odd 'winding))])
    (for ([v (in-list commands)])
      (case (vector-ref v 0)
        [(move) (sk:path-move-to! p (vector-ref v 1) (vector-ref v 2))]
        [(line) (sk:path-line-to! p (vector-ref v 1) (vector-ref v 2))]
        [(cubic) (sk:path-cubic-to! p (vector-ref v 1) (vector-ref v 2)
                                   (vector-ref v 3) (vector-ref v 4)
                                   (vector-ref v 5) (vector-ref v 6))]
        [(close) (sk:path-close! p)]
        [else (error 'skia-dc% "invalid internal path command")]))
    (proc p)))
(define (set-matrix! c m)
  (sk:canvas-set-matrix3! c
    (sk:make-matrix3 (vector-ref m 0) (vector-ref m 2) (vector-ref m 4)
                     (vector-ref m 1) (vector-ref m 3) (vector-ref m 5)
                     0 0 1)))
(define (install-clip! c clip)
  (sk:canvas-reset-transform! c)
  (when clip
    (call-with-path clip 'winding
      (lambda (p) (sk:canvas-clip-path! c p #:antialias? #f)))))
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
(define skia-dc-renderer
  (dc-renderer
   (lambda (w h) (sk:make-surface w h #:background 'transparent))
   sk:skia-close! draw! clear! sk:surface-snapshot
   (lambda (s p?) (sk:surface->rgba-bytes s #:premultiplied? p?))
   sk:surface->png-bytes))
