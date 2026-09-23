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
         paint? make-paint paint-copy paint-color
         paint-set-color! paint-set-style! paint-set-stroke-width!
         paint-set-antialias! paint-set-cap! paint-set-join!
         paint-set-miter-limit! paint-set-blend-mode!
         skia-path? make-path path-copy path-move-to! path-line-to!
         path-quad-to! path-cubic-to! path-close! path-reset!
         path-add-rect! path-add-oval! path-add-circle!
         path-bounds path-tight-bounds path-contains?
         path-fill-rule path-set-fill-rule!
         image? image-width image-height surface-snapshot
         rgba-bytes->image image->rgba-bytes draw-image draw-image-rect
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
;; The surface, not a separately finalized canvas pointer, owns the canvas.
(struct canvas (surface) #:constructor-name make-canvas-record)
(struct paint (handle) #:constructor-name make-paint-record)
(struct skia-path (handle) #:constructor-name make-path-record)
(struct image (handle width height) #:constructor-name make-image-record)
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
  (or (surface? v) (paint? v) (skia-path? v) (image? v)
      (typeface? v) (font? v)))

(define (resource-handle who v)
  (cond [(surface? v) (surface-handle v)]
        [(paint? v) (paint-handle v)]
        [(skia-path? v) (skia-path-handle v)]
        [(image? v) (image-handle v)]
        [(typeface? v) (typeface-handle v)]
        [(font? v) (font-handle v)]
        [else (raise-argument-error who "skia-resource? (not a borrowed canvas)" v)]))

(define (skia-closed? v)
  (owned-closed?
   (if (canvas? v)
       (surface-handle (canvas-surface v))
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
(define (path-h who v) (typed-handle who v skia-path? skia-path-handle "skia-path?"))
(define (image-h who v) (typed-handle who v image? image-handle "image?"))
(define (typeface-h who v) (typed-handle who v typeface? typeface-handle "typeface?"))
(define (font-h who v) (typed-handle who v font? font-handle "font?"))

(define (canvas-owner who c)
  (unless (canvas? c) (raise-argument-error who "canvas?" c))
  (canvas-surface c))

(define (call-on-canvas who c others proc)
  (define s (canvas-owner who c))
  (call-with-owned
   who (cons (surface-handle s) others)
   (lambda (sp . ps)
     (define cp (sk_surface_get_canvas sp))
     (unless cp (error who "native surface returned a null canvas"))
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
                    #:blend-mode [blend 'src-over])
  ;; Validate every option before allocating native state.
  (define col (color->argb color))
  (define sty (choice 'make-paint style style-values))
  (define wid (nonnegative-scalar 'make-paint width))
  (define aa (boolean 'make-paint antialias?))
  (define ca (choice 'make-paint cap cap-values))
  (define jo (choice 'make-paint join join-values))
  (define mi (nonnegative-scalar 'make-paint miter))
  (define bl (choice 'make-paint blend blend-values))
  (skia-check!)
  (define hnd (new-owned 'make-paint 'paint sk_paint_new sk_paint_delete))
  (initialize-resource
   (make-paint-record hnd)
   (lambda (_)
     (call-with-owned
      'make-paint (list hnd)
      (lambda (p)
        (sk_paint_set_color p col)
        (sk_paint_set_style p sty)
        (sk_paint_set_stroke_width p wid)
        (sk_paint_set_antialias p aa)
        (sk_paint_set_stroke_cap p ca)
        (sk_paint_set_stroke_join p jo)
        (sk_paint_set_stroke_miter p mi)
        (sk_paint_set_blendmode p bl))))))

(define (paint-copy p)
  (call-with-owned 'paint-copy (list (paint-h 'paint-copy p))
    (lambda (ptr)
      (make-paint-record
       (new-owned 'paint-copy 'paint (lambda () (sk_paint_clone ptr)) sk_paint_delete)))))

(define (paint-color p)
  (color->rgba
   (call-with-owned 'paint-color (list (paint-h 'paint-color p)) sk_paint_get_color)))

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

;; Canvas state -------------------------------------------------------------

(define (canvas-clear! c color)
  (define argb (color->argb color))
  (call-on-canvas 'canvas-clear! c '() (lambda (cp) (sk_canvas_clear cp argb))))
(define (canvas-save! c)
  (call-on-canvas 'canvas-save! c '() sk_canvas_save))
(define (canvas-save-count c)
  (call-on-canvas 'canvas-save-count c '() sk_canvas_get_save_count))

(define (restore-floor c)
  (define floors (surface-floors (canvas-surface c)))
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
            (set-surface-floors! s (cons (add1 old-count) (surface-floors s))))))
       thunk
       (lambda ()
         ;; Closing the owner in the body is permitted. Never touch a dangling
         ;; borrowed pointer during cleanup; the Racket bookkeeping still unwinds.
         (unless (skia-closed? s)
           (call-on-canvas 'call-with-canvas-state c '()
             (lambda (cp) (sk_canvas_restore_to_count cp old-count))))
         (set-surface-floors! s (cdr (surface-floors s))))))))

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
(define (path-line-to! p x y)
  (mutate-path! 'path-line-to! p (list x y) sk_path_line_to))
(define (path-quad-to! p cx cy x y)
  (mutate-path! 'path-quad-to! p (list cx cy x y) sk_path_quad_to))
(define (path-cubic-to! p cx1 cy1 cx2 cy2 x y)
  (mutate-path! 'path-cubic-to! p (list cx1 cy1 cx2 cy2 x y) sk_path_cubic_to))
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

;; Immutable image snapshots and copied pixel input -------------------------

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
