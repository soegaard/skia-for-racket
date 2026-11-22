#lang info

;;;
;;; Package Registration
;;;

;; Declares package dependencies, registered manuals, test exclusions, and command-line tools.
;; Racket's package manager and documentation builder read this metadata to install the Skia
;; collection and expose its public entry points.

;;;
;;; Package Metadata
;;;

; collection : string?
;   Names the installed Racket collection used by require paths.
(define collection "skia")

; version : string?
;   Identifies the package version reported by Racket's package manager.
(define version "0.79")

; pkg-desc : string?
;   Summarizes the package and its accumulated feature milestones for package metadata.
(define pkg-desc "Skia CPU drawing, codecs, documents, and HarfBuzz text shaping")
(define pkg-authors '(soegaard))

; deps : list?
;   Declares runtime dependencies and minimum versions required by the collection.
(define deps '(("base" #:version "8.18") ("draw-lib" #:version "1.22")
               "gui-lib" "rackunit-lib" "pict-lib" "plot-lib"
               "scribble-lib" "racket-index"
               ("skia-fonts-1" #:version "1.0")
               ("skia-native-macos-1" #:version "1.0" #:platform #rx"^(aarch64|x86_64)-macosx$")
               ("skia-native-x86_64-linux-1" #:version "1.0" #:platform #rx"^x86_64-linux(-natipkg)?$")))

; license : symbol?
;   Declares the package's MIT license using Racket package metadata syntax.
(define license 'MIT)

;;;
;;; Test and Compilation Exclusions
;;;

; test-omit-paths : (listof string?)
;   Excludes opt-in GPU/GUI probes and tool/example trees from the default package test traversal.
(define test-omit-paths
  '("tests/gpu-diagnostics-gpu-test.rkt"
    "tests/gpu-context-control-gpu-test.rkt"
    "tests/live-ffi-probe"
    "tests/advanced-canvas-gpu-test.rkt"
    "tests/gpu-format-gpu-test.rkt"
    "tests/image-operation-gpu-test.rkt"
    "tests/float-pixel-gpu-test.rkt"
    "tests/integer-pixel-gpu-test.rkt"
    "tests/text-blob-gpu-test.rkt"
    "tests/font-query-gpu-test.rkt"
    "tests/geometry-completion-gpu-test.rkt"
    "tests/effects-gpu-test.rkt"
    "tests/gpu-frame-target-native-test.rkt"
    "render-canvas.rkt"
    "tests/render-canvas-gui-test.rkt"
    ;; Registered manuals execute during setup; DrDr must not rebuild them a second time.
    "scribblings"
    ;; Setup copies editable example .rkt files into generated manual output;
    ;; they are download assets, not a second runnable source/test tree.
    "doc" "html" "output" "downloads"
    "examples"
    "tools"
    "native"
    "gpu-gui.rkt"
    "gpu-canvas.rkt"
    "tests/gpu-dc-gui-test.rkt"
    "tests/gpu-dc-native-test.rkt"
    "canvas.rkt"
    "tests/canvas-gui-test.rkt"
    "tests/canvas-text-load-order.rkt"))

; compile-omit-paths : (listof string?)
;   Keeps downloaded artifacts and generated output out of source compilation.
(define compile-omit-paths '("native" "downloads" "html" "doc" "output"))

;; The advertised copier needs editable tutorial source even in binary-lib
;; installs. Build paths from components so Windows retention keys match the
;; native paths used by Racket's package stripper. Pin files are read lazily
;; by both loaders in every package form.

; binary-keep-files : (listof path-string?)
;   Preserves editable tutorials and lazy loader inputs in binary package forms.
(define binary-keep-files
  (list "examples" "scribblings"
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
        (build-path "private" "native-default-version.txt")
        (build-path "private" "harfbuzz-default-version.txt")
        (build-path "packaging" "native-assets.json")
        (build-path "tools" "install-native-windows.py")
        (build-path "tools" "install-native-windows.ps1")
        (build-path "tools" "windows_native.py")
        (build-path "tools" "native_packages.py")
        (build-path "tools" "native_abi.py")
        (build-path "private" "source-identity.json")))
(define binary-lib-keep-files binary-keep-files)

;; Manuals use Scribble plus reference targets from Racket and the GUI libraries.

;;;
;;; Build, Documentation, and Command Registration
;;;

; build-deps : (listof string?)
;   Declares documentation packages needed to build the installed manuals.
(define build-deps '("racket-doc" "draw-doc" "gui-doc" "pict-doc"))

;; The Reference is multi-page; tutorials retain their unique single-page output names.
;; The landing page appears in the documentation index; individual lessons stay searchable.

; scribblings : list?
;   Registers manuals, output names, and index placement; omit-start tutorials remain individually
;   linked.
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
  '(("skia-examples" skia/tools/copy-tutorial-examples
     "copy a complete Skia tutorial example" #f)))
