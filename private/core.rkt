#lang racket/base
(require "output-util.rkt")
(provide current-text-output-mode current-raster-output-scale text-blob->path)

;; Legacy drawing remains native by default. Shared exporters parameterize
;; these choices only while authoring a page; no global backend is installed.
(define current-text-output-mode
  (make-parameter 'native
                  (lambda (v) (output-text-mode 'current-text-output-mode v))))
(define current-raster-output-scale
  (make-parameter 1
                  (lambda (v) (raster-output-scale 'current-raster-output-scale v))))

(require ffi/unsafe
         racket/list
         racket/match
         racket/path
         racket/vector
         "native.rkt" "types.rkt" "lifetime.rkt" "check.rkt" "codec-util.rkt" "pdf-util.rkt" "svg-util.rkt"
         "harfbuzz-native.rkt" "harfbuzz-types.rkt" "bidi.rkt" "line-break.rkt" "joining.rkt"
         "../color.rkt")
(provide current-skia-byte-limit
         skia-resource? skia-closed? skia-close!
         call-with-skia-resource with-skia
         color-space? make-srgb-color-space make-linear-srgb-color-space
         color-space-from-icc-bytes color-space->icc-bytes
         color-space-srgb? color-space-linear-gamma? color-space-gamma-close-to-srgb?
         color-space=? color-space->linear-gamma color-space->srgb-gamma
         surface? make-surface surface-width surface-height surface-canvas surface-color-space
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
         image? image-width image-height image-color-type image-alpha-type image-color-space
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
         font-manager? make-font-manager default-font-manager
         font-manager-family-count font-manager-family-name font-manager-families
         font-manager-match-family font-manager-match-character
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
         font-text->glyphs font-char->glyph font-glyph-path simple-text-path
         text-blob? make-positioned-text-blob text-blob-bounds text-blob-unique-id
         draw-text-blob
         shaper? make-shaper
         shaped-run? shaped-run-glyphs shaped-run-clusters shaped-run-positions
         shaped-run-advance-x shaped-run-advance-y shaped-run-glyph-count
         shape-text shaped-run->text-blob draw-shaped-run draw-shaped-text
         layout-break-opportunity? make-layout-break-opportunity
         layout-break-opportunity-index layout-break-opportunity-insert
         text-layout? text-layout-lines text-layout-width text-layout-height
         text-layout-line-height text-layout-line-count
         text-layout-line? text-layout-line-text text-layout-line-run
         text-layout-line-origin-x text-layout-line-baseline
         text-layout-line-width text-layout-line-direction
         layout-text draw-text-layout
         mixed-text-layout? mixed-text-layout-lines mixed-text-layout-width
         mixed-text-layout-height mixed-text-layout-line-height
         mixed-text-layout-line-count
         mixed-text-line? mixed-text-line-text mixed-text-line-runs
         mixed-text-line-origin-x mixed-text-line-baseline
         mixed-text-line-width mixed-text-line-direction
         mixed-text-run? mixed-text-run-text mixed-text-run-shaped-run
         mixed-text-run-origin-x mixed-text-run-width mixed-text-run-direction
         mixed-text-run-level mixed-text-run-script mixed-text-run-family
         layout-mixed-text draw-mixed-text-layout)

(struct surface (handle width height [floors #:mutable])
  #:constructor-name make-surface-record)
;; A canvas is always borrowed from a surface, picture recorder, or individual PDF page.
(struct canvas (resource) #:constructor-name make-canvas-record)
(struct paint (handle) #:constructor-name make-paint-record)
(struct shader (handle) #:constructor-name make-shader-record)
(struct path-effect (handle) #:constructor-name make-path-effect-record)
(struct color-filter (handle) #:constructor-name make-color-filter-record)
(struct mask-filter (handle) #:constructor-name make-mask-filter-record)
(struct image-filter (handle) #:constructor-name make-image-filter-record)
(struct color-space (handle) #:constructor-name make-color-space-record)
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
(struct font-manager (handle) #:constructor-name make-font-manager-record)
(struct typeface (handle) #:constructor-name make-typeface-record)
;; owner keeps an implicitly-created default typeface reachable for at least
;; as long as the font wrapper. SkFont itself also retains its typeface.
(struct font (handle owner) #:constructor-name make-font-record)
;; A private font snapshot and immutable positions allow exact outline replay
;; after the caller mutates/closes the font used to construct this blob.
(struct text-blob (handle font glyphs positions) #:constructor-name make-text-blob-record)
(struct shaper (handle font) #:constructor-name make-shaper-record)
(struct shaped-run (glyphs clusters positions advance-x advance-y) #:transparent)
(struct layout-break-opportunity (index insert)
  #:transparent
  #:constructor-name make-layout-break-opportunity-record)
;; A text layout is a pure Racket value, but it intentionally keeps the shaper
;; wrapper reachable. It therefore remains drawable while the shaper is live;
;; explicitly closing that shaper invalidates later drawing from the layout.
(struct text-layout (shaper lines width height line-height) #:transparent)
(struct text-layout-line (text run origin-x baseline width direction) #:transparent)
;; Mixed layouts keep caller-owned base shaper/font-manager wrappers reachable.
;; Fallback fonts/shapers are created transiently during layout/drawing, so the
;; layout itself owns no hidden native resources.
(struct mixed-text-layout (shaper font-manager lines width height line-height) #:transparent)
(struct mixed-text-line (text runs origin-x baseline width direction) #:transparent)
(struct mixed-text-run
  (text shaped-run origin-x width direction level script
        family weight font-width slant)
  #:transparent)
(struct fallback-choice (family weight width slant) #:transparent)
(struct font-metrics
  (top ascent descent bottom leading
   average-character-width max-character-width
   x-min x-max x-height cap-height
   underline-thickness underline-position
   strikeout-thickness strikeout-position spacing)
  #:transparent)

(define (skia-resource? v)
  (or (surface? v) (paint? v) (shader? v) (path-effect? v)
      (color-filter? v) (mask-filter? v) (image-filter? v) (color-space? v)
      (picture? v) (picture-recorder? v) (document? v) (svg-document? v)
      (skia-path? v) (path-measure? v) (image? v) (codec? v)
      (font-manager? v) (typeface? v) (font? v) (text-blob? v) (shaper? v)))

(define (resource-handle who v)
  (cond [(surface? v) (surface-handle v)]
        [(document? v) (document-handle v)]
        [(svg-document? v) (svg-document-handle v)]
        [(pdf-page? v) (document-handle (pdf-page-document v))]
        [(paint? v) (paint-handle v)]
        [(shader? v) (shader-handle v)]
        [(path-effect? v) (path-effect-handle v)]
        [(color-filter? v) (color-filter-handle v)]
        [(mask-filter? v) (mask-filter-handle v)]
        [(image-filter? v) (image-filter-handle v)]
        [(color-space? v) (color-space-handle v)]
        [(picture? v) (picture-handle v)]
        [(picture-recorder? v) (picture-recorder-handle v)]
        [(skia-path? v) (skia-path-handle v)]
        [(path-measure? v) (path-measure-handle v)]
        [(image? v) (image-handle v)]
        [(codec? v) (codec-handle v)]
        [(font-manager? v) (font-manager-handle v)]
        [(typeface? v) (typeface-handle v)]
        [(font? v) (font-handle v)]
        [(text-blob? v) (text-blob-handle v)]
        [(shaper? v) (shaper-handle v)]
        [else (raise-argument-error who "skia-resource? (not a borrowed canvas)" v)]))

(define (skia-closed? v)
  (define owner (if (canvas? v) (canvas-owner 'skia-closed? v) v))
  (cond [(pdf-page? owner) (pdf-page-closed? owner)]
        [(and (canvas? v) (svg-document? owner)) (svg-canvas-closed? owner)]
        [else (owned-closed? (resource-handle 'skia-closed? owner))]))

(define (skia-close! v)
  (owned-close! 'skia-close! (resource-handle 'skia-close! v))
  ;; A font created without an explicit typeface owns a private default
  ;; typeface wrapper as well. Close that wrapper deterministically after
  ;; closing the font; explicit user-supplied typefaces are never closed here.
  (when (and (font? v) (font-owner v))
    (owned-close! 'skia-close! (typeface-handle (font-owner v))))
  ;; A shaper snapshots the SkFont used for later TextBlob construction.
  (when (shaper? v)
    (skia-close! (shaper-font v)))
  ;; A blob's snapshot is independent of the native blob's retained typeface.
  ;; Each has its own GC fallback; explicit close releases both immediately.
  (when (text-blob? v)
    (skia-close! (text-blob-font v))))

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
(define (color-space-h who v)
  (typed-handle who v color-space? color-space-handle "color-space?"))
(define (picture-h who v) (typed-handle who v picture? picture-handle "picture?"))
(define (picture-recorder-h who v)
  (typed-handle who v picture-recorder? picture-recorder-handle "picture-recorder?"))
(define (path-h who v) (typed-handle who v skia-path? skia-path-handle "skia-path?"))
(define (path-measure-h who v)
  (typed-handle who v path-measure? path-measure-handle "path-measure?"))
(define (image-h who v) (typed-handle who v image? image-handle "image?"))
(define (font-manager-h who v)
  (typed-handle who v font-manager? font-manager-handle "font-manager?"))
(define (typeface-h who v) (typed-handle who v typeface? typeface-handle "typeface?"))
(define (font-h who v) (typed-handle who v font? font-handle "font?"))
(define (text-blob-h who v) (typed-handle who v text-blob? text-blob-handle "text-blob?"))
(define (shaper-h who v) (typed-handle who v shaper? shaper-handle "shaper?"))

(define (canvas-owner who c)
  (unless (canvas? c) (raise-argument-error who "canvas?" c))
  (define owner (canvas-resource c))
  (unless (or (surface? owner) (picture-recorder? owner) (pdf-page? owner)
              (svg-document? owner))
    (error who "canvas owner is corrupted"))
  owner)

(define (owner-floors owner)
  (cond [(surface? owner) (surface-floors owner)]
        [(picture-recorder? owner) (picture-recorder-floors owner)]
        [(pdf-page? owner) (pdf-page-floors owner)]
        [(svg-document? owner) (svg-document-floors owner)]
        [else (error 'owner-floors "unsupported owner")]))

(define (set-owner-floors! owner floors)
  (cond [(surface? owner) (set-surface-floors! owner floors)]
        [(picture-recorder? owner) (set-picture-recorder-floors! owner floors)]
        [(pdf-page? owner) (set-pdf-page-floors! owner floors)]
        [(svg-document? owner) (set-svg-document-floors! owner floors)]
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
         [(pdf-page? owner) (pdf-page-pointer/checked who owner)]
         [(svg-document? owner) (svg-canvas-pointer/checked who owner)]
         [else (error who "unsupported canvas owner")]))
     (apply proc cp ps))))

(define (initialize-resource v proc)
  (with-handlers ([exn? (lambda (e) (skia-close! v) (raise e))])
    (proc v)
    v))

;; Private bridge for the path/matrix module. This submodule is not re-exported
;; by main.rkt; only safe value/resource operations form the public API.
(module* path-matrix-internals #f
  (provide call-on-canvas path-h path-measure-h shader-h make-shader-record
           call-with-native-temporary))

(provide svg-document? make-svg-document svg-document-width svg-document-height
         svg-document-state svg-document-canvas
         svg-document-finish! svg-document-abort!
         svg-document->bytes svg-document->string save-svg
         call-with-svg-bytes call-with-svg-string call-with-svg-file
         shaped-run->path draw-rasterized)

;; SVG output ---------------------------------------------------------------
;; Unlike PDF, Skia's SVG backend owns a canvas, not an SkDocument. Deleting
;; that canvas closes the XML root. One owned STREAM handle keeps everything
;; alive; its release closure captures storage, never the public wrapper.
(struct svg-storage ([canvas #:mutable] [xml #:mutable]))
(struct svg-document (handle storage width height title description prefix
                             [status #:mutable] [floors #:mutable])
  #:constructor-name make-svg-document-record)

(define (svg-document-h who d)
  (typed-handle who d svg-document? svg-document-handle "svg-document?"))

(define (svg-document-state d)
  (define h (svg-document-h 'svg-document-state d))
  (if (owned-closed? h)
      (if (eq? (svg-document-status d) 'aborted) 'aborted 'closed)
      (svg-document-status d)))

(define (svg-canvas-closed? d)
  (or (owned-closed? (svg-document-handle d))
      (not (eq? (svg-document-status d) 'open))
      (not (svg-storage-canvas (svg-document-storage d)))))

(define (svg-canvas-pointer/checked who d)
  (when (svg-canvas-closed? d)
    (error who "SVG canvas is closed (document finished, aborted, or released)"))
  (svg-storage-canvas (svg-document-storage d)))

(define (release-svg-native! storage sp)
  ;; Clear first: explicit release and GC cleanup cannot delete the same canvas
  ;; twice. Finalizers may finish an XML stream internally but never publish it.
  (define cp (svg-storage-canvas storage))
  (set-svg-storage-canvas! storage #f)
  (when cp (sk_canvas_destroy cp))
  (set-svg-storage-xml! storage #f)
  (sk_dynamicmemorywstream_destroy sp))

(define (make-svg-document width height #:title [title ""]
                            #:description [description ""] #:id-prefix [id-prefix "skia"])
  (define who 'make-svg-document)
  (define w (svg-dimension who width))
  (define h (svg-dimension who height))
  (define-values (t d) (svg-metadata who title description))
  (define prefix (svg-id-prefix who id-prefix))
  ;; All argument validation precedes native loading/allocation.
  (skia-check!)
  (define storage (svg-storage #f #f))
  (define handle
    (new-owned
     who 'svg-document
     (lambda ()
       (define sp (sk_dynamicmemorywstream_new))
       (unless sp (error who "native SVG stream allocation failed"))
       (with-handlers ([(lambda (_) #t)
                        (lambda (e) (release-svg-native! storage sp) (raise e))])
         (define bounds (make-sk-rect 0.0 0.0 w h))
         (define cp (sk_svgcanvas_create_with_stream bounds sp))
         (unless cp (error who "native SVG canvas allocation failed"))
         (set-svg-storage-canvas! storage cp)
         sp))
     (lambda (sp) (release-svg-native! storage sp))))
  (make-svg-document-record handle storage w h t d prefix 'open '()))

(define (svg-document-canvas d)
  (call-with-owned
   'svg-document-canvas (list (svg-document-h 'svg-document-canvas d))
   (lambda (_sp)
     (svg-canvas-pointer/checked 'svg-document-canvas d)
     (make-canvas-record d))))

(define (svg-document-finish! d)
  (define who 'svg-document-finish!)
  (define hnd (svg-document-h who d))
  (call-with-owned
   who (list hnd)
   (lambda (sp)
     (unless (eq? (svg-document-status d) 'finished)
       (svg-canvas-pointer/checked who d)
       (unless (null? (svg-document-floors d))
         (error who "cannot finish SVG inside a protected canvas-state scope"))
       (with-handlers ([(lambda (_) #t)
                        (lambda (e)
                          (set-svg-document-status! d 'aborted)
                          (owned-close! who hnd)
                          (raise e))])
         (define storage (svg-document-storage d))
         (define cp (svg-storage-canvas storage))
         (set-svg-document-status! d 'finishing)
         (set-svg-storage-canvas! storage #f)
         ;; A flush is not sufficient. This MUST precede stream detachment.
         (sk_canvas_destroy cp)
         (define xml
           (call-with-native-temporary
            who 'svg-data
            (lambda () (sk_dynamicmemorywstream_detach_as_data sp)) sk_data_unref
            (lambda (dp)
              (finish-svg-xml who (copy-native-data who dp)
                              (svg-document-width d) (svg-document-height d)
                              (svg-document-title d) (svg-document-description d)
                              (svg-document-prefix d)))))
         (set-svg-storage-xml! storage xml)
         (set-svg-document-status! d 'finished)))))
  (void))

(define (svg-document-abort! d)
  (define hnd (svg-document-h 'svg-document-abort! d))
  ;; Also checks thread ownership after an earlier close/abort.
  (owned-close! 'svg-document-abort! hnd)
  (set-svg-document-status! d 'aborted)
  (void))

(define (svg-document->bytes d)
  (define who 'svg-document->bytes)
  (call-with-owned
   who (list (svg-document-h who d))
   (lambda (_sp)
     (unless (eq? (svg-document-status d) 'finished)
       (error who "svg-document-finish! must succeed before reading SVG bytes"))
     (define xml (svg-storage-xml (svg-document-storage d)))
     (unless (<= (bytes-length xml) (current-skia-byte-limit))
       (error who "SVG output exceeds current-skia-byte-limit"))
     ;; Independent mutable result, like document->pdf-bytes and image encoders.
     (bytes-copy xml))))

(define (svg-document->string d)
  (bytes->string/utf-8 (svg-document->bytes d) #f))

(define (save-svg d filename #:exists [exists 'error])
  (define target (svg-output-path 'save-svg filename exists))
  (write-svg-file-bytes! 'save-svg (svg-document->bytes d) target exists))

(define (call-with-svg-bytes width height proc #:title [title ""]
                             #:description [description ""] #:id-prefix [id-prefix "skia"])
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error 'call-with-svg-bytes "procedure accepting one canvas argument" proc))
  (with-skia ([d (make-svg-document width height #:title title
                                   #:description description #:id-prefix id-prefix)])
    ;; with-skia covers arbitrary raises, breaks, and continuation escapes.
    ;; No completed bytes escape until the callback AND XML finalization succeed.
    (call-with-values (lambda () (proc (svg-document-canvas d))) (lambda ignored (void)))
    (svg-document-finish! d)
    (svg-document->bytes d)))

(define (call-with-svg-string width height proc #:title [title ""]
                              #:description [description ""] #:id-prefix [id-prefix "skia"])
  (bytes->string/utf-8
   (call-with-svg-bytes width height proc #:title title
                        #:description description #:id-prefix id-prefix) #f))

(define (call-with-svg-file filename width height proc #:exists [exists 'error]
                            #:title [title ""] #:description [description ""]
                            #:id-prefix [id-prefix "skia"])
  ;; Fix the absolute destination before a callback can change current-directory.
  (define target (svg-output-path 'call-with-svg-file filename exists))
  (define bs (call-with-svg-bytes width height proc #:title title
                                 #:description description #:id-prefix id-prefix))
  (write-svg-file-bytes! 'call-with-svg-file bs target exists))

;; These two helpers work with every backend, not only SVG. They make the
;; trade-off between editable text, glyph outlines, and raster content explicit.
(define (shaped-run->path sh run)
  (define who 'shaped-run->path)
  (define hh (shaper-h who sh))
  (unless (shaped-run? run) (raise-argument-error who "shaped-run?" run))
  (call-with-owned who (list hh) (lambda (_) (void)))
  (define out (make-path))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! out) (raise e))])
    (for ([gid (in-list (shaped-run-glyphs run))]
          [pos (in-list (shaped-run-positions run))])
      (define gp (font-glyph-path (shaper-font sh) gid))
      ;; Empty/bitmap-only glyphs need not expose an outline. This intentionally
      ;; has the same outline-only limitation as simple-text-path, not a claim
      ;; to preserve color emoji. draw-rasterized preserves rendered glyphs.
      (when gp
        (call-with-skia-resource gp
          (lambda (p) (path-add-path! out p #:dx (car pos) #:dy (cadr pos))))))
    out))

(define (draw-rasterized c x y width height proc
                         #:scale [scale (current-raster-output-scale)]
                         #:padding [padding 0] #:color-space [cs #f])
  (define who 'draw-rasterized)
  (define fx (scalar who x))
  (define fy (scalar who y))
  (define-values (pw ph left top bw bh)
    (rasterized-geometry who width height scale padding))
  (define dx (scalar who (- fx left)))
  (define dy (scalar who (- fy top)))
  (define cs-hnd (optional-color-space-h who cs))
  (output-drawing-procedure who proc)
  ;; Validate all resources before executing user code or allocating a surface.
  (call-on-canvas who c (if cs-hnd (list cs-hnd) '()) (lambda ignored (void)))
  (with-skia ([s (make-surface pw ph #:color-space cs)])
    (define rc (surface-canvas s))
    (canvas-scale! rc (/ pw bw) (/ ph bh))
    (canvas-translate! rc left top)
    ;; Padding expands the image without rescaling/repositioning the original
    ;; content box. Native glyph rendering inside a raster group also preserves
    ;; bitmap/color glyphs that have no monochrome outline.
    (parameterize ([current-text-output-mode 'native])
      (call-with-values (lambda () (proc rc)) (lambda ignored (void))))
    (with-skia ([im (surface-snapshot s)])
      (draw-image-rect c im dx dy bw bh #:sampling 'linear)))
  (void))

(provide document? make-pdf-document document-state document-page-count
         document-begin-page! document-end-page! document-finish! document-abort!
         document->pdf-bytes save-pdf
         call-with-document-page with-document-page
         call-with-pdf-bytes call-with-pdf-file)

;; PDF documents ------------------------------------------------------------
;; One owned handle releases the document before its borrowed output stream.
;; The release closure captures storage, never the wrapper (no finalizer cycle).
(struct pdf-storage ([stream #:mutable] [data #:mutable] [native-closed? #:mutable]))
(struct document (handle storage [status #:mutable] [page #:mutable] [count #:mutable])
  #:constructor-name make-document-record)
;; Each begin-page gets a distinct token. In particular, an old canvas must
;; NEVER become usable again when the same document starts its next page.
(struct pdf-page (document pointer [floors #:mutable] [scoped? #:mutable]))

(define (document-h who d)
  (typed-handle who d document? document-handle "document?"))

(define (document-state d)
  (define h (document-h 'document-state d))
  (if (owned-closed? h)
      (if (eq? (document-status d) 'aborted) 'aborted 'closed)
      (document-status d)))

(define (document-page-count d)
  (document-h 'document-page-count d)
  (document-count d))

(define (pdf-page-closed? p)
  (define d (pdf-page-document p))
  (or (owned-closed? (document-handle d))
      (not (eq? p (document-page d)))))

(define (pdf-page-pointer/checked who p)
  (when (pdf-page-closed? p)
    (error who "PDF page canvas is closed (page ended or document released)"))
  (pdf-page-pointer p))

(define (release-pdf-native! storage dp)
  ;; An unfinished document is aborted rather than accidentally published by
  ;; SkDocument's destructor. No file output or Racket callback occurs here.
  (unless (pdf-storage-native-closed? storage)
    (sk_document_abort dp)
    (set-pdf-storage-native-closed?! storage #t))
  (sk_document_unref dp)
  (when (pdf-storage-data storage)
    (sk_data_unref (pdf-storage-data storage))
    (set-pdf-storage-data! storage #f))
  (when (pdf-storage-stream storage)
    (sk_dynamicmemorywstream_destroy (pdf-storage-stream storage))
    (set-pdf-storage-stream! storage #f)))

(define (call-with-pdf-metadata who fields creation modified dpi quality proc)
  ;; AsDocumentPDFMetadata copies strings/timestamps by value. Keep all
  ;; temporary SkStrings and date structs alive through that conversion.
  (let loop ([remaining fields] [pointers '()])
    (cond
      [(null? remaining)
       (define metadata
         (apply make-sk-pdf-metadata
                (append (reverse pointers) (list creation modified dpi #f quality))))
       (begin0 (proc metadata)
         (void/reference-sink creation modified metadata))]
      [(zero? (bytes-length (car remaining)))
       (loop (cdr remaining) (cons #f pointers))]
      [else
       (define bs (car remaining))
       (call-with-native-temporary
        who 'pdf-metadata-string
        (lambda () (sk_string_new_with_copy bs (bytes-length bs)))
        sk_string_destructor
        (lambda (sp) (loop (cdr remaining) (cons sp pointers))))])))

(define (make-pdf-document #:title [title ""] #:author [author ""]
                           #:subject [subject ""] #:keywords [keywords ""]
                           #:creator [creator "skia-for-racket"]
                           #:producer [producer "Skia/PDF m119; skia-for-racket"]
                           #:creation-date [creation-date #f]
                           #:modified-date [modified-date #f]
                           #:raster-dpi [raster-dpi 144]
                           #:encoding-quality [encoding-quality 101])
  (define who 'make-pdf-document)
  ;; Validate every public option before resolving or loading native code.
  (define fields (pdf-metadata-bytes who (list title author subject keywords creator producer)))
  (define creation (pdf-date-time who creation-date))
  (define modified (pdf-date-time who modified-date))
  (define dpi (pdf-raster-dpi who raster-dpi))
  (define quality (pdf-encoding-quality who encoding-quality))
  (skia-check!)
  (define storage (pdf-storage #f #f #f))
  (define hnd
    (call-with-pdf-metadata
     who fields creation modified dpi quality
     (lambda (metadata)
       (new-owned
        who 'pdf-document
        (lambda ()
          (define sp (sk_dynamicmemorywstream_new))
          (unless sp (error who "native PDF stream allocation failed"))
          (set-pdf-storage-stream! storage sp)
          (with-handlers ([(lambda (_) #t)
                           (lambda (e)
                             (sk_dynamicmemorywstream_destroy sp)
                             (set-pdf-storage-stream! storage #f)
                             (raise e))])
            (define dp (sk_document_create_pdf_from_stream_with_metadata sp metadata))
            (unless dp (error who "native PDF document allocation failed"))
            dp))
        (lambda (dp) (release-pdf-native! storage dp))))))
  (make-document-record hnd storage 'open #f 0))

(define (document-begin-page! d width height)
  (define who 'document-begin-page!)
  (define hnd (document-h who d))
  (define w (pdf-page-dimension who width))
  (define h (pdf-page-dimension who height))
  (call-with-owned
   who (list hnd)
   (lambda (dp)
     (unless (eq? (document-status d) 'open)
       (error who "document must be open and between pages; state: ~a" (document-status d)))
     (define cp (sk_document_begin_page dp w h #f))
     (unless cp
       ;; Native beginPage can enter its in-page state even when its canvas
       ;; allocation fails. Do not leave a half-open document usable.
       (set-document-status! d 'aborted)
       (owned-close! who hnd)
       (error who "native PDF page creation failed"))
     (define page (pdf-page d cp '() #f))
     (set-document-page! d page)
     (set-document-status! d 'page)
     (make-canvas-record page))))

(define (end-document-page! who d expected scoped?)
  (call-with-owned
   who (list (document-h who d))
   (lambda (dp)
     (define page (document-page d))
     (unless (and page (eq? (document-status d) 'page)
                  (or (not expected) (eq? expected page)))
       (error who "document has no matching active PDF page"))
     (when (or (pair? (pdf-page-floors page))
               (and (pdf-page-scoped? page) (not scoped?)))
       (error who "cannot end a protected PDF page or canvas-state scope"))
     (sk_document_end_page dp)
     (set-document-page! d #f)
     (set-document-status! d 'open)
     (set-document-count! d (add1 (document-count d))))))

(define (document-end-page! d)
  (end-document-page! 'document-end-page! d #f #f))

(define (document-finish! d)
  (define who 'document-finish!)
  (define hnd (document-h who d))
  (call-with-owned
   who (list hnd)
   (lambda (dp)
     (unless (eq? (document-status d) 'finished)
       (unless (eq? (document-status d) 'open)
         (error who "end the active PDF page before finishing the document"))
       (unless (positive? (document-count d))
         (error who "a PDF document must contain at least one completed page"))
       (with-handlers ([(lambda (_) #t)
                        (lambda (e)
                          (set-document-status! d 'aborted)
                          (owned-close! who hnd)
                          (raise e))])
         (define storage (document-storage d))
         (sk_document_close dp)
         (set-pdf-storage-native-closed?! storage #t)
         (define data (sk_dynamicmemorywstream_detach_as_data (pdf-storage-stream storage)))
         (unless data (error who "native PDF finalization returned no data"))
         (set-pdf-storage-data! storage data)
         (define n (sk_data_get_size data))
         (unless (<= 1 n (current-skia-byte-limit))
           (error who "PDF output size ~a is empty or exceeds current-skia-byte-limit (~a)"
                  n (current-skia-byte-limit)))
         (set-document-status! d 'finished)))))
  (void))

(define (document-abort! d)
  (define hnd (document-h 'document-abort! d))
  ;; owned-close! checks thread affinity even for an already-closed resource.
  (owned-close! 'document-abort! hnd)
  (set-document-page! d #f)
  (set-document-status! d 'aborted)
  (void))

(define (document->pdf-bytes d)
  (define who 'document->pdf-bytes)
  (call-with-owned
   who (list (document-h who d))
   (lambda (_dp)
     (unless (eq? (document-status d) 'finished)
       (error who "document-finish! must succeed before reading PDF bytes"))
     (copy-native-data who (pdf-storage-data (document-storage d))))))

(define (save-pdf d filename #:exists [exists 'error])
  (define target (pdf-output-path 'save-pdf filename exists))
  (write-pdf-file-bytes! 'save-pdf (document->pdf-bytes d) target exists))

(define (call-with-document-page d width height proc)
  (define who 'call-with-document-page)
  (document-h who d)
  (pdf-page-dimension who width)
  (pdf-page-dimension who height)
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error who "procedure accepting one canvas argument" proc))
  (define c #f)
  (define completed? #f)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       (lambda ()
         (parameterize-break #f
           (set! c (document-begin-page! d width height))
           (set-pdf-page-scoped?! (canvas-resource c) #t)))
       (lambda ()
         (call-with-values
          (lambda () (proc c))
          (lambda results
            (parameterize-break #f
              (end-document-page! who d (canvas-resource c) #t)
              (set! completed? #t))
            (apply values results))))
       (lambda ()
         ;; Includes arbitrary raised values, breaks, and continuation escapes.
         ;; A partially authored page cannot silently become a successful PDF.
         (unless completed? (document-abort! d)))))))

(define-syntax-rule (with-document-page (canvas document width height) body ...)
  (call-with-document-page document width height (lambda (canvas) body ...)))

(define (call-with-pdf-bytes proc
                             #:title [title ""] #:author [author ""]
                             #:subject [subject ""] #:keywords [keywords ""]
                             #:creator [creator "skia-for-racket"]
                             #:producer [producer "Skia/PDF m119; skia-for-racket"]
                             #:creation-date [creation-date #f]
                             #:modified-date [modified-date #f]
                             #:raster-dpi [raster-dpi 144]
                             #:encoding-quality [encoding-quality 101])
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error 'call-with-pdf-bytes "procedure accepting one document argument" proc))
  (with-skia ([d (make-pdf-document
                 #:title title #:author author #:subject subject #:keywords keywords
                 #:creator creator #:producer producer
                 #:creation-date creation-date #:modified-date modified-date
                 #:raster-dpi raster-dpi #:encoding-quality encoding-quality)])
    (call-with-values (lambda () (proc d)) (lambda ignored (void)))
    (document-finish! d)
    (document->pdf-bytes d)))

(define (call-with-pdf-file filename proc #:exists [exists 'error]
                            #:title [title ""] #:author [author ""]
                            #:subject [subject ""] #:keywords [keywords ""]
                            #:creator [creator "skia-for-racket"]
                            #:producer [producer "Skia/PDF m119; skia-for-racket"]
                            #:creation-date [creation-date #f]
                            #:modified-date [modified-date #f]
                            #:raster-dpi [raster-dpi 144]
                            #:encoding-quality [encoding-quality 101])
  ;; Freeze the destination before user code can change current-directory.
  (define target (pdf-output-path 'call-with-pdf-file filename exists))
  (define bs
    (call-with-pdf-bytes
     proc #:title title #:author author #:subject subject #:keywords keywords
     #:creator creator #:producer producer
     #:creation-date creation-date #:modified-date modified-date
     #:raster-dpi raster-dpi #:encoding-quality encoding-quality))
  (write-pdf-file-bytes! 'call-with-pdf-file bs target exists))

(define (optional-color-space-h who cs)
  (cond [(not cs) #f]
        [(color-space? cs) (color-space-h who cs)]
        [else (raise-argument-error who "(or/c #f color-space?)" cs)]))

(define (wrap-owned-color-space who create)
  (make-color-space-record
   (new-owned who 'color-space create sk_colorspace_unref)))

(define (make-ref-counted-singleton-color-space who getter)
  (skia-check!)
  (wrap-owned-color-space
   who
   (lambda ()
     (define ptr (getter))
     (when ptr (sk_colorspace_ref ptr))
     ptr)))

(define (make-srgb-color-space)
  (make-ref-counted-singleton-color-space 'make-srgb-color-space
                                          sk_colorspace_new_srgb))

(define (make-linear-srgb-color-space)
  (make-ref-counted-singleton-color-space 'make-linear-srgb-color-space
                                          sk_colorspace_new_srgb_linear))

(define (positive-profile-bytes who bs)
  (unless (bytes? bs) (raise-argument-error who "bytes?" bs))
  (define n (bytes-length bs))
  (unless (positive? n)
    (raise-arguments-error who "ICC profile bytes are empty" "bytes" bs))
  (unless (<= n (current-skia-byte-limit))
    (raise-arguments-error who "ICC profile exceeds current-skia-byte-limit"
                           "profile bytes" n
                           "limit" (current-skia-byte-limit)))
  n)

(define (color-space-from-icc-bytes bs)
  (define who 'color-space-from-icc-bytes)
  (define n (positive-profile-bytes who bs))
  (skia-check!)
  ;; skcms keeps pointers into the source buffer while the temporary profile is
  ;; being parsed, so copy the bytes into native SKData for the duration of the
  ;; parse. SkColorSpace::Make copies the resulting transfer function/matrix;
  ;; neither the profile nor its backing bytes need to outlive construction.
  (define data (sk_data_new_with_copy bs n))
  (unless data (error who "native ICC data copy failed"))
  (define profile (sk_colorspace_icc_profile_new))
  (unless profile
    (sk_data_unref data)
    (error who "native ICC profile allocation failed"))
  (dynamic-wind
    void
    (lambda ()
      (define src (sk_data_get_data data))
      (unless (and src (sk_colorspace_icc_profile_parse src n profile))
        (error who "invalid or unsupported ICC profile"))
      (define ptr (sk_colorspace_new_icc profile))
      (unless ptr (error who "native color space rejected ICC profile"))
      (wrap-owned-color-space who (lambda () ptr)))
    (lambda ()
      (sk_colorspace_icc_profile_delete profile)
      (sk_data_unref data))))

(define (icc-put-u16! out at n)
  (bytes-set! out at (bitwise-and (arithmetic-shift n -8) #xff))
  (bytes-set! out (+ at 1) (bitwise-and n #xff)))

(define (icc-put-u32! out at n)
  (bytes-set! out at (bitwise-and (arithmetic-shift n -24) #xff))
  (bytes-set! out (+ at 1) (bitwise-and (arithmetic-shift n -16) #xff))
  (bytes-set! out (+ at 2) (bitwise-and (arithmetic-shift n -8) #xff))
  (bytes-set! out (+ at 3) (bitwise-and n #xff)))

(define (icc-put-signature! out at text)
  (define raw (string->bytes/utf-8 text))
  (unless (= (bytes-length raw) 4)
    (error 'color-space->icc-bytes "internal ICC signature is not four bytes: ~s" text))
  (bytes-copy! out at raw))

(define (icc-put-s15fixed16! out at x)
  (define scaled (inexact->exact (round (* (exact->inexact x) 65536.0))))
  (unless (<= (- (expt 2 31)) scaled (sub1 (expt 2 31)))
    (error 'color-space->icc-bytes "ICC fixed-point value is out of range: ~a" x))
  (icc-put-u32! out at (if (negative? scaled) (+ scaled (expt 2 32)) scaled)))

(define (make-icc-xyz-tag x y z)
  (define out (make-bytes 20 0))
  (icc-put-signature! out 0 "XYZ ")
  (icc-put-s15fixed16! out 8 x)
  (icc-put-s15fixed16! out 12 y)
  (icc-put-s15fixed16! out 16 z)
  out)

(define (make-icc-parametric-tag transfer)
  ;; ICC parametricCurveType function 4 is exactly the seven-parameter form
  ;; used by skcms/SkColorSpace: y=(a*x+b)^g+e above d, else c*x+f.
  (define out (make-bytes 40 0))
  (icc-put-signature! out 0 "para")
  (icc-put-u16! out 8 4)
  (for ([x (in-vector transfer)] [at (in-range 12 40 4)])
    (icc-put-s15fixed16! out at x))
  out)

(define (align4 n) (bitwise-and (+ n 3) (bitwise-not 3)))

(define (matrix+trc->icc-bytes transfer xyz)
  ;; Minimal deterministic ICC v4 RGB monitor profile. The XYZ matrix returned
  ;; by Skia is row-major RGB->XYZ(D50); ICC rXYZ/gXYZ/bXYZ tags are its columns.
  (define tags
    (list
     (cons "rXYZ" (make-icc-xyz-tag (vector-ref xyz 0)
                                     (vector-ref xyz 3)
                                     (vector-ref xyz 6)))
     (cons "gXYZ" (make-icc-xyz-tag (vector-ref xyz 1)
                                     (vector-ref xyz 4)
                                     (vector-ref xyz 7)))
     (cons "bXYZ" (make-icc-xyz-tag (vector-ref xyz 2)
                                     (vector-ref xyz 5)
                                     (vector-ref xyz 8)))
     (cons "wtpt" (make-icc-xyz-tag 0.9642 1.0 0.8249))
     (cons "rTRC" (make-icc-parametric-tag transfer))
     (cons "gTRC" (make-icc-parametric-tag transfer))
     (cons "bTRC" (make-icc-parametric-tag transfer))))
  (define table-end (+ 128 4 (* 12 (length tags))))
  (define total
    (+ table-end
       (for/sum ([tag (in-list tags)])
         (align4 (bytes-length (cdr tag))))))
  (define out (make-bytes total 0))
  ;; ICC header.
  (icc-put-u32! out 0 total)
  (icc-put-u32! out 8 #x04300000) ; ICC v4.3
  (icc-put-signature! out 12 "mntr")
  (icc-put-signature! out 16 "RGB ")
  (icc-put-signature! out 20 "XYZ ")
  ;; Fixed deterministic creation date: 2026-09-25 00:00:00.
  (for ([n (in-list '(2026 9 25 0 0 0))] [at (in-range 24 36 2)])
    (icc-put-u16! out at n))
  (icc-put-signature! out 36 "acsp")
  (icc-put-s15fixed16! out 68 0.9642)
  (icc-put-s15fixed16! out 72 1.0)
  (icc-put-s15fixed16! out 76 0.8249)
  (icc-put-signature! out 80 "Rkt ")
  ;; Tag table and aligned payloads.
  (icc-put-u32! out 128 (length tags))
  (let loop ([rest tags] [entry-at 132] [data-at table-end])
    (unless (null? rest)
      (define sig (caar rest))
      (define payload (cdar rest))
      (define n (bytes-length payload))
      (icc-put-signature! out entry-at sig)
      (icc-put-u32! out (+ entry-at 4) data-at)
      (icc-put-u32! out (+ entry-at 8) n)
      (bytes-copy! out data-at payload)
      (loop (cdr rest) (+ entry-at 12) (+ data-at (align4 n)))))
  out)

(define (color-space->icc-bytes cs)
  (define who 'color-space->icc-bytes)
  (define hnd (color-space-h who cs))
  (skia-check!)
  (call-with-owned
   who (list hnd)
   (lambda (cp)
     (define transfer-ptr (malloc (* 7 (ctype-sizeof _float)) 'atomic))
     (define xyz-ptr (malloc (* 9 (ctype-sizeof _float)) 'atomic))
     (unless (sk_colorspace_is_numerical_transfer_fn cp transfer-ptr)
       (error who "color space has no numerical transfer function suitable for ICC export"))
     (unless (sk_colorspace_to_xyzd50 cp xyz-ptr)
       (error who "color space has no XYZ D50 matrix suitable for ICC export"))
     (define transfer
       (for/vector ([i (in-range 7)]) (ptr-ref transfer-ptr _float i)))
     (define xyz
       (for/vector ([i (in-range 9)]) (ptr-ref xyz-ptr _float i)))
     (define out (matrix+trc->icc-bytes transfer xyz))
     (unless (<= (bytes-length out) (current-skia-byte-limit))
       (error who "ICC profile size ~a exceeds current-skia-byte-limit"
              (bytes-length out)))
     out)))

(define (color-space-srgb? cs)
  (define who 'color-space-srgb?)
  (call-with-owned who (list (color-space-h who cs)) sk_colorspace_is_srgb))

(define (color-space-linear-gamma? cs)
  (define who 'color-space-linear-gamma?)
  (call-with-owned who (list (color-space-h who cs)) sk_colorspace_gamma_is_linear))

(define (color-space-gamma-close-to-srgb? cs)
  (define who 'color-space-gamma-close-to-srgb?)
  (call-with-owned who (list (color-space-h who cs)) sk_colorspace_gamma_close_to_srgb))

(define (color-space=? a b)
  (define who 'color-space=?)
  (call-with-owned who (list (color-space-h who a) (color-space-h who b))
                   sk_colorspace_equals))

(define (color-space->linear-gamma cs)
  (define who 'color-space->linear-gamma)
  (define ptr
    (call-with-owned who (list (color-space-h who cs)) sk_colorspace_make_linear_gamma))
  (wrap-owned-color-space who (lambda () ptr)))

(define (color-space->srgb-gamma cs)
  (define who 'color-space->srgb-gamma)
  (define ptr
    (call-with-owned who (list (color-space-h who cs)) sk_colorspace_make_srgb_gamma))
  (wrap-owned-color-space who (lambda () ptr)))

;; Surfaces -----------------------------------------------------------------

(define (make-surface w h #:background [background 'transparent]
                      #:color-space [cs #f])
  (define who 'make-surface)
  (check-dimensions who w h)
  (define argb (color->argb background))
  (define cs-hnd (optional-color-space-h who cs))
  (skia-check!)
  (define ptr
    (if cs-hnd
        (call-with-owned
         who (list cs-hnd)
         (lambda (cp)
           (sk_surface_new_raster
            (make-sk-image-info cp w h rgba-8888 alpha-premul) 0 #f)))
        (sk_surface_new_raster
         (make-sk-image-info #f w h rgba-8888 alpha-premul) 0 #f)))
  (define hnd
    (new-owned who 'surface (lambda () ptr) sk_surface_unref))
  (initialize-resource
   (make-surface-record hnd w h '())
   (lambda (s) (canvas-clear! (surface-canvas s) argb))))

(define (surface-canvas s)
  (call-with-owned 'surface-canvas (list (surface-h 'surface-canvas s))
                   (lambda (_) (make-canvas-record s))))

(define (surface-color-space s)
  (call-with-skia-resource (surface-snapshot s) image-color-space))

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

(define (surface->rgba-bytes s #:premultiplied? [premultiplied? #f]
                             #:color-space [cs #f])
  (define who 'surface->rgba-bytes)
  (define hnd (surface-h who s))
  (boolean who premultiplied?)
  (define cs-hnd (optional-color-space-h who cs))
  (define w (surface-width s))
  (define h (surface-height s))
  (define out (make-bytes (check-dimensions who w h)))
  (define handles (if cs-hnd (list hnd cs-hnd) (list hnd)))
  (call-with-owned
   who handles
   (lambda (sp . rest)
     (define cp (and (pair? rest) (car rest)))
     (unless (sk_surface_read_pixels
              sp (make-sk-image-info cp w h rgba-8888
                                     (if premultiplied? alpha-premul alpha-unpremul))
              out (* 4 w) 0 0)
       (error who "native pixel read failed"))))
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
         (unless (skia-closed? c)
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
         [(list 'rmove dx dy) (path-rmove-to! p dx dy)]
         [(list 'line x y) (path-line-to! p x y)]
         [(list 'rline dx dy) (path-rline-to! p dx dy)]
         [(list 'quad cx cy x y) (path-quad-to! p cx cy x y)]
         [(list 'rquad dcx dcy dx dy) (path-rquad-to! p dcx dcy dx dy)]
         [(list 'conic cx cy x y weight) (path-conic-to! p cx cy x y weight)]
         [(list 'rconic dcx dcy dx dy weight) (path-rconic-to! p dcx dcy dx dy weight)]
         [(list 'cubic cx1 cy1 cx2 cy2 x y) (path-cubic-to! p cx1 cy1 cx2 cy2 x y)]
         [(list 'rcubic dcx1 dcy1 dcx2 dcy2 dx dy) (path-rcubic-to! p dcx1 dcy1 dcx2 dcy2 dx dy)]
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

;; Font managers, typefaces, fonts, and text blobs --------------------------

(define (make-font-manager)
  (skia-check!)
  (make-font-manager-record
   (new-owned 'make-font-manager 'font-manager sk_fontmgr_create_default sk_fontmgr_unref)))

(define (default-font-manager)
  (skia-check!)
  (make-font-manager-record
   (new-owned 'default-font-manager 'font-manager sk_fontmgr_ref_default sk_fontmgr_unref)))

(define (font-manager-family-count fm)
  (call-with-owned 'font-manager-family-count
                   (list (font-manager-h 'font-manager-family-count fm))
                   sk_fontmgr_count_families))

(define (font-manager-family-name fm index)
  (define who 'font-manager-family-name)
  (unless (exact-nonnegative-integer? index)
    (raise-argument-error who "exact-nonnegative-integer?" index))
  (call-with-owned
   who (list (font-manager-h who fm))
   (lambda (mp)
     (define n (sk_fontmgr_count_families mp))
     (unless (< index n)
       (raise-arguments-error who "family index out of range" "index" index "count" n))
     (call-with-native-temporary
      who 'native-string sk_string_new_empty sk_string_destructor
      (lambda (sp)
        (sk_fontmgr_get_family_name mp index sp)
        (copy-sk-string who sp))))))

(define (font-manager-families fm)
  (for/list ([i (in-range (font-manager-family-count fm))])
    (font-manager-family-name fm i)))

(define (native-c-string-pointer who value description)
  (define str (nul-free-string who value description))
  (define bs (nul-terminated-bytes (string->bytes/utf-8 str)))
  (define ptr (malloc (bytes-length bs) _byte 'atomic))
  (memcpy ptr bs (bytes-length bs))
  ptr)

(define (font-manager-style-values who weight width slant)
  (values (font-weight who weight)
          (font-width who width)
          (choice who slant font-slant-values)))

(define (wrap-matched-typeface who ptr)
  (and ptr
       (make-typeface-record
        (new-owned who 'typeface (lambda () ptr) sk_typeface_unref))))

(define (font-manager-match-family fm family
                                   #:weight [weight 'normal]
                                   #:width [width 'normal]
                                   #:slant [slant 'upright])
  (define who 'font-manager-match-family)
  (define fmh (font-manager-h who fm))
  (define family-ptr (native-c-string-pointer who family "string?"))
  (define-values (wt wd sl) (font-manager-style-values who weight width slant))
  (skia-check!)
  (call-with-native-temporary
   who 'font-style (lambda () (sk_fontstyle_new wt wd sl)) sk_fontstyle_delete
   (lambda (style-ptr)
     (call-with-owned
      who (list fmh)
      (lambda (mp)
        (define result (sk_fontmgr_match_family_style mp family-ptr style-ptr))
        (void (ptr-ref family-ptr _byte 0))
        (wrap-matched-typeface who result))))))

(define (font-manager-match-character fm character
                                      #:family [family #f]
                                      #:weight [weight 'normal]
                                      #:width [width 'normal]
                                      #:slant [slant 'upright]
                                      #:languages [languages '()])
  (define who 'font-manager-match-character)
  (define fmh (font-manager-h who fm))
  (define codepoint (unicode-scalar who character))
  (unless (or (not family) (string? family))
    (raise-argument-error who "(or/c #f string?)" family))
  (unless (list? languages)
    (raise-argument-error who "list? of language-tag strings" languages))
  (define family-ptr
    (and family (native-c-string-pointer who family "string?")))
  (define language-ptrs
    (for/list ([language (in-list languages)])
      (native-c-string-pointer who language "language-tag string?")))
  (define language-array
    (and (pair? language-ptrs)
         (let ([p (malloc (length language-ptrs) _pointer 'atomic)])
           (for ([lp (in-list language-ptrs)] [i (in-naturals)])
             (ptr-set! p _pointer i lp))
           p)))
  (define-values (wt wd sl) (font-manager-style-values who weight width slant))
  (skia-check!)
  (call-with-native-temporary
   who 'font-style (lambda () (sk_fontstyle_new wt wd sl)) sk_fontstyle_delete
   (lambda (style-ptr)
     (call-with-owned
      who (list fmh)
      (lambda (mp)
        (define result
          (sk_fontmgr_match_family_style_character
           mp family-ptr style-ptr language-array (length language-ptrs) codepoint))
        (when family-ptr (void (ptr-ref family-ptr _byte 0)))
        (when language-array (void (ptr-ref language-array _pointer 0)))
        (for ([lp (in-list language-ptrs)]) (void (ptr-ref lp _byte 0)))
        (wrap-matched-typeface who result))))))

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
  (define handles (list (font-h who f) (paint-h who p)))
  (cond
    [(eq? (current-text-output-mode) 'outline)
     (call-on-canvas who c handles (lambda ignored (void)))
     (with-skia ([outline (simple-text-path f text fx fy)])
       (draw-path c outline p))]
    [else
     (call-on-canvas
      who c handles
      (lambda (cp fp pp)
        (sk_canvas_draw_simple_text cp bs (bytes-length bs) text-encoding-utf8
                                    fx fy fp pp)))]))

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

(define (glyph-sequence who glyphs)
  (define xs
    (cond [(vector? glyphs) (vector->list glyphs)]
          [(list? glyphs) glyphs]
          [else (raise-argument-error who "list? or vector? of glyph ids" glyphs)]))
  (for/list ([g (in-list xs)]) (glyph-id who g)))

(define (position-sequence who positions)
  (define xs
    (cond [(vector? positions) (vector->list positions)]
          [(list? positions) positions]
          [else (raise-argument-error who "list? or vector? of (list x y) positions" positions)]))
  (for/list ([position (in-list xs)])
    (match position
      [(list x y) (list (scalar who x) (scalar who y))]
      [(vector x y) (list (scalar who x) (scalar who y))]
      [_ (raise-argument-error who "(list x y) or #(x y) position" position)])))

(define (make-positioned-text-blob f glyphs positions)
  (define who 'make-positioned-text-blob)
  (define fh (font-h who f))
  (define gs (glyph-sequence who glyphs))
  (define ps (position-sequence who positions))
  (unless (= (length gs) (length ps))
    (raise-arguments-error who "glyph and position counts differ"
                           "glyph count" (length gs)
                           "position count" (length ps)))
  (unless (pair? gs)
    (raise-arguments-error who "at least one glyph is required" "glyphs" glyphs))
  (define bytes-required (* (length gs) (+ (ctype-sizeof _uint16) (ctype-sizeof _sk-point))))
  (unless (<= bytes-required (current-skia-byte-limit))
    (raise-arguments-error who "text-blob input exceeds current-skia-byte-limit"
                           "required bytes" bytes-required
                           "limit" (current-skia-byte-limit)))
  (skia-check!)
  (call-with-native-temporary
   who 'text-blob-builder sk_textblob_builder_new sk_textblob_builder_delete
   (lambda (builder)
     (call-with-owned
      who (list fh)
      (lambda (fp)
        (define runbuffer (make-sk-textblob-runbuffer #f #f #f #f))
        (sk_textblob_builder_alloc_run_pos builder fp (length gs) #f runbuffer)
        (define glyph-ptr (sk-textblob-runbuffer-glyphs runbuffer))
        (define pos-ptr (sk-textblob-runbuffer-pos runbuffer))
        (unless (and glyph-ptr pos-ptr)
          (error who "native text-blob builder returned null run buffers"))
        (for ([g (in-list gs)] [i (in-naturals)])
          (ptr-set! glyph-ptr _uint16 i g))
        (for ([xy (in-list ps)] [i (in-naturals)])
          ;; sk_point_t is exactly two consecutive C floats.
          (ptr-set! pos-ptr _float (* 2 i) (car xy))
          (ptr-set! pos-ptr _float (add1 (* 2 i)) (cadr xy)))
        (define blob-ptr (sk_textblob_builder_make builder))
        (unless blob-ptr
          (error who "native text-blob builder produced no blob"))
        (define hnd (new-owned who 'text-blob (lambda () blob-ptr) sk_textblob_unref))
        (with-handlers ([(lambda (_) #t)
                         (lambda (e) (owned-close! who hnd) (raise e))])
          (call-with-native-temporary
           who 'text-blob-typeface
           (lambda () (sk_font_get_typeface fp)) sk_typeface_unref
           (lambda (tp)
             (define snapshot (copy-font-for-shaper who fp tp))
             (make-text-blob-record hnd snapshot gs ps)))))))))

(define (text-blob-bounds blob)
  (define who 'text-blob-bounds)
  (define r (make-sk-rect 0.0 0.0 0.0 0.0))
  (call-with-owned who (list (text-blob-h who blob))
    (lambda (bp) (sk_textblob_get_bounds bp r)))
  (values (sk-rect-left r) (sk-rect-top r)
          (- (sk-rect-right r) (sk-rect-left r))
          (- (sk-rect-bottom r) (sk-rect-top r))))

(define (text-blob-unique-id blob)
  (call-with-owned 'text-blob-unique-id
                   (list (text-blob-h 'text-blob-unique-id blob))
                   sk_textblob_get_unique_id))

(define (text-blob->path blob)
  (define who 'text-blob->path)
  (call-with-owned who (list (text-blob-h who blob)) (lambda (_) (void)))
  (define out (make-path))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! out) (raise e))])
    (for ([gid (in-list (text-blob-glyphs blob))]
          [pos (in-list (text-blob-positions blob))])
      (define gp (font-glyph-path (text-blob-font blob) gid))
      ;; Spaces and bitmap-only/color glyphs need not have monochrome outlines.
      (when gp
        (call-with-skia-resource gp
          (lambda (p) (path-add-path! out p #:dx (car pos) #:dy (cadr pos))))))
    out))

(define (draw-text-blob c blob x y p)
  (define who 'draw-text-blob)
  (define fx (scalar who x))
  (define fy (scalar who y))
  (define handles (list (text-blob-h who blob) (paint-h who p)))
  (cond
    [(eq? (current-text-output-mode) 'outline)
     (call-on-canvas who c handles (lambda ignored (void)))
     (with-skia ([outline (text-blob->path blob)])
       (with-canvas-state c
         (canvas-translate! c fx fy)
         (draw-path c outline p)))]
    [else
     (call-on-canvas who c handles
       (lambda (cp bp pp) (sk_canvas_draw_text_blob cp bp fx fy pp)))]))


;; HarfBuzz shaping ---------------------------------------------------------

(define (copy-font-for-shaper who font-ptr typeface-ptr)
  (define size (sk_font_get_size font-ptr))
  (define scale-x (sk_font_get_scale_x font-ptr))
  (define skew-x (sk_font_get_skew_x font-ptr))
  (define hnd
    (new-owned who 'shaper-font
               (lambda () (sk_font_new_with_values typeface-ptr size scale-x skew-x))
               sk_font_delete))
  (define result (make-font-record hnd #f))
  (with-handlers ([exn? (lambda (e) (skia-close! result) (raise e))])
    (call-with-owned
     who (list hnd)
     (lambda (fp)
       (sk_font_set_edging fp (sk_font_get_edging font-ptr))
       (sk_font_set_hinting fp (sk_font_get_hinting font-ptr))
       (sk_font_set_subpixel fp (sk_font_is_subpixel font-ptr))
       (sk_font_set_linear_metrics fp (sk_font_is_linear_metrics font-ptr))
       (sk_font_set_embolden fp (sk_font_is_embolden font-ptr))))
    result))

(define (typeface-font-bytes who typeface-ptr)
  (define ttc-index (malloc _int 'atomic))
  (ptr-set! ttc-index _int 0)
  (call-with-native-temporary
   who 'font-stream
   (lambda () (sk_typeface_open_stream typeface-ptr ttc-index))
   sk_stream_asset_destroy
   (lambda (stream)
     (define n (sk_stream_get_length stream))
     (unless (and (exact-nonnegative-integer? n)
                  (<= n (current-skia-byte-limit)))
       (error who "font stream size ~a exceeds current-skia-byte-limit" n))
     (unless (positive? n)
       (error who "typeface exposed an empty font stream"))
     (define bytes (make-bytes n))
     (define got (sk_stream_read stream bytes n))
     (unless (= got n)
       (error who "font stream short read: expected ~a bytes, got ~a" n got))
     (define index (ptr-ref ttc-index _int))
     (unless (<= 0 index #xffffffff)
       (error who "typeface returned invalid collection index ~a" index))
     (values bytes index))))

(define (make-hb-font who typeface-ptr)
  (harfbuzz-check!)
  (define-values (font-bytes ttc-index) (typeface-font-bytes who typeface-ptr))
  (define units-per-em (sk_typeface_get_units_per_em typeface-ptr))
  (call-with-native-temporary
   who 'harfbuzz-blob
   (lambda ()
     (hb_blob_create font-bytes (bytes-length font-bytes)
                     hb-memory-mode-duplicate #f #f))
   hb_blob_destroy
   (lambda (blob)
     (call-with-native-temporary
      who 'harfbuzz-face
      (lambda () (hb_face_create blob ttc-index))
      hb_face_destroy
      (lambda (face)
        (when (positive? units-per-em)
          (hb_face_set_upem face units-per-em))
        (define hb-font
          (new-owned who 'harfbuzz-font
                     (lambda () (hb_font_create face))
                     hb_font_destroy))
        (with-handlers ([exn? (lambda (e) (owned-close! who hb-font) (raise e))])
          (call-with-owned
           who (list hb-font)
           (lambda (hp)
             (hb_font_set_scale hp hb-font-size-scale hb-font-size-scale)
             (hb_ot_font_set_funcs hp)))
          hb-font))))))

(define (make-shaper f)
  (define who 'make-shaper)
  (define fh (font-h who f))
  (skia-check!)
  (harfbuzz-check!)
  (call-with-owned
   who (list fh)
   (lambda (font-ptr)
     ;; sk_font_get_typeface returns one owned reference in the pinned C shim.
     (call-with-native-temporary
      who 'typeface-from-font
      (lambda () (sk_font_get_typeface font-ptr))
      sk_typeface_unref
      (lambda (typeface-ptr)
        (define private-font (copy-font-for-shaper who font-ptr typeface-ptr))
        (with-handlers ([exn? (lambda (e) (skia-close! private-font) (raise e))])
          (define hb-font (make-hb-font who typeface-ptr))
          (make-shaper-record hb-font private-font)))))))

(define (shaped-run-glyph-count run)
  (unless (shaped-run? run)
    (raise-argument-error 'shaped-run-glyph-count "shaped-run?" run))
  (length (shaped-run-glyphs run)))

(define (normalize-shape-direction who direction)
  (unless (memq direction '(auto ltr rtl ttb btt))
    (raise-argument-error who "one of 'auto, 'ltr, 'rtl, 'ttb, or 'btt" direction))
  direction)

(define (normalize-shape-script who script)
  (cond [(not script) #f]
        [(symbol? script) (symbol->string script)]
        [(string? script) script]
        [else (raise-argument-error who "(or/c #f symbol? string?)" script)]))

(define (normalize-shape-language who language)
  (cond [(not language) #f]
        [(string? language)
         (nul-free-string who language "language string")]
        [else (raise-argument-error who "(or/c #f string?)" language)]))

(define (normalize-shape-features who features)
  (define xs
    (cond [(list? features) features]
          [(vector? features) (vector->list features)]
          [else (raise-argument-error who "list? or vector? of HarfBuzz feature strings" features)]))
  (for/list ([feature (in-list xs)])
    (nul-free-string who feature "HarfBuzz feature string")))

(define (make-hb-feature-array who features)
  (define count (length features))
  (if (zero? count)
      (values #f 0)
      (let* ([size (ctype-sizeof _hb-feature)]
             [ptr (malloc (* count size) 'atomic)])
        (for ([feature (in-list features)] [i (in-naturals)])
          (define bs (string->bytes/utf-8 feature))
          (unless (hb_feature_from_string bs (bytes-length bs) (ptr-add ptr (* i size)))
            (raise-arguments-error who "invalid HarfBuzz feature" "feature" feature)))
        (values ptr count))))

(define (shape-text sh text
                    #:direction [direction 'auto]
                    #:script [script #f]
                    #:language [language #f]
                    #:features [features '()])
  (define who 'shape-text)
  (define hh (shaper-h who sh))
  (unless (string? text) (raise-argument-error who "string?" text))
  (define dir (normalize-shape-direction who direction))
  (define scr (normalize-shape-script who script))
  (define lang (normalize-shape-language who language))
  (define feats (normalize-shape-features who features))
  (define utf8 (string->bytes/utf-8 text))
  (define private-font (shaper-font sh))
  (define font-size-value (font-size private-font))
  (define font-scale-value (font-scale-x private-font))
  (define text-size-y (/ font-size-value hb-font-size-scale))
  (define text-size-x (* text-size-y font-scale-value))
  (call-with-owned
   who (list hh)
   (lambda (hb-font)
     (if (zero? (bytes-length utf8))
         (shaped-run '() '() '() 0.0 0.0)
         (call-with-native-temporary
          who 'harfbuzz-buffer hb_buffer_create hb_buffer_destroy
          (lambda (buffer)
            (hb_buffer_add_utf8 buffer utf8 (bytes-length utf8) 0 (bytes-length utf8))
            (hb_buffer_guess_segment_properties buffer)
            (unless (eq? dir 'auto)
              (let* ([db (string->bytes/utf-8 (symbol->string dir))]
                     [d (hb_direction_from_string db (bytes-length db))])
                (when (zero? d) (error who "HarfBuzz rejected direction ~a" dir))
                (hb_buffer_set_direction buffer d)))
            (when scr
              (let* ([sb (string->bytes/utf-8 scr)]
                     [sv (hb_script_from_string sb (bytes-length sb))])
                (when (zero? sv)
                  (raise-arguments-error who "invalid HarfBuzz script" "script" script))
                (hb_buffer_set_script buffer sv)))
            (when lang
              (let* ([lb (string->bytes/utf-8 lang)]
                     [lv (hb_language_from_string lb (bytes-length lb))])
                (unless lv
                  (raise-arguments-error who "invalid HarfBuzz language" "language" lang))
                (hb_buffer_set_language buffer lv)))
            (define-values (feature-ptr feature-count)
              (make-hb-feature-array who feats))
            (hb_shape hb-font buffer feature-ptr feature-count)
            (define count (hb_buffer_get_length buffer))
            (define n1 (malloc _uint32 'atomic))
            (define n2 (malloc _uint32 'atomic))
            (ptr-set! n1 _uint32 count)
            (ptr-set! n2 _uint32 count)
            (define infos (hb_buffer_get_glyph_infos buffer n1))
            (define positions (hb_buffer_get_glyph_positions buffer n2))
            (unless (and (= (ptr-ref n1 _uint32) count)
                         (= (ptr-ref n2 _uint32) count)
                         (or (zero? count) (and infos positions)))
              (error who "HarfBuzz returned inconsistent glyph buffers"))
            (define glyphs '())
            (define clusters '())
            (define points '())
            (define x 0.0)
            (define y 0.0)
            (for ([i (in-range count)])
              (define info (ptr-ref infos _hb-glyph-info i))
              (define pos (ptr-ref positions _hb-glyph-position i))
              (define glyph (hb-glyph-info-codepoint info))
              (unless (<= glyph #xffff)
                (error who "glyph id ~a cannot be represented by Skia's uint16 text-blob API" glyph))
              (set! glyphs (cons glyph glyphs))
              (set! clusters (cons (hb-glyph-info-cluster info) clusters))
              (set! points
                    (cons (list (+ x (* (hb-glyph-position-x-offset pos) text-size-x))
                                (- y (* (hb-glyph-position-y-offset pos) text-size-y)))
                          points))
              (set! x (+ x (* (hb-glyph-position-x-advance pos) text-size-x)))
              (set! y (+ y (* (hb-glyph-position-y-advance pos) text-size-y))))
            (shaped-run (reverse glyphs) (reverse clusters) (reverse points) x y)))))))

(define (shaped-run->text-blob sh run)
  (define who 'shaped-run->text-blob)
  (shaper-h who sh)
  (unless (shaped-run? run) (raise-argument-error who "shaped-run?" run))
  (when (null? (shaped-run-glyphs run))
    (raise-arguments-error who "cannot create a text blob from an empty shaped run" "run" run))
  (make-positioned-text-blob (shaper-font sh)
                             (shaped-run-glyphs run)
                             (shaped-run-positions run)))

(define (draw-shaped-run c sh run x y p)
  (define who 'draw-shaped-run)
  (shaper-h who sh)
  (unless (shaped-run? run) (raise-argument-error who "shaped-run?" run))
  (cond
    [(null? (shaped-run-glyphs run)) (void)]
    [(eq? (current-text-output-mode) 'outline)
     (define fx (scalar who x))
     (define fy (scalar who y))
     (call-on-canvas who c (list (shaper-h who sh) (paint-h who p)) (lambda ignored (void)))
     (with-skia ([outline (shaped-run->path sh run)])
       (with-canvas-state c
         (canvas-translate! c fx fy)
         (draw-path c outline p)))]
    [else
     (with-skia ([blob (shaped-run->text-blob sh run)])
       (draw-text-blob c blob x y p))]))

(define (draw-shaped-text c sh text x y p
                          #:direction [direction 'auto]
                          #:script [script #f]
                          #:language [language #f]
                          #:features [features '()])
  (define run
    (shape-text sh text
                #:direction direction
                #:script script
                #:language language
                #:features features))
  (draw-shaped-run c sh run x y p)
  run)


;; Paragraph text layout ----------------------------------------------------

(define (text-layout-line-count layout)
  (unless (text-layout? layout)
    (raise-argument-error 'text-layout-line-count "text-layout?" layout))
  (length (text-layout-lines layout)))

(define (normalize-layout-direction who direction)
  (unless (memq direction '(auto ltr rtl))
    (raise-argument-error who "one of 'auto, 'ltr, or 'rtl" direction))
  direction)

(define (normalize-layout-align who align)
  (unless (memq align '(start center end left right justify justify-all))
    (raise-argument-error
     who
     "one of 'start, 'center, 'end, 'left, 'right, 'justify, or 'justify-all"
     align))
  align)

(define (normalize-layout-width who width)
  (cond [(not width) #f]
        [else (positive-scalar who width)]))

(define (layout-break-insert-valid? insert)
  (for/and ([ch (in-string insert)])
    (and (not (bidi-explicit-control? ch))
         (not (memv ch '(#\newline #\return #\u000B #\u000C
                         #\u0085 #\u2028 #\u2029))))))

(define (make-layout-break-opportunity index [insert ""])
  (unless (and (exact-integer? index) (>= index 0))
    (raise-argument-error 'make-layout-break-opportunity
                          "exact-nonnegative-integer?" index))
  (unless (string? insert)
    (raise-argument-error 'make-layout-break-opportunity "string?" insert))
  (unless (layout-break-insert-valid? insert)
    (raise-arguments-error
     'make-layout-break-opportunity
     "insert must not contain hard line breaks or bidi formatting controls"
     "insert" insert))
  (make-layout-break-opportunity-record index insert))

(struct wrap-break (index insert) #:transparent)

(define (normalize-layout-break-provider who provider)
  (cond
    [(not provider) #f]
    [(and (procedure? provider) (procedure-arity-includes? provider 2)) provider]
    [else
     (raise-argument-error
      who
      "#f or a procedure accepting (paragraph language)"
      provider)]))

(define (grapheme-boundary-table text)
  (define n (string-length text))
  (define boundaries (make-hasheqv))
  (hash-set! boundaries 0 #t)
  (let loop ([i 0])
    (when (< i n)
      (define next (+ i (string-grapheme-span text i n)))
      (hash-set! boundaries next #t)
      (loop next)))
  boundaries)

(define (provider-wrap-breaks who provider text language)
  (cond
    [(not provider) '()]
    [else
     (define supplied (provider text language))
     (unless (list? supplied)
       (raise-arguments-error who
                              "break provider must return a list"
                              "result" supplied))
     (define n (string-length text))
     (define boundaries (grapheme-boundary-table text))
     (define by-index (make-hasheqv))
     (for ([item (in-list supplied)])
       (define opportunity
         (cond
           [(and (exact-integer? item) (>= item 0))
            (make-layout-break-opportunity item)]
           [(layout-break-opportunity? item) item]
           [else
            (raise-arguments-error
             who
             "break provider entries must be exact indices or layout-break-opportunity values"
             "entry" item)]))
       (define index (layout-break-opportunity-index opportunity))
       (define insert (layout-break-opportunity-insert opportunity))
       (unless (and (> index 0) (< index n))
         (raise-arguments-error who
                                "break provider index must be inside the paragraph"
                                "index" index
                                "paragraph-length" n))
       (unless (hash-ref boundaries index #f)
         (raise-arguments-error
          who
          "break provider index must be a default grapheme-cluster boundary"
          "index" index))
       (when (hash-has-key? by-index index)
         (define previous (hash-ref by-index index))
         (unless (string=? previous insert)
           (raise-arguments-error
            who
            "break provider returned conflicting insertions for one index"
            "index" index
            "first" previous
            "second" insert)))
       (hash-set! by-index index insert))
     (sort
      (for/list ([(index insert) (in-hash by-index)])
        (wrap-break index insert))
      < #:key wrap-break-index)]))

(define (combined-wrap-breaks who text language break-provider)
  ;; Higher-level opportunities supplement rather than replace UAX #14. A
  ;; provider entry at an already-legal boundary may attach display-only text.
  (define by-index (make-hasheqv))
  (for ([op (in-list (line-break-opportunities text))]
        #:when (positive? (line-break-opportunity-index op)))
    (hash-set! by-index (line-break-opportunity-index op) ""))
  (for ([br (in-list (provider-wrap-breaks who break-provider text language))])
    (hash-set! by-index (wrap-break-index br) (wrap-break-insert br)))
  (sort
   (for/list ([(index insert) (in-hash by-index)])
     (wrap-break index insert))
   < #:key wrap-break-index))

(define (split-explicit-lines text)
  ;; UAX #14 hard line breaks (BK/CR/LF/NL) delimit layout paragraphs. The
  ;; separators themselves are not shaped; empty and trailing lines survive.
  (split-hard-lines text))

(define (breakable-layout-whitespace? ch)
  ;; Trimming policy at an actual wrap boundary. UAX #14 decides *where* a
  ;; break is legal; ordinary whitespace at that chosen boundary is omitted
  ;; from the visual line, while no-break spaces remain part of the text.
  (and (char-whitespace? ch)
       (not (or (char=? ch #\u00A0) (char=? ch #\u202F)))))

(define (trim-wrap-end text start end)
  (let loop ([i end])
    (if (and (> i start)
             (breakable-layout-whitespace? (string-ref text (sub1 i))))
        (loop (sub1 i))
        i)))

(define (skip-wrap-leading-whitespace text start)
  (define n (string-length text))
  (let loop ([i start])
    (if (and (< i n) (breakable-layout-whitespace? (string-ref text i)))
        (loop (add1 i))
        i)))

(define (wrap-at-line-breaks text max-width measure
                             [break-provider #f] [language #f]
                             [who 'layout-text])
  ;; Greedy line fitting over UAX #14 plus higher-level opportunities. A
  ;; provider insertion is rendered only when that break is actually selected.
  (define n (string-length text))
  (define breaks (combined-wrap-breaks who text language break-provider))
  (define first-start (skip-wrap-leading-whitespace text 0))
  (cond
    [(= first-start n) (list "")]
    [else
     (let wrap ([start first-start] [acc '()])
       (define candidates
         (let drop ([xs breaks])
           (cond [(null? xs) '()]
                 [(<= (wrap-break-index (car xs)) start) (drop (cdr xs))]
                 [else xs])))
       (let choose ([xs candidates] [best #f])
         (cond
           [(null? xs)
            (reverse (cons (substring text start n) acc))]
           [else
            (define br (car xs))
            (define pos (wrap-break-index br))
            (define insert (wrap-break-insert br))
            (define render-end (trim-wrap-end text start pos))
            (define candidate
              (string-append (substring text start render-end) insert))
            (define fits? (<= (measure candidate) max-width))
            (cond
              [(and fits? (= pos n))
               (reverse (cons candidate acc))]
              [fits? (choose (cdr xs) br)]
              [else
               ;; Preserve an over-wide first legal segment rather than
               ;; synthesizing an emergency break inside an unbreakable span.
               (define chosen (or best br))
               (define chosen-pos (wrap-break-index chosen))
               (define chosen-end (trim-wrap-end text start chosen-pos))
               (define line
                 (string-append (substring text start chosen-end)
                                (wrap-break-insert chosen)))
               (define next-start
                 (skip-wrap-leading-whitespace text chosen-pos))
               (if (>= next-start n)
                   (reverse (cons line acc))
                   (wrap next-start (cons line acc)))])])))]))

(struct wrapped-slice (start render-end logical-end text insert) #:transparent)

(define (wrap-at-line-break-slices text max-width measure-range
                                   [break-provider #f] [language #f]
                                   [who 'layout-mixed-text])
  ;; Coordinate-preserving counterpart to wrap-at-line-breaks. Insertions are
  ;; display-only and are not part of the paragraph coordinates used by bidi.
  (define n (string-length text))
  (define breaks (combined-wrap-breaks who text language break-provider))
  (define first-start (skip-wrap-leading-whitespace text 0))
  (cond
    [(= first-start n) (list (wrapped-slice n n n "" ""))]
    [else
     (let wrap ([start first-start] [acc '()])
       (define candidates
         (let drop ([xs breaks])
           (cond [(null? xs) '()]
                 [(<= (wrap-break-index (car xs)) start) (drop (cdr xs))]
                 [else xs])))
       (let choose ([xs candidates] [best #f])
         (cond
           [(null? xs)
            (reverse
             (cons (wrapped-slice start n n (substring text start n) "") acc))]
           [else
            (define br (car xs))
            (define pos (wrap-break-index br))
            (define insert (wrap-break-insert br))
            (define render-end (trim-wrap-end text start pos))
            (define fits? (<= (measure-range start render-end insert) max-width))
            (cond
              [(and fits? (= pos n))
               (reverse
                (cons (wrapped-slice start render-end pos
                                     (substring text start render-end) insert)
                      acc))]
              [fits? (choose (cdr xs) br)]
              [else
               (define chosen (or best br))
               (define chosen-pos (wrap-break-index chosen))
               (define chosen-end (trim-wrap-end text start chosen-pos))
               (define line
                 (wrapped-slice start chosen-end chosen-pos
                                (substring text start chosen-end)
                                (wrap-break-insert chosen)))
               (define next-start
                 (skip-wrap-leading-whitespace text chosen-pos))
               (if (>= next-start n)
                   (reverse (cons line acc))
                   (wrap next-start (cons line acc)))])])))]))

(define (run-horizontal-width run)
  (abs (shaped-run-advance-x run)))

(define (shape-layout-run sh text direction script language features)
  (shape-text sh text
              #:direction direction
              #:script script
              #:language language
              #:features features))

(define (wrapped-paragraph-lines sh paragraph max-width
                                 direction script language features
                                 [break-provider #f])
  ;; With wrapping disabled, preserve the paragraph text exactly, including
  ;; leading/trailing whitespace. Wrapped lines deliberately trim whitespace
  ;; only where it becomes a line-break boundary.
  (if max-width
      (wrapped-paragraph-lines/limited sh paragraph max-width
                                       direction script language features
                                       break-provider)
      (list paragraph)))

(define (wrapped-paragraph-lines/limited sh paragraph max-width
                                         direction script language features
                                         break-provider)
  (define (measure str)
    (if (zero? (string-length str))
        0.0
        (run-horizontal-width
         (shape-layout-run sh str direction script language features))))
  (wrap-at-line-breaks paragraph max-width measure
                       break-provider language 'layout-text))
(define (effective-line-direction requested run)
  (cond
    [(eq? requested 'rtl) 'rtl]
    [(eq? requested 'ltr) 'ltr]
    [else
     ;; shape-text currently exposes clusters but not the HarfBuzz buffer's
     ;; direction. For ordinary horizontal runs, descending UTF-8 cluster
     ;; offsets identify an RTL visual run; ambiguous one-glyph/empty runs
     ;; default to LTR. Callers needing deterministic ambiguous-line alignment
     ;; can pass #:direction explicitly.
     (define clusters (shaped-run-clusters run))
     (if (and (pair? clusters) (pair? (cdr clusters))
              (> (car clusters) (last clusters)))
         'rtl
         'ltr)]))

(define (line-left-offset align direction box-width line-width)
  (case align
    [(left) 0.0]
    [(right) (- box-width line-width)]
    [(center) (/ (- box-width line-width) 2.0)]
    [(start justify justify-all)
     (if (eq? direction 'rtl) (- box-width line-width) 0.0)]
    [(end) (if (eq? direction 'rtl) 0.0 (- box-width line-width))]))

(define (justification-align? align)
  (and (memq align '(justify justify-all)) #t))

(define (check-justification-width who align max-width)
  (when (and (justification-align? align) (not max-width))
    (raise-arguments-error
     who
     "justification alignment requires a positive #:width"
     "alignment" align
     "width" #f)))

(define (ordinary-space-byte-offsets text)
  ;; Stage 0.14 intentionally implements inter-word justification only.
  ;; U+0020 SPACE is the stretchable opportunity; NBSP, NNBSP, ideographic
  ;; space, tabs, and script-specific elongation are not modified.
  (define n (string-length text))
  (let loop ([i 0] [byte-offset 0] [out '()])
    (cond
      [(= i n) (reverse out)]
      [else
       (define ch (string-ref text i))
       (define next-byte-offset
         (+ byte-offset (bytes-length (string->bytes/utf-8 (string ch)))))
       (loop (add1 i) next-byte-offset
             (if (char=? ch #\space) (cons byte-offset out) out))])))

(define (justify-shaped-run run text direction target-width natural-width)
  ;; HarfBuzz clusters are UTF-8 byte offsets. Move each positioned glyph by
  ;; the accumulated expansion of ordinary spaces preceding it in visual flow;
  ;; keep glyph IDs and shaping decisions unchanged.
  (define spaces (ordinary-space-byte-offsets text))
  (cond
    [(or (null? spaces) (<= target-width natural-width))
     (values run natural-width #f)]
    [else
     (define extra-total (- target-width natural-width))
     (define per-space (/ extra-total (length spaces)))
     (define rtl? (eq? direction 'rtl))
     (define advance (shaped-run-advance-x run))
     (define axis-sign (if (negative? advance) -1.0 1.0))
     (define shifted-positions
       (for/list ([point (in-list (shaped-run-positions run))]
                  [cluster (in-list (shaped-run-clusters run))])
         (define preceding-spaces
           (for/sum ([space-offset (in-list spaces)]
                     #:when (if rtl?
                                (> space-offset cluster)
                                (< space-offset cluster)))
             1))
         (match point
           [(list px py)
            (list (+ px (* axis-sign per-space preceding-spaces)) py)]
           [_ point])))
     (values
      (shaped-run (shaped-run-glyphs run)
                  (shaped-run-clusters run)
                  shifted-positions
                  (+ advance (* axis-sign extra-total))
                  (shaped-run-advance-y run))
      target-width
      #t)]))

(define cjk-justification-scripts '(hani hira kana hang))

(define (cjk-justification-script? script)
  (and script (memq script cjk-justification-scripts) #t))

(define (inferred-line-script text requested-script)
  (or requested-script
      (for/or ([ch (in-string text)]) (unicode-script-symbol ch))))

(define (ordinary-space-boundary-byte-offsets text)
  ;; Boundaries immediately after U+0020. Unlike the 0.14 helper, using the
  ;; post-space byte offset lets the same position-shifting primitive serve CJK
  ;; inter-character and Arabic connection boundaries too.
  (define n (string-length text))
  (let loop ([i 0] [byte-offset 0] [out '()])
    (cond
      [(= i n) (reverse out)]
      [else
       (define ch (string-ref text i))
       (define next-byte-offset
         (+ byte-offset (bytes-length (string->bytes/utf-8 (string ch)))))
       (loop (add1 i) next-byte-offset
             (if (char=? ch #\space)
                 (cons next-byte-offset out)
                 out))])))

(define (cjk-boundary-byte-offsets text)
  ;; Stretch only between adjacent default grapheme clusters that both have a
  ;; CJK script. Common punctuation therefore stays attached to the surrounding
  ;; text instead of becoming an inter-character expansion point.
  (define n (string-length text))
  (let loop ([start 0] [byte-offset 0] [previous-script #f] [out '()])
    (cond
      [(>= start n) (reverse out)]
      [else
       (define end (+ start (string-grapheme-span text start n)))
       (define cluster-text (substring text start end))
       (define script
         (for/or ([ch (in-string cluster-text)]) (unicode-script-symbol ch)))
       (define next-byte-offset
         (+ byte-offset (bytes-length (string->bytes/utf-8 cluster-text))))
       (loop end next-byte-offset script
             (if (and (cjk-justification-script? previous-script)
                      (cjk-justification-script? script))
                 (cons byte-offset out)
                 out))])))

(define (string-index-boundaries->byte-offsets text indices)
  (define wanted (make-hasheqv))
  (for ([i (in-list indices)]) (hash-set! wanted i #t))
  (define n (string-length text))
  (let loop ([i 0] [byte-offset 0] [out '()])
    (cond
      [(= i n) (reverse out)]
      [else
       (define out* (if (hash-ref wanted i #f) (cons byte-offset out) out))
       (define ch (string-ref text i))
       (loop (add1 i)
             (+ byte-offset (bytes-length (string->bytes/utf-8 (string ch))))
             out*)])))

(define (adjust-shaped-run-at-boundaries run direction byte-boundaries delta)
  ;; Change the visual advance by DELTA without altering glyph IDs. A boundary
  ;; is a UTF-8 byte offset immediately before the glyphs that move in logical
  ;; LTR order. RTL uses the mirror count because HarfBuzz clusters descend.
  (cond
    [(or (null? byte-boundaries) (zero? delta)) run]
    [else
     (define rtl? (eq? direction 'rtl))
     (define advance (shaped-run-advance-x run))
     (define axis-sign
       (cond [(negative? advance) -1.0]
             [(positive? advance) 1.0]
             [rtl? -1.0]
             [else 1.0]))
     (define per (/ delta (length byte-boundaries)))
     (define shifted
       (for/list ([point (in-list (shaped-run-positions run))]
                  [cluster (in-list (shaped-run-clusters run))])
         (define preceding
           (for/sum ([boundary (in-list byte-boundaries)]
                     #:when (if rtl?
                                (> boundary cluster)
                                (<= boundary cluster)))
             1))
         (match point
           [(list px py) (list (+ px (* axis-sign per preceding)) py)]
           [_ point])))
     (shaped-run (shaped-run-glyphs run)
                 (shaped-run-clusters run)
                 shifted
                 (+ advance (* axis-sign delta))
                 (shaped-run-advance-y run))]))

(define tatweel-char #\u0640)
(define tatweel-byte-length
  (bytes-length (string->bytes/utf-8 (string tatweel-char))))

(define (build-kashida-display text boundaries counts)
  ;; COUNTS is parallel to BOUNDARIES. Return the display-only string together
  ;; with UTF-8 boundaries immediately after every inserted tatweel. Those
  ;; boundaries let a small overshoot be compressed without changing glyphs.
  (define counts-by-index (make-hasheqv))
  (for ([boundary (in-list boundaries)]
        [count (in-vector counts)])
    (when (positive? count) (hash-set! counts-by-index boundary count)))
  (define n (string-length text))
  (let loop ([i 0] [byte-offset 0] [pieces '()] [after-offsets '()])
    (cond
      [(> i n)
       (values (apply string-append (reverse pieces))
               (reverse after-offsets))]
      [else
       (define count (hash-ref counts-by-index i 0))
       (define-values (byte-after-inserts offsets*)
         (for/fold ([cursor byte-offset] [outs after-offsets])
                   ([_ (in-range count)])
           (define next (+ cursor tatweel-byte-length))
           (values next (cons next outs))))
       (define pieces*
         (if (positive? count)
             (cons (make-string count tatweel-char) pieces)
             pieces))
       (cond
         [(= i n)
          (values (apply string-append (reverse pieces*))
                  (reverse offsets*))]
         [else
          (define ch (string-ref text i))
          (loop (add1 i)
                (+ byte-after-inserts
                   (bytes-length (string->bytes/utf-8 (string ch))))
                (cons (string ch) pieces*)
                offsets*)])])) )

(define (remap-kashida-run-clusters run after-offsets)
  ;; HarfBuzz cluster offsets belong to the temporary display string. Collapse
  ;; each inserted TATWEEL byte span back onto its logical source boundary so
  ;; public shaped-run clusters remain offsets into mixed/text-layout line text.
  (cond
    [(null? after-offsets) run]
    [else
     (define clusters
       (for/list ([cluster (in-list (shaped-run-clusters run))])
         (- cluster
            (* tatweel-byte-length
               (for/sum ([after (in-list after-offsets)]
                         #:when (<= after cluster))
                 1)))))
     (shaped-run (shaped-run-glyphs run)
                 clusters
                 (shaped-run-positions run)
                 (shaped-run-advance-x run)
                 (shaped-run-advance-y run))]))

(define (shape-kashida-to-width shape-display text direction target-width natural-run)
  ;; Insert U+0640 at Unicode Joining_Type-compatible cursive boundaries. The
  ;; final small difference is absorbed at the inserted connection boundaries,
  ;; so the positioned run reaches the requested measure exactly while the
  ;; logical line text remains unchanged.
  (define natural-width (run-horizontal-width natural-run))
  (define candidates (arabic-kashida-boundaries text))
  (cond
    [(or (null? candidates) (<= target-width natural-width))
     (values natural-run natural-width text #f)]
    [else
     (define count (length candidates))
     (define counts (make-vector count 0))
     (define max-attempts 128)
     (let loop ([attempt 0]
                [counts counts]
                [run natural-run]
                [width natural-width]
                [display text]
                [after-offsets '()]
                [stalled 0])
       (cond
         [(>= width target-width)
          (define adjusted
            (adjust-shaped-run-at-boundaries
             run direction after-offsets (- target-width width)))
          (values (remap-kashida-run-clusters adjusted after-offsets)
                  target-width display #t)]
         [(or (>= attempt max-attempts) (>= stalled count))
          (define fallback-boundaries
            (if (pair? after-offsets)
                after-offsets
                (string-index-boundaries->byte-offsets text candidates)))
          (define adjusted
            (adjust-shaped-run-at-boundaries
             run direction fallback-boundaries (- target-width width)))
          (values (if (pair? after-offsets)
                      (remap-kashida-run-clusters adjusted after-offsets)
                      adjusted)
                  target-width display #t)]
         [else
          (define slot (modulo attempt count))
          (define next-counts (vector-copy counts))
          (vector-set! next-counts slot (add1 (vector-ref next-counts slot)))
          (define-values (next-display next-after-offsets)
            (build-kashida-display text candidates next-counts))
          (define next-run (shape-display next-display))
          (define next-width (run-horizontal-width next-run))
          (loop (add1 attempt) next-counts next-run next-width
                next-display next-after-offsets
                (if (> next-width (+ width 0.001)) 0 (add1 stalled)))]))]))

(define (justify-layout-run sh run text direction script language features
                            target-width natural-width)
  (define effective-script (inferred-line-script text script))
  (define spaces (ordinary-space-boundary-byte-offsets text))
  (define cjk-boundaries
    (if (cjk-justification-script? effective-script)
        (cjk-boundary-byte-offsets text)
        '()))
  (define kashida-indices
    (if (eq? effective-script 'arab)
        (arabic-kashida-boundaries text)
        '()))
  (define total-opportunities
    (+ (length spaces) (length cjk-boundaries) (length kashida-indices)))
  (cond
    [(or (zero? total-opportunities) (<= target-width natural-width))
     (values run natural-width #f)]
    [else
     (define per (/ (- target-width natural-width) total-opportunities))
     (define arabic-target
       (+ natural-width (* per (length kashida-indices))))
     (define-values (base-run base-width display-text _used-kashida?)
       (if (pair? kashida-indices)
           (shape-kashida-to-width
            (lambda (display)
              (shape-layout-run sh display direction script language features))
            text direction arabic-target run)
           (values run natural-width text #f)))
     (define post-boundaries
       (append (ordinary-space-boundary-byte-offsets text)
               (if (cjk-justification-script? effective-script)
                   (cjk-boundary-byte-offsets text)
                   '())))
     (define remaining (- target-width base-width))
     (values (adjust-shaped-run-at-boundaries
              base-run direction post-boundaries remaining)
             target-width #t)]))

(define (paragraph-line-justify? align index count)
  (case align
    [(justify-all) #t]
    [(justify) (< index (sub1 count))]
    [else #f]))

(define (layout-text sh text
                     #:width [width #f]
                     #:align [align 'start]
                     #:direction [direction 'auto]
                     #:script [script #f]
                     #:language [language #f]
                     #:features [features '()]
                     #:break-provider [break-provider #f]
                     #:line-height [line-height #f])
  (define who 'layout-text)
  (unless (string? text) (raise-argument-error who "string?" text))
  (define max-width (normalize-layout-width who width))
  (define al (normalize-layout-align who align))
  (check-justification-width who al max-width)
  (define dir (normalize-layout-direction who direction))
  ;; Reuse shape-text's public normalization semantics, but validate before
  ;; accessing the shaper so option errors do not need native loading.
  (define scr (normalize-shape-script who script))
  (define lang (normalize-shape-language who language))
  (define feats (normalize-shape-features who features))
  (define bp (normalize-layout-break-provider who break-provider))
  (define requested-line-height
    (cond [(not line-height) #f]
          [else (positive-scalar who line-height)]))
  (shaper-h who sh)
  (define metrics (font-get-metrics (shaper-font sh)))
  (define ascent (font-metrics-ascent metrics))
  (define descent (font-metrics-descent metrics))
  (define natural-height
    (let ([spacing (font-metrics-spacing metrics)])
      (cond [(and (real? spacing) (> spacing 0)) spacing]
            [else
             (max 1.0
                  (+ (- descent ascent)
                     (max 0.0 (font-metrics-leading metrics))))])))
  (define line-step (or requested-line-height natural-height))
  ;; Keep paragraph boundaries long enough to distinguish a wrapped line from
  ;; the final line of each hard-break-delimited paragraph. `justify` leaves
  ;; that final line at start alignment; `justify-all` stretches it too.
  (define paragraph-line-specs
    (apply append
           (for/list ([paragraph (in-list (split-explicit-lines text))])
             (define paragraph-lines
               (wrapped-paragraph-lines sh paragraph max-width
                                        dir scr lang feats bp))
             (define paragraph-line-count (length paragraph-lines))
             (for/list ([line-text (in-list paragraph-lines)]
                        [line-index (in-naturals)])
               (list line-text
                     (and max-width
                          (paragraph-line-justify?
                           al line-index paragraph-line-count)))))))
  (define raw-lines
    (for/list ([spec (in-list paragraph-line-specs)])
      (define line-text (car spec))
      (define request-justify? (cadr spec))
      (define run (shape-layout-run sh line-text dir scr lang feats))
      (define natural-width (run-horizontal-width run))
      (define actual-dir (effective-line-direction dir run))
      (define-values (final-run final-width _justified?)
        (if request-justify?
            (justify-layout-run sh run line-text actual-dir scr lang feats
                                max-width natural-width)
            (values run natural-width #f)))
      (list line-text final-run final-width actual-dir)))
  (define content-width
    (for/fold ([m 0.0]) ([entry (in-list raw-lines)])
      (max m (list-ref entry 2))))
  ;; If an unbreakable span exceeds the requested wrap width, report the true
  ;; occupied width instead of manufacturing negative alignment offsets.
  (define box-width (max content-width (or max-width 0.0)))
  (define baseline0 (max 0.0 (- ascent)))
  (define lines
    (for/list ([entry (in-list raw-lines)] [i (in-naturals)])
      (define line-text (list-ref entry 0))
      (define run (list-ref entry 1))
      (define w (list-ref entry 2))
      (define actual-dir (list-ref entry 3))
      (define left (line-left-offset al actual-dir box-width w))
      ;; HarfBuzz returns glyphs in visual order; the positioned-run x values
      ;; are measured from the run's left drawing origin even for RTL text.
      ;; Direction affects start/end alignment, not the TextBlob origin itself.
      (text-layout-line line-text run left
                        (+ baseline0 (* i line-step))
                        w actual-dir)))
  (define height
    (if (null? lines)
        0.0
        (+ baseline0
           (* (sub1 (length lines)) line-step)
           (max 0.0 descent))))
  (text-layout sh lines box-width height line-step))

(define (draw-text-layout c layout x y p)
  (define who 'draw-text-layout)
  (unless (text-layout? layout)
    (raise-argument-error who "text-layout?" layout))
  (define fx (scalar who x))
  (define fy (scalar who y))
  (define sh (text-layout-shaper layout))
  ;; Report a clear closed-resource error even for an all-empty layout.
  (call-with-owned who (list (shaper-h who sh)) (lambda (_) (void)))
  (paint-h who p)
  ;; Validate the borrowed canvas even when every line is empty.
  (call-on-canvas who c '() (lambda (_) (void)))
  (for ([line (in-list (text-layout-lines layout))])
    (draw-shaped-run c sh (text-layout-line-run line)
                     (+ fx (text-layout-line-origin-x line))
                     (+ fy (text-layout-line-baseline line))
                     p))
  (void))

;; Mixed-script / mixed-direction layout -----------------------------------

(define (mixed-text-layout-line-count layout)
  (unless (mixed-text-layout? layout)
    (raise-argument-error 'mixed-text-layout-line-count "mixed-text-layout?" layout))
  (length (mixed-text-layout-lines layout)))

(define (hb-tag->script-symbol tag)
  (cond
    [(zero? tag) #f]
    [else
     (define chars
       (for/list ([shift '(24 16 8 0)])
         (integer->char (bitwise-and #xff (arithmetic-shift tag (- shift))))))
     (define sym (string->symbol (string-downcase (list->string chars))))
     (if (memq sym '(zyyy zinh zzzz)) #f sym)]))

(define (unicode-script-symbol ch)
  (define ufuncs (hb_unicode_funcs_get_default))
  (unless ufuncs (error 'unicode-script-symbol "HarfBuzz returned no Unicode property provider"))
  (hb-tag->script-symbol (hb_unicode_script ufuncs (char->integer ch))))

(define (font-choice-relevant-char? ch)
  ;; Directional formatting controls, join controls, variation selectors, and
  ;; other format characters need not have standalone cmap glyphs. They must
  ;; remain in the grapheme text passed to HarfBuzz, but should not by
  ;; themselves trigger a fallback font.
  (define cp (char->integer ch))
  (and (not (char-whitespace? ch))
       (not (bidi-explicit-control? ch))
       (not (eq? (char-general-category ch) 'cf))
       (not (<= #xfe00 cp #xfe0f))
       (not (<= #xe0100 cp #xe01ef))))

(define (hash-ref/cache! ht key thunk)
  (hash-ref ht key
            (lambda ()
              (define value (thunk))
              (hash-set! ht key value)
              value)))

(define (cluster-font-choice base-font fm cluster language cache)
  (define missing
    (for/first ([ch (in-string cluster)]
                #:when (and (font-choice-relevant-char? ch)
                            (zero? (font-char->glyph base-font ch))))
      ch))
  (if (not missing)
      #f
      (let ([key (cons (char->integer missing) language)])
        (hash-ref/cache!
         cache key
         (lambda ()
           (define tf
             (font-manager-match-character
              fm missing
              #:languages (if language (list language) '())))
           (if (not tf)
               #f
               (call-with-skia-resource
                tf
                (lambda (face)
                  (fallback-choice (typeface-family-name face)
                                   (typeface-weight face)
                                   (typeface-width face)
                                   (typeface-slant face))))))))))

(define (make-font-like base-font tf)
  (make-font tf
             #:size (font-size base-font)
             #:scale-x (font-scale-x base-font)
             #:skew-x (font-skew-x base-font)
             #:edging (font-edging base-font)
             #:hinting (font-hinting base-font)
             #:subpixel? (font-subpixel? base-font)
             #:linear-metrics? (font-linear-metrics? base-font)
             #:embolden? (font-embolden? base-font)))

(define (call-with-choice-shaper who base-shaper fm choice proc)
  (cond
    [(not choice) (proc base-shaper)]
    [else
     (define tf
       (font-manager-match-family
        fm (fallback-choice-family choice)
        #:weight (fallback-choice-weight choice)
        #:width (fallback-choice-width choice)
        #:slant (fallback-choice-slant choice)))
     (unless tf
       (error who "fallback family ~s is no longer available"
              (fallback-choice-family choice)))
     (call-with-skia-resource
      tf
      (lambda (face)
        (call-with-skia-resource
         (make-font-like (shaper-font base-shaper) face)
         (lambda (font)
           (call-with-skia-resource (make-shaper font) proc)))))]))

(define (strip-explicit-bidi-controls str)
  (list->string
   (for/list ([ch (in-string str)] #:unless (bidi-explicit-control? ch)) ch)))

(struct logical-mixed-piece (text level script choice) #:transparent)

(define (grapheme-pieces sh fm text levels language choice-cache)
  (define base-font (shaper-font sh))
  (define n (string-length text))
  (let loop ([start 0] [acc '()])
    (cond
      [(>= start n) (reverse acc)]
      [else
       (define span (string-grapheme-span text start n))
       (define end (+ start span))
       (define raw (substring text start end))
       (define clean (strip-explicit-bidi-controls raw))
       (define render-indices
         (for/list ([i (in-range start end)]
                    #:unless (bidi-explicit-control? (string-ref text i)))
           i))
       (cond
         [(zero? (string-length clean)) (loop end acc)]
         [else
          (define level
            (if (pair? render-indices)
                (vector-ref levels (car render-indices))
                0))
          (define script
            (for/or ([ch (in-string clean)]) (unicode-script-symbol ch)))
          (define choice (cluster-font-choice base-font fm clean language choice-cache))
          (loop end (cons (logical-mixed-piece clean level script choice) acc))])])) )

(define (coalesce-logical-pieces pieces)
  (define out '())
  (for ([piece (in-list pieces)])
    (cond
      [(and (pair? out)
            (= (logical-mixed-piece-level piece)
               (logical-mixed-piece-level (car out)))
            (equal? (logical-mixed-piece-script piece)
                    (logical-mixed-piece-script (car out)))
            (equal? (logical-mixed-piece-choice piece)
                    (logical-mixed-piece-choice (car out))))
       (define prev (car out))
       (set! out
             (cons (logical-mixed-piece
                    (string-append (logical-mixed-piece-text prev)
                                   (logical-mixed-piece-text piece))
                    (logical-mixed-piece-level prev)
                    (logical-mixed-piece-script prev)
                    (logical-mixed-piece-choice prev))
                   (cdr out)))]
      [else (set! out (cons piece out))]))
  (reverse out))

(define (mixed-run-from-piece sh fm piece language features)
  (define level (logical-mixed-piece-level piece))
  (define direction (if (odd? level) 'rtl 'ltr))
  (define script (logical-mixed-piece-script piece))
  (define choice (logical-mixed-piece-choice piece))
  (define shaped
    (call-with-choice-shaper
     'layout-mixed-text sh fm choice
     (lambda (run-shaper)
       (shape-text run-shaper (logical-mixed-piece-text piece)
                   #:direction direction
                   #:script script
                   #:language language
                   #:features features))))
  (define width (run-horizontal-width shaped))
  (mixed-text-run
   (logical-mixed-piece-text piece) shaped 0.0 width direction level script
   (and choice (fallback-choice-family choice))
   (and choice (fallback-choice-weight choice))
   (and choice (fallback-choice-width choice))
   (and choice (fallback-choice-slant choice))))

(define (place-visual-mixed-runs runs)
  (let loop ([xs runs] [cursor 0.0] [out '()])
    (cond
      [(null? xs) (values (reverse out) cursor)]
      [else
       (define r (car xs))
       (define advance (shaped-run-advance-x (mixed-text-run-shaped-run r)))
       ;; RTL HarfBuzz runs commonly advance toward negative x. Put the run's
       ;; drawing origin at the right edge in that case so its visual extent
       ;; still begins at the current left-to-right visual cursor.
       (define origin (+ cursor (if (negative? advance) (mixed-text-run-width r) 0.0)))
       (define placed
         (mixed-text-run (mixed-text-run-text r)
                         (mixed-text-run-shaped-run r)
                         origin
                         (mixed-text-run-width r)
                         (mixed-text-run-direction r)
                         (mixed-text-run-level r)
                         (mixed-text-run-script r)
                         (mixed-text-run-family r)
                         (mixed-text-run-weight r)
                         (mixed-text-run-font-width r)
                         (mixed-text-run-slant r)))
       (loop (cdr xs) (+ cursor (mixed-text-run-width r)) (cons placed out))])))

(define (shape-mixed-line/resolved sh fm text levels resolved-direction
                                   language features choice-cache
                                   #:insert [insert ""]
                                   #:insert-level [insert-level #f])
  (define display-level
    (or insert-level (if (eq? resolved-direction 'rtl) 1 0)))
  (define base-pieces
    (grapheme-pieces sh fm text levels language choice-cache))
  (define insert-pieces
    (if (zero? (string-length insert))
        '()
        (grapheme-pieces sh fm insert
                         (make-vector (string-length insert) display-level)
                         language choice-cache)))
  (define logical
    (coalesce-logical-pieces (append base-pieces insert-pieces)))
  (define shaped
    (for/list ([piece (in-list logical)])
      (mixed-run-from-piece sh fm piece language features)))
  (define visual
    (bidi-reorder-items shaped mixed-text-run-level))
  (define-values (placed width) (place-visual-mixed-runs visual))
  (values placed width resolved-direction))

(define (slice-levels levels start end)
  (for/vector ([i (in-range start end)]) (vector-ref levels i)))

(define (display-insert-level text levels paragraph-direction)
  ;; A discretionary suffix does not participate in paragraph bidi resolution.
  ;; It inherits the resolved level of the last drawable character before it.
  (let loop ([i (sub1 (string-length text))])
    (cond
      [(negative? i) (if (eq? paragraph-direction 'rtl) 1 0)]
      [(bidi-explicit-control? (string-ref text i)) (loop (sub1 i))]
      [else (vector-ref levels i)])))

(define (wrapped-mixed-line-slices sh fm paragraph max-width paragraph-direction
                                   paragraph-levels language features choice-cache
                                   [break-provider #f])
  (cond
    [(not max-width)
     (list (wrapped-slice 0 (string-length paragraph) (string-length paragraph)
                          paragraph ""))]
    [else
     (wrap-at-line-break-slices
      paragraph max-width
      (lambda (start end insert)
        (define line-text (substring paragraph start end))
        (define line-levels (slice-levels paragraph-levels start end))
        (if (and (= start end) (zero? (string-length insert)))
            0.0
            (let-values ([(runs width dir)
                          (shape-mixed-line/resolved
                           sh fm line-text line-levels paragraph-direction
                           language features choice-cache
                           #:insert insert
                           #:insert-level
                           (display-insert-level line-text line-levels
                                                 paragraph-direction))])
              width)))
      break-provider language 'layout-mixed-text)]))

(define (shape-mixed-line sh fm text paragraph-direction language features choice-cache)
  (define-values (levels resolved-direction)
    (bidi-resolve-levels text paragraph-direction))
  (define logical
    (coalesce-logical-pieces
     (grapheme-pieces sh fm text levels language choice-cache)))
  (define shaped
    (for/list ([piece (in-list logical)])
      (mixed-run-from-piece sh fm piece language features)))
  (define visual
    (bidi-reorder-items shaped mixed-text-run-level))
  (define-values (placed width) (place-visual-mixed-runs visual))
  (values placed width resolved-direction))

(define (mixed-paragraph-direction paragraph requested)
  (define-values (_levels dir) (bidi-resolve-levels paragraph requested))
  dir)

(define (wrapped-mixed-lines sh fm paragraph max-width paragraph-direction
                             language features choice-cache)
  (if max-width
      (wrapped-mixed-lines/limited sh fm paragraph max-width paragraph-direction
                                   language features choice-cache)
      (list paragraph)))

(define (wrapped-mixed-lines/limited sh fm paragraph max-width paragraph-direction
                                     language features choice-cache)
  (define (measure str)
    (if (zero? (string-length str))
        0.0
        (let-values ([(runs width dir)
                      (shape-mixed-line sh fm str paragraph-direction
                                        language features choice-cache)])
          width)))
  (wrap-at-line-breaks paragraph max-width measure))

(define (mixed-run-choice r)
  (and (mixed-text-run-family r)
       (fallback-choice (mixed-text-run-family r)
                        (mixed-text-run-weight r)
                        (mixed-text-run-font-width r)
                        (mixed-text-run-slant r))))

(define (mixed-run-space-count r)
  (length (ordinary-space-boundary-byte-offsets (mixed-text-run-text r))))

(define (mixed-run-cjk-boundaries r)
  (if (cjk-justification-script? (mixed-text-run-script r))
      (cjk-boundary-byte-offsets (mixed-text-run-text r))
      '()))

(define (mixed-run-kashida-indices r)
  (if (eq? (mixed-text-run-script r) 'arab)
      (arabic-kashida-boundaries (mixed-text-run-text r))
      '()))

(define (mixed-run-justification-count r)
  (+ (mixed-run-space-count r)
     (length (mixed-run-cjk-boundaries r))
     (length (mixed-run-kashida-indices r))))

(define (cjk-run-boundary? left right)
  (and left right
       (cjk-justification-script? (mixed-text-run-script left))
       (cjk-justification-script? (mixed-text-run-script right))))

(define (cross-run-cjk-count runs)
  (for/sum ([left (in-list runs)]
            [right (in-list (if (pair? runs) (cdr runs) '()))])
    (if (cjk-run-boundary? left right) 1 0)))

(define (shape-mixed-run-display sh fm r display language features)
  (call-with-choice-shaper
   'layout-mixed-text sh fm (mixed-run-choice r)
   (lambda (run-shaper)
     (shape-text run-shaper display
                 #:direction (mixed-text-run-direction r)
                 #:script (mixed-text-run-script r)
                 #:language language
                 #:features features))))

(define (justify-one-mixed-run sh fm r per language features)
  (define natural-width (mixed-text-run-width r))
  (define text (mixed-text-run-text r))
  (define spaces (mixed-run-space-count r))
  (define cjk-boundaries (mixed-run-cjk-boundaries r))
  (define kashida-indices (mixed-run-kashida-indices r))
  (define target-arabic
    (+ natural-width (* per (length kashida-indices))))
  (define-values (base-shaped base-width display-text _used-kashida?)
    (if (pair? kashida-indices)
        (shape-kashida-to-width
         (lambda (display)
           (shape-mixed-run-display sh fm r display language features))
         text (mixed-text-run-direction r) target-arabic
         (mixed-text-run-shaped-run r))
        (values (mixed-text-run-shaped-run r) natural-width text #f)))
  (define post-boundaries
    (append (ordinary-space-boundary-byte-offsets text)
            (if (cjk-justification-script? (mixed-text-run-script r))
                (cjk-boundary-byte-offsets text)
                '())))
  (define final-width
    (+ natural-width (* per (+ spaces
                              (length cjk-boundaries)
                              (length kashida-indices)))))
  (define final-shaped
    (adjust-shaped-run-at-boundaries
     base-shaped (mixed-text-run-direction r) post-boundaries
     (- final-width base-width)))
  (mixed-text-run text final-shaped 0.0 final-width
                  (mixed-text-run-direction r)
                  (mixed-text-run-level r)
                  (mixed-text-run-script r)
                  (mixed-text-run-family r)
                  (mixed-text-run-weight r)
                  (mixed-text-run-font-width r)
                  (mixed-text-run-slant r)))

(define (place-visual-mixed-runs/justified runs cjk-gap)
  (let loop ([xs runs] [cursor 0.0] [out '()])
    (cond
      [(null? xs) (values (reverse out) cursor)]
      [else
       (define r (car xs))
       (define advance (shaped-run-advance-x (mixed-text-run-shaped-run r)))
       (define origin (+ cursor (if (negative? advance) (mixed-text-run-width r) 0.0)))
       (define placed
         (mixed-text-run (mixed-text-run-text r)
                         (mixed-text-run-shaped-run r)
                         origin
                         (mixed-text-run-width r)
                         (mixed-text-run-direction r)
                         (mixed-text-run-level r)
                         (mixed-text-run-script r)
                         (mixed-text-run-family r)
                         (mixed-text-run-weight r)
                         (mixed-text-run-font-width r)
                         (mixed-text-run-slant r)))
       (define next (and (pair? (cdr xs)) (cadr xs)))
       (define gap (if (cjk-run-boundary? r next) cjk-gap 0.0))
       (loop (cdr xs)
             (+ cursor (mixed-text-run-width r) gap)
             (cons placed out))])))

(define (justify-mixed-runs sh fm runs natural-width target-width language features)
  ;; Distribute slack over script-appropriate visual opportunities. Latin and
  ;; other scripts retain inter-word U+0020 expansion; CJK also expands between
  ;; adjacent CJK graphemes/runs; Arabic uses joining-compatible tatweel points.
  (define internal-count
    (for/sum ([r (in-list runs)]) (mixed-run-justification-count r)))
  (define cross-count (cross-run-cjk-count runs))
  (define total-count (+ internal-count cross-count))
  (cond
    [(or (zero? total-count) (<= target-width natural-width))
     (values runs natural-width #f)]
    [else
     (define per (/ (- target-width natural-width) total-count))
     (define stretched
       (for/list ([r (in-list runs)])
         (justify-one-mixed-run sh fm r per language features)))
     (define-values (placed placed-width)
       (place-visual-mixed-runs/justified stretched per))
     ;; Floating-point accumulation may differ by a few ulps; expose the exact
     ;; requested layout measure just like the 0.14 inter-word implementation.
     (values placed target-width #t)]))

(define (layout-mixed-text sh fm text
                           #:width [width #f]
                           #:align [align 'start]
                           #:direction [direction 'auto]
                           #:language [language #f]
                           #:features [features '()]
                           #:break-provider [break-provider #f]
                           #:line-height [line-height #f])
  (define who 'layout-mixed-text)
  (unless (string? text) (raise-argument-error who "string?" text))
  (define max-width (normalize-layout-width who width))
  (define al (normalize-layout-align who align))
  (check-justification-width who al max-width)
  (define dir (normalize-layout-direction who direction))
  (define lang (normalize-shape-language who language))
  (define feats (normalize-shape-features who features))
  (define bp (normalize-layout-break-provider who break-provider))
  (define requested-line-height
    (and line-height (positive-scalar who line-height)))
  (shaper-h who sh)
  (font-manager-h who fm)
  (define base-font (shaper-font sh))
  (define metrics (font-get-metrics base-font))
  (define ascent (font-metrics-ascent metrics))
  (define descent (font-metrics-descent metrics))
  (define natural-height
    (let ([spacing (font-metrics-spacing metrics)])
      (cond [(and (real? spacing) (> spacing 0)) spacing]
            [else (max 1.0 (+ (- descent ascent)
                              (max 0.0 (font-metrics-leading metrics))))])))
  (define line-step (or requested-line-height natural-height))
  (define choice-cache (make-hash))
  (define raw-lines '())
  (for ([paragraph (in-list (split-explicit-lines text))])
    ;; Resolve the whole hard-break-delimited paragraph before wrapping. UAX #9
    ;; explicit scopes therefore survive visual line breaks instead of being
    ;; restarted independently on each wrapped substring.
    (define-values (paragraph-levels paragraph-dir)
      (bidi-resolve-levels paragraph dir))
    (define paragraph-slices
      (wrapped-mixed-line-slices sh fm paragraph max-width paragraph-dir
                                 paragraph-levels lang feats choice-cache bp))
    (define logical-line-ends
      (for/list ([slice (in-list paragraph-slices)])
        (wrapped-slice-logical-end slice)))
    (define-values (final-paragraph-levels _final-dir)
      (bidi-resolve-levels paragraph dir #:line-breaks logical-line-ends))
    (define paragraph-line-count (length paragraph-slices))
    (for ([slice (in-list paragraph-slices)]
          [line-index (in-naturals)])
      (define start (wrapped-slice-start slice))
      (define end (wrapped-slice-render-end slice))
      (define base-line-text (wrapped-slice-text slice))
      (define insert (wrapped-slice-insert slice))
      (define line-text (string-append base-line-text insert))
      (define line-levels (slice-levels final-paragraph-levels start end))
      (define-values (runs natural-width _resolved)
        (shape-mixed-line/resolved
         sh fm base-line-text line-levels paragraph-dir lang feats choice-cache
         #:insert insert
         #:insert-level
         (display-insert-level base-line-text line-levels paragraph-dir)))
      (define request-justify?
        (and max-width
             (paragraph-line-justify? al line-index paragraph-line-count)))
      (define-values (final-runs final-width _justified?)
        (if request-justify?
            (justify-mixed-runs sh fm runs natural-width max-width
                                lang feats)
            (values runs natural-width #f)))
      (set! raw-lines
            (cons (list line-text final-runs final-width paragraph-dir)
                  raw-lines))))
  (set! raw-lines (reverse raw-lines))
  (define content-width
    (for/fold ([m 0.0]) ([entry (in-list raw-lines)])
      (max m (list-ref entry 2))))
  (define box-width (max content-width (or max-width 0.0)))
  (define baseline0 (max 0.0 (- ascent)))
  (define lines
    (for/list ([entry (in-list raw-lines)] [i (in-naturals)])
      (define line-text (list-ref entry 0))
      (define runs (list-ref entry 1))
      (define w (list-ref entry 2))
      (define line-dir (list-ref entry 3))
      (mixed-text-line line-text runs
                       (line-left-offset al line-dir box-width w)
                       (+ baseline0 (* i line-step))
                       w line-dir)))
  (define height
    (if (null? lines)
        0.0
        (+ baseline0 (* (sub1 (length lines)) line-step)
           (max 0.0 descent))))
  (mixed-text-layout sh fm lines box-width height line-step))

(define (fallback-choice-from-run r)
  (and (mixed-text-run-family r)
       (fallback-choice (mixed-text-run-family r)
                        (mixed-text-run-weight r)
                        (mixed-text-run-font-width r)
                        (mixed-text-run-slant r))))

(define (draw-mixed-text-layout c layout x y p)
  (define who 'draw-mixed-text-layout)
  (unless (mixed-text-layout? layout)
    (raise-argument-error who "mixed-text-layout?" layout))
  (define fx (scalar who x))
  (define fy (scalar who y))
  (define base-shaper (mixed-text-layout-shaper layout))
  (define fm (mixed-text-layout-font-manager layout))
  ;; Caller-owned dependencies must still be live when the pure layout is used.
  (call-with-owned who (list (shaper-h who base-shaper)
                             (font-manager-h who fm))
                   (lambda (_a _b) (void)))
  (paint-h who p)
  (call-on-canvas who c '() (lambda (_) (void)))
  (define cache (make-hash))
  (define (cached-shaper run)
    (define choice (fallback-choice-from-run run))
    (cond
      [(not choice) base-shaper]
      [else
       (hash-ref/cache!
        cache choice
        (lambda ()
          (define tf
            (font-manager-match-family
             fm (fallback-choice-family choice)
             #:weight (fallback-choice-weight choice)
             #:width (fallback-choice-width choice)
             #:slant (fallback-choice-slant choice)))
          (unless tf
            (error who "fallback family ~s is no longer available"
                   (fallback-choice-family choice)))
          (call-with-skia-resource
           tf
           (lambda (face)
             (call-with-skia-resource
              (make-font-like (shaper-font base-shaper) face)
              (lambda (font) (make-shaper font)))))))]))
  (dynamic-wind
    void
    (lambda ()
      (for ([line (in-list (mixed-text-layout-lines layout))])
        (for ([run (in-list (mixed-text-line-runs line))])
          (draw-shaped-run
           c (cached-shaper run) (mixed-text-run-shaped-run run)
           (+ fx (mixed-text-line-origin-x line) (mixed-text-run-origin-x run))
           (+ fy (mixed-text-line-baseline line)) p))))
    (lambda ()
      (for ([sh (in-hash-values cache)]) (skia-close! sh))))
  (void))

;; Images, encoded data, codecs, and copied pixel input ---------------------

(define (surface-snapshot s)
  (call-with-owned 'surface-snapshot (list (surface-h 'surface-snapshot s))
    (lambda (sp)
      (make-image-record
       (new-owned 'surface-snapshot 'image
                  (lambda () (sk_surface_new_image_snapshot sp)) sk_image_unref)
       (surface-width s) (surface-height s)))))

(define (rgba-bytes->image w h pixels #:premultiplied? [premultiplied? #f]
                           #:color-space [cs #f])
  (define who 'rgba-bytes->image)
  (define n (check-dimensions who w h))
  (boolean who premultiplied?)
  (define cs-hnd (optional-color-space-h who cs))
  (unless (and (bytes? pixels) (= n (bytes-length pixels)))
    (raise-arguments-error who "expected exactly width*height*4 RGBA bytes"
                           "required length" n "pixels" pixels))
  ;; Invalid premultiplied input can violate native assumptions.
  (when premultiplied?
    (for ([i (in-range 0 n 4)])
      (define a (bytes-ref pixels (+ i 3)))
      (unless (and (<= (bytes-ref pixels i) a)
                   (<= (bytes-ref pixels (+ i 1)) a)
                   (<= (bytes-ref pixels (+ i 2)) a))
        (error who "RGB exceeds alpha in premultiplied pixel ~a" (quotient i 4)))))
  (skia-check!)
  (define ptr
    (if cs-hnd
        (call-with-owned
         who (list cs-hnd)
         (lambda (cp)
           (sk_image_new_raster_copy
            (make-sk-image-info cp w h rgba-8888
                                (if premultiplied? alpha-premul alpha-unpremul))
            pixels (* 4 w))))
        (sk_image_new_raster_copy
         (make-sk-image-info #f w h rgba-8888
                             (if premultiplied? alpha-premul alpha-unpremul))
         pixels (* 4 w))))
  (make-image-record
   (new-owned who 'image (lambda () ptr) sk_image_unref)
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

;; Advanced codecs ---------------------------------------------------------
;; These resources own immutable encoded data through SkCodec. Frame output
;; is an independent raster image; no prior-frame pixel buffer is retained.
(provide codec? codec-from-bytes codec-from-file codec-info codec-frame-count
         codec-repetition-count codec-frame-info codec-color-space codec->image
         image-frame-from-bytes image-frame-from-file
         encoded-image-info-display-width encoded-image-info-display-height
         codec-frame-info? codec-frame-info-index codec-frame-info-required-frame
         codec-frame-info-duration codec-frame-info-fully-received?
         codec-frame-info-alpha-type codec-frame-info-has-alpha-within-bounds?
         codec-frame-info-disposal-method codec-frame-info-blend
         codec-frame-info-rect)

(struct codec (handle) #:constructor-name make-codec-record)
(struct codec-frame-info
  (index required-frame duration fully-received? alpha-type
         has-alpha-within-bounds? disposal-method blend rect)
  #:transparent
  #:constructor-name make-codec-frame-info-record
  #:omit-define-syntaxes)

(define (codec-h who c)
  (typed-handle who c codec? codec-handle "codec?"))

(define (codec-native-frame-count who cp)
  (define count (sk_codec_get_frame_count cp))
  (unless (exact-nonnegative-integer? count)
    (error who "codec returned invalid animation frame count ~a" count))
  count)

(define (codec-check-frame who cp index)
  (checked-codec-index who index)
  (define count (codec-native-frame-count who cp))
  (unless (< index (max 1 count))
    (raise-arguments-error who "frame index is outside the image"
                           "frame index" index "decodable frames" (max 1 count)))
  count)

;; The C shim returns an owned color-space reference in image info. It must
;; remain live during decode/copy and must be released even when decoding fails.
(define (call-with-codec-image-info who cp proc)
  (define info (make-sk-image-info #f 0 0 0 0))
  (sk_codec_get_info cp info)
  (define cs (sk-image-info-colorspace info))
  (dynamic-wind
    void
    (lambda ()
      (unless (and (exact-positive-integer? (sk-image-info-width info))
                   (exact-positive-integer? (sk-image-info-height info)))
        (error who "codec returned invalid dimensions"))
      (proc info))
    (lambda () (when cs (sk_colorspace_unref cs)))))

(define (make-codec-from-data who call-with-data)
  (call-with-data
   (lambda (dp)
     (define c
       (make-codec-record
        (new-owned who 'codec (lambda () (sk_codec_new_from_data dp))
                   sk_codec_destroy)))
     (with-handlers ([exn? (lambda (e) (skia-close! c) (raise e))])
       ;; Metadata is safe to inspect without allocating a decoded raster.
       (codec-info c)
       c))))

(define (codec-from-bytes bs)
  (define who 'codec-from-bytes)
  (make-codec-from-data
   who (lambda (proc) (call-with-encoded-data-from-bytes who bs proc))))

(define (codec-from-file filename)
  (define who 'codec-from-file)
  ;; Read an owned snapshot rather than retaining a file mapping. Bound every
  ;; read, including when a file grows after the initial size check.
  (checked-file-data who filename)
  (define bs
    (call-with-input-file filename
      (lambda (in)
        (define out (open-output-bytes))
        (define limit (current-skia-byte-limit))
        (let loop ([total 0])
          (define chunk (read-bytes (min 65536 (add1 (- limit total))) in))
          (cond
            [(eof-object? chunk) (get-output-bytes out)]
            [else
             (define next (+ total (bytes-length chunk)))
             (when (> next limit)
               (error who "encoded image file exceeds current-skia-byte-limit"))
             (write-bytes chunk out)
             (loop next)])))
      #:mode 'binary))
  (make-codec-from-data
   who (lambda (proc) (call-with-encoded-data-from-bytes who bs proc))))

(define (codec-info c)
  (define who 'codec-info)
  (call-with-owned
   who (list (codec-h who c))
   (lambda (cp)
     (call-with-codec-image-info
      who cp
      (lambda (info)
        (make-encoded-image-info-record
         (sk-image-info-width info) (sk-image-info-height info)
         (enum-name who (sk_codec_get_encoded_format cp)
                    encoded-format-values "encoded image format")
         (enum-name who (sk-image-info-color-type info) color-type-values "color type")
         (enum-name who (sk-image-info-alpha-type info) alpha-type-values "alpha type")
         (enum-name who (sk_codec_get_origin cp) encoded-origin-values "encoded origin")
         (codec-native-frame-count who cp)))))))

(define (encoded-image-info-display-width info)
  (define-values (w h)
    (oriented-dimensions 'encoded-image-info-display-width
                        (encoded-image-info-width info) (encoded-image-info-height info)
                        (encoded-image-info-origin info)))
  w)
(define (encoded-image-info-display-height info)
  (define-values (w h)
    (oriented-dimensions 'encoded-image-info-display-height
                        (encoded-image-info-width info) (encoded-image-info-height info)
                        (encoded-image-info-origin info)))
  h)

;; Unlike the legacy metadata field, this is the number of decodable frames:
;; still images have one frame, although their animation metadata table is empty.
(define (codec-frame-count c)
  (define who 'codec-frame-count)
  (call-with-owned who (list (codec-h who c))
    (lambda (cp) (max 1 (codec-native-frame-count who cp)))))

(define (codec-repetition-count c)
  (define who 'codec-repetition-count)
  (call-with-owned who (list (codec-h who c))
    (lambda (cp)
      (define count (sk_codec_get_repetition_count cp))
      (unless (and (exact-integer? count) (>= count -1))
        (error who "codec returned invalid repetition count ~a" count))
      count)))

;; Returns #f only for the valid still-image frame with no animation metadata.
;; Rect is #(x y width height), always in encoded (not oriented) pixels.
(define (codec-frame-info c index)
  (define who 'codec-frame-info)
  (define hnd (codec-h who c))
  (checked-codec-index who index)
  (call-with-owned
   who (list hnd)
   (lambda (cp)
     (define count (codec-check-frame who cp index))
     (cond
       [(zero? count) #f]
       [else
        (define info
          (make-sk-codec-frame-info -1 0 #f 0 #f 1 0 (make-sk-irect 0 0 0 0)))
        (unless (sk_codec_get_frame_info_for_index cp index info)
          (error who "native frame metadata is unavailable for frame ~a" index))
        (define required (sk-codec-frame-info-required-frame info))
        (define duration (sk-codec-frame-info-duration info))
        (unless (and (<= -1 required) (< required index) (>= duration 0))
          (error who "native frame metadata has an invalid dependency or duration"))
        (define r (sk-codec-frame-info-frame-rect info))
        (make-codec-frame-info-record
         index (and (>= required 0) required) duration
         (sk-codec-frame-info-fully-received info)
         (enum-name who (sk-codec-frame-info-alpha-type info) alpha-type-values "alpha type")
         (sk-codec-frame-info-has-alpha-within-bounds info)
         (enum-name who (sk-codec-frame-info-disposal-method info)
                    codec-disposal-values "animation disposal method")
         (enum-name who (sk-codec-frame-info-blend info)
                    codec-blend-values "animation blend")
         (vector-immutable (sk-irect-left r) (sk-irect-top r)
                           (- (sk-irect-right r) (sk-irect-left r))
                           (- (sk-irect-bottom r) (sk-irect-top r))))]))))

(define (codec-color-space c)
  (define who 'codec-color-space)
  (call-with-owned
   who (list (codec-h who c))
   (lambda (cp)
     (call-with-codec-image-info
      who cp
      (lambda (info)
        (define cs (sk-image-info-colorspace info))
        (and cs
             (wrap-owned-color-space
              who (lambda () (sk_colorspace_ref cs) cs))))))))

(define (codec->image c #:frame-index [index 0]
                       #:normalize-origin? [normalize? #t]
                       #:color-space [cs #f])
  (define who 'codec->image)
  (define hnd (codec-h who c))
  (checked-codec-index who index)
  (boolean who normalize?)
  (define cs-hnd (optional-color-space-h who cs))
  (call-with-owned
   who (if cs-hnd (list hnd cs-hnd) (list hnd))
   (lambda (cp . colorspaces)
     (codec-check-frame who cp index)
     (call-with-codec-image-info
      who cp
      (lambda (source-info)
        (define w (sk-image-info-width source-info))
        (define h (sk-image-info-height source-info))
        (define n (check-dimensions who w h))
        ;; #f preserves the source color space; a supplied space converts during
        ;; decode. The output copy retains the chosen native color-space tag.
        (define target-cs
          (if cs-hnd (car colorspaces) (sk-image-info-colorspace source-info)))
        (define pixels (make-bytes n 0))
        (define options (make-sk-codec-options 0 #f index -1))
        ;; kNoFrame (-1) asks Skia to decode dependencies into this fresh buffer.
        ;; Passing index-1 here would falsely claim the buffer already held it.
        (define result
          (sk_codec_get_pixels cp (make-sk-image-info target-cs w h rgba-8888 alpha-premul)
                               pixels (* 4 w) options))
        (unless (= result 0)
          (error who "frame ~a decode failed: ~a (native result ~a)"
                 index (codec-result-name result) result))
        (define-values (ow oh output)
          (if normalize?
              (orient-rgba-bytes
               who w h pixels
               (enum-name who (sk_codec_get_origin cp) encoded-origin-values "encoded origin"))
              (values w h pixels)))
        ;; Both _bytes calls are synchronous and retain no Racket buffer.
        (make-image-record
         (new-owned who 'image
                    (lambda ()
                      (sk_image_new_raster_copy
                       (make-sk-image-info target-cs ow oh rgba-8888 alpha-premul)
                       output (* 4 ow)))
                    sk_image_unref)
         ow oh))))))

(define (image-frame-from-bytes bs [index 0]
                                #:normalize-origin? [normalize? #t]
                                #:color-space [cs #f])
  (define who 'image-frame-from-bytes)
  (checked-codec-index who index)
  (boolean who normalize?)
  (optional-color-space-h who cs)
  (with-skia ([c (codec-from-bytes bs)])
    (codec->image c #:frame-index index #:normalize-origin? normalize? #:color-space cs)))

(define (image-frame-from-file filename [index 0]
                              #:normalize-origin? [normalize? #t]
                              #:color-space [cs #f])
  (define who 'image-frame-from-file)
  (checked-codec-index who index)
  (boolean who normalize?)
  (optional-color-space-h who cs)
  (with-skia ([c (codec-from-file filename)])
    (codec->image c #:frame-index index #:normalize-origin? normalize? #:color-space cs)))


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

(define (image-color-space im)
  (define who 'image-color-space)
  ;; The pinned C shim returns image->refColorSpace().release(), i.e. a newly
  ;; owned reference rather than a borrowed pointer.
  (define ptr
    (call-with-owned who (list (image-h who im)) sk_image_get_colorspace))
  (and ptr (wrap-owned-color-space who (lambda () ptr))))

(define (image->rgba-bytes im #:premultiplied? [premultiplied? #f]
                           #:color-space [cs #f])
  (define who 'image->rgba-bytes)
  (define hnd (image-h who im))
  (boolean who premultiplied?)
  (define cs-hnd (optional-color-space-h who cs))
  (define w (image-width im))
  (define h (image-height im))
  (define out (make-bytes (check-dimensions who w h)))
  (define handles (if cs-hnd (list hnd cs-hnd) (list hnd)))
  (call-with-owned who handles
    (lambda (ip . rest)
      (define cp (and (pair? rest) (car rest)))
      (unless (sk_image_read_pixels
               ip (make-sk-image-info cp w h rgba-8888
                                      (if premultiplied? alpha-premul alpha-unpremul))
               out (* 4 w) 0 0 0)
        (error who "native image pixel read failed"))))
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
