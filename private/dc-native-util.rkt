#lang racket/base

;;;
;;; Drawing Context Native Helpers
;;;

;; Installs matrices and clips and scopes temporary native paths.
;; Shares the native setup needed by drawing-context rendering and queries.

;;;
;;; Imports and Exports
;;;

(require (prefix-in sk: "../main.rkt") "dc-support.rkt")
(provide native-color call-with-path set-matrix! install-clip!)

;;;
;;; Scoped Native Drawing State
;;;

; native-color : vector? -> rgba?
;;   Converts RGB-byte/unit-alpha DC colors to Skia colors with rounded byte alpha.
(define (native-color v)
  (sk:rgba (vector-ref v 0) (vector-ref v 1) (vector-ref v 2)
           (inexact->exact (round (* 255 (vector-ref v 3))))))

; call-with-path : (listof vector?) symbol? procedure? -> any
;;   Builds a temporary native path for a callback, translating the Racket odd-even fill rule and
;;   releasing the path afterward.
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

; set-matrix! : canvas? vector? -> void?
;;   Installs the six affine coefficients in Racket xx/yx/xy/yy/x0/y0 order on the native canvas.
(define (set-matrix! c m)
  (sk:canvas-set-matrix3! c
    (sk:make-matrix3 (vector-ref m 0) (vector-ref m 2) (vector-ref m 4)
                     (vector-ref m 1) (vector-ref m 3) (vector-ref m 5) 0 0 1)))

; install-clip! : canvas? (or/c #f dc-clip?) -> void?
;;   Resets the transform and intersects device-coordinate clip paths; #f adds no clip, while an empty
;;   clip excludes everything.
(define (install-clip! c clip)
  (sk:canvas-reset-transform! c)
  (when clip
    (if (null? (dc-clip-paths clip))
        (sk:canvas-clip-rect! c 0 0 0 0)
        (for ([part (in-list (dc-clip-paths clip))])
          (call-with-path (dc-clip-path-commands part) (dc-clip-path-rule part)
            (lambda (p) (sk:canvas-clip-path! c p #:antialias? #f)))))))
