#lang racket/base
(require ffi/unsafe
         racket/match
         racket/path
         "native.rkt" "types.rkt" "lifetime.rkt" "check.rkt"
         "../color.rkt")
(provide current-skia-byte-limit
         skia-resource? skia-closed? skia-close!
         call-with-skia-resource with-skia
         surface? make-surface surface-width surface-height surface-canvas
         surface->rgba-bytes surface-pixel surface->png-bytes save-png
         canvas? canvas-clear! canvas-save! canvas-save-count
         canvas-restore! canvas-restore-to-count!
         call-with-canvas-state with-canvas-state
         canvas-translate! canvas-scale! canvas-rotate!
         canvas-rotate-radians! canvas-skew! canvas-reset-transform!
         canvas-clip-rect! canvas-clip-path!
         draw-paint draw-line draw-rect draw-rounded-rect draw-circle draw-oval
         draw-path draw-polygon
         paint? make-paint paint-copy paint-color paint-shader paint-path-effect
         paint-color-filter paint-mask-filter paint-image-filter
         paint-set-color! paint-set-style! paint-set-stroke-width!
         paint-set-antialias! paint-set-cap! paint-set-join!
         paint-set-miter-limit! paint-set-blend-mode! paint-set-shader!
         paint-set-path-effect! paint-set-color-filter! paint-set-mask-filter!
         paint-set-image-filter!
         shader? make-color-shader make-linear-gradient-shader
         make-radial-gradient-shader make-sweep-gradient-shader
         make-two-point-conical-gradient-shader make-image-shader
         make-blend-shader
         path-effect? make-dash-path-effect make-corner-path-effect
         make-discrete-path-effect make-trim-path-effect
         make-compose-path-effect make-sum-path-effect
         color-filter? make-color-matrix-filter make-blend-color-filter
         make-compose-color-filter
         mask-filter? make-blur-mask-filter
         image-filter? make-blur-image-filter make-drop-shadow-image-filter
         make-drop-shadow-only-image-filter make-color-filter-image-filter
         make-compose-image-filter
         picture? picture-width picture-height
         picture-recorder? picture-recorder-recording?
         make-picture-recorder call-with-picture
         picture-recorder-begin-recording! picture-recorder-finish-recording!
         skia-path? make-path path-copy path-move-to! path-line-to!
         path-rmove-to! path-rline-to!
         path-quad-to! path-rquad-to! path-conic-to! path-rconic-to!
         path-cubic-to! path-rcubic-to! path-close! path-reset!
         path-add-rect! path-add-rounded-rect! path-add-oval! path-add-circle!
         path-add-path! path-add-reversed-path!
         path-point-count path-point-ref path-points path-last-point path-convex?
         svg-path->path path->svg-path
         path-bounds path-tight-bounds path-contains?
         path-fill-rule path-set-fill-rule!
         path-op path-union path-intersect path-difference path-xor
         path-reverse-difference path-simplify path-as-winding
         path-measure? make-path-measure path-measure-set-path!
         path-measure-length path-measure-position+tangent
         path-measure-segment path-measure-next-contour! path-measure-closed?
         image? image-width image-height image-color-type image-alpha-type
         surface-snapshot rgba-bytes->image image-from-bytes image-from-file
         image->rgba-bytes image-original-encoded-bytes
         image->png-bytes image->jpeg-bytes image->webp-bytes
         image->encoded-bytes save-image image-subset
         draw-image draw-image-rect draw-image-subrect
         draw-picture picture->image
         encoded-image-info? encoded-image-info-width encoded-image-info-height
         encoded-image-info-format encoded-image-info-color-type
         encoded-image-info-alpha-type encoded-image-info-origin
         encoded-image-info-frame-count
         encoded-image-info-from-bytes encoded-image-info-from-file
         typeface? make-typeface typeface-from-family typeface-from-file
         typeface-family-name typeface-weight typeface-width typeface-slant
         font? make-font font-size font-set-size!
         font-scale-x font-set-scale-x! font-skew-x font-set-skew-x!
         font-edging font-set-edging! font-hinting font-set-hinting!
         font-subpixel? font-set-subpixel!
         font-linear-metrics? font-set-linear-metrics!
         font-embolden? font-set-embolden!
         font-get-metrics font-metrics?
         font-metrics-top font-metrics-ascent font-metrics-descent
         font-metrics-bottom font-metrics-leading
         font-metrics-average-character-width font-metrics-max-character-width
         font-metrics-x-min font-metrics-x-max font-metrics-x-height
         font-metrics-cap-height font-metrics-underline-thickness
         font-metrics-underline-position font-metrics-strikeout-thickness
         font-metrics-strikeout-position font-metrics-spacing
         draw-simple-text measure-simple-text simple-text-bounds
         font-text->glyphs font-char->glyph font-glyph-path simple-text-path)

(struct surface (handle width height [floors #:mutable])
  #:constructor-name make-surface-record)
;; A canvas is always borrowed from an owning surface or picture recorder.
(struct canvas (resource) #:constructor-name make-canvas-record)
(struct paint (handle) #:constructor-name make-paint-record)
(struct shader (handle) #:constructor-name make-shader-record)
(struct path-effect (handle) #:constructor-name make-path-effect-record)
(struct color-filter (handle) #:constructor-name make-color-filter-record)
(struct mask-filter (handle) #:constructor-name make-mask-filter-record)
(struct image-filter (handle) #:constructor-name make-image-filter-record)
(struct picture (handle width height) #:constructor-name make-picture-record)
(struct picture-recorder (handle [recording? #:mutable] [canvas-ptr #:mutable]
                                 [bounds #:mutable] [floors #:mutable])
  #:constructor-name make-picture-recorder-record)
(struct skia-path (handle) #:constructor-name make-path-record)
;; snapshot-box contains a raw native SkPath pointer owned together with the
;; native SkPathMeasure. It is never exposed by the public API.
(struct path-measure (handle snapshot-box) #:constructor-name make-path-measure-record)
(struct image (handle width height) #:constructor-name make-image-record)
(struct encoded-image-info
  (width height format color-type alpha-type origin frame-count)
  #:transparent
  #:constructor-name make-encoded-image-info-record)
(struct typeface (handle) #:constructor-name make-typeface-record)
;; owner keeps an implicitly-created default typeface reachable for at least
;; as long as the font wrapper. SkFont itself also retains its typeface.
(struct font (handle owner) #:constructor-name make-font-record)
(struct font-metrics
  (top ascent descent bottom leading
   average-character-width max-character-width
   x-min x-max x-height cap-height
   underline-thickness underline-position
   strikeout-thickness strikeout-position spacing)
  #:transparent)

(define (skia-resource? v)
  (or (surface? v) (paint? v) (shader? v) (path-effect? v)
      (color-filter? v) (mask-filter? v) (image-filter? v)
      (picture? v) (picture-recorder? v)
      (skia-path? v) (path-measure? v) (image? v)
      (typeface? v) (font? v)))

(define (resource-handle who v)
  (cond [(surface? v) (surface-handle v)]
        [(paint? v) (paint-handle v)]
        [(shader? v) (shader-handle v)]
        [(path-effect? v) (path-effect-handle v)]
        [(color-filter? v) (color-filter-handle v)]
        [(mask-filter? v) (mask-filter-handle v)]
        [(image-filter? v) (image-filter-handle v)]
        [(picture? v) (picture-handle v)]
        [(picture-recorder? v) (picture-recorder-handle v)]
        [(skia-path? v) (skia-path-handle v)]
        [(path-measure? v) (path-measure-handle v)]
        [(image? v) (image-handle v)]
        [(typeface? v) (typeface-handle v)]
        [(font? v) (font-handle v)]
        [else (raise-argument-error who "skia-resource? (not a borrowed canvas)" v)]))

(define (skia-closed? v)
  (owned-closed?
   (if (canvas? v)
       (resource-handle 'skia-closed? (canvas-owner 'skia-closed? v))
       (resource-handle 'skia-closed? v))))

(define (skia-close! v)
  (owned-close! 'skia-close! (resource-handle 'skia-close! v))
  ;; A font created without an explicit typeface owns a private default
  ;; typeface wrapper as well. Close that wrapper deterministically after
  ;; closing the font; explicit user-supplied typefaces are never closed here.
  (when (and (font? v) (font-owner v))
    (owned-close! 'skia-close! (typeface-handle (font-owner v)))))

(define (call-with-skia-resource v proc)
  (resource-handle 'call-with-skia-resource v)
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error 'call-with-skia-resource "procedure accepting one argument" proc))
  (call-with-scoped-resource v skia-close! proc))

(define-syntax with-skia
  (syntax-rules ()
    [(_ () body ...) (let () body ...)]
    [(_ ([id expression] rest ...) body ...)
     (call-with-skia-resource expression
       (lambda (id) (with-skia (rest ...) body ...)))]))

(define (typed-handle who v pred accessor description)
  (unless (pred v) (raise-argument-error who description v))
  (accessor v))
(define (surface-h who v) (typed-handle who v surface? surface-handle "surface?"))
(define (paint-h who v) (typed-handle who v paint? paint-handle "paint?"))
(define (shader-h who v) (typed-handle who v shader? shader-handle "shader?"))
(define (path-effect-h who v)
  (typed-handle who v path-effect? path-effect-handle "path-effect?"))
(define (color-filter-h who v)
  (typed-handle who v color-filter? color-filter-handle "color-filter?"))
(define (mask-filter-h who v)
  (typed-handle who v mask-filter? mask-filter-handle "mask-filter?"))
(define (image-filter-h who v)
  (typed-handle who v image-filter? image-filter-handle "image-filter?"))
(define (picture-h who v) (typed-handle who v picture? picture-handle "picture?"))
(define (picture-recorder-h who v)
  (typed-handle who v picture-recorder? picture-recorder-handle "picture-recorder?"))
(define (path-h who v) (typed-handle who v skia-path? skia-path-handle "skia-path?"))
(define (path-measure-h who v)
  (typed-handle who v path-measure? path-measure-handle "path-measure?"))
(define (image-h who v) (typed-handle who v image? image-handle "image?"))
(define (typeface-h who v) (typed-handle who v typeface? typeface-handle "typeface?"))
(define (font-h who v) (typed-handle who v font? font-handle "font?"))

(define (canvas-owner who c)
  (unless (canvas? c) (raise-argument-error who "canvas?" c))
  (define owner (canvas-resource c))
  (unless (or (surface? owner) (picture-recorder? owner))
    (error who "canvas owner is corrupted"))
  owner)

(define (owner-floors owner)
  (cond [(surface? owner) (surface-floors owner)]
        [(picture-recorder? owner) (picture-recorder-floors owner)]
        [else (error 'owner-floors "unsupported owner")]))

(define (set-owner-floors! owner floors)
  (cond [(surface? owner) (set-surface-floors! owner floors)]
        [(picture-recorder? owner) (set-picture-recorder-floors! owner floors)]
        [else (error 'set-owner-floors! "unsupported owner")]))

(define (call-on-canvas who c others proc)
  (define owner (canvas-owner who c))
  (call-with-owned
   who (cons (resource-handle who owner) others)
   (lambda (op . ps)
     (define cp
       (cond
         [(surface? owner)
          (define ptr (sk_surface_get_canvas op))
          (unless ptr (error who "native surface returned a null canvas"))
          ptr]
         [(picture-recorder? owner)
          (unless (picture-recorder-recording? owner)
            (error who "picture recorder is not currently recording"))
          (define ptr (picture-recorder-canvas-ptr owner))
          (unless ptr (error who "picture recorder has no active canvas"))
          ptr]
         [else (error who "unsupported canvas owner")]))
     (apply proc cp ps))))

(define (initialize-resource v proc)
  (with-handlers ([exn? (lambda (e) (skia-close! v) (raise e))])
    (proc v)
    v))

;; Surfaces -----------------------------------------------------------------

(define (make-surface w h #:background [background 'transparent])
  (check-dimensions 'make-surface w h)
  (define argb (color->argb background))
  (skia-check!)
  (define hnd
    (new-owned 'make-surface 'surface
               (lambda ()
                 (sk_surface_new_raster
                  (make-sk-image-info #f w h rgba-8888 alpha-premul) 0 #f))
               sk_surface_unref))
  (initialize-resource
   (make-surface-record hnd w h '())
   (lambda (s) (canvas-clear! (surface-canvas s) argb))))

(define (surface-canvas s)
  (call-with-owned 'surface-canvas (list (surface-h 'surface-canvas s))
                   (lambda (_) (make-canvas-record s))))

;; Pictures and recording ---------------------------------------------------

(define (make-picture-recorder)
  (skia-check!)
  (make-picture-recorder-record
   (new-owned 'make-picture-recorder 'picture-recorder
              sk_picture_recorder_new
              sk_picture_recorder_delete)
   #f #f #f '()))

(define (picture-recorder-begin-recording! recorder x y w h)
  (define who 'picture-recorder-begin-recording!)
  (define rr
    (if (picture-recorder? recorder)
        recorder
        (raise-argument-error who "picture-recorder?" recorder)))
  (when (picture-recorder-recording? rr)
    (error who "picture recorder is already recording"))
  (define bounds (rect who x y w h))
  (call-with-owned
   who (list (picture-recorder-h who rr))
   (lambda (rp)
     (define cp (sk_picture_recorder_begin_recording rp bounds))
     (unless cp
       (error who "native picture recorder did not return a canvas"))
     (set-picture-recorder-recording?! rr #t)
     (set-picture-recorder-canvas-ptr! rr cp)
     (set-picture-recorder-bounds! rr (list (sk-rect-left bounds)
                                            (sk-rect-top bounds)
                                            (- (sk-rect-right bounds) (sk-rect-left bounds))
                                            (- (sk-rect-bottom bounds) (sk-rect-top bounds))))
     (set-picture-recorder-floors! rr '())
     (make-canvas-record rr))))

(define (picture-recorder-finish-recording! recorder)
  (define who 'picture-recorder-finish-recording!)
  (define rr
    (if (picture-recorder? recorder)
        recorder
        (raise-argument-error who "picture-recorder?" recorder)))
  (unless (picture-recorder-recording? rr)
    (error who "picture recorder is not currently recording"))
  (define bounds (or (picture-recorder-bounds rr) '(0.0 0.0 0.0 0.0)))
  (call-with-owned
   who (list (picture-recorder-h who rr))
   (lambda (rp)
     (define pp (sk_picture_recorder_end_recording rp))
     (set-picture-recorder-recording?! rr #f)
     (set-picture-recorder-canvas-ptr! rr #f)
     (set-picture-recorder-floors! rr '())
     (unless pp
       (error who "native picture recording did not produce a picture"))
     (make-picture-record
      (new-owned who 'picture (lambda () pp) sk_picture_unref)
      (list-ref bounds 2) (list-ref bounds 3)))))

(define (call-with-picture w h proc)
  (define who 'call-with-picture)
  (check-dimensions who w h)
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error who "procedure accepting one argument" proc))
  (call-with-skia-resource
   (make-picture-recorder)
   (lambda (rec)
     (define c (picture-recorder-begin-recording! rec 0 0 w h))
     (proc c)
     (picture-recorder-finish-recording! rec))))

(define (surface->rgba-bytes s #:premultiplied? [premultiplied? #f])
  (define hnd (surface-h 'surface->rgba-bytes s))
  (boolean 'surface->rgba-bytes premultiplied?)
  (define w (surface-width s))
  (define h (surface-height s))
  (define out (make-bytes (check-dimensions 'surface->rgba-bytes w h)))
  (call-with-owned
   'surface->rgba-bytes (list hnd)
   (lambda (sp)
     (unless (sk_surface_read_pixels
              sp (make-sk-image-info #f w h rgba-8888
                                     (if premultiplied? alpha-premul alpha-unpremul))
              out (* 4 w) 0 0)
       (error 'surface->rgba-bytes "native pixel read failed"))))
  out)

(define (surface-pixel s x y)
  (define hnd (surface-h 'surface-pixel s))
  (unless (and (exact-integer? x) (<= 0 x) (< x (surface-width s))
               (exact-integer? y) (<= 0 y) (< y (surface-height s)))
    (raise-arguments-error 'surface-pixel "pixel coordinates are outside the surface"
                           "x" x "y" y
                           "width" (surface-width s) "height" (surface-height s)))
  (define out (make-bytes 4))
  (call-with-owned
   'surface-pixel (list hnd)
   (lambda (sp)
     (unless (sk_surface_read_pixels
              sp (make-sk-image-info #f 1 1 rgba-8888 alpha-unpremul) out 4 x y)
       (error 'surface-pixel "native pixel read failed"))))
  (rgba (bytes-ref out 0) (bytes-ref out 1) (bytes-ref out 2) (bytes-ref out 3)))

(define (call-with-native-temporary who kind create release proc)
  (define hnd (new-owned who kind create release))
  (call-with-scoped-resource
   hnd (lambda (h) (owned-close! who h))
   (lambda (h) (call-with-owned who (list h) proc))))

(define (surface->png-bytes s #:compression [compression 6])
  (define who 'surface->png-bytes)
  (define hnd (surface-h who s))
  (unless (and (exact-integer? compression) (<= 0 compression 9))
    (raise-argument-error who "exact integer from 0 through 9" compression))
  (define options (make-sk-png-options png-all-filters compression #f #f #f))
  (call-with-owned
   who (list hnd)
   (lambda (sp)
     ;; The pixmap borrows the surface's pixels only within this call.
     (call-with-native-temporary
      who 'pixmap sk_pixmap_new sk_pixmap_destructor
      (lambda (pixmap)
        (unless (sk_surface_peek_pixels sp pixmap)
          (error who "CPU surface did not expose its pixels"))
        (call-with-native-temporary
         who 'png-stream sk_dynamicmemorywstream_new sk_dynamicmemorywstream_destroy
         (lambda (stream)
           (unless (sk_pngencoder_encode stream pixmap options)
             (error who "native PNG encoder failed"))
           (call-with-native-temporary
            who 'encoded-data
            (lambda () (sk_dynamicmemorywstream_detach_as_data stream)) sk_data_unref
            (lambda (data)
              (define n (sk_data_get_size data))
              (unless (<= 1 n (current-skia-byte-limit))
                (error who "encoded PNG size ~a exceeds the byte limit, or is empty" n))
              (define src (sk_data_get_data data))
              (unless src (error who "encoded PNG returned a null data pointer"))
              (define out (make-bytes n))
              ;; make-sized-byte-string is intentionally avoided: it is not
              ;; supported by Racket CS. Copy into an ordinary Racket byte string.
              (memcpy out src n)
              out)))))))))

(define (save-png s filename #:exists [exists 'error] #:compression [compression 6])
  (unless (path-string? filename)
    (raise-argument-error 'save-png "path-string?" filename))
  (unless (memq exists '(error replace))
    (raise-argument-error 'save-png "'error or 'replace" exists))
  ;; Encode before opening the destination, so native errors do not truncate it.
  (define data (surface->png-bytes s #:compression compression))
  (call-with-output-file filename
    (lambda (out) (write-bytes data out) (void))
    #:mode 'binary #:exists exists))

;; Paint --------------------------------------------------------------------

(define (make-paint #:color [color 'black]
                    #:style [style 'fill]
                    #:stroke-width [width 1]
                    #:antialias? [antialias? #t]
                    #:cap [cap 'butt]
                    #:join [join 'miter]
                    #:miter-limit [miter 4]
                    #:blend-mode [blend 'src-over]
                    #:shader [sh #f]
                    #:path-effect [effect #f]
                    #:color-filter [cf #f]
                    #:mask-filter [mf #f]
                    #:image-filter [imf #f])
  ;; Validate every option before allocating native state.
  (define col (color->argb color))
  (define sty (choice 'make-paint style style-values))
  (define wid (nonnegative-scalar 'make-paint width))
  (define aa (boolean 'make-paint antialias?))
  (define ca (choice 'make-paint cap cap-values))
  (define jo (choice 'make-paint join join-values))
  (define mi (nonnegative-scalar 'make-paint miter))
  (define bl (choice 'make-paint blend blend-values))
  (unless (or (not sh) (shader? sh))
    (raise-argument-error 'make-paint "(or/c #f shader?)" sh))
  (unless (or (not effect) (path-effect? effect))
    (raise-argument-error 'make-paint "(or/c #f path-effect?)" effect))
  (unless (or (not cf) (color-filter? cf))
    (raise-argument-error 'make-paint "(or/c #f color-filter?)" cf))
  (unless (or (not mf) (mask-filter? mf))
    (raise-argument-error 'make-paint "(or/c #f mask-filter?)" mf))
  (unless (or (not imf) (image-filter? imf))
    (raise-argument-error 'make-paint "(or/c #f image-filter?)" imf))
  (define sh-hnd (and sh (shader-h 'make-paint sh)))
  (define effect-hnd (and effect (path-effect-h 'make-paint effect)))
  (define cf-hnd (and cf (color-filter-h 'make-paint cf)))
  (define mf-hnd (and mf (mask-filter-h 'make-paint mf)))
  (define imf-hnd (and imf (image-filter-h 'make-paint imf)))
  (skia-check!)
  (define hnd (new-owned 'make-paint 'paint sk_paint_new sk_paint_delete))
  (initialize-resource
   (make-paint-record hnd)
   (lambda (_)
     (define handles
       (append (list hnd)
               (if sh-hnd (list sh-hnd) '())
               (if effect-hnd (list effect-hnd) '())
               (if cf-hnd (list cf-hnd) '())
               (if mf-hnd (list mf-hnd) '())
               (if imf-hnd (list imf-hnd) '())))
     (call-with-owned
      'make-paint handles
      (lambda (p . optional-pointers)
        (sk_paint_set_color p col)
        (sk_paint_set_style p sty)
        (sk_paint_set_stroke_width p wid)
        (sk_paint_set_antialias p aa)
        (sk_paint_set_stroke_cap p ca)
        (sk_paint_set_stroke_join p jo)
        (sk_paint_set_stroke_miter p mi)
        (sk_paint_set_blendmode p bl)
        (define remaining optional-pointers)
        (when sh-hnd
          (sk_paint_set_shader p (car remaining))
          (set! remaining (cdr remaining)))
        (when effect-hnd
          (sk_paint_set_path_effect p (car remaining))
          (set! remaining (cdr remaining)))
        (when cf-hnd
          (sk_paint_set_colorfilter p (car remaining))
          (set! remaining (cdr remaining)))
        (when mf-hnd
          (sk_paint_set_maskfilter p (car remaining))
          (set! remaining (cdr remaining)))
        (when imf-hnd
          (sk_paint_set_imagefilter p (car remaining))))))))

(define (paint-copy p)
  (call-with-owned 'paint-copy (list (paint-h 'paint-copy p))
    (lambda (ptr)
      (make-paint-record
       (new-owned 'paint-copy 'paint (lambda () (sk_paint_clone ptr)) sk_paint_delete)))))

(define (paint-color p)
  (color->rgba
   (call-with-owned 'paint-color (list (paint-h 'paint-color p)) sk_paint_get_color)))

(define (paint-shader p)
  (define who 'paint-shader)
  (call-with-owned
   who (list (paint-h who p))
   (lambda (pp)
     ;; The m119 C shim uses refShader().release(), so this is already one
     ;; owned reference. Wrapping it directly avoids an extra leaked ref.
     (define sp (sk_paint_get_shader pp))
     (and sp
          (make-shader-record
           (new-owned who 'shader (lambda () sp) sk_shader_unref))))))

(define (paint-path-effect p)
  (define who 'paint-path-effect)
  (call-with-owned
   who (list (paint-h who p))
   (lambda (pp)
     ;; Like sk_paint_get_shader, the C shim returns one owned reference.
     (define ep (sk_paint_get_path_effect pp))
     (and ep
          (make-path-effect-record
           (new-owned who 'path-effect (lambda () ep) sk_path_effect_unref))))))

(define (paint-owned-filter who p native-get constructor kind release)
  (call-with-owned
   who (list (paint-h who p))
   (lambda (pp)
     ;; The m119 paint getters use ref...().release(), so a non-null result is
     ;; already one independently-owned native reference.
     (define fp (native-get pp))
     (and fp
          (constructor (new-owned who kind (lambda () fp) release))))))

(define (paint-color-filter p)
  (paint-owned-filter 'paint-color-filter p sk_paint_get_colorfilter
                      make-color-filter-record 'color-filter sk_colorfilter_unref))
(define (paint-mask-filter p)
  (paint-owned-filter 'paint-mask-filter p sk_paint_get_maskfilter
                      make-mask-filter-record 'mask-filter sk_maskfilter_unref))
(define (paint-image-filter p)
  (paint-owned-filter 'paint-image-filter p sk_paint_get_imagefilter
                      make-image-filter-record 'image-filter sk_imagefilter_unref))

(define (set-paint-value! who p value native-setter)
  (call-with-owned who (list (paint-h who p))
    (lambda (ptr) (native-setter ptr value))))
(define (paint-set-color! p c)
  (set-paint-value! 'paint-set-color! p (color->argb c) sk_paint_set_color))
(define (paint-set-style! p v)
  (set-paint-value! 'paint-set-style! p
                    (choice 'paint-set-style! v style-values) sk_paint_set_style))
(define (paint-set-stroke-width! p v)
  (set-paint-value! 'paint-set-stroke-width! p
                    (nonnegative-scalar 'paint-set-stroke-width! v) sk_paint_set_stroke_width))
(define (paint-set-antialias! p v)
  (set-paint-value! 'paint-set-antialias! p
                    (boolean 'paint-set-antialias! v) sk_paint_set_antialias))
(define (paint-set-cap! p v)
  (set-paint-value! 'paint-set-cap! p
                    (choice 'paint-set-cap! v cap-values) sk_paint_set_stroke_cap))
(define (paint-set-join! p v)
  (set-paint-value! 'paint-set-join! p
                    (choice 'paint-set-join! v join-values) sk_paint_set_stroke_join))
(define (paint-set-miter-limit! p v)
  (set-paint-value! 'paint-set-miter-limit! p
                    (nonnegative-scalar 'paint-set-miter-limit! v) sk_paint_set_stroke_miter))
(define (paint-set-blend-mode! p v)
  (set-paint-value! 'paint-set-blend-mode! p
                    (choice 'paint-set-blend-mode! v blend-values) sk_paint_set_blendmode))

(define (paint-set-shader! p sh)
  (define who 'paint-set-shader!)
  (unless (or (not sh) (shader? sh))
    (raise-argument-error who "(or/c #f shader?)" sh))
  (cond
    [sh
     (call-with-owned who (list (paint-h who p) (shader-h who sh))
       (lambda (pp sp) (sk_paint_set_shader pp sp)))]
    [else
     (call-with-owned who (list (paint-h who p))
       (lambda (pp) (sk_paint_set_shader pp #f)))]))

(define (paint-set-path-effect! p effect)
  (define who 'paint-set-path-effect!)
  (unless (or (not effect) (path-effect? effect))
    (raise-argument-error who "(or/c #f path-effect?)" effect))
  (cond
    [effect
     (call-with-owned who (list (paint-h who p) (path-effect-h who effect))
       (lambda (pp ep) (sk_paint_set_path_effect pp ep)))]
    [else
     (call-with-owned who (list (paint-h who p))
       (lambda (pp) (sk_paint_set_path_effect pp #f)))]))

(define (set-paint-filter! who p value pred get-handle description native-setter)
  (unless (or (not value) (pred value))
    (raise-argument-error who description value))
  (cond
    [value
     (call-with-owned who (list (paint-h who p) (get-handle who value))
       (lambda (pp fp) (native-setter pp fp)))]
    [else
     (call-with-owned who (list (paint-h who p))
       (lambda (pp) (native-setter pp #f)))]))

(define (paint-set-color-filter! p cf)
  (set-paint-filter! 'paint-set-color-filter! p cf color-filter? color-filter-h
                     "(or/c #f color-filter?)" sk_paint_set_colorfilter))
(define (paint-set-mask-filter! p mf)
  (set-paint-filter! 'paint-set-mask-filter! p mf mask-filter? mask-filter-h
                     "(or/c #f mask-filter?)" sk_paint_set_maskfilter))
(define (paint-set-image-filter! p imf)
  (set-paint-filter! 'paint-set-image-filter! p imf image-filter? image-filter-h
                     "(or/c #f image-filter?)" sk_paint_set_imagefilter))

;; Shaders and gradients ----------------------------------------------------

(define (gradient-sequence who value description)
  (cond [(list? value) value]
        [(vector? value) (vector->list value)]
        [else (raise-argument-error who description value)]))

(define (checked-gradient-stops who colors positions)
  (define color-list
    (gradient-sequence who colors "(or/c list? vector?) for gradient colors"))
  (unless (>= (length color-list) 2)
    (raise-arguments-error who "a gradient requires at least two colors"
                           "colors" colors))
  (define packed-colors (for/list ([c (in-list color-list)]) (color->argb c)))
  (define position-list
    (and positions
         (gradient-sequence who positions
                            "(or/c #f list? vector?) for gradient positions")))
  (when (and position-list (not (= (length position-list) (length color-list))))
    (raise-arguments-error who "colors and positions must have the same length"
                           "color count" (length color-list)
                           "position count" (length position-list)))
  (define checked-positions
    (and position-list
         (for/list ([pos (in-list position-list)])
           (define f (scalar who pos))
           (unless (<= 0.0 f 1.0)
             (raise-arguments-error who "gradient positions must be between 0 and 1"
                                    "position" pos))
           f)))
  (when checked-positions
    (for ([a (in-list checked-positions)]
          [b (in-list (cdr checked-positions))])
      (when (> a b)
        (raise-arguments-error who "gradient positions must be nondecreasing"
                               "positions" positions))))
  (define native-bytes
    (* 4 (+ (length packed-colors)
            (if checked-positions (length checked-positions) 0))))
  (unless (<= native-bytes (current-skia-byte-limit))
    (raise-arguments-error who "gradient stop arrays exceed current-skia-byte-limit"
                           "required native bytes" native-bytes
                           "limit" (current-skia-byte-limit)))
  (values packed-colors checked-positions))

(define (native-array values type)
  (define out (malloc (length values) type 'atomic))
  (for ([v (in-list values)] [i (in-naturals)])
    (ptr-set! out type i v))
  out)

(define (gradient-native-arrays colors positions)
  (values (native-array colors _uint32)
          (and positions (native-array positions _float))))

(define (new-shader who create)
  (skia-check!)
  (make-shader-record (new-owned who 'shader create sk_shader_unref)))

(define (make-color-shader color)
  (define argb (color->argb color))
  (new-shader 'make-color-shader (lambda () (sk_shader_new_color argb))))

(define (make-linear-gradient-shader x0 y0 x1 y1 colors
                                     #:positions [positions #f]
                                     #:tile-mode [tile-mode 'clamp])
  (define who 'make-linear-gradient-shader)
  (define fx0 (scalar who x0))
  (define fy0 (scalar who y0))
  (define fx1 (scalar who x1))
  (define fy1 (scalar who y1))
  (when (and (= fx0 fx1) (= fy0 fy1))
    (raise-arguments-error who "gradient endpoints must be distinct"
                           "start" (list x0 y0) "end" (list x1 y1)))
  (define tile (choice who tile-mode tile-mode-values))
  (define-values (packed pos) (checked-gradient-stops who colors positions))
  ;; sk_point_t is exactly two floats; two points are therefore four
  ;; contiguous floats at this ABI boundary.
  (define points (native-array (list fx0 fy0 fx1 fy1) _float))
  (define-values (native-colors native-pos) (gradient-native-arrays packed pos))
  (new-shader
   who
   (lambda ()
     (sk_shader_new_linear_gradient points native-colors native-pos
                                    (length packed) tile #f))))

(define (make-radial-gradient-shader cx cy radius colors
                                     #:positions [positions #f]
                                     #:tile-mode [tile-mode 'clamp])
  (define who 'make-radial-gradient-shader)
  (define center (make-sk-point (scalar who cx) (scalar who cy)))
  (define r (positive-scalar who radius))
  (define tile (choice who tile-mode tile-mode-values))
  (define-values (packed pos) (checked-gradient-stops who colors positions))
  (define-values (native-colors native-pos) (gradient-native-arrays packed pos))
  (new-shader
   who
   (lambda ()
     (sk_shader_new_radial_gradient center r native-colors native-pos
                                    (length packed) tile #f))))

(define (make-sweep-gradient-shader cx cy colors
                                    #:positions [positions #f]
                                    #:tile-mode [tile-mode 'clamp]
                                    #:start-angle [start-angle 0]
                                    #:end-angle [end-angle 360])
  (define who 'make-sweep-gradient-shader)
  (define center (make-sk-point (scalar who cx) (scalar who cy)))
  (define start (scalar who start-angle))
  (define end (scalar who end-angle))
  (unless (< start end)
    (raise-arguments-error who "start angle must be less than end angle"
                           "start-angle" start-angle "end-angle" end-angle))
  (define tile (choice who tile-mode tile-mode-values))
  (define-values (packed pos) (checked-gradient-stops who colors positions))
  (define-values (native-colors native-pos) (gradient-native-arrays packed pos))
  (new-shader
   who
   (lambda ()
     (sk_shader_new_sweep_gradient center native-colors native-pos
                                   (length packed) tile start end #f))))

(define (make-two-point-conical-gradient-shader x0 y0 radius0 x1 y1 radius1 colors
                                                #:positions [positions #f]
                                                #:tile-mode [tile-mode 'clamp])
  (define who 'make-two-point-conical-gradient-shader)
  (define fx0 (scalar who x0))
  (define fy0 (scalar who y0))
  (define fx1 (scalar who x1))
  (define fy1 (scalar who y1))
  (define r0 (nonnegative-scalar who radius0))
  (define r1 (nonnegative-scalar who radius1))
  (when (and (= fx0 fx1) (= fy0 fy1) (= r0 r1))
    (raise-arguments-error who "the two gradient circles must differ"
                           "first circle" (list x0 y0 radius0)
                           "second circle" (list x1 y1 radius1)))
  (define start (make-sk-point fx0 fy0))
  (define end (make-sk-point fx1 fy1))
  (define tile (choice who tile-mode tile-mode-values))
  (define-values (packed pos) (checked-gradient-stops who colors positions))
  (define-values (native-colors native-pos) (gradient-native-arrays packed pos))
  (new-shader
   who
   (lambda ()
     (sk_shader_new_two_point_conical_gradient
      start r0 end r1 native-colors native-pos (length packed) tile #f))))

(define (make-image-shader im
                           #:tile-x [tile-x 'clamp]
                           #:tile-y [tile-y 'clamp]
                           #:sampling [mode 'nearest])
  (define who 'make-image-shader)
  (define ih (image-h who im))
  (define tx (choice who tile-x tile-mode-values))
  (define ty (choice who tile-y tile-mode-values))
  (define smp (sampling who mode))
  (skia-check!)
  (call-with-owned
   who (list ih)
   (lambda (ip)
     (make-shader-record
      (new-owned who 'shader
                 (lambda () (sk_image_make_shader ip tx ty smp #f))
                 sk_shader_unref)))))

(define (make-blend-shader mode destination source)
  (define who 'make-blend-shader)
  (define blend (choice who mode blend-values))
  (define dh (shader-h who destination))
  (define sh (shader-h who source))
  (skia-check!)
  (call-with-owned
   who (list dh sh)
   (lambda (dp sp)
     (make-shader-record
      (new-owned who 'shader
                 (lambda () (sk_shader_new_blend blend dp sp))
                 sk_shader_unref)))))

;; Path effects -------------------------------------------------------------

(define (new-path-effect who create)
  (skia-check!)
  (make-path-effect-record
   (new-owned who 'path-effect create sk_path_effect_unref)))

(define (path-effect-sequence who intervals)
  (define xs
    (cond [(list? intervals) intervals]
          [(vector? intervals) (vector->list intervals)]
          [else (raise-argument-error who "(or/c list? vector?)" intervals)]))
  (unless (and (>= (length xs) 2) (even? (length xs)))
    (raise-arguments-error who
                           "dash intervals must contain an even number of entries, at least two"
                           "intervals" intervals))
  (define checked (for/list ([x (in-list xs)]) (nonnegative-scalar who x)))
  (unless (positive? (apply + checked))
    (raise-arguments-error who "dash intervals must not all be zero"
                           "intervals" intervals))
  (define native-bytes (* 4 (length checked)))
  (unless (<= native-bytes (current-skia-byte-limit))
    (raise-arguments-error who "dash interval array exceeds current-skia-byte-limit"
                           "required native bytes" native-bytes
                           "limit" (current-skia-byte-limit)))
  checked)

(define (make-dash-path-effect intervals [phase 0])
  (define who 'make-dash-path-effect)
  (define checked (path-effect-sequence who intervals))
  (define ph (scalar who phase))
  (define arr (native-array checked _float))
  (new-path-effect who
                   (lambda ()
                     (sk_path_effect_create_dash arr (length checked) ph))))

(define (make-corner-path-effect radius)
  (define who 'make-corner-path-effect)
  (define r (positive-scalar who radius))
  (new-path-effect who (lambda () (sk_path_effect_create_corner r))))

(define (make-discrete-path-effect segment-length deviation [seed 0])
  (define who 'make-discrete-path-effect)
  (define seg (positive-scalar who segment-length))
  ;; SkDiscretePathEffect::Make rejects lengths <= SK_ScalarNearlyZero
  ;; (1/4096), so reject them here rather than surfacing a native-null error.
  (unless (> seg (/ 1.0 4096.0))
    (raise-argument-error who "finite real greater than 1/4096" segment-length))
  (define dev (nonnegative-scalar who deviation))
  (define sd (uint32 who seed))
  (new-path-effect who
                   (lambda () (sk_path_effect_create_discrete seg dev sd))))

(define (make-trim-path-effect start stop #:mode [mode 'normal])
  (define who 'make-trim-path-effect)
  (define a (scalar who start))
  (define b (scalar who stop))
  (unless (and (<= 0.0 a 1.0) (<= 0.0 b 1.0) (< a b))
    (raise-arguments-error who
                           "start and stop must satisfy 0 <= start < stop <= 1"
                           "start" start "stop" stop))
  (define m (choice who mode trim-path-effect-mode-values))
  ;; Upstream treats the full normal span as a no-op and returns NULL rather
  ;; than a path-effect object. Keep the public constructor total over its
  ;; documented domain by rejecting that no-op explicitly.
  (when (and (= m 0) (= a 0.0) (= b 1.0))
    (raise-arguments-error who
                           "the full normal interval is a no-op, not a native path effect"
                           "start" start "stop" stop "mode" mode))
  (new-path-effect who (lambda () (sk_path_effect_create_trim a b m))))

(define (make-compose-path-effect outer inner)
  (define who 'make-compose-path-effect)
  (define oh (path-effect-h who outer))
  (define ih (path-effect-h who inner))
  (new-path-effect
   who
   (lambda ()
     (call-with-owned who (list oh ih)
       (lambda (op ip) (sk_path_effect_create_compose op ip))))))

(define (make-sum-path-effect first second)
  (define who 'make-sum-path-effect)
  (define fh (path-effect-h who first))
  (define sh (path-effect-h who second))
  (new-path-effect
   who
   (lambda ()
     (call-with-owned who (list fh sh)
       (lambda (fp sp) (sk_path_effect_create_sum fp sp))))))

;; Color, mask, and image filters ------------------------------------------

(define (filter-sequence who value count description)
  (define xs
    (cond [(list? value) value]
          [(vector? value) (vector->list value)]
          [else (raise-argument-error who "(or/c list? vector?)" value)]))
  (unless (= (length xs) count)
    (raise-arguments-error who description
                           "required entries" count "given entries" (length xs)))
  (for/list ([x (in-list xs)]) (scalar who x)))

(define (new-color-filter who create)
  (skia-check!)
  (make-color-filter-record
   (new-owned who 'color-filter create sk_colorfilter_unref)))

(define (make-color-matrix-filter matrix)
  (define who 'make-color-matrix-filter)
  (define values
    (filter-sequence who matrix 20
                     "a color matrix must contain exactly 20 finite real values"))
  (define native (native-array values _float))
  (new-color-filter who (lambda () (sk_colorfilter_new_color_matrix native))))

(define (make-blend-color-filter color mode)
  (define who 'make-blend-color-filter)
  (define argb (color->argb color))
  (define blend (choice who mode blend-values))
  ;; SkColorFilters::Blend returns null for Dst because it is exactly the
  ;; identity operation, so represent that explicitly instead of reporting a
  ;; misleading allocation failure.
  (when (eq? mode 'dst)
    (raise-arguments-error who "'dst is a no-op and has no native color-filter object"
                           "mode" mode))
  (new-color-filter who (lambda () (sk_colorfilter_new_mode argb blend))))

(define (make-compose-color-filter outer inner)
  (define who 'make-compose-color-filter)
  (define oh (color-filter-h who outer))
  (define ih (color-filter-h who inner))
  (new-color-filter
   who
   (lambda ()
     (call-with-owned who (list oh ih)
       (lambda (op ip) (sk_colorfilter_new_compose op ip))))))

(define (new-mask-filter who create)
  (skia-check!)
  (make-mask-filter-record
   (new-owned who 'mask-filter create sk_maskfilter_unref)))

(define (make-blur-mask-filter sigma
                               #:style [style 'normal]
                               #:respect-ctm? [respect-ctm? #t])
  (define who 'make-blur-mask-filter)
  (define sig (positive-scalar who sigma))
  (define sty (choice who style blur-style-values))
  (define respect? (boolean who respect-ctm?))
  (new-mask-filter who
                   (lambda ()
                     (sk_maskfilter_new_blur_with_flags sty sig respect?))))

(define (new-image-filter who create)
  (skia-check!)
  (make-image-filter-record
   (new-owned who 'image-filter create sk_imagefilter_unref)))

(define (optional-image-filter-h who input)
  (unless (or (not input) (image-filter? input))
    (raise-argument-error who "(or/c #f image-filter?)" input))
  (and input (image-filter-h who input)))

(define (with-optional-image-input who input-h proc)
  (if input-h
      (call-with-owned who (list input-h) (lambda (ip) (proc ip)))
      (proc #f)))

(define (make-blur-image-filter sigma-x sigma-y
                                #:tile-mode [tile-mode 'decal]
                                #:input [input #f])
  (define who 'make-blur-image-filter)
  (define sx (nonnegative-scalar who sigma-x))
  (define sy (nonnegative-scalar who sigma-y))
  (when (and (zero? sx) (zero? sy))
    (raise-arguments-error who "at least one blur sigma must be positive"
                           "sigma-x" sigma-x "sigma-y" sigma-y))
  (define tile (choice who tile-mode tile-mode-values))
  ;; Upstream m119 explicitly documents mirror as unsupported for blur image
  ;; filters. Reject it instead of silently promising a tile behavior that the
  ;; pinned raster backend does not implement.
  (when (eq? tile-mode 'mirror)
    (raise-arguments-error who
                           "'mirror is not supported for blur image filters by the pinned m119 Skia"
                           "tile-mode" tile-mode))
  (define ih (optional-image-filter-h who input))
  (new-image-filter
   who
   (lambda ()
     (with-optional-image-input
      who ih
      (lambda (ip) (sk_imagefilter_new_blur sx sy tile ip #f))))))

(define (make-drop-shadow-filter who native-create dx dy sigma-x sigma-y color input)
  (define fdx (scalar who dx))
  (define fdy (scalar who dy))
  (define sx (nonnegative-scalar who sigma-x))
  (define sy (nonnegative-scalar who sigma-y))
  (define argb (color->argb color))
  (define ih (optional-image-filter-h who input))
  (new-image-filter
   who
   (lambda ()
     (with-optional-image-input
      who ih
      (lambda (ip) (native-create fdx fdy sx sy argb ip #f))))))

(define (make-drop-shadow-image-filter dx dy sigma-x sigma-y color
                                       #:input [input #f])
  (make-drop-shadow-filter 'make-drop-shadow-image-filter
                           sk_imagefilter_new_drop_shadow
                           dx dy sigma-x sigma-y color input))

(define (make-drop-shadow-only-image-filter dx dy sigma-x sigma-y color
                                            #:input [input #f])
  (make-drop-shadow-filter 'make-drop-shadow-only-image-filter
                           sk_imagefilter_new_drop_shadow_only
                           dx dy sigma-x sigma-y color input))

(define (make-color-filter-image-filter cf #:input [input #f])
  (define who 'make-color-filter-image-filter)
  (define ch (color-filter-h who cf))
  (define ih (optional-image-filter-h who input))
  (new-image-filter
   who
   (lambda ()
     (define handles (if ih (list ch ih) (list ch)))
     (call-with-owned
      who handles
      (lambda (cp . rest)
        (sk_imagefilter_new_color_filter cp (if ih (car rest) #f) #f))))))

(define (make-compose-image-filter outer inner)
  (define who 'make-compose-image-filter)
  (define oh (image-filter-h who outer))
  (define ih (image-filter-h who inner))
  (new-image-filter
   who
   (lambda ()
     (call-with-owned who (list oh ih)
       (lambda (op ip) (sk_imagefilter_new_compose op ip))))))

;; Canvas state -------------------------------------------------------------

(define (canvas-clear! c color)
  (define argb (color->argb color))
  (call-on-canvas 'canvas-clear! c '() (lambda (cp) (sk_canvas_clear cp argb))))
(define (canvas-save! c)
  (call-on-canvas 'canvas-save! c '() sk_canvas_save))
(define (canvas-save-count c)
  (call-on-canvas 'canvas-save-count c '() sk_canvas_get_save_count))

(define (restore-floor c)
  (define floors (owner-floors (canvas-owner 'restore-floor c)))
  (if (null? floors) 1 (car floors)))

(define (canvas-restore! c)
  (call-on-canvas
   'canvas-restore! c '()
   (lambda (cp)
     (unless (> (sk_canvas_get_save_count cp) (restore-floor c))
       (error 'canvas-restore! "cannot pop the base or a protected canvas state"))
     (sk_canvas_restore cp))))

(define (canvas-restore-to-count! c count)
  (unless (exact-positive-integer? count)
    (raise-argument-error 'canvas-restore-to-count! "exact-positive-integer?" count))
  (call-on-canvas
   'canvas-restore-to-count! c '()
   (lambda (cp)
     (define now (sk_canvas_get_save_count cp))
     (unless (<= (restore-floor c) count now)
       (raise-arguments-error 'canvas-restore-to-count! "invalid or protected save count"
                              "requested" count "minimum" (restore-floor c) "current" now))
     (sk_canvas_restore_to_count cp count))))

(define (call-with-canvas-state c thunk)
  (define s (canvas-owner 'call-with-canvas-state c))
  (unless (and (procedure? thunk) (procedure-arity-includes? thunk 0))
    (raise-argument-error 'call-with-canvas-state "procedure accepting zero arguments" thunk))
  (define old-count #f)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       (lambda ()
         (call-on-canvas
          'call-with-canvas-state c '()
          (lambda (cp)
            (set! old-count (sk_canvas_save cp))
            (set-owner-floors! s (cons (add1 old-count) (owner-floors s))))))
       thunk
       (lambda ()
         ;; Closing the owner in the body is permitted. Never touch a dangling
         ;; borrowed pointer during cleanup; the Racket bookkeeping still unwinds.
         (unless (skia-closed? s)
           (call-on-canvas 'call-with-canvas-state c '()
             (lambda (cp) (sk_canvas_restore_to_count cp old-count))))
         (set-owner-floors! s (cdr (owner-floors s))))))))

(define-syntax-rule (with-canvas-state c body ...)
  (call-with-canvas-state c (lambda () body ...)))

(define (canvas-translate! c x y)
  (define fx (scalar 'canvas-translate! x))
  (define fy (scalar 'canvas-translate! y))
  (call-on-canvas 'canvas-translate! c '() (lambda (cp) (sk_canvas_translate cp fx fy))))
(define (canvas-scale! c x [y x])
  (define fx (scalar 'canvas-scale! x))
  (define fy (scalar 'canvas-scale! y))
  (call-on-canvas 'canvas-scale! c '() (lambda (cp) (sk_canvas_scale cp fx fy))))
(define (canvas-rotate! c degrees)
  (define f (scalar 'canvas-rotate! degrees))
  (call-on-canvas 'canvas-rotate! c '() (lambda (cp) (sk_canvas_rotate_degrees cp f))))
(define (canvas-rotate-radians! c radians)
  (define f (scalar 'canvas-rotate-radians! radians))
  (call-on-canvas 'canvas-rotate-radians! c '() (lambda (cp) (sk_canvas_rotate_radians cp f))))
(define (canvas-skew! c x y)
  (define fx (scalar 'canvas-skew! x))
  (define fy (scalar 'canvas-skew! y))
  (call-on-canvas 'canvas-skew! c '() (lambda (cp) (sk_canvas_skew cp fx fy))))
(define (canvas-reset-transform! c)
  (call-on-canvas 'canvas-reset-transform! c '() sk_canvas_reset_matrix))

(define (canvas-clip-rect! c x y w h #:operation [operation 'intersect]
                           #:antialias? [antialias? #f])
  (define r (rect 'canvas-clip-rect! x y w h))
  (define op (choice 'canvas-clip-rect! operation clip-values))
  (boolean 'canvas-clip-rect! antialias?)
  (call-on-canvas 'canvas-clip-rect! c '()
    (lambda (cp) (sk_canvas_clip_rect_with_operation cp r op antialias?))))

(define (canvas-clip-path! c path #:operation [operation 'intersect]
                           #:antialias? [antialias? #f])
  (define hnd (path-h 'canvas-clip-path! path))
  (define op (choice 'canvas-clip-path! operation clip-values))
  (boolean 'canvas-clip-path! antialias?)
  (call-on-canvas 'canvas-clip-path! c (list hnd)
    (lambda (cp pp) (sk_canvas_clip_path_with_operation cp pp op antialias?))))

;; Drawing ------------------------------------------------------------------

(define (draw-paint c p)
  (call-on-canvas 'draw-paint c (list (paint-h 'draw-paint p)) sk_canvas_draw_paint))

(define (draw-line c x0 y0 x1 y1 p)
  (define coordinates (map (lambda (x) (scalar 'draw-line x)) (list x0 y0 x1 y1)))
  (call-on-canvas 'draw-line c (list (paint-h 'draw-line p))
    (lambda (cp pp) (apply sk_canvas_draw_line cp (append coordinates (list pp))))))

(define (draw-rect c x y w h p)
  (define r (rect 'draw-rect x y w h))
  (call-on-canvas 'draw-rect c (list (paint-h 'draw-rect p))
    (lambda (cp pp) (sk_canvas_draw_rect cp r pp))))

(define (draw-rounded-rect c x y w h rx ry p)
  (define r (rect 'draw-rounded-rect x y w h))
  (define frx (nonnegative-scalar 'draw-rounded-rect rx))
  (define fry (nonnegative-scalar 'draw-rounded-rect ry))
  (call-on-canvas 'draw-rounded-rect c (list (paint-h 'draw-rounded-rect p))
    (lambda (cp pp) (sk_canvas_draw_round_rect cp r frx fry pp))))

(define (draw-circle c x y radius p)
  (define fx (scalar 'draw-circle x))
  (define fy (scalar 'draw-circle y))
  (define fr (nonnegative-scalar 'draw-circle radius))
  (call-on-canvas 'draw-circle c (list (paint-h 'draw-circle p))
    (lambda (cp pp) (sk_canvas_draw_circle cp fx fy fr pp))))

(define (draw-oval c x y w h p)
  (define r (rect 'draw-oval x y w h))
  (call-on-canvas 'draw-oval c (list (paint-h 'draw-oval p))
    (lambda (cp pp) (sk_canvas_draw_oval cp r pp))))

(define (draw-path c path p)
  (call-on-canvas 'draw-path c (list (path-h 'draw-path path) (paint-h 'draw-path p))
                 sk_canvas_draw_path))

(define (draw-polygon c points p #:closed? [closed? #t])
  (boolean 'draw-polygon closed?)
  (unless (and (list? points) (pair? points))
    (raise-argument-error 'draw-polygon "nonempty list of (list x y) points" points))
  (define commands
    (for/list ([pt (in-list points)] [i (in-naturals)])
      (match pt
        [(list x y)
         (list (if (= i 0) 'move 'line) (scalar 'draw-polygon x) (scalar 'draw-polygon y))]
        [_ (raise-argument-error 'draw-polygon "(list x y) point" pt)])))
  (with-skia ([path (make-path (if closed? (append commands '((close))) commands))])
    (draw-path c path p)))

;; Paths --------------------------------------------------------------------

(define (make-path [commands '()] #:fill-rule [fill-rule 'winding])
  (unless (list? commands) (raise-argument-error 'make-path "list?" commands))
  (define fill (choice 'make-path fill-rule fill-values))
  (skia-check!)
  (define p (make-path-record (new-owned 'make-path 'path sk_path_new sk_path_delete)))
  (initialize-resource
   p
   (lambda (_)
     (call-with-owned 'make-path (list (skia-path-handle p))
       (lambda (pp) (sk_path_set_filltype pp fill)))
     (for ([command (in-list commands)])
       (match command
         [(list 'move x y) (path-move-to! p x y)]
         [(list 'line x y) (path-line-to! p x y)]
         [(list 'quad cx cy x y) (path-quad-to! p cx cy x y)]
         [(list 'cubic cx1 cy1 cx2 cy2 x y) (path-cubic-to! p cx1 cy1 cx2 cy2 x y)]
         [(list 'close) (path-close! p)]
         [_ (raise-arguments-error 'make-path "invalid path command"
                                    "command" command)])))))

(define (path-copy p)
  (call-with-owned 'path-copy (list (path-h 'path-copy p))
    (lambda (pp)
      (make-path-record
       (new-owned 'path-copy 'path (lambda () (sk_path_clone pp)) sk_path_delete)))))

(define (mutate-path! who p args native-op)
  (define vals (map (lambda (x) (scalar who x)) args))
  (call-with-owned who (list (path-h who p))
    (lambda (pp) (apply native-op pp vals))))
(define (path-move-to! p x y)
  (mutate-path! 'path-move-to! p (list x y) sk_path_move_to))
(define (path-rmove-to! p dx dy)
  (mutate-path! 'path-rmove-to! p (list dx dy) sk_path_rmove_to))
(define (path-line-to! p x y)
  (mutate-path! 'path-line-to! p (list x y) sk_path_line_to))
(define (path-rline-to! p dx dy)
  (mutate-path! 'path-rline-to! p (list dx dy) sk_path_rline_to))
(define (path-quad-to! p cx cy x y)
  (mutate-path! 'path-quad-to! p (list cx cy x y) sk_path_quad_to))
(define (path-rquad-to! p dcx dcy dx dy)
  (mutate-path! 'path-rquad-to! p (list dcx dcy dx dy) sk_path_rquad_to))
(define (path-conic-to! p cx cy x y weight)
  (mutate-path! 'path-conic-to! p (list cx cy x y weight) sk_path_conic_to))
(define (path-rconic-to! p dcx dcy dx dy weight)
  (mutate-path! 'path-rconic-to! p (list dcx dcy dx dy weight) sk_path_rconic_to))
(define (path-cubic-to! p cx1 cy1 cx2 cy2 x y)
  (mutate-path! 'path-cubic-to! p (list cx1 cy1 cx2 cy2 x y) sk_path_cubic_to))
(define (path-rcubic-to! p dcx1 dcy1 dcx2 dcy2 dx dy)
  (mutate-path! 'path-rcubic-to! p (list dcx1 dcy1 dcx2 dcy2 dx dy) sk_path_rcubic_to))
(define (path-close! p)
  (call-with-owned 'path-close! (list (path-h 'path-close! p)) sk_path_close))
(define (path-reset! p)
  ;; Skia resets the fill rule to winding along with the geometry.
  (call-with-owned 'path-reset! (list (path-h 'path-reset! p)) sk_path_reset))

(define (path-add-rect! p x y w h #:direction [direction 'cw])
  (define r (rect 'path-add-rect! x y w h))
  (define dir (choice 'path-add-rect! direction direction-values))
  (call-with-owned 'path-add-rect! (list (path-h 'path-add-rect! p))
    (lambda (pp) (sk_path_add_rect pp r dir))))
(define (path-add-rounded-rect! p x y w h rx ry #:direction [direction 'cw])
  (define r (rect 'path-add-rounded-rect! x y w h))
  (define frx (nonnegative-scalar 'path-add-rounded-rect! rx))
  (define fry (nonnegative-scalar 'path-add-rounded-rect! ry))
  (define dir (choice 'path-add-rounded-rect! direction direction-values))
  (call-with-owned 'path-add-rounded-rect! (list (path-h 'path-add-rounded-rect! p))
    (lambda (pp) (sk_path_add_rounded_rect pp r frx fry dir))))
(define (path-add-oval! p x y w h #:direction [direction 'cw])
  (define r (rect 'path-add-oval! x y w h))
  (define dir (choice 'path-add-oval! direction direction-values))
  (call-with-owned 'path-add-oval! (list (path-h 'path-add-oval! p))
    (lambda (pp) (sk_path_add_oval pp r dir))))
(define (path-add-circle! p x y radius #:direction [direction 'cw])
  (define fx (scalar 'path-add-circle! x))
  (define fy (scalar 'path-add-circle! y))
  (define fr (nonnegative-scalar 'path-add-circle! radius))
  (define dir (choice 'path-add-circle! direction direction-values))
  (call-with-owned 'path-add-circle! (list (path-h 'path-add-circle! p))
    (lambda (pp) (sk_path_add_circle pp fx fy fr dir))))

(define (path-add-path! dest src #:dx [dx 0] #:dy [dy 0] #:mode [mode 'append])
  (define who 'path-add-path!)
  (define fdx (scalar who dx))
  (define fdy (scalar who dy))
  (define mo (choice who mode path-add-mode-values))
  (call-with-owned who (list (path-h who dest) (path-h who src))
    (lambda (dp sp)
      (if (and (zero? fdx) (zero? fdy))
          (sk_path_add_path dp sp mo)
          (sk_path_add_path_offset dp sp fdx fdy mo)))))

(define (path-add-reversed-path! dest src)
  (define who 'path-add-reversed-path!)
  (call-with-owned who (list (path-h who dest) (path-h who src))
    (lambda (dp sp) (sk_path_add_path_reverse dp sp))))

(define (path-point-count p)
  (call-with-owned 'path-point-count (list (path-h 'path-point-count p)) sk_path_count_points))

(define (path-point-ref p index)
  (define who 'path-point-ref)
  (unless (and (exact-integer? index) (>= index 0))
    (raise-argument-error who "exact-nonnegative-integer?" index))
  (define pt (make-sk-point 0.0 0.0))
  (call-with-owned who (list (path-h who p))
    (lambda (pp)
      (define n (sk_path_count_points pp))
      (unless (< index n)
        (raise-arguments-error who "point index out of range" "index" index "count" n))
      (sk_path_get_point pp index pt)))
  (values (sk-point-x pt) (sk-point-y pt)))

(define (path-points p)
  (for/list ([i (in-range (path-point-count p))])
    (call-with-values (lambda () (path-point-ref p i)) list)))

(define (path-last-point p)
  (define who 'path-last-point)
  (define pt (make-sk-point 0.0 0.0))
  (call-with-owned who (list (path-h who p))
    (lambda (pp)
      (unless (sk_path_get_last_point pp pt)
        (error who "path has no last point"))))
  (values (sk-point-x pt) (sk-point-y pt)))

(define (path-convex? p)
  (call-with-owned 'path-convex? (list (path-h 'path-convex? p)) sk_path_is_convex))

(define (svg-path->path data #:fill-rule [fill-rule 'winding])
  (define who 'svg-path->path)
  (unless (string? data) (raise-argument-error who "string?" data))
  (when (regexp-match? #rx"\0" data)
    (raise-arguments-error who "SVG path data contains an embedded NUL" "data" data))
  (define bytes (nul-terminated-bytes (string->bytes/utf-8 data)))
  (define p (make-path '() #:fill-rule fill-rule))
  (call-with-owned who (list (path-h who p))
    (lambda (pp)
      (unless (sk_path_parse_svg_string pp bytes)
        (error who "invalid SVG path data"))))
  p)

(define (path->svg-path p)
  (define who 'path->svg-path)
  (call-with-owned
   who (list (path-h who p))
   (lambda (pp)
     (call-with-native-temporary
      who 'native-string sk_string_new_empty sk_string_destructor
      (lambda (sp)
        (sk_path_to_svg_string pp sp)
        (copy-sk-string who sp))))))

(define (get-path-bounds who p native-get)
  (define r (make-sk-rect 0.0 0.0 0.0 0.0))
  (call-with-owned who (list (path-h who p))
    (lambda (pp) (native-get pp r)))
  (values (sk-rect-left r) (sk-rect-top r)
          (- (sk-rect-right r) (sk-rect-left r))
          (- (sk-rect-bottom r) (sk-rect-top r))))
(define (path-bounds p) (get-path-bounds 'path-bounds p sk_path_get_bounds))
(define (path-tight-bounds p)
  (get-path-bounds 'path-tight-bounds p sk_path_compute_tight_bounds))
(define (path-contains? p x y)
  (define fx (scalar 'path-contains? x))
  (define fy (scalar 'path-contains? y))
  (call-with-owned 'path-contains? (list (path-h 'path-contains? p))
    (lambda (pp) (sk_path_contains pp fx fy))))
(define (path-fill-rule p)
  (case (call-with-owned 'path-fill-rule (list (path-h 'path-fill-rule p)) sk_path_get_filltype)
    [(0) 'winding] [(1) 'even-odd]
    [else (error 'path-fill-rule "unexpected native fill rule")]))
(define (path-set-fill-rule! p value)
  (define fill (choice 'path-set-fill-rule! value fill-values))
  (call-with-owned 'path-set-fill-rule! (list (path-h 'path-set-fill-rule! p))
    (lambda (pp) (sk_path_set_filltype pp fill))))

;; Boolean path operations --------------------------------------------------

(define (path-result who proc)
  (define result (make-path))
  (with-handlers ([exn? (lambda (e) (skia-close! result) (raise e))])
    (if (proc (path-h who result))
        result
        (begin
          (skia-close! result)
          (error who "native path operation failed")))))

(define (path-op a b operation)
  (define who 'path-op)
  (define op (choice who operation path-op-values))
  (define ah (path-h who a))
  (define bh (path-h who b))
  (path-result
   who
   (lambda (rh)
     (call-with-owned who (list ah bh rh)
       (lambda (ap bp rp) (sk_pathop_op ap bp op rp))))))

(define (path-union a b) (path-op a b 'union))
(define (path-intersect a b) (path-op a b 'intersect))
(define (path-difference a b) (path-op a b 'difference))
(define (path-xor a b) (path-op a b 'xor))
(define (path-reverse-difference a b) (path-op a b 'reverse-difference))

(define (path-simplify p)
  (define who 'path-simplify)
  (define ph (path-h who p))
  (path-result
   who
   (lambda (rh)
     (call-with-owned who (list ph rh)
       (lambda (pp rp) (sk_pathop_simplify pp rp))))))

(define (path-as-winding p)
  (define who 'path-as-winding)
  (define ph (path-h who p))
  (path-result
   who
   (lambda (rh)
     (call-with-owned who (list ph rh)
       (lambda (pp rp) (sk_pathop_as_winding pp rp))))))

;; Path measurement ---------------------------------------------------------

(define (snapshot-native-path who p)
  (call-with-owned who (list (path-h who p))
    (lambda (pp)
      (define snapshot (sk_path_clone pp))
      (unless snapshot (error who "native path snapshot failed"))
      snapshot)))

(define (make-path-measure p #:force-closed? [force-closed? #f]
                           #:res-scale [res-scale 1])
  (define who 'make-path-measure)
  (boolean who force-closed?)
  (define scale (positive-scalar who res-scale))
  ;; Validate the wrapper before native loading, then snapshot after preflight.
  (path-h who p)
  ;; Snapshot semantics make the measure independent of later path mutation or
  ;; explicit closure. The measure and snapshot are destroyed in that order.
  (skia-check!)
  (define snapshot (snapshot-native-path who p))
  (define snapshot-box (box snapshot))
  (with-handlers ([exn?
                   (lambda (e)
                     (define sp (unbox snapshot-box))
                     (when sp
                       (set-box! snapshot-box #f)
                       (sk_path_delete sp))
                     (raise e))])
    (define hnd
      (new-owned
       who 'path-measure
       (lambda () (sk_pathmeasure_new_with_path snapshot force-closed? scale))
       (lambda (mp)
         (sk_pathmeasure_destroy mp)
         (define sp (unbox snapshot-box))
         (when sp
           (set-box! snapshot-box #f)
           (sk_path_delete sp)))))
    (make-path-measure-record hnd snapshot-box)))

(define (path-measure-set-path! m p #:force-closed? [force-closed? #f])
  (define who 'path-measure-set-path!)
  (unless (or (not p) (skia-path? p))
    (raise-argument-error who "(or/c #f skia-path?)" p))
  (boolean who force-closed?)
  (define new-snapshot (and p (snapshot-native-path who p)))
  (with-handlers ([exn?
                   (lambda (e)
                     (when new-snapshot (sk_path_delete new-snapshot))
                     (raise e))])
    (call-with-owned who (list (path-measure-h who m))
      (lambda (mp)
        (sk_pathmeasure_set_path mp new-snapshot force-closed?)))
    (define box (path-measure-snapshot-box m))
    (define old-snapshot (unbox box))
    (set-box! box new-snapshot)
    (when old-snapshot (sk_path_delete old-snapshot))
    (void)))

(define (path-measure-length m)
  (call-with-owned 'path-measure-length
                   (list (path-measure-h 'path-measure-length m))
                   sk_pathmeasure_get_length))

(define (path-measure-closed? m)
  (call-with-owned 'path-measure-closed?
                   (list (path-measure-h 'path-measure-closed? m))
                   sk_pathmeasure_is_closed))

(define (checked-measure-distance who m value)
  (define d (nonnegative-scalar who value))
  (define len (path-measure-length m))
  (unless (<= d len)
    (raise-arguments-error who "distance is beyond the current contour"
                           "distance" value "contour length" len))
  d)

(define (path-measure-position+tangent m distance)
  (define who 'path-measure-position+tangent)
  (define d (checked-measure-distance who m distance))
  (define pos (make-sk-point 0.0 0.0))
  (define tan (make-sk-point 0.0 0.0))
  (define ok?
    (call-with-owned who (list (path-measure-h who m))
      (lambda (mp) (sk_pathmeasure_get_pos_tan mp d pos tan))))
  (if ok?
      (values (sk-point-x pos) (sk-point-y pos)
              (sk-point-x tan) (sk-point-y tan))
      (values #f #f #f #f)))

(define (path-measure-segment m start stop
                              #:start-with-move-to? [start-with-move-to? #t])
  (define who 'path-measure-segment)
  (boolean who start-with-move-to?)
  (define a (checked-measure-distance who m start))
  (define b (checked-measure-distance who m stop))
  (unless (< a b)
    (raise-arguments-error who "start must be less than stop"
                           "start" start "stop" stop))
  (define result (make-path))
  (with-handlers ([exn? (lambda (e) (skia-close! result) (raise e))])
    (define ok?
      (call-with-owned who (list (path-measure-h who m) (path-h who result))
        (lambda (mp rp)
          (sk_pathmeasure_get_segment mp a b rp start-with-move-to?))))
    (if ok?
        result
        (begin (skia-close! result) #f))))

(define (path-measure-next-contour! m)
  (call-with-owned 'path-measure-next-contour!
                   (list (path-measure-h 'path-measure-next-contour! m))
                   sk_pathmeasure_next_contour))

;; Typefaces and fonts --------------------------------------------------------

(define (make-typeface)
  (skia-check!)
  (make-typeface-record
   (new-owned 'make-typeface 'typeface sk_typeface_create_default sk_typeface_unref)))

(define (typeface-from-family family
                              #:weight [weight 'normal]
                              #:width [width 'normal]
                              #:slant [slant 'upright])
  (define who 'typeface-from-family)
  (define fam (nul-free-string who family "string?"))
  (define wt (font-weight who weight))
  (define wd (font-width who width))
  (define sl (choice who slant font-slant-values))
  (define family-bytes
    (nul-terminated-bytes (string->bytes/utf-8 fam)))
  (skia-check!)
  (call-with-native-temporary
   who 'font-style
   (lambda () (sk_fontstyle_new wt wd sl))
   sk_fontstyle_delete
   (lambda (style-ptr)
     (make-typeface-record
      (new-owned who 'typeface
                 (lambda () (sk_typeface_create_from_name family-bytes style-ptr))
                 sk_typeface_unref)))))

(define (typeface-from-file filename #:index [index 0])
  (define who 'typeface-from-file)
  (unless (path-string? filename)
    (raise-argument-error who "path-string?" filename))
  (unless (and (exact-integer? index) (>= index 0))
    (raise-argument-error who "exact-nonnegative-integer?" index))
  (unless (file-exists? filename)
    (raise-arguments-error who "font file does not exist" "path" filename))
  (define raw-path (path->bytes (path->complete-path filename)))
  (when (regexp-match? #rx#"\0" raw-path)
    (raise-arguments-error who "font path contains an embedded NUL" "path" filename))
  (define path-bytes (nul-terminated-bytes raw-path))
  (skia-check!)
  (make-typeface-record
   (new-owned who 'typeface
              (lambda () (sk_typeface_create_from_file path-bytes index))
              sk_typeface_unref)))

(define (copy-sk-string who string-ptr)
  (define n (sk_string_get_size string-ptr))
  (unless (<= n (current-skia-byte-limit))
    (error who "native string size ~a exceeds current-skia-byte-limit" n))
  (define out (make-bytes n))
  (when (positive? n)
    (define src (sk_string_get_c_str string-ptr))
    (unless src (error who "native string returned a null data pointer"))
    (memcpy out src n))
  (bytes->string/utf-8 out))

(define (typeface-family-name tf)
  (define who 'typeface-family-name)
  (call-with-owned
   who (list (typeface-h who tf))
   (lambda (tp)
     (call-with-native-temporary
      who 'native-string
      (lambda () (sk_typeface_get_family_name tp))
      sk_string_destructor
      (lambda (sp) (copy-sk-string who sp))))))

(define (typeface-weight tf)
  (call-with-owned 'typeface-weight (list (typeface-h 'typeface-weight tf))
                   sk_typeface_get_font_weight))
(define (typeface-width tf)
  (call-with-owned 'typeface-width (list (typeface-h 'typeface-width tf))
                   sk_typeface_get_font_width))
(define (typeface-slant tf)
  (define who 'typeface-slant)
  (enum-name who
             (call-with-owned who (list (typeface-h who tf))
                              sk_typeface_get_font_slant)
             font-slant-values "font slant"))

(define (make-font [tf #f]
                   #:size [size 12]
                   #:scale-x [scale-x 1]
                   #:skew-x [skew-x 0]
                   #:edging [edging 'antialias]
                   #:hinting [hinting 'normal]
                   #:subpixel? [subpixel? #f]
                   #:linear-metrics? [linear-metrics? #f]
                   #:embolden? [embolden? #f])
  (define who 'make-font)
  (unless (or (not tf) (typeface? tf))
    (raise-argument-error who "(or/c #f typeface?)" tf))
  (define fsize (positive-scalar who size))
  (define fsx (positive-scalar who scale-x))
  (define fskew (scalar who skew-x))
  (define edge (choice who edging font-edging-values))
  (define hint (choice who hinting font-hinting-values))
  (define sub? (boolean who subpixel?))
  (define linear? (boolean who linear-metrics?))
  (define bold? (boolean who embolden?))
  (skia-check!)
  (define implicit-typeface (and (not tf) (make-typeface)))
  (define use-typeface (or tf implicit-typeface))
  (with-handlers ([exn?
                   (lambda (e)
                     (when implicit-typeface (skia-close! implicit-typeface))
                     (raise e))])
    (define hnd
      (call-with-owned
       who (list (typeface-h who use-typeface))
       (lambda (tp)
         (new-owned who 'font
                    (lambda () (sk_font_new_with_values tp fsize fsx fskew))
                    sk_font_delete))))
    (define f (make-font-record hnd implicit-typeface))
    (initialize-resource
     f
     (lambda (_)
       (call-with-owned
        who (list hnd)
        (lambda (fp)
          (sk_font_set_edging fp edge)
          (sk_font_set_hinting fp hint)
          (sk_font_set_subpixel fp sub?)
          (sk_font_set_linear_metrics fp linear?)
          (sk_font_set_embolden fp bold?)))))))

(define (font-native-get who f getter)
  (call-with-owned who (list (font-h who f)) getter))
(define (font-native-set! who f value setter)
  (call-with-owned who (list (font-h who f))
                   (lambda (fp) (setter fp value))))

(define (font-size f) (font-native-get 'font-size f sk_font_get_size))
(define (font-set-size! f value)
  (font-native-set! 'font-set-size! f
                    (positive-scalar 'font-set-size! value) sk_font_set_size))
(define (font-scale-x f) (font-native-get 'font-scale-x f sk_font_get_scale_x))
(define (font-set-scale-x! f value)
  (font-native-set! 'font-set-scale-x! f
                    (positive-scalar 'font-set-scale-x! value) sk_font_set_scale_x))
(define (font-skew-x f) (font-native-get 'font-skew-x f sk_font_get_skew_x))
(define (font-set-skew-x! f value)
  (font-native-set! 'font-set-skew-x! f
                    (scalar 'font-set-skew-x! value) sk_font_set_skew_x))
(define (font-edging f)
  (define who 'font-edging)
  (enum-name who (font-native-get who f sk_font_get_edging)
             font-edging-values "font edging"))
(define (font-set-edging! f value)
  (font-native-set! 'font-set-edging! f
                    (choice 'font-set-edging! value font-edging-values)
                    sk_font_set_edging))
(define (font-hinting f)
  (define who 'font-hinting)
  (enum-name who (font-native-get who f sk_font_get_hinting)
             font-hinting-values "font hinting"))
(define (font-set-hinting! f value)
  (font-native-set! 'font-set-hinting! f
                    (choice 'font-set-hinting! value font-hinting-values)
                    sk_font_set_hinting))
(define (font-subpixel? f) (font-native-get 'font-subpixel? f sk_font_is_subpixel))
(define (font-set-subpixel! f value)
  (font-native-set! 'font-set-subpixel! f
                    (boolean 'font-set-subpixel! value) sk_font_set_subpixel))
(define (font-linear-metrics? f)
  (font-native-get 'font-linear-metrics? f sk_font_is_linear_metrics))
(define (font-set-linear-metrics! f value)
  (font-native-set! 'font-set-linear-metrics! f
                    (boolean 'font-set-linear-metrics! value)
                    sk_font_set_linear_metrics))
(define (font-embolden? f) (font-native-get 'font-embolden? f sk_font_is_embolden))
(define (font-set-embolden! f value)
  (font-native-set! 'font-set-embolden! f
                    (boolean 'font-set-embolden! value) sk_font_set_embolden))

(define (metric-if-valid metrics flag value)
  (and (not (zero? (bitwise-and (sk-font-metrics-flags metrics) flag))) value))

(define (font-get-metrics f)
  (define who 'font-get-metrics)
  (define metrics
    (make-sk-font-metrics 0
                          0.0 0.0 0.0 0.0 0.0
                          0.0 0.0 0.0 0.0 0.0 0.0
                          0.0 0.0 0.0 0.0))
  (define spacing
    (call-with-owned who (list (font-h who f))
      (lambda (fp) (sk_font_get_metrics fp metrics))))
  (font-metrics
   (sk-font-metrics-top metrics)
   (sk-font-metrics-ascent metrics)
   (sk-font-metrics-descent metrics)
   (sk-font-metrics-bottom metrics)
   (sk-font-metrics-leading metrics)
   (sk-font-metrics-avg-char-width metrics)
   (sk-font-metrics-max-char-width metrics)
   (sk-font-metrics-x-min metrics)
   (sk-font-metrics-x-max metrics)
   (sk-font-metrics-x-height metrics)
   (sk-font-metrics-cap-height metrics)
   (metric-if-valid metrics font-metric-underline-thickness-valid
                    (sk-font-metrics-underline-thickness metrics))
   (metric-if-valid metrics font-metric-underline-position-valid
                    (sk-font-metrics-underline-position metrics))
   (metric-if-valid metrics font-metric-strikeout-thickness-valid
                    (sk-font-metrics-strikeout-thickness metrics))
   (metric-if-valid metrics font-metric-strikeout-position-valid
                    (sk-font-metrics-strikeout-position metrics))
   spacing))

(define (call-with-font+paint who f p proc)
  (define fh (font-h who f))
  (cond
    [p
     (call-with-owned who (list fh (paint-h who p)) proc)]
    [else
     (call-with-owned who (list fh)
       (lambda (fp) (proc fp #f)))]))

(define (draw-simple-text c text x y f p)
  (define who 'draw-simple-text)
  (define bs (utf8-text who text))
  (define fx (scalar who x))
  (define fy (scalar who y))
  (call-on-canvas
   who c (list (font-h who f) (paint-h who p))
   (lambda (cp fp pp)
     (sk_canvas_draw_simple_text cp bs (bytes-length bs) text-encoding-utf8
                                 fx fy fp pp))))

(define (measure-simple-text f text #:paint [p #f])
  (define who 'measure-simple-text)
  (define bs (utf8-text who text))
  (define bounds (make-sk-rect 0.0 0.0 0.0 0.0))
  (call-with-font+paint
   who f p
   (lambda (fp pp)
     (sk_font_measure_text fp bs (bytes-length bs) text-encoding-utf8 bounds pp))))

(define (simple-text-bounds f text #:paint [p #f])
  (define who 'simple-text-bounds)
  (define bs (utf8-text who text))
  (define bounds (make-sk-rect 0.0 0.0 0.0 0.0))
  (call-with-font+paint
   who f p
   (lambda (fp pp)
     (sk_font_measure_text fp bs (bytes-length bs) text-encoding-utf8 bounds pp)
     (void)))
  (values (sk-rect-left bounds)
          (sk-rect-top bounds)
          (- (sk-rect-right bounds) (sk-rect-left bounds))
          (- (sk-rect-bottom bounds) (sk-rect-top bounds))))

(define (font-text->glyphs f text)
  (define who 'font-text->glyphs)
  (define bs (utf8-text who text))
  (call-with-owned
   who (list (font-h who f))
   (lambda (fp)
     (define count
       (sk_font_text_to_glyphs fp bs (bytes-length bs) text-encoding-utf8 #f 0))
     (unless (and (exact-integer? count) (>= count 0))
       (error who "native glyph count is invalid: ~a" count))
     (cond
       [(zero? count) #()]
       [else
        (define byte-count (* count (ctype-sizeof _uint16)))
        (unless (<= byte-count (current-skia-byte-limit))
          (error who "glyph buffer size ~a exceeds current-skia-byte-limit" byte-count))
        (define buffer (malloc count _uint16 'atomic))
        (define written
          (sk_font_text_to_glyphs fp bs (bytes-length bs) text-encoding-utf8
                                  buffer count))
        (unless (= written count)
          (error who "native glyph conversion changed count from ~a to ~a"
                 count written))
        (for/vector ([i (in-range count)])
          (ptr-ref buffer _uint16 i))]))))

(define (font-char->glyph f ch)
  (define who 'font-char->glyph)
  (define codepoint (unicode-scalar who ch))
  (call-with-owned who (list (font-h who f))
    (lambda (fp) (sk_font_unichar_to_glyph fp codepoint))))

(define (font-glyph-path f glyph)
  (define who 'font-glyph-path)
  (define gid (glyph-id who glyph))
  (define p (make-path))
  (with-handlers ([exn? (lambda (e) (skia-close! p) (raise e))])
    (define found?
      (call-with-owned who (list (font-h who f) (path-h who p))
        (lambda (fp pp) (sk_font_get_path fp gid pp))))
    (if found?
        p
        (begin (skia-close! p) #f))))

(define (simple-text-path f text [x 0] [y 0])
  (define who 'simple-text-path)
  (define bs (utf8-text who text))
  (define fx (scalar who x))
  (define fy (scalar who y))
  (define p (make-path))
  (with-handlers ([exn? (lambda (e) (skia-close! p) (raise e))])
    (call-with-owned who (list (font-h who f) (path-h who p))
      (lambda (fp pp)
        (sk_text_utils_get_path bs (bytes-length bs) text-encoding-utf8
                                fx fy fp pp)))
    p))

;; Images, encoded data, codecs, and copied pixel input ---------------------

(define (surface-snapshot s)
  (call-with-owned 'surface-snapshot (list (surface-h 'surface-snapshot s))
    (lambda (sp)
      (make-image-record
       (new-owned 'surface-snapshot 'image
                  (lambda () (sk_surface_new_image_snapshot sp)) sk_image_unref)
       (surface-width s) (surface-height s)))))

(define (rgba-bytes->image w h pixels #:premultiplied? [premultiplied? #f])
  (define n (check-dimensions 'rgba-bytes->image w h))
  (boolean 'rgba-bytes->image premultiplied?)
  (unless (and (bytes? pixels) (= n (bytes-length pixels)))
    (raise-arguments-error 'rgba-bytes->image "expected exactly width*height*4 RGBA bytes"
                           "required length" n "pixels" pixels))
  ;; Invalid premultiplied input can violate native assumptions.
  (when premultiplied?
    (for ([i (in-range 0 n 4)])
      (define a (bytes-ref pixels (+ i 3)))
      (unless (and (<= (bytes-ref pixels i) a)
                   (<= (bytes-ref pixels (+ i 1)) a)
                   (<= (bytes-ref pixels (+ i 2)) a))
        (error 'rgba-bytes->image "RGB exceeds alpha in premultiplied pixel ~a" (quotient i 4)))))
  (skia-check!)
  (make-image-record
   (new-owned 'rgba-bytes->image 'image
              (lambda ()
                (sk_image_new_raster_copy
                 (make-sk-image-info #f w h rgba-8888
                                     (if premultiplied? alpha-premul alpha-unpremul))
                 pixels (* 4 w)))
              sk_image_unref)
   w h))

(define (checked-file-data who filename)
  (unless (path-string? filename)
    (raise-argument-error who "path-string?" filename))
  (unless (file-exists? filename)
    (raise-arguments-error who "image file does not exist" "path" filename))
  (define n (file-size filename))
  (unless (positive? n)
    (raise-arguments-error who "encoded image file is empty" "path" filename))
  (unless (<= n (current-skia-byte-limit))
    (raise-arguments-error who "encoded image file exceeds current-skia-byte-limit"
                           "encoded bytes" n "limit" (current-skia-byte-limit)))
  (define raw-path (path->bytes (path->complete-path filename)))
  (when (regexp-match? #rx#"\0" raw-path)
    (raise-arguments-error who "image path contains an embedded NUL" "path" filename))
  (values (nul-terminated-bytes raw-path) n))

(define (call-with-encoded-data-from-bytes who bs proc)
  (positive-encoded-bytes who bs)
  (skia-check!)
  (call-with-native-temporary
   who 'encoded-data
   (lambda () (sk_data_new_with_copy bs (bytes-length bs)))
   sk_data_unref proc))

(define (call-with-encoded-data-from-file who filename proc)
  (define-values (path-bytes _n) (checked-file-data who filename))
  (skia-check!)
  (call-with-native-temporary
   who 'encoded-data
   (lambda () (sk_data_new_from_file path-bytes))
   sk_data_unref proc))

(define (make-image-from-data who call-with-data)
  (call-with-data
   (lambda (dp)
     (define hnd
       (new-owned who 'image (lambda () (sk_image_new_from_encoded dp)) sk_image_unref))
     (with-handlers ([exn? (lambda (e) (owned-close! who hnd) (raise e))])
       (define-values (w h)
         (call-with-owned who (list hnd)
           (lambda (ip) (values (sk_image_get_width ip) (sk_image_get_height ip)))))
       ;; Reject dimensions that the rest of this CPU binding cannot safely
       ;; materialize under its documented limits.
       (check-dimensions who w h)
       (make-image-record hnd w h)))))

(define (image-from-bytes bs)
  (define who 'image-from-bytes)
  (positive-encoded-bytes who bs)
  (make-image-from-data
   who (lambda (proc) (call-with-encoded-data-from-bytes who bs proc))))

(define (image-from-file filename)
  (define who 'image-from-file)
  ;; Validate before loading the native library.
  (checked-file-data who filename)
  (make-image-from-data
   who (lambda (proc) (call-with-encoded-data-from-file who filename proc))))

(define (copy-native-data who data)
  (define n (sk_data_get_size data))
  (unless (<= 1 n (current-skia-byte-limit))
    (error who "native data size ~a exceeds current-skia-byte-limit, or is empty" n))
  (define src (sk_data_get_data data))
  (unless src (error who "native data returned a null pointer"))
  (define out (make-bytes n))
  (memcpy out src n)
  out)

(define (image-original-encoded-bytes im)
  (define who 'image-original-encoded-bytes)
  (call-with-owned
   who (list (image-h who im))
   (lambda (ip)
     (define dp (sk_image_ref_encoded ip))
     (and dp
          (call-with-native-temporary
           who 'encoded-data (lambda () dp) sk_data_unref
           (lambda (data) (copy-native-data who data)))))))

(define (codec-info-from-data who data)
  (call-with-native-temporary
   who 'codec (lambda () (sk_codec_new_from_data data)) sk_codec_destroy
   (lambda (cp)
     (define info (make-sk-image-info #f 0 0 0 0))
     (sk_codec_get_info cp info)
     ;; ToImageInfo() returns a referenced color-space pointer in this ABI.
     ;; Metadata inspection does not expose colorspaces yet, so release that
     ;; reference after copying the scalar fields, including on exceptions.
     (define colorspace (sk-image-info-colorspace info))
     (dynamic-wind
       void
       (lambda ()
         (define w (sk-image-info-width info))
         (define h (sk-image-info-height info))
         (unless (and (exact-positive-integer? w) (exact-positive-integer? h))
           (error who "codec returned invalid dimensions ~ax~a" w h))
         (define frames (sk_codec_get_frame_count cp))
         ;; The pinned C shim implements this as getFrameInfo().size(); still
         ;; images commonly report zero rather than one.
         (unless (and (exact-integer? frames) (>= frames 0))
           (error who "codec returned invalid frame count ~a" frames))
         (make-encoded-image-info-record
          w h
          (enum-name who (sk_codec_get_encoded_format cp)
                     encoded-format-values "encoded image format")
          (enum-name who (sk-image-info-color-type info)
                     color-type-values "color type")
          (enum-name who (sk-image-info-alpha-type info)
                     alpha-type-values "alpha type")
          (enum-name who (sk_codec_get_origin cp)
                     encoded-origin-values "encoded origin")
          frames))
       (lambda ()
         (when colorspace
           (sk_colorspace_unref colorspace)))))))

(define (encoded-image-info-from-bytes bs)
  (define who 'encoded-image-info-from-bytes)
  (call-with-encoded-data-from-bytes
   who bs (lambda (dp) (codec-info-from-data who dp))))

(define (encoded-image-info-from-file filename)
  (define who 'encoded-image-info-from-file)
  (call-with-encoded-data-from-file
   who filename (lambda (dp) (codec-info-from-data who dp))))

(define (image-color-type im)
  (define who 'image-color-type)
  (enum-name who
             (call-with-owned who (list (image-h who im)) sk_image_get_color_type)
             color-type-values "color type"))

(define (image-alpha-type im)
  (define who 'image-alpha-type)
  (enum-name who
             (call-with-owned who (list (image-h who im)) sk_image_get_alpha_type)
             alpha-type-values "alpha type"))

(define (image->rgba-bytes im #:premultiplied? [premultiplied? #f])
  (define hnd (image-h 'image->rgba-bytes im))
  (boolean 'image->rgba-bytes premultiplied?)
  (define w (image-width im))
  (define h (image-height im))
  (define out (make-bytes (check-dimensions 'image->rgba-bytes w h)))
  (call-with-owned 'image->rgba-bytes (list hnd)
    (lambda (ip)
      (unless (sk_image_read_pixels
               ip (make-sk-image-info #f w h rgba-8888
                                      (if premultiplied? alpha-premul alpha-unpremul))
               out (* 4 w) 0 0 0)
        (error 'image->rgba-bytes "native image pixel read failed"))))
  out)

(define (call-with-image-pixmap who im proc)
  (call-with-owned
   who (list (image-h who im))
   (lambda (ip)
     ;; Deferred encoded images do not necessarily expose a pixmap. Ask Skia
     ;; for a raster image first, then borrow its pixels only within this scope.
     (call-with-native-temporary
      who 'raster-image (lambda () (sk_image_make_raster_image ip)) sk_image_unref
      (lambda (raster)
        (call-with-native-temporary
         who 'pixmap sk_pixmap_new sk_pixmap_destructor
         (lambda (pixmap)
           (unless (sk_image_peek_pixels raster pixmap)
             (error who "raster image did not expose its pixels"))
           (proc pixmap))))))))

(define (encode-pixmap-to-bytes who pixmap encoder options)
  (call-with-native-temporary
   who 'encoded-stream sk_dynamicmemorywstream_new sk_dynamicmemorywstream_destroy
   (lambda (stream)
     (unless (encoder stream pixmap options)
       (error who "native image encoder failed"))
     (call-with-native-temporary
      who 'encoded-data
      (lambda () (sk_dynamicmemorywstream_detach_as_data stream)) sk_data_unref
      (lambda (data) (copy-native-data who data))))))

(define (image->png-bytes im #:compression [compression 6])
  (define who 'image->png-bytes)
  (unless (and (exact-integer? compression) (<= 0 compression 9))
    (raise-argument-error who "exact integer from 0 through 9" compression))
  (define options (make-sk-png-options png-all-filters compression #f #f #f))
  (call-with-image-pixmap
   who im (lambda (pixmap) (encode-pixmap-to-bytes who pixmap sk_pngencoder_encode options))))

(define (image->jpeg-bytes im
                           #:quality [quality 90]
                           #:downsample [downsample 'yuv-420]
                           #:alpha [alpha 'ignore])
  (define who 'image->jpeg-bytes)
  (define q (quality-integer who quality))
  (define ds (choice who downsample jpeg-downsample-values))
  (define a (choice who alpha jpeg-alpha-values))
  (define options (make-sk-jpeg-options q ds a #f #f #f))
  (call-with-image-pixmap
   who im (lambda (pixmap) (encode-pixmap-to-bytes who pixmap sk_jpegencoder_encode options))))

(define (image->webp-bytes im #:quality [quality 90] #:lossless? [lossless? #f])
  (define who 'image->webp-bytes)
  (define q (quality-scalar who quality))
  (define lossless (boolean who lossless?))
  (define compression (choice who (if lossless 'lossless 'lossy) webp-compression-values))
  (define options (make-sk-webp-options compression q #f #f))
  (call-with-image-pixmap
   who im (lambda (pixmap) (encode-pixmap-to-bytes who pixmap sk_webpencoder_encode options))))

(define (image->encoded-bytes im format
                              #:quality [quality 90]
                              #:png-compression [png-compression 6]
                              #:jpeg-downsample [jpeg-downsample 'yuv-420]
                              #:jpeg-alpha [jpeg-alpha 'ignore]
                              #:webp-lossless? [webp-lossless? #f])
  (case format
    [(png) (image->png-bytes im #:compression png-compression)]
    [(jpeg) (image->jpeg-bytes im #:quality quality
                               #:downsample jpeg-downsample #:alpha jpeg-alpha)]
    [(webp) (image->webp-bytes im #:quality quality #:lossless? webp-lossless?)]
    [else
     (raise-argument-error 'image->encoded-bytes "'png, 'jpeg, or 'webp" format)]))

(define (save-image im filename format
                    #:exists [exists 'error]
                    #:quality [quality 90]
                    #:png-compression [png-compression 6]
                    #:jpeg-downsample [jpeg-downsample 'yuv-420]
                    #:jpeg-alpha [jpeg-alpha 'ignore]
                    #:webp-lossless? [webp-lossless? #f])
  (unless (path-string? filename)
    (raise-argument-error 'save-image "path-string?" filename))
  (unless (memq exists '(error replace))
    (raise-argument-error 'save-image "'error or 'replace" exists))
  ;; Encode first so a native failure never truncates an existing destination.
  (define data
    (image->encoded-bytes im format
                          #:quality quality
                          #:png-compression png-compression
                          #:jpeg-downsample jpeg-downsample
                          #:jpeg-alpha jpeg-alpha
                          #:webp-lossless? webp-lossless?))
  (call-with-output-file filename
    (lambda (out) (write-bytes data out) (void))
    #:mode 'binary #:exists exists))

(define (image-subset im x y w h)
  (define who 'image-subset)
  (define subset
    (exact-source-rectangle who x y w h (image-width im) (image-height im)))
  (call-with-owned
   who (list (image-h who im))
   (lambda (ip)
     (make-image-record
      (new-owned who 'image
                 (lambda () (sk_image_make_subset_raster ip subset))
                 sk_image_unref)
      w h))))

(define (draw-image c im x y #:sampling [mode 'nearest] #:paint [p #f])
  (define ih (image-h 'draw-image im))
  (define fx (scalar 'draw-image x))
  (define fy (scalar 'draw-image y))
  (define smp (sampling 'draw-image mode))
  (define others (if p (list ih (paint-h 'draw-image p)) (list ih)))
  (call-on-canvas 'draw-image c others
    (lambda (cp ip . paints)
      (sk_canvas_draw_image cp ip fx fy smp (if p (car paints) #f)))))

(define (draw-image-rect c im x y w h #:sampling [mode 'linear] #:paint [p #f])
  (define ih (image-h 'draw-image-rect im))
  (define src (rect 'draw-image-rect 0 0 (image-width im) (image-height im)))
  (define dst (rect 'draw-image-rect x y w h))
  (define smp (sampling 'draw-image-rect mode))
  (define others (if p (list ih (paint-h 'draw-image-rect p)) (list ih)))
  (call-on-canvas 'draw-image-rect c others
    (lambda (cp ip . paints)
      (sk_canvas_draw_image_rect cp ip src dst smp (if p (car paints) #f)))))

(define (draw-image-subrect c im sx sy sw sh dx dy dw dh
                            #:sampling [mode 'linear] #:paint [p #f])
  (define who 'draw-image-subrect)
  (define ih (image-h who im))
  (define src (source-rect who sx sy sw sh (image-width im) (image-height im)))
  (define dst (rect who dx dy dw dh))
  (define smp (sampling who mode))
  (define others (if p (list ih (paint-h who p)) (list ih)))
  (call-on-canvas who c others
    (lambda (cp ip . paints)
      (sk_canvas_draw_image_rect cp ip src dst smp (if p (car paints) #f)))))


(define (draw-picture c pic #:x [x 0] #:y [y 0] #:width [w #f] #:height [h #f])
  (define who 'draw-picture)
  (define _ph (picture-h who pic))
  (define fx (scalar who x))
  (define fy (scalar who y))
  (define scaled?
    (cond
      [(and (eq? w #f) (eq? h #f)) #f]
      [(and (not (eq? w #f)) (not (eq? h #f))) #t]
      [else
       (raise-arguments-error who
                              "#:width and #:height must be given together or both omitted"
                              "width" w "height" h)]))
  (define fw (and scaled? (nonnegative-scalar who w)))
  (define fh (and scaled? (nonnegative-scalar who h)))
  (call-with-canvas-state
   c
   (lambda ()
     (unless (and (= fx 0.0) (= fy 0.0))
       (canvas-translate! c fx fy))
     (when scaled?
       (when (or (zero? (picture-width pic)) (zero? (picture-height pic)))
         (error who "cannot scale a picture with a zero-size recorded extent"))
       (canvas-scale! c (/ fw (picture-width pic)) (/ fh (picture-height pic))))
     (call-on-canvas who c (list (picture-h who pic))
       (lambda (cp pp) (sk_canvas_draw_picture cp pp #f #f))))))

(define (picture->image pic width height #:background [background 'transparent])
  (define who 'picture->image)
  (define _ph (picture-h who pic))
  (check-dimensions who width height)
  (with-skia ([surface (make-surface width height #:background background)])
    (draw-picture (surface-canvas surface) pic #:width width #:height height)
    (surface-snapshot surface)))
