#lang info

(define collection "skia-doc")
(define version "0.79")
(define pkg-desc "Skia manuals, editable tutorials and licensed font assets")
(define pkg-authors '(soegaard))
(define license '(MIT AND OFL-1.1))
(define deps '(("base" #:version "8.18") ("skia-lib" #:version "0.79")
               "scribble-lib" "racket-index" "rackunit-lib"
               "draw-lib" "gui-lib" "pict-lib" "plot-lib"))
(define build-deps '("racket-doc" "draw-doc" "gui-doc" "pict-doc"))
;; Manuals run during setup; package testing executes the documentation tests.
(define test-omit-paths '("scribblings" "fonts" "licenses" "tools" "doc" "html"))
(define compile-omit-paths '("fonts" "licenses" "doc" "html"))

(define binary-keep-files
  (list "scribblings" "private" "tools"
        ;; Directory entries do not recursively retain compiled .rkt source.
        ;; Explicit files are the editable sets in support/catalog.json;
        ;; the round-trip validator checks every member independently.
        (build-path "scribblings" "quick" "moonlight.rkt")
        (build-path "scribblings" "tutorials" "animation" "orbiting-lights.rkt")
        (build-path "scribblings" "tutorials" "animation" "scene.rkt")
        (build-path "scribblings" "tutorials" "clock" "clock.rkt")
        (build-path "scribblings" "tutorials" "color-spaces" "color-study.rkt")
        (build-path "scribblings" "tutorials" "effects" "card-with-shadows.rkt")
        (build-path "scribblings" "tutorials" "gpu" "gpu-offscreen.rkt")
        (build-path "scribblings" "tutorials" "gpu" "linux-opengl.rkt")
        (build-path "scribblings" "tutorials" "gpu" "render-scene.rkt")
        (build-path "scribblings" "tutorials" "gpu" "scene.rkt")
        (build-path "scribblings" "tutorials" "images" "contact-sheet.rkt")
        (build-path "scribblings" "tutorials" "images" "fixtures" "flower.png")
        (build-path "scribblings" "tutorials" "images" "fixtures" "mountains.jpg")
        (build-path "scribblings" "tutorials" "images" "fixtures" "pattern.webp")
        (build-path "scribblings" "tutorials" "images" "fixtures" "pixel-art.png")
        (build-path "scribblings" "tutorials" "interaction" "bezier-editor.rkt")
        (build-path "scribblings" "tutorials" "interaction" "scene.rkt")
        (build-path "scribblings" "tutorials" "logo" "logo.rkt")
        (build-path "scribblings" "tutorials" "navigation" "model.rkt")
        (build-path "scribblings" "tutorials" "navigation" "navigate.rkt")
        (build-path "scribblings" "tutorials" "navigation" "scene.rkt")
        (build-path "scribblings" "tutorials" "paragraph" "article-card.rkt")
        (build-path "scribblings" "tutorials" "path-ops" "badge.rkt")
        (build-path "scribblings" "tutorials" "pdf-svg" "geometry-diagram.rkt")
        (build-path "scribblings" "tutorials" "pictures" "pattern-sheet.rkt")
        (build-path "scribblings" "tutorials" "pixels" "pixel-lab.rkt")
        (build-path "scribblings" "tutorials" "poster" "poster.rkt")
        (build-path "scribblings" "tutorials" "shaders" "waves-window.rkt")
        (build-path "scribblings" "tutorials" "shaders" "waves.rkt")
        (build-path "scribblings" "tutorials" "shaping" "language-sampler.rkt")
        (build-path "scribblings" "tutorials" "sprites" "atlas.rkt")
        (build-path "scribblings" "tutorials" "sprites" "balls.rkt")
        (build-path "scribblings" "tutorials" "sprites" "model.rkt")
        (build-path "scribblings" "tutorials" "sprites" "scene.rkt")
        (build-path "scribblings" "tutorials" "squadron" "atlas.rkt")
        (build-path "scribblings" "tutorials" "squadron" "model.rkt")
        (build-path "scribblings" "tutorials" "squadron" "scene.rkt")
        (build-path "scribblings" "tutorials" "squadron" "squadron.rkt")
        (build-path "scribblings" "tutorials" "support" "sprite-assets.rkt")
        (build-path "scribblings" "tutorials" "support" "sprite-math.rkt")
        (build-path "scribblings" "tutorials" "support" "sprite-window.rkt")
        (build-path "scribblings" "tutorials" "text" "type-specimen.rkt")
        (build-path "scribblings" "tutorials" "vector-raster" "vector-raster.rkt")
        "fonts" "licenses"))
(define binary-lib-keep-files binary-keep-files)

(define scribblings
  '(("scribblings/reference/reference.scrbl" (multi-page) (gui-library) "skia-reference")
    ("scribblings/guide/guide.scrbl" () (gui-library) "skia-guide")
    ("scribblings/tutorials/index.scrbl" () (gui-library) "skia-tutorials")
    ("scribblings/quick/quick.scrbl" () (omit-start) "skia-tutorial-quick")
    ("scribblings/tutorials/clock/clock.scrbl" () (omit-start) "skia-tutorial-clock")
    ("scribblings/tutorials/logo/logo.scrbl" () (omit-start) "skia-tutorial-logo")
    ("scribblings/tutorials/images/images.scrbl" () (omit-start) "skia-tutorial-images")
    ("scribblings/tutorials/poster/poster.scrbl" () (omit-start) "skia-tutorial-poster")
    ("scribblings/tutorials/text/text.scrbl" () (omit-start) "skia-tutorial-text")
    ("scribblings/tutorials/shaping/shaping.scrbl" () (omit-start) "skia-tutorial-shaping")
    ("scribblings/tutorials/paragraph/paragraph.scrbl" () (omit-start) "skia-tutorial-paragraph")
    ("scribblings/tutorials/pdf-svg/pdf-svg.scrbl" () (omit-start) "skia-tutorial-pdf-svg")
    ("scribblings/tutorials/effects/effects.scrbl" () (omit-start) "skia-tutorial-effects")
    ("scribblings/tutorials/pictures/pictures.scrbl" () (omit-start) "skia-tutorial-pictures")
    ("scribblings/tutorials/vector-raster/vector-raster.scrbl"
     () (omit-start) "skia-tutorial-vector-raster")
    ("scribblings/tutorials/gpu/gpu.scrbl" () (omit-start) "skia-tutorial-gpu")
    ("scribblings/tutorials/animation/animation.scrbl" () (omit-start) "skia-tutorial-animation")
    ("scribblings/tutorials/interaction/interaction.scrbl"
     () (omit-start) "skia-tutorial-interaction")
    ("scribblings/tutorials/navigation/navigation.scrbl" () (omit-start) "skia-tutorial-navigation")
    ("scribblings/tutorials/shaders/shaders.scrbl" () (omit-start) "skia-tutorial-shaders")
    ("scribblings/tutorials/pixels/pixels.scrbl" () (omit-start) "skia-tutorial-pixels")
    ("scribblings/tutorials/color-spaces/color-spaces.scrbl"
     () (omit-start) "skia-tutorial-color-spaces")
    ("scribblings/tutorials/path-ops/path-ops.scrbl" () (omit-start) "skia-tutorial-path-ops")
    ("scribblings/tutorials/sprites/sprites.scrbl" () (omit-start) "skia-tutorial-sprites")
    ("scribblings/tutorials/squadron/squadron.scrbl" () (omit-start) "skia-tutorial-squadron")))

; raco-commands : list?
;   Registers the tutorial-example copier as the skia-examples raco command.
(define raco-commands
  '(("skia-examples" skia-doc/tools/copy-tutorial-examples
     "copy a complete Skia tutorial example" #f)))
