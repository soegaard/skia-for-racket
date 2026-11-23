#lang racket/base

;;;
;;; Shader Local Transforms
;;;

;; Converts optional affine transforms for shader constructors.
;; Keeps the byte-color, floating-point, and image shader interfaces consistent.

(require "types.rkt" "../matrix.rkt")
(provide shader-local-matrix)

; shader-local-matrix : symbol? (or/c #f matrix?) -> (or/c #f sk-matrix?)
;   Copies an optional affine transform into the native shader matrix layout.
(define (shader-local-matrix who matrix)
  (cond
    [(not matrix) #f]
    [(matrix? matrix)
     (make-sk-matrix (matrix-xx matrix) (matrix-xy matrix) (matrix-x0 matrix)
                     (matrix-yx matrix) (matrix-yy matrix) (matrix-y0 matrix)
                     0.0 0.0 1.0)]
    [else (raise-argument-error who "(or/c #f matrix?)" matrix)]))
