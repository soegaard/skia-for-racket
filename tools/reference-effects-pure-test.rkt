#lang racket/base

;;;
;;; Reference Effects Pure Test
;;;

;; Checks effect argument ranges, runtime-source validation, and graph options before native
;; allocation.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Public argument validation only. No native initialization, drawing, or GPU context.
(require rackunit racket/list skia)

;;;
;;; Effect Constructor Argument Checks
;;;

(module+ test
  (test-case "invalid runtime source and kind fail before compilation"
    (check-exn exn:fail? (lambda () (make-runtime-effect "")))
    (check-exn exn:fail? (lambda () (make-runtime-effect "bad\u0000source")))
    (check-exn exn:fail? (lambda () (make-runtime-effect "x" #:kind 'vertex))))
  (test-case "invalid finite blend modes and the color-filter identity exception"
    (check-exn exn:fail? (lambda () (make-blend-mode-blender 'unsupported)))
    (check-exn exn:fail? (lambda () (make-blend-color-filter 'red 'dst))))
  (test-case "table domains differ for mask and color filters"
    (check-exn exn:fail? (lambda () (make-table-mask-filter (make-list 256 0))))
    (check-exn exn:fail? (lambda () (make-table-color-filter (make-bytes 255))))
    (check-exn exn:fail? (lambda () (make-clip-mask-filter 128 128)))
    (check-exn exn:fail? (lambda () (make-hsla-matrix-filter '(1 0 0)))))
  (test-case "invalid path effects include non-obvious no-op cases"
    (check-exn exn:fail? (lambda () (make-dash-path-effect '(0 0))))
    (check-exn exn:fail? (lambda () (make-dash-path-effect '(2 3 4))))
    (check-exn exn:fail? (lambda () (make-discrete-path-effect 1/4096 1)))
    (check-exn exn:fail? (lambda () (make-trim-path-effect 0 1))))
  (test-case "graph options reject unsupported sampling and tiling"
    (check-exn exn:fail? (lambda () (make-blur-image-filter 1 1 #:tile-mode 'mirror)))
    (check-exn exn:fail?
               (lambda () (make-matrix-convolution-image-filter 1 1 '(1)
                                                                #:tile-mode 'clamp)))
    (check-exn exn:fail?
               (lambda () (make-matrix-transform-image-filter (matrix-scale 0))))
    (check-exn exn:fail? (lambda () (make-merge-image-filter '()))))
  (test-case "noise arguments are bounded before native allocation"
    (check-exn exn:fail? (lambda () (make-fractal-noise-shader -1 0.1 2)))
    (check-exn exn:fail? (lambda () (make-turbulence-shader 0.1 0.1 256)))
    (check-exn exn:fail?
               (lambda () (make-turbulence-shader 0.1 0.1 2 #:tile-size '(0 8))))))
