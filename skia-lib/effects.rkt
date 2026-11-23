#lang racket/base

;;;
;;; Path, Mask, Shader, and Blender Effects
;;;

;; Constructs additional path effects, masks, procedural shaders, and compositing effects.
;; This public factory layer validates effect inputs and carries their native dependencies into the
;; shared lifetime machinery.

;;;
;;; Imports and Exports
;;;

;; Additive m119 effects. Native handles remain private and every returned
;; object uses the existing close/thread/context-affinity protocol.
(require ffi/unsafe racket/list
         "private/core.rkt" "private/native.rkt" "private/types.rkt"
         "private/check.rkt" "private/filter-util.rkt" "private/effects-util.rkt"
         "private/lifetime.rkt" "private/color-filter-util.rkt" "matrix.rkt"
         (submod "private/core.rkt" effects-internals)
         (only-in (submod "private/core.rkt" runtime-internals)
                  blender-resource? blender-resource-handle make-blender-record))
(provide make-1d-path-effect make-2d-line-path-effect make-2d-path-effect
         make-table-mask-filter make-gamma-mask-filter make-clip-mask-filter
         make-shader-mask-filter make-fractal-noise-shader make-turbulence-shader
         make-empty-shader shader-with-color-filter make-blender-shader
         make-arithmetic-blender make-blender-image-filter)

;;;
;;; Blender Handle Validation
;;;

; blender-h : symbol? blender? -> (or/c owned? domain-resource?)
;   Checks the blender resource wrapper and retrieves its managed native handle.
(define (blender-h who v)
  (unless (blender-resource? v) (raise-argument-error who "blender?" v))
  (blender-resource-handle v))

;;;
;;; Path Effects
;;;

; make-1d-path-effect : skia-path? (and/c real? (>/c 0)) [real?] [#:style (or/c 'translate 'rotate
;   'morph)] -> path-effect?
;   Returns an effect that repeats the supplied stamp path along the drawn path.
(define (make-1d-path-effect path advance [phase 0] #:style [style 'translate])
  (define who 'make-1d-path-effect)
  (define step (effect-positive who advance))
  (define offset (filter-float who phase))
  (define mode (choice who style (hasheq 'translate 0 'rotate 1 'morph 2)))
  (define h (path-h who path))
  (effect-path-size! who (path-point-count path))
  (call-with-owned who (list h)
    (lambda (p) (new-path-effect who
                  (lambda () (sk_path_effect_create_1d_path p step offset mode))))))

; make-2d-line-path-effect : (and/c real? (>/c 0)) matrix? -> path-effect?
;   Returns an effect that covers the input region with parallel strokes using the lattice defined
;   by matrix.
(define (make-2d-line-path-effect width matrix)
  (define who 'make-2d-line-path-effect)
  (define w (effect-positive who width))
  (define m (effect-matrix who matrix))
  (new-path-effect who (lambda () (sk_path_effect_create_2d_line w m))))

; make-2d-path-effect : matrix? skia-path? -> path-effect?
;   Returns an effect that places copies of a stamp path on a two-dimensional lattice within the
;   input region.
(define (make-2d-path-effect matrix path)
  (define who 'make-2d-path-effect)
  (define m (effect-matrix who matrix))
  (define h (path-h who path))
  (effect-path-size! who (path-point-count path))
  (call-with-owned who (list h)
    (lambda (p) (new-path-effect who
                  (lambda () (sk_path_effect_create_2d_path m p))))))

;;;
;;; Mask Filters
;;;

; make-table-mask-filter : (or/c bytes? (listof byte?) (vectorof byte?)) -> mask-filter?
;   Returns a coverage remapping specified by exactly 256 byte values.
(define (make-table-mask-filter table)
  (define who 'make-table-mask-filter)
  (define copied (checked-filter-table who table))
  (new-mask-filter who (lambda () (sk_maskfilter_new_table copied))))

; make-gamma-mask-filter : (and/c real? (>/c 0)) -> mask-filter?
;   Returns a coverage remapping using a power curve with the given exponent.
(define (make-gamma-mask-filter gamma)
  (define who 'make-gamma-mask-filter)
  (define g (effect-positive who gamma))
  (new-mask-filter who (lambda () (sk_maskfilter_new_gamma g))))

; make-clip-mask-filter : byte? byte? -> mask-filter?
;   Returns a coverage remapping with coverage below the lower threshold mapped to zero and
;   coverage above the upper threshold mapped to full coverage.
(define (make-clip-mask-filter lo hi)
  (define who 'make-clip-mask-filter)
  (define-values (a b) (effect-clip who lo hi))
  (new-mask-filter who (lambda () (sk_maskfilter_new_clip a b))))

; make-shader-mask-filter : shader? -> mask-filter?
;   Returns a mask filter using the shader's alpha to modulate shape coverage.
(define (make-shader-mask-filter shader)
  (define who 'make-shader-mask-filter)
  (define h (shader-h who shader))
  (call-with-owned who (list h)
    (lambda (p) (new-mask-filter who (lambda () (sk_maskfilter_new_shader p))))))

;;;
;;; Noise and Composed Shaders
;;;

; noise-shader : symbol? procedure? real? real? exact-integer? real? any/c -> shader?
;   Validates noise parameters and constructs an owned shader with the selected native factory.
(define (noise-shader who native x y octaves seed tile)
  (define-values (fx fy count sd ts) (effect-noise who x y octaves seed tile))
  (new-shader who (lambda () (native fx fy count sd ts))))

; make-fractal-noise-shader : real? real? (integer-in 0 255) [real?] [#:tile-size (or/c #f (list/c
;   (integer-in 1 32768) (integer-in 1 32768)) (vector/c (integer-in 1 32768) (integer-in 1
;   32768)))] -> shader?
;   Returns a Perlin fractal-noise shader.
(define (make-fractal-noise-shader x y octaves [seed 0] #:tile-size [tile #f])
  (noise-shader 'make-fractal-noise-shader sk_shader_new_perlin_noise_fractal_noise
                x y octaves seed tile))

; make-turbulence-shader : real? real? (integer-in 0 255) [real?] [#:tile-size (or/c #f (list/c
;   (integer-in 1 32768) (integer-in 1 32768)) (vector/c (integer-in 1 32768) (integer-in 1
;   32768)))] -> shader?
;   Returns a turbulence shader using the magnitudes of successive noise octaves rather than their
;   signed contributions.
(define (make-turbulence-shader x y octaves [seed 0] #:tile-size [tile #f])
  (noise-shader 'make-turbulence-shader sk_shader_new_perlin_noise_turbulence
                x y octaves seed tile))

; make-empty-shader : -> shader?
;   Returns an owned shader that draws nothing.
(define (make-empty-shader)
  (new-shader 'make-empty-shader sk_shader_new_empty))

; shader-with-color-filter : shader? color-filter? -> shader?
;   Returns a shader applying the color filter to the source shader's output.
(define (shader-with-color-filter shader filter)
  (define who 'shader-with-color-filter)
  (define sh (shader-h who shader))
  (define fh (color-filter-h who filter))
  (call-with-owned who (list sh fh)
    (lambda (s f) (new-shader who (lambda () (sk_shader_with_color_filter s f))))))

; make-blender-shader : blender? shader? shader? -> shader?
;   Returns a shader combining two shader results through a retained blender.
(define (make-blender-shader blender destination source)
  (define who 'make-blender-shader)
  (define bh (blender-h who blender))
  (define dh (shader-h who destination))
  (define sh (shader-h who source))
  (call-with-owned who (list bh dh sh)
    (lambda (b d s) (new-shader who (lambda () (sk_shader_new_blender b d s))))))

;;;
;;; Arithmetic Blenders and Image Filters
;;;

; make-arithmetic-blender : real? real? real? real? [#:enforce-premul? boolean?] -> blender?
;   Returns a blender computing k1 S D + k2 S + k3 D + k4 for each normalized premultiplied
;   component, where S is source and D is destination.
(define (make-arithmetic-blender k1 k2 k3 k4 #:enforce-premul? [enforce? #t])
  (define who 'make-arithmetic-blender)
  (define ks (map (lambda (v) (filter-float who v)) (list k1 k2 k3 k4)))
  (boolean who enforce?)
  (skia-check!)
  (make-blender-record
   (new-owned who 'blender
     (lambda () (apply sk_blender_new_arithmetic (append ks (list enforce?))))
     sk_blender_unref)))

; make-blender-image-filter : blender? (or/c image-filter? #f) (or/c image-filter? #f) [#:crop (or/c
;   #f (list/c real? real? real? real?) (vector/c real? real? real? real?))] -> image-filter?
;   Returns a filter using the supplied blender to combine foreground and background.
(define (make-blender-image-filter blender background foreground #:crop [crop #f])
  (define who 'make-blender-image-filter)
  (define bh (blender-h who blender))
  (define bg (optional-image-filter-h who background))
  (define fg (optional-image-filter-h who foreground))
  (define cr (optional-filter-crop who crop))
  (call-with-owned who (filter values (list bh bg fg))
    (lambda (b . inputs)
      (define bp (and bg (car inputs)))
      (define fp (and fg (if bg (cadr inputs) (car inputs))))
      (new-image-filter who
        (lambda ()
          (define (create implicit-source)
            (sk_imagefilter_new_blender b (or bp implicit-source) (or fp implicit-source) cr))
          ;; Match the production graph's null-slot semantics and normalize
          ;; identity results before a native optimizer returns NULL as source.
          (if (and bg fg)
              (create #f)
              (call-with-native-temporary who 'filter-source
                (lambda () (sk_imagefilter_new_offset 0.0 0.0 #f #f))
                sk_imagefilter_unref create)))))))
