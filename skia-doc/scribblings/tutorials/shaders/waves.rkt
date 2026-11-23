#lang racket

;;;
;;; Waves
;;;

;; Defines runtime shader sources and shared drawing functions for animated waves.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require skia)
(provide solid-source coordinate-source bands-source wave-source
         scene-width scene-height phase-speed phase-at
         make-wave-shader draw-wave-panel draw-wave-scene)

;;;
;;; Scene Dimensions and Timing
;;;

; scene-width : exact-integer?
;   Specifies scene width in the drawing's local coordinate units.
(define scene-width 760)

; scene-height : exact-integer?
;   Specifies scene height in the drawing's local coordinate units.
(define scene-height 460)

; phase-speed : real?
;   Sets the shader phase change per elapsed second.
(define phase-speed 2.0)

; phase-at : real? -> real?
;   Converts elapsed seconds into the wave shader's animation phase.
(define (phase-at seconds)
  (* phase-speed seconds))

;;;
;;; Shader Programs
;;;

; solid-source : string?
;   Contains the SkSL source compiled by the runtime-effect example.
(define solid-source
  "half4 main(float2 p) { return half4(0.18, 0.74, 0.90, 1.0); }")

; coordinate-source : string?
;   Contains the SkSL source compiled by the runtime-effect example.
(define coordinate-source
  #<<SKSL
uniform float2 extent;
half4 main(float2 p) {
  float2 uv = p / extent;
  return half4(uv.x, uv.y, 0.25, 1.0);
}
SKSL
  )

; bands-source : string?
;   Contains the SkSL source compiled by the runtime-effect example.
(define bands-source
  #<<SKSL
uniform float2 extent;
uniform float frequency;

half4 main(float2 p) {
  float2 q = (p - 0.5 * extent) / min(extent.x, extent.y);
  float gray = 0.5 + 0.5 * sin(6.2831853 * frequency * q.x);
  return half4(gray, gray, gray, 1.0);
}
SKSL
  )

; wave-source : string?
;   Contains the SkSL source compiled by the runtime-effect example.
(define wave-source
  #<<SKSL
uniform float2 extent;
uniform float frequency;
uniform float bend;
uniform float phase;
uniform float hue;
uniform float glow;

half4 main(float2 p) {
  float2 q = (p - 0.5 * extent) / min(extent.x, extent.y);

  float field = q.x + bend * (
      sin(4.7 * q.y + 0.55 * phase)
    + 0.30 * sin(7.0 * q.x - 3.0 * q.y - 0.35 * phase));

  float angle = 6.2831853 * (frequency * field - 0.22 * phase + hue);
  float3 rainbow = 0.5 + 0.5 * cos(
      angle + float3(0.0, 2.0943951, 4.1887902));

  float light = 0.58 + 0.42 * (0.5 + 0.5 * sin(0.5 * angle + 0.7));
  float crest = pow(max(0.0, sin(angle)), 16.0);
  float vignette = clamp(1.13 - 0.42 * length(q), 0.45, 1.0);
  float3 color = vignette * light * (0.10 + 0.88 * rainbow);
  color += 0.24 * glow * crest * float3(0.9, 0.95, 1.0);

  return half4(half3(clamp(color, 0.0, 1.0)), 1.0);
}
SKSL
  )

;;;
;;; Shader Uniforms and Drawing
;;;

; make-wave-shader : runtime-effect? real? real? #:frequency [real?] #:bend [real?] #:phase
; [real?] #:hue [real?] #:glow [real?] -> shader?
;   Constructs wave shader for the example's drawing pipeline.
(define (make-wave-shader effect width height
                          #:frequency [frequency 5]
                          #:bend [bend 0.30]
                          #:phase [phase 0]
                          #:hue [hue 0.08]
                          #:glow [glow 1.0])
  (runtime-effect->shader
   effect
   #:uniforms (hash 'extent (list width height)
                    'frequency frequency
                    'bend bend
                    'phase phase
                    'hue hue
                    'glow glow)))

; draw-wave-panel : canvas? runtime-effect? real? real? real? real? #:frequency [real?] #:bend
; [real?] #:phase [real?] #:hue [real?] #:glow [real?] -> void?
;   Draws the wave panel component in the current canvas coordinate system.
(define (draw-wave-panel canvas effect x y width height
                         #:frequency [frequency 5]
                         #:bend [bend 0.30]
                         #:phase [phase 0]
                         #:hue [hue 0.08]
                         #:glow [glow 1.0])
  (with-skia ([shader (make-wave-shader effect width height
                                        #:frequency frequency
                                        #:bend bend
                                        #:phase phase
                                        #:hue hue
                                        #:glow glow)]
              [paint (make-paint #:shader shader)])
    (with-canvas-state canvas
      (canvas-translate! canvas x y)
      (draw-rounded-rect canvas 0 0 width height 20 20 paint))))

; draw-wave-scene : canvas? runtime-effect? real? real? real? #:frequency [real?] #:bend [real?]
; #:hue [real?] -> void?
;   Draws the wave scene component in the current canvas coordinate system.
(define (draw-wave-scene canvas effect seconds width height
                         #:frequency [frequency 5]
                         #:bend [bend 0.30]
                         #:hue [hue 0.08])
  (define margin 14)
  (define panel-width (max 1 (- width (* 2 margin))))
  (define panel-height (max 1 (- height (* 2 margin))))
  (canvas-clear! canvas "#070D21")
  (draw-wave-panel canvas effect margin margin panel-width panel-height
                   #:frequency frequency
                   #:bend bend
                   #:phase (phase-at seconds)
                   #:hue hue))

;;;
;;; Command-Line Entry Point
;;;

(module+ main
  (with-skia ([effect (make-runtime-effect wave-source)]
              [surface (make-surface scene-width scene-height)])
    (draw-wave-scene (surface-canvas surface) effect 0 scene-width scene-height)
    (save-png surface "wave-frame.png" #:exists 'replace)))
