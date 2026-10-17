#lang racket/base

;;;
;;; Floating-Point Paints and Shaders
;;;

;; Uses extended-range color values in paints, canvas fills, and gradient shaders.
;; This public drawing layer connects detached Color4f values and explicit source color spaces to
;; native floating-point color operations.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe racket/list racket/match racket/vector
         "color4f.rkt" (submod "color4f.rkt" internals)
         "private/core.rkt" "private/check.rkt" "private/native.rkt" "private/types.rkt"
         "private/lifetime.rkt" "private/float-color-native.rkt"
         "matrix.rkt" (only-in (submod "image-info.rkt" internals) copy-descriptor)
         (submod "private/core.rkt" float-color-internals))
(provide make-paint/color4f paint-color4f paint-set-color4f!
         canvas-clear-color4f! draw-color4f
         make-color4f-shader make-linear-gradient-color4f-shader
         make-radial-gradient-color4f-shader make-sweep-gradient-color4f-shader
         make-two-point-conical-gradient-color4f-shader)

;;;
;;; Floating-Point Paint Colors
;;;

; paint-color4f : paint? -> color4f?
;   Returns the paint's stored unpremultiplied extended-sRGB color as a detached value.
(define (paint-color4f paint)
  (define who 'paint-color4f)
  (define out (make-sk-color4f 0.0 0.0 0.0 0.0))
  (call-with-owned who (list (paint-h who paint))
    (lambda (p) (sk_paint_get_color4f p out)))
  ;; SkPaint stores extended sRGB, regardless of the setter's source space.
  (native->color4f out))

; paint-set-color4f! : paint? color4f? #:color-space (or/c 'srgb 'linear-srgb bytes?) -> void?
;   Sets the paint's color after interpreting it in the explicitly supplied source space.
(define (paint-set-color4f! paint color #:color-space space)
  (define who 'paint-set-color4f!)
  (define native (color4f-native who color))
  (define h (paint-h who paint))
  (call-with-owned who (list h) (lambda (_) (void)))
  (call-with-float-source-space who space
    (lambda (cp)
      (call-with-owned who (list h)
        (lambda (pp) (sk_paint_set_color4f pp native cp)))))
  (void))

; make-paint/color4f : color4f? #:color-space (or/c 'srgb 'linear-srgb bytes?) [#:style (or/c 'fill
;   'stroke 'stroke-and-fill)] [#:stroke-width (and/c real? (>=/c 0))] [#:antialias? boolean?] ->
;   paint?
;   Returns an owned mutable paint with the specified color, its source interpretation, and the
;   displayed drawing settings.
(define (make-paint/color4f color #:color-space space
                           #:style [style 'fill] #:stroke-width [width 1]
                           #:antialias? [antialias? #t])
  (define who 'make-paint/color4f)
  (checked-color4f who color)
  ;; Pure argument checks precede either paint or color-space native allocation.
  (choice who style style-values) (nonnegative-scalar who width) (boolean who antialias?)
  (when (not space) (error who "an explicit source color-space descriptor is required"))
  (define descriptor (copy-descriptor who space))
  (define p (make-paint #:style style #:stroke-width width #:antialias? antialias?))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! p) (raise e))])
    (paint-set-color4f! p color #:color-space descriptor)
    p))

;;;
;;; Solid-Color Drawing and Shaders
;;;

; canvas-clear-color4f! : canvas? color4f? -> void?
;   Fills the current clip with the supplied unpremultiplied color using source replacement.
(define (canvas-clear-color4f! canvas color)
  (define native (color4f-native 'canvas-clear-color4f! color))
  (call-on-canvas 'canvas-clear-color4f! canvas '()
    (lambda (cp) (sk_canvas_clear_color4f cp native))))

; draw-color4f : canvas? color4f? [#:blend-mode (or/c 'clear 'src 'dst 'src-over 'dst-over 'src-in
;   'dst-in 'src-out 'dst-out 'src-atop 'dst-atop 'xor 'plus 'modulate 'screen 'overlay 'darken
;   'lighten 'color-dodge 'color-burn 'hard-light 'soft-light 'difference 'exclusion 'multiply 'hue
;   'saturation 'color 'luminosity)] -> void?
;   Fills the current clip with the extended-sRGB color, combined with the destination using the
;   selected blend mode.
(define (draw-color4f canvas color #:blend-mode [mode 'src-over])
  (define who 'draw-color4f)
  (define native (color4f-native who color))
  (define blend (choice who mode blend-values))
  (call-on-canvas who canvas '() (lambda (cp) (sk_canvas_draw_color4f cp native blend))))

; make-color4f-shader : color4f? #:color-space (or/c 'srgb 'linear-srgb bytes?) -> shader?
;   Returns an owned constant-color shader with the explicit source interpretation.
(define (make-color4f-shader color #:color-space space)
  (define who 'make-color4f-shader)
  (define native (color4f-native who color))
  (call-with-float-source-space who space
    (lambda (cp) (new-shader who (lambda () (sk_shader_new_color4f native cp))))))

;;;
;;; Gradient Geometry and Color Preparation
;;;

; point : symbol? (or/c list? vector?) -> sk-point?
;   Validates an x/y pair and converts it to a native point.
(define (point who value)
  (match value
    [(list x y) (make-sk-point (scalar who x) (scalar who y))]
    [(vector x y) (make-sk-point (scalar who x) (scalar who y))]
    [_ (raise-argument-error who "(list x y) or #(x y)" value)]))

; local-matrix : symbol? (or/c #f matrix?) -> (or/c #f sk-matrix?)
;   Converts an optional affine local transform to Skia's 3-by-3 layout.
(define (local-matrix who matrix)
  (cond
    [(not matrix) #f]
    [(matrix? matrix)
     (make-sk-matrix (matrix-xx matrix) (matrix-xy matrix) (matrix-x0 matrix)
                     (matrix-yx matrix) (matrix-yy matrix) (matrix-y0 matrix) 0.0 0.0 1.0)]
    [else (raise-argument-error who "#f or affine matrix?" matrix)]))

; sequence : symbol? (or/c list? vector?) -> list?
;   Normalizes gradient input sequences while preserving their order.
(define (sequence who value)
  (cond [(vector? value) (vector->list value)] [(list? value) value]
        [else (raise-argument-error who "list or vector" value)]))

; with-gradient : symbol? any/c any/c symbol? (or/c #f matrix?) any/c procedure? -> shader?
;   Validates gradient colors and strictly increasing float32 stops, retaining native buffers
;   through construction.
(define (with-gradient who colors stops tile matrix space build)
  (define xs (sequence who colors))
  (define n (length xs))
  (unless (and (<= 2 n #x7fffffff) (<= (* n 64) (current-skia-byte-limit)))
    (error who "gradient needs at least two colors and must fit the byte/count limits"))
  (for ([c (in-list xs)]) (checked-color4f who c))
  (define positions
    (and stops
         (for/list ([v (in-list (sequence who stops))])
           (define t (scalar who v))
           (unless (<= 0 t 1) (error who "gradient stops must lie in [0,1]"))
           ;; Validate ordering AFTER conversion to C float; do not accept
           ;; distinct doubles that collapse to one stop at the native boundary.
           (floating-point-bytes->real (real->floating-point-bytes t 4 #f) #f))))
  (when positions
    (unless (= (length positions) n) (error who "color/stop counts differ"))
    (for ([a (in-list positions)] [b (in-list (cdr positions))])
      (unless (< a b) (error who "stops must increase strictly at float32 precision"))))
  (define mode (choice who tile tile-mode-values))
  (define lm (local-matrix who matrix))
  (call-with-float-source-space who space
    (lambda (cp)
      (define cs (malloc (* n 4) _float 'atomic))
      (for ([color (in-list xs)] [i (in-naturals)])
        (for ([v (in-vector (color4f->vector color))] [j (in-naturals)])
          (ptr-set! cs _float (+ (* i 4) j) v)))
      (define ps (and positions (malloc n _float 'atomic)))
      (when ps (for ([v (in-list positions)] [i (in-naturals)]) (ptr-set! ps _float i v)))
      (begin0 (new-shader who (lambda () (build cs cp ps n mode lm)))
        (void/reference-sink cs ps lm xs positions)))))

;;;
;;; Gradient Shader Factories
;;;

; make-linear-gradient-color4f-shader : (or/c (list/c real? real?) (vector/c real? real?)) (or/c
;   (list/c real? real?) (vector/c real? real?)) (or/c (listof color4f?) (vectorof color4f?))
;   #:color-space (or/c 'srgb 'linear-srgb bytes?) [#:stops (or/c #f (listof real?) (vectorof
;   real?))] [#:tile-mode (or/c 'clamp 'repeat 'mirror 'decal)] [#:matrix (or/c matrix? #f)] ->
;   shader?
;   Returns a linear gradient from start to end.
(define (make-linear-gradient-color4f-shader start end colors #:color-space space
                                            #:stops [stops #f] #:tile-mode [tile 'clamp]
                                            #:matrix [matrix #f])
  (define who 'make-linear-gradient-color4f-shader)
  (define a (point who start)) (define b (point who end))
  (when (and (= (sk-point-x a) (sk-point-x b)) (= (sk-point-y a) (sk-point-y b)))
    (error who "linear gradient endpoints must differ"))
  (define points (malloc 4 _float 'atomic))
  (for ([v (in-list (list (sk-point-x a) (sk-point-y a) (sk-point-x b) (sk-point-y b)))]
        [i (in-naturals)])
    (ptr-set! points _float i v))
  (begin0
    (with-gradient who colors stops tile matrix space
      (lambda (cs cp ps n mode lm) (sk_shader_new_linear_gradient_color4f points cs cp ps n mode lm)))
    (void/reference-sink points)))

; make-radial-gradient-color4f-shader : (or/c (list/c real? real?) (vector/c real? real?)) (and/c
;   real? (>/c 0)) (or/c (listof color4f?) (vectorof color4f?)) #:color-space (or/c 'srgb
;   'linear-srgb bytes?) [#:stops (or/c #f (listof real?) (vectorof real?))] [#:tile-mode (or/c
;   'clamp 'repeat 'mirror 'decal)] [#:matrix (or/c matrix? #f)] -> shader?
;   Returns a radial gradient from center outward to radius.
(define (make-radial-gradient-color4f-shader center radius colors #:color-space space
                                            #:stops [stops #f] #:tile-mode [tile 'clamp]
                                            #:matrix [matrix #f])
  (define who 'make-radial-gradient-color4f-shader)
  (define c (point who center)) (define r (positive-scalar who radius))
  (with-gradient who colors stops tile matrix space
    (lambda (cs cp ps n mode lm) (sk_shader_new_radial_gradient_color4f c r cs cp ps n mode lm))))

; make-sweep-gradient-color4f-shader : (or/c (list/c real? real?) (vector/c real? real?)) (or/c
;   (listof color4f?) (vectorof color4f?)) #:color-space (or/c 'srgb 'linear-srgb bytes?)
;   [#:start-angle real?] [#:end-angle real?] [#:stops (or/c #f (listof real?) (vectorof real?))]
;   [#:tile-mode (or/c 'clamp 'repeat 'mirror 'decal)] [#:matrix (or/c matrix? #f)] -> shader?
;   Returns an angular gradient around center.
(define (make-sweep-gradient-color4f-shader center colors #:color-space space
                                           #:start-angle [start 0] #:end-angle [end 360]
                                           #:stops [stops #f] #:tile-mode [tile 'clamp]
                                           #:matrix [matrix #f])
  (define who 'make-sweep-gradient-color4f-shader)
  (define c (point who center)) (define a (scalar who start)) (define b (scalar who end))
  (unless (< a b) (error who "sweep end angle must exceed start angle"))
  (with-gradient who colors stops tile matrix space
    (lambda (cs cp ps n mode lm) (sk_shader_new_sweep_gradient_color4f c cs cp ps n mode a b lm))))

; make-two-point-conical-gradient-color4f-shader : (or/c (list/c real? real?) (vector/c real?
;   real?)) (and/c real? (>=/c 0)) (or/c (list/c real? real?) (vector/c real? real?)) (and/c real?
;   (>=/c 0)) (or/c (listof color4f?) (vectorof color4f?)) #:color-space (or/c 'srgb 'linear-srgb
;   bytes?) [#:stops (or/c #f (listof real?) (vectorof real?))] [#:tile-mode (or/c 'clamp 'repeat
;   'mirror 'decal)] [#:matrix (or/c matrix? #f)] -> shader?
;   Returns a gradient between circles with the given centers and nonnegative radii.
(define (make-two-point-conical-gradient-color4f-shader start start-radius end end-radius colors
                                                       #:color-space space #:stops [stops #f]
                                                       #:tile-mode [tile 'clamp] #:matrix [matrix #f])
  (define who 'make-two-point-conical-gradient-color4f-shader)
  (define a (point who start)) (define b (point who end))
  (define ar (nonnegative-scalar who start-radius)) (define br (nonnegative-scalar who end-radius))
  (when (and (= (sk-point-x a) (sk-point-x b)) (= (sk-point-y a) (sk-point-y b)) (= ar br))
    (error who "conical gradient circles must differ"))
  (with-gradient who colors stops tile matrix space
    (lambda (cs cp ps n mode lm)
      (sk_shader_new_two_point_conical_gradient_color4f a ar b br cs cp ps n mode lm))))
