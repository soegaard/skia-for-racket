#lang racket/base
;; Declarative selection only: never load racket/gui, a driver, or Skia here.
(provide resolve-render-canvas-policy render-canvas-capabilities)

(define (native-backend os arch)
  (cond [(eq? os 'macosx) 'metal]
        [(and (eq? os 'windows) (eq? arch 'x86_64)) 'direct3d]
        [(eq? os 'unix) 'opengl]
        [else #f]))

(define (resolve-render-canvas-policy renderer backend adapter adapter-index sync-interval
                                     #:os [os (system-type 'os)]
                                     #:arch [arch (system-type 'arch)])
  (define who 'make-skia-render-canvas)
  (unless (memq renderer '(auto raster gpu))
    (raise-argument-error who "'auto, 'raster, or 'gpu renderer" renderer))
  (unless (memq backend '(auto opengl metal direct3d))
    (raise-argument-error who "'auto, 'opengl, 'metal, or 'direct3d backend" backend))
  (when (and (eq? renderer 'raster) (not (eq? backend 'auto)))
    (raise-arguments-error who "a GPU backend cannot be combined with the raster renderer"
                           "renderer" renderer "backend" backend))
  (define preferred (native-backend os arch))
  (define actual-renderer
    (if (or (eq? renderer 'raster)
            (and (eq? renderer 'auto) (eq? backend 'auto) (not preferred)))
        'raster 'gpu))
  (define actual-backend
    (cond [(eq? actual-renderer 'raster) 'raster]
          [(eq? backend 'auto)
           (or preferred
               (raise-arguments-error who "no default GPU backend for this platform"
                                      "os" os "architecture" arch))]
          [else backend]))
  (case actual-backend
    [(metal)
     (unless (eq? os 'macosx)
       (raise-arguments-error who "Metal requires macOS" "os" os))]
    [(direct3d)
     (unless (and (eq? os 'windows) (eq? arch 'x86_64))
       (raise-arguments-error who "Direct3D requires Windows x64"
                              "os" os "architecture" arch))]
    [(opengl)
     (unless (or (memq os '(macosx unix))
                 (and (eq? os 'windows) (eq? arch 'x86_64)))
       (raise-arguments-error who "no built-in desktop OpenGL host for this platform"
                              "os" os "architecture" arch))])
  (when (and (or adapter adapter-index sync-interval) (not (eq? actual-backend 'direct3d)))
    (raise-arguments-error who "adapter, adapter-index and sync-interval require Direct3D"
                           "backend" actual-backend))
  (when (and adapter (not (memq adapter '(hardware warp))))
    (raise-argument-error who "#f, 'hardware, or 'warp adapter" adapter))
  (when (and adapter-index
             (not (and (exact-nonnegative-integer? adapter-index) (<= adapter-index #x7fffffff))))
    (raise-argument-error who "#f or a nonnegative signed-32-bit adapter index" adapter-index))
  (when (and sync-interval
             (not (and (exact-integer? sync-interval) (<= 0 sync-interval 4))))
    (raise-argument-error who "#f or an exact sync interval from 0 through 4" sync-interval))
  (when (and (eq? adapter 'warp) adapter-index (not (zero? adapter-index)))
    (raise-arguments-error who "WARP does not select a hardware adapter index" "adapter-index" adapter-index))
  (hasheq 'requested_renderer renderer 'requested_backend backend
          'renderer actual-renderer 'backend actual-backend
          'adapter (and (eq? actual-backend 'direct3d) (or adapter 'hardware))
          'adapter_index (and (eq? actual-backend 'direct3d) (or adapter-index 0))
          'sync_interval (and (eq? actual-backend 'direct3d) (or sync-interval 1))
          'selection "declarative platform policy; not a driver probe"
          'runtime_fallback #f))

(define (render-canvas-capabilities policy)
  (define raster? (eq? (hash-ref policy 'renderer) 'raster))
  (hasheq 'renderer (hash-ref policy 'renderer) 'backend (hash-ref policy 'backend)
          'get_dc 'callback-only
          'dc_lifetime (if raster? 'persistent 'frame-scoped)
          'persistent_dc raster? 'cached_pixel_presentation raster?
          'drawing_state_between_callbacks (if raster? 'retained 'fresh)
          'gpu_execution (not raster?) 'implicit_gpu_readback #f
          'raster_bitmap_bridge raster? 'runtime_fallback #f))
