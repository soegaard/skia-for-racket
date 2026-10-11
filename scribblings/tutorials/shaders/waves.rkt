#lang racket

(require skia)
(provide solid-source coordinate-source wave-source make-wave-shader
         draw-wave-panel draw-wave-poster poster-width poster-height)

(define poster-width 760)
(define poster-height 460)

(define solid-source
  "half4 main(float2 p) { return half4(0.08, 0.65, 0.72, 1.0); }")

(define coordinate-source
  #<<SKSL
uniform float2 extent;
half4 main(float2 p) {
  float2 uv = p / extent;
  return half4(uv.x, uv.y, 0.25, 1.0);
}
SKSL
  )

(define wave-source
  #<<SKSL
uniform float2 extent;
uniform float frequency;
uniform float bend;
uniform float phase;
layout(color) uniform half4 dark;
layout(color) uniform half4 light;

half4 main(float2 p) {
  // Normalize both axes by the same length to preserve the wave's proportions.
  float2 q = (p - 0.5 * extent) / min(extent.x, extent.y);
  float field = q.x + bend * sin(3.5 * q.y + phase);
  float wave = 0.5 + 0.5 * sin(6.2831853 * frequency * field);
  float band = smoothstep(0.25, 0.75, wave);
  half4 color = mix(dark, light, half(band));
  return half4(color.rgb * color.a, color.a);
}
SKSL
  )

(define (make-wave-shader effect width height
                           #:frequency [frequency 5]
                           #:bend [bend 0.28]
                           #:phase [phase 0]
                           #:dark [dark '(0.035 0.09 0.19 1)]
                           #:light [light '(0.22 0.84 0.80 1)])
  (runtime-effect->shader
   effect
   #:uniforms (hash 'extent (list width height)
                    'frequency frequency 'bend bend 'phase phase
                    'dark dark 'light light)))

(define (draw-wave-panel canvas effect x y width height
                         #:frequency [frequency 5] #:bend [bend 0.28] #:phase [phase 0])
  (define shader
    (make-wave-shader effect width height
                      #:frequency frequency #:bend bend #:phase phase))
  (define paint (make-paint #:shader shader))
  ;; Translate the drawing origin as well as setting the size uniform.
  (with-canvas-state canvas
    (canvas-translate! canvas x y)
    (draw-rounded-rect canvas 0 0 width height 18 18 paint)))

(define (draw-wave-poster canvas effect)
  (define ink (make-paint #:color "#EAF6F9"))
  (define muted (make-paint #:color "#A6C4CE"))
  (define title-font (make-font #:size 30))
  (define caption-font (make-font #:size 14))
  (canvas-clear! canvas "#0A1527")
  (draw-simple-text canvas "CONTOUR WAVES" 32 50 title-font ink)
  (draw-simple-text canvas "A short program supplies the paint's color." 34 80
                    caption-font muted)
  (draw-wave-panel canvas effect 32 106 696 284)
  (draw-simple-text canvas "COORDINATES  /  UNIFORMS  /  COLOR" 34 428 caption-font muted))

(module+ main
  ;; Compilation happens once, not once per rectangle or pixel.
  (define effect (make-runtime-effect wave-source))
  (define surface (make-surface poster-width poster-height))
  (draw-wave-poster (surface-canvas surface) effect)
  (save-png surface "contour-waves.png" #:exists 'replace))
