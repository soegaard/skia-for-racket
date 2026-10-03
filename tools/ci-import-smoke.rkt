#lang racket/base
;; The CI driver sets both native-library overrides to nonexistent paths and
;; unsets display variables. Import must not force either library or a GUI.
;; skia/canvas, skia/gpu-canvas and skia/gpu-gui are GUI-only entry points. The
;; headless imports below must not pull either of those modules in indirectly.
(require json)
(module+ main
  (for ([module '(skia skia/dc skia/gpu-dc skia/bitmap skia/native-capabilities skia/gpu skia/gpu-egl skia/gpu-gl-interop skia/gpu-output skia/gpu-interop skia/unsafe/gpu-d3d12 skia/unsafe/gpu-metal)])
    (dynamic-require module #f))
  (define gui-instantiated?
    (with-handlers ([exn:fail? (lambda (_) #f)])
      (module->namespace 'racket/gui/base)
      #t))
  (when gui-instantiated?
    (error 'ci-import-smoke "an optional/CPU import instantiated racket/gui/base"))
  (for ([module '(skia/canvas skia/gpu-canvas skia/gpu-gui)])
    (define instantiated?
      (with-handlers ([exn:fail? (lambda (_) #f)])
        (module->namespace module)
        #t))
    (when instantiated?
      (error 'ci-import-smoke "a headless import instantiated GUI-only module ~a" module)))
  (write-json (hasheq 'status "passed" 'gui_instantiated #f
                      'native_library_overrides "nonexistent paths supplied by CI"))
  (newline))
