#lang racket/base
(require racket/cmdline racket/file racket/path racket/string json "../main.rkt")

(define ink "#20344e")
(define blue "#3269d5")
(define teal "#10988e")
(define orange "#efa02b")
(define solid-source
  "layout(color) uniform half4 color; half4 main(float2 p) { return half4(color.rgb*color.a,color.a); }")
(define wave-source
  (string-append
   "uniform float2x2 basis; uniform float phase; layout(color) uniform half4 low; layout(color) uniform half4 high;\n"
   "half4 main(float2 p) { float2 q=basis*p; half t=half(0.5+0.5*sin(q.x*0.055+q.y*0.025+phase));\n"
   "half4 c=mix(low,high,t); return half4(c.rgb*c.a,c.a); }"))
(define palette-source
  (string-append
   "uniform int enabled; layout(color) uniform half4 palette[2]; uniform float cell;\n"
   "half4 main(float2 p) { float k=mod(floor(p.x/cell)+floor(p.y/cell),2.0);\n"
   "half4 c=(enabled==0 || k<1.0) ? palette[0] : palette[1]; return half4(c.rgb*c.a,c.a); }"))
(define pass-source "uniform shader child; half4 main(float2 p) { return child.eval(p); }")
(define warp-source
  "uniform shader child; uniform float amount; half4 main(float2 p) { return child.eval(p+float2(0,amount*sin(p.x*0.045))); }")
(define mixed-source
  "uniform shader image; uniform colorFilter filter; uniform blender blend; half4 main(float2 p) { return blend.eval(filter.eval(image.eval(p)),half4(0,0,1,1)); }")
(define invert-source "half4 main(half4 c) { return half4(c.a-c.rgb,c.a); }")
(define mix-source "uniform float amount; half4 main(half4 s, half4 d) { return mix(s,d,amount); }")

(define (label c text x y size [color ink])
  (with-skia ([f (make-font #:size size #:linear-metrics? #t #:subpixel? #t #:hinting 'none)]
              [p (make-paint #:color color)])
    (draw-simple-text c text x y f p)))
(define (fill-shader c sh)
  (with-skia ([p (make-paint #:shader sh)]) (draw-paint c p)))
(define (motif c [cf #f])
  (with-skia ([a (make-paint #:color blue #:color-filter cf)]
              [b (make-paint #:color orange #:color-filter cf)]
              [t (make-paint #:color teal #:color-filter cf #:style 'stroke #:stroke-width 7)])
    (draw-rounded-rect c 24 14 196 80 15 15 a)
    (draw-line c 52 32 186 75 t)
    (draw-line c 111 20 138 86 t)
    (draw-circle c 239 74 31 b)))
(define (checker c x y)
  (with-skia ([light (make-paint #:color "#f1f4f7")]
              [dark (make-paint #:color "#e2e7ee")])
    (draw-rect c x y 312 112 light)
    (for* ([row (in-range 7)] [col (in-range 20)] #:when (odd? (+ row col)))
      (draw-rect c (+ x (* col 16)) (+ y (* row 16)) (min 16 (- 312 (* col 16))) 16 dark))))
(define (panel c x y title description draw)
  (label c title x (- y 11) 12)
  (checker c x y)
  ;; Explicit, bounded fallback on BOTH vector backends. Generic SkSL and
  ;; custom blend programs are not claimed to have a PDF/SVG representation.
  (draw-rasterized c x y 312 112 draw #:scale 2)
  (with-skia ([border (make-paint #:color "#cbd5e2" #:style 'stroke #:stroke-width 0.5)])
    (draw-rect c x y 312 112 border))
  (label c description x (+ y 130) 9))
(define (page title subtitle panels)
  (make-output-page
   720 500
   (lambda (c)
     (with-skia ([p (make-paint #:color teal)]) (draw-rect c 0 0 34 2 p))
     (label c title 0 32 22)
     (label c subtitle 0 54 10)
     (for ([spec (in-list panels)] [xy (in-list '((0 100) (352 100) (0 276) (352 276)))])
       (panel c (car xy) (cadr xy) (car spec) (cadr spec) (caddr spec)))
     (label c "RACKET / SKIA   |   RUNTIME EFFECTS / SKSL" 0 447 9)
     (label c "Four bounded raster panels; surrounding labels and checkerboards stay vector." 0 430 9))
   #:margins 24 #:background 'white))
(define (waves e phase [basis '(1 0 0 1)])
  (runtime-effect->shader e #:uniforms
     (hash 'basis basis 'phase phase 'low '(0.20 0.41 0.84 1) 'high '(0.94 0.63 0.17 1))))
(define (make-tile)
  (with-skia ([s (make-surface 32 32 #:background teal)]
              [a (make-paint #:color blue)] [b (make-paint #:color orange)])
    (define c (surface-canvas s))
    (draw-rect c 0 0 16 16 a) (draw-rect c 16 16 16 16 a)
    (draw-circle c 16 16 8 b)
    (surface-snapshot s)))
(define (reflection-entry name e)
  (hasheq 'name name 'kind (symbol->string (runtime-effect-kind e))
          'uniform_bytes (runtime-effect-uniform-byte-size e)
          'uniforms
          (for/list ([u (in-list (runtime-effect-uniforms e))])
            (hasheq 'name (runtime-uniform-name u) 'offset (runtime-uniform-offset u)
                    'type (symbol->string (runtime-uniform-type u)) 'count (runtime-uniform-count u)
                    'bytes (runtime-uniform-byte-size u) 'array (runtime-uniform-array? u)
                    'color (runtime-uniform-color? u) 'half (runtime-uniform-half-precision? u)))
          'children
          (for/list ([child (in-list (runtime-effect-children e))])
            (hasheq 'name (runtime-child-name child)
                    'kind (symbol->string (runtime-child-kind child))
                    'index (runtime-child-index child)))))
(define (escaped s)
  (string-replace (string-replace (string-replace (string-replace s "&" "&amp;")
                                                  "<" "&lt;") ">" "&gt;") "\"" "&quot;"))
(define (basename p) (escaped (path->string (file-name-from-path p))))

(module+ main
  (define prefix (command-line #:program "runtime-effects.rkt"
                              #:args ([prefix "runtime-effects-0.28"]) prefix))
  (define (name suffix) (string-append prefix suffix))
  (make-parent-directory* (name ".pdf"))
  ;; Compile once, create independent uniform/child snapshots for each draw.
  ;; The same live programs are reused across PDF, SVG, and raster references.
  (with-skia ([solid (make-runtime-effect solid-source)]
              [wave (make-runtime-effect wave-source)]
              [palette (make-runtime-effect palette-source)]
              [pass (make-runtime-effect pass-source)]
              [warp (make-runtime-effect warp-source)]
              [mixed (make-runtime-effect mixed-source)]
              [invert (make-runtime-effect invert-source #:kind 'color-filter)]
              [mix (make-runtime-effect mix-source #:kind 'blender)]
              [tile (make-tile)])
    (define uniforms-page
      (page "Programs are reusable; values are snapshots"
            "Uniforms are checked by name, type, count, and reflected byte offset. No raw pointers or mutable native buffers."
            (list
             (list "01  A color uniform, including alpha" "layout(color) input; premultiplied shader output."
                   (lambda (c)
                     (with-skia ([sh (runtime-effect->shader solid #:uniforms (hash 'color '(0.2 0.41 0.84 0.65)))])
                       (fill-shader c sh))))
             (list "02  Procedural bands" "One compiled program; phase = 0."
                   (lambda (c) (with-skia ([sh (waves wave 0)]) (fill-shader c sh))))
             (list "03  The same program, new values" "A matrix and a phase are copied into a new instance."
                   (lambda (c) (with-skia ([sh (waves wave 1.2 '(0.65 0.45 -0.25 1))]) (fill-shader c sh))))
             (list "04  Integer and color-array uniforms" "A flat eight-number palette; half values use 32-bit storage."
                   (lambda (c)
                     (with-skia ([sh (runtime-effect->shader palette #:uniforms
                                     (hash 'enabled 1 'cell 22 'palette '(0.2 0.41 0.84 1 0.06 0.60 0.56 1)))])
                       (fill-shader c sh)))))))
    (define children-page
      (page "A child is a shader, not just a texture"
            "Gradient, image, nested runtime, color-filter, and blender children are bound with their reflected types."
            (list
             (list "01  An ordinary gradient child" "The child is evaluated directly in local coordinates."
                   (lambda (c)
                     (with-skia ([gradient (make-linear-gradient-shader 0 0 312 0 (list blue teal orange))]
                                 [sh (runtime-effect->shader pass #:children (hash 'child gradient))])
                       (fill-shader c sh))))
             (list "02  A tiled image child" "Image-shader coordinates are measured in pixels."
                   (lambda (c)
                     (with-skia ([image (make-image-shader tile #:tile-x 'repeat #:tile-y 'repeat)]
                                 [sh (runtime-effect->shader warp #:uniforms (hash 'amount 9)
                                                               #:children (hash 'child image))])
                       (fill-shader c sh))))
             (list "03  Runtime effect inside a runtime effect" "The parent remaps the coordinates passed to its child."
                   (lambda (c)
                     (with-skia ([inner (waves wave 0)]
                                 [sh (runtime-effect->shader warp #:uniforms (hash 'amount 28)
                                                               #:children (hash 'child inner))])
                       (fill-shader c sh))))
             (list "04  Three different child kinds" "Shader -> color filter -> explicit source blender."
                   (lambda (c)
                     (with-skia ([gradient (make-linear-gradient-shader 0 0 312 0 (list blue teal orange))]
                                 [cf (runtime-effect->color-filter invert)]
                                 [b (make-blend-mode-blender 'src)]
                                 [sh (runtime-effect->shader mixed #:children
                                      (hash 'image gradient 'filter cf 'blend b))])
                       (fill-shader c sh)))))))
    (define pipeline-page
      (page "The ordinary paint API accepts runtime nodes"
            "Color filters and blenders use the same lifetime rules as shaders. Native inputs are retained by their parents."
            (list
             (list "01  A runtime color filter" "Inversion is alpha-aware: (alpha - RGB, alpha)."
                   (lambda (c) (with-skia ([cf (runtime-effect->color-filter invert)]) (motif c cf))))
             (list "02  Existing filter composition" "Invert twice: the original colors are restored."
                   (lambda (c)
                     (with-skia ([cf (runtime-effect->color-filter invert)]
                                 [twice (make-compose-color-filter cf cf)])
                       (motif c twice))))
             (list "03  A runtime paint blender" "mix(source, destination, 0.45), including alpha."
                   (lambda (c)
                     (with-skia ([bg (make-paint #:color blue)]
                                 [fg (make-paint #:color orange)]
                                 [b (runtime-effect->blender mix #:uniforms (hash 'amount 0.45))])
                       (draw-rounded-rect c 26 18 190 72 15 15 bg)
                       (paint-set-blender! fg b)
                       (draw-circle c 216 61 44 fg))))
             (list "04  Closed parents do not invalidate the result" "Program and original child closed before this drawing."
                   (lambda (c)
                     (with-skia ([e (make-runtime-effect pass-source)]
                                 [child (make-linear-gradient-shader 0 0 312 112 (list teal blue orange))]
                                 [sh (runtime-effect->shader e #:children (hash 'child child))])
                       (skia-close! e) (skia-close! child)
                       (fill-shader c sh)))))))
    (define registry (list (cons "uniforms" uniforms-page) (cons "children" children-page)
                           (cons "pipeline" pipeline-page)))
    (save-output (map cdr registry) (name ".pdf") 'pdf #:exists 'replace
                 #:title "Runtime effects / SkSL" #:raster-dpi 144)
    (for ([entry (in-list registry)])
      (define stem (string-append "." (car entry)))
      (save-output (cdr entry) (name (string-append stem ".svg")) 'svg #:exists 'replace
                   #:title (string-append "Runtime effects: " (car entry))
                   #:id-prefix (car entry) #:raster-dpi 144)
      (with-skia ([image (output-page->image (cdr entry) #:dpi 144)])
        (save-image image (name (string-append stem ".reference.png")) 'png #:exists 'replace)))
    (call-with-output-file (name ".trace.json")
      (lambda (out)
        (write-json
         (hasheq 'version "0.28.0" 'note "Native reflection, not a rendering or display measurement"
                 'effects (for/list ([e (in-list (list solid wave palette pass warp mixed invert mix))]
                                      [n (in-list '("solid" "wave" "palette" "pass" "warp" "mixed" "invert" "mix"))])
                            (reflection-entry n e))) out))
      #:exists 'replace)
    (call-with-output-file (name ".review.html")
      (lambda (out)
        (display "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Runtime effects review</title><style>body{font:16px system-ui;margin:24px;background:#edf0f4;color:#20344e}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:32px}figure{margin:0}img{width:100%;background:white}figcaption{margin:8px 0}@media(max-width:900px){.pair{grid-template-columns:1fr}}</style><h1>Runtime effects / SkSL</h1>" out)
        (fprintf out "<p><a href=\"~a\">Open the three-page PDF</a>. All effect panels are explicitly rasterized on both vector backends. Labels and checkerboards stay vector. Left: actual SVG. Right: separate raster drawing, not a PDF/SVG rasterization.</p>" (basename (name ".pdf")))
        (for ([entry (in-list registry)])
          (define stem (string-append "." (car entry)))
          (fprintf out "<h2>~a</h2><section class=\"pair\"><figure><figcaption>Actual SVG; four 624 x 224 effect images</figcaption><img src=\"~a\" alt=\"SVG\"></figure><figure><figcaption>Independent raster reference</figcaption><img src=\"~a\" alt=\"Reference\"></figure></section>"
                   (car entry) (basename (name (string-append stem ".svg")))
                   (basename (name (string-append stem ".reference.png")))))
        (display "</html>" out)) #:exists 'replace))
  (printf "Wrote ~a.pdf; 3 SVGs; 3 independent raster references; reflection trace; ~a.review.html\n" prefix prefix))
