#lang racket/base

;;;
;;; Render Canvas Backend Policy
;;;

;; Resolves requested rendering backends and reports supported capabilities.
;; Keeps backend selection separate from GUI canvas state and native activation.

;; Declarative selection only: never load racket/gui, a driver, or Skia here.

;;;
;;; Exports
;;;

(require "gpu-selection.rkt" "gpu-dxgi-util.rkt")
(provide resolve-render-canvas-policy render-canvas-capabilities check-canvas-style)

;;;
;;; Declarative Backend Selection
;;;

; native-backend : symbol? symbol? -> (or/c #f symbol?)
;   Selects the platform's default Metal, Direct3D, or OpenGL backend without probing a driver.
(define (native-backend os arch)
  (cond [(eq? os 'macosx) 'metal]
        [(and (eq? os 'windows) (eq? arch 'x86_64)) 'direct3d]
        [(eq? os 'unix) 'opengl]
        [else #f]))

; resolve-render-canvas-policy : symbol? symbol? (or/c #f symbol?) (or/c #f exact-integer?) (or/c #f
; exact-integer?) [#:os symbol? #:arch symbol? #:who symbol?] -> hash?
;   Validates renderer/backend/adapter choices and resolves platform defaults without enabling
;   runtime fallback.
(define (resolve-render-canvas-policy renderer backend adapter adapter-index sync-interval
                                     #:os [os (system-type 'os)]
                                     #:arch [arch (system-type 'arch)]
                                     #:who [who 'make-skia-render-canvas])
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
  (when (eq? actual-backend 'direct3d)
    (d3d12-selection! (or adapter 'hardware) (or adapter-index 0) #:who who)
    (dxgi-sync-interval! (or sync-interval 1) #:who who))
  (hasheq 'requested_renderer renderer 'requested_backend backend
          'renderer actual-renderer 'backend actual-backend
          'adapter (and (eq? actual-backend 'direct3d) (or adapter 'hardware))
          'adapter_index (and (eq? actual-backend 'direct3d) (or adapter-index 0))
          'sync_interval (and (eq? actual-backend 'direct3d) (or sync-interval 1))
          'selection "declarative platform policy; not a driver probe"
          'runtime_fallback #f))

; check-canvas-style : symbol? any/c [#:raster? boolean?] -> void?
;   Checks portable widget styles, permitting pixel persistence only for raster canvases.
(define (check-canvas-style who style #:raster? [raster? #f])
  (define allowed
    (if raster? '(border control-border no-focus deleted no-autoclear)
        '(border control-border no-focus deleted)))
  (unless (and (list? style) (andmap (lambda (flag) (memq flag allowed)) style))
    (raise-argument-error who (format "list of canvas styles from ~s" allowed) style))
  (void))

;;;
;;; Resolved Capability Description
;;;

; render-canvas-capabilities : hash? -> hash?
;   Describes callback lifetime, retained drawing state, and presentation behavior for a resolved
;   renderer policy.
(define (render-canvas-capabilities policy)
  (define raster? (eq? (hash-ref policy 'renderer) 'raster))
  (hasheq 'renderer (hash-ref policy 'renderer) 'backend (hash-ref policy 'backend)
          'get_dc 'callback-only
          'dc_lifetime (if raster? 'persistent 'frame-scoped)
          'persistent_dc raster? 'cached_pixel_presentation raster?
          'drawing_state_between_callbacks (if raster? 'retained 'fresh)
          'gpu_execution (not raster?) 'implicit_gpu_readback #f
          'raster_bitmap_bridge raster? 'runtime_fallback #f))
