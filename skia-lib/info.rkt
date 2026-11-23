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
               ("skia-native-macos-1" #:version "1.0" #:platform #rx"^(aarch64|x86_64)-macosx$")
               ("skia-native-win32-x86_64-1" #:version "1.0" #:platform "win32\\x86_64")
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

;; Installed diagnostic and acquisition tools must survive binary-lib
;; installs. Build paths from components so Windows retention keys match the
;; native paths used by Racket's package stripper. Pin files are read lazily
;; by both loaders in every package form.

; binary-keep-files : (listof path-string?)
;   Preserves installed tools and lazy loader inputs in binary package forms.
(define binary-keep-files
  (list "examples" "packaging"
        (build-path "tools" "annotation-doctor.rkt")
        (build-path "tools" "canvas-doctor.rkt")
        (build-path "tools" "codec-doctor.rkt")
        (build-path "tools" "color-output-doctor.rkt")
        (build-path "tools" "filter-graph-doctor.rkt")
        (build-path "tools" "geometry-doctor.rkt")
        (build-path "tools" "output-audit-doctor.rkt")
        (build-path "tools" "output-doctor.rkt")
        (build-path "tools" "path-matrix-doctor.rkt")
        (build-path "tools" "pdf-doctor.rkt")
        (build-path "tools" "picture-doctor.rkt")
        (build-path "tools" "projective-doctor.rkt")
        (build-path "tools" "runtime-doctor.rkt")
        (build-path "tools" "svg-doctor.rkt")

        (build-path "tests" "typeface-fixtures.rkt")
        (build-path "tests" "codec-fixtures.rkt")
        (build-path "tests" "runtime-fixtures.rkt")
        (build-path "tests" "geometry-completion-fixtures.rkt")
        (build-path "tools" "doctor.rkt")
        (build-path "tools" "ci-import-smoke.rkt")
        (build-path "tools" "ci-package-smoke.rkt")
        (build-path "tools" "catalog-smoke.rkt")
        (build-path "tools" "install-windows-natives.rkt")
        (build-path "tools" "check-package-version.rkt")
        (build-path "tools" "native-abi-reject.rkt")
        (build-path "tools" "native-abi-doctor.rkt")
        (build-path "tools" "install-native-windows.py")
        (build-path "tools" "install-native-windows.ps1")
        (build-path "tools" "windows_native.py")
        (build-path "tools" "native_packages.py")
        (build-path "tools" "native_abi.py")
        (build-path "tools" "repository_layout.py")
        (build-path "private" "native-default-version.txt")
        (build-path "private" "harfbuzz-default-version.txt")
        (build-path "private" "source-identity.json")))
(define binary-lib-keep-files binary-keep-files)


; build-deps : list?
;   The implementation needs no documentation package to build or test.
(define build-deps '())
