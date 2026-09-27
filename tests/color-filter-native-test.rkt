#lang racket/base
(require rackunit racket/list ffi/unsafe "../main.rkt"
         "../private/color-filter-types.rkt" "color-filter-fixtures.rkt")
(provide color-filter-native-tests)
(define (close-color? actual expected [tolerance 2])
  (for ([a (in-list (rgba-list actual))] [b (in-list (rgba-list expected))])
    (check-= a b tolerance)))
(define (one make color expected [tolerance 2])
  (with-skia ([cf (make)]) (close-color? (filter-pixel cf color) expected tolerance)))
(define (filtered-page cf)
  (make-output-page 48 32
    (lambda (c)
      (with-skia ([p (make-paint #:color filter-swatch-color #:color-filter cf)])
        (draw-rect c 2 2 44 28 p)))))
(define color-filter-native-tests
  (test-suite
   "CPU color filters: native results, ownership, and output policy"
   (test-case "high contrast ABI layout"
     (check-equal? (ctype-sizeof _sk-high-contrast-config) 12)
     (define c (make-sk-high-contrast-config #t 2 0.25))
     (check-equal? (ptr-ref c _uint8 0) 1)
     (check-equal? (ptr-ref c _int 1) 2)
     (check-= (ptr-ref c _float 2) 0.25 0))
   (test-case "all probe factories return ordinary color filters"
     (for ([n '(identity hue desaturate lighting encode decode rgb-table threshold luma contrast lerp compose)])
       (with-skia ([cf (make-probe-color-filter n)]) (check-true (color-filter? cf)))))
   (test-case "HSLA identity preserves opaque color"
     (one (lambda () (make-hsla-matrix-filter identity-hsla)) filter-swatch-color filter-swatch-color))
   (test-case "HSLA hue uses normalized turns"
     (one (lambda () (make-hsla-matrix-filter hue-third-hsla)) (rgb 255 0 0) (rgb 0 255 0)))
   (test-case "HSLA zero saturation uses HSL lightness"
     (one (lambda () (make-hsla-matrix-filter saturation-zero-hsla)) (rgb 255 0 0) (rgb 128 128 128)))
   (test-case "HSLA offsets are normalized rather than byte offsets"
     (one (lambda () (make-hsla-matrix-filter lightness-invert-hsla)) (rgb 64 64 64) (rgb 191 191 191)))
   (test-case "HSLA copied input survives mutation"
     (define v (list->vector identity-hsla))
     (with-skia ([cf (make-hsla-matrix-filter v)])
       (vector-set! v 12 0) (close-color? (filter-pixel cf filter-swatch-color) filter-swatch-color)))
   (test-case "linear to sRGB midpoint"
     (one make-linear-to-srgb-gamma-color-filter (rgb 128 128 128) (rgb 188 188 188)))
   (test-case "sRGB to linear midpoint"
     (one make-srgb-to-linear-gamma-color-filter (rgb 128 128 128) (rgb 55 55 55)))
   (test-case "gamma composition restores samples"
     (one (lambda () (make-probe-color-filter 'compose)) filter-swatch-color filter-swatch-color))
   (test-case "gamma preserves alpha rather than applying transfer to alpha"
     (one make-linear-to-srgb-gamma-color-filter (rgba 255 0 0 128) (rgba 255 0 0 128)))
   (test-case "luma black disappears"
     (one make-luma-color-filter (rgb 0 0 0) (rgba 0 0 0 0) 0))
   (test-case "luma white preserves existing alpha"
     (one make-luma-color-filter (rgba 255 255 255 128) (rgba 0 0 0 128)))
   (test-case "luma RGB becomes black with weighted alpha"
     (with-skia ([cf (make-luma-color-filter)])
       (define r (filter-pixel cf (rgb 255 0 0)))
       (define g (filter-pixel cf (rgb 0 255 0)))
       (define b (filter-pixel cf (rgb 0 0 255)))
       (check-true (< 0 (rgba-alpha b) (rgba-alpha r) (rgba-alpha g) 255))
       (for ([v (in-list (list r g b))]) (check-equal? (take (rgba-list v) 3) '(0 0 0)))))
   (test-case "luma folds in input alpha"
     (with-skia ([cf (make-luma-color-filter)])
       (define a (rgba-alpha (filter-pixel cf (rgba 255 0 0 128))))
       (define b (rgba-alpha (filter-pixel cf (rgb 255 0 0))))
       (check-= (* 2 a) b 2)))
   (test-case "all-component identity table"
     (one (lambda () (make-table-color-filter identity-table)) filter-swatch-color filter-swatch-color 0))
   (test-case "all-component inversion also changes alpha"
     (one (lambda () (make-table-color-filter inverse-table)) 'white (rgba 0 0 0 0) 0))
   (test-case "table bytes copied before caller mutation"
     (define b (bytes-copy identity-table))
     (with-skia ([cf (make-table-color-filter b)])
       (bytes-fill! b 0) (close-color? (filter-pixel cf filter-swatch-color) filter-swatch-color 0)))
   (test-case "table vector copied before caller mutation"
     (define v (list->vector (build-list 256 values)))
     (with-skia ([cf (make-table-argb-color-filter #:red v)])
       (vector-set! v 72 0) (close-color? (filter-pixel cf filter-swatch-color) filter-swatch-color 0)))
   (test-case "ARGB omitted channels are identity"
     (one make-table-argb-color-filter filter-swatch-color filter-swatch-color 0))
   (test-case "red table does not change other channels"
     (one (lambda () (make-table-argb-color-filter #:red inverse-table))
          (rgb 32 64 96) (rgb 223 64 96) 1))
   (test-case "blue table is in the correct native slot"
     (one (lambda () (make-table-argb-color-filter #:blue inverse-table))
          (rgb 32 64 96) (rgb 32 64 159) 1))
   (test-case "alpha table maps coverage without tinting RGB"
     (one (lambda () (make-table-argb-color-filter #:alpha (make-bytes 256 128)))
          'red (rgba 255 0 0 128) 1))
   (test-case "table lookup is in unpremultiplied coordinates"
     (one (lambda () (make-table-argb-color-filter #:red inverse-table))
          (rgba 255 0 0 64) (rgba 0 0 0 64) 1))
   (test-case "threshold keeps alpha unchanged"
     (one (lambda () (make-probe-color-filter 'threshold)) (rgb 127 128 200) (rgb 0 255 255) 1))
   (test-case "high contrast default preserves colors"
     (one make-high-contrast-color-filter filter-swatch-color filter-swatch-color))
   (test-case "high contrast grayscale equalizes RGB"
     (with-skia ([cf (make-high-contrast-color-filter #:grayscale? #t)])
       (define p (filter-pixel cf (rgb 190 60 20)))
       (check-= (rgba-red p) (rgba-green p) 1)
       (check-= (rgba-green p) (rgba-blue p) 1)
       (check-equal? (rgba-alpha p) 255)))
   (test-case "brightness inversion exchanges black and white"
     (with-skia ([cf (make-high-contrast-color-filter #:invert-style 'brightness)])
       (close-color? (filter-pixel cf 'black) (rgb 255 255 255))
       (close-color? (filter-pixel cf 'white) (rgb 0 0 0))))
   (test-case "lightness and brightness inversion are distinct"
     (one (lambda () (make-high-contrast-color-filter #:invert-style 'brightness)) 'red (rgb 0 255 255))
     (one (lambda () (make-high-contrast-color-filter #:invert-style 'lightness)) 'red (rgb 255 0 0)))
   (test-case "contrast endpoints produce valid colors and preserve alpha"
     (for ([amount '(-1 1)])
       (with-skia ([cf (make-high-contrast-color-filter #:contrast amount)])
         (define p (filter-pixel cf (rgba 255 0 0 128)))
         (check-true (rgba? p)) (check-= (rgba-alpha p) 128 1))))
   (test-case "lighting white multiply and black add is identity"
     (one (lambda () (make-lighting-color-filter 'white 'black)) filter-swatch-color filter-swatch-color))
   (test-case "lighting ignores argument alpha"
     (one (lambda () (make-lighting-color-filter (rgba 0 0 0 0) (rgba 50 100 150 0)))
          (rgb 20 40 60) (rgb 50 100 150) 1))
   (test-case "lighting clamps channels and preserves alpha"
     (one (lambda () (make-lighting-color-filter 'white 'white))
          (rgba 255 0 0 128) (rgba 255 255 255 128)))
   (test-case "lerp endpoints follow first and second child"
     (with-skia ([a (make-blend-color-filter 'red 'src)] [b (make-blend-color-filter 'blue 'src)]
                 [lo (make-lerp-color-filter 0 a b)] [hi (make-lerp-color-filter 1 a b)])
       (close-color? (filter-pixel lo 'white) (rgb 255 0 0) 0)
       (close-color? (filter-pixel hi 'white) (rgb 0 0 255) 0)))
   (test-case "lerp mixes parallel results rather than composing"
     (with-skia ([a (make-blend-color-filter 'red 'src)] [b (make-blend-color-filter 'blue 'src)]
                 [cf (make-lerp-color-filter 0.25 a b)])
       (close-color? (filter-pixel cf 'white) (rgb 191 0 64) 1)))
   (test-case "lerp retains closed child wrappers"
     (define a (make-blend-color-filter 'red 'src))
     (define b (make-blend-color-filter 'blue 'src))
     (with-skia ([cf (make-lerp-color-filter 0.5 a b)])
       (skia-close! a) (skia-close! b) (collect-garbage)
       (close-color? (filter-pixel cf 'white) (rgb 128 0 128) 1)))
   (test-case "paint getter retains filter after original closure and detach"
     (define cf (make-probe-color-filter 'rgb-table))
     (with-skia ([p (make-paint #:color-filter cf)])
       (skia-close! cf)
       (with-skia ([held (paint-color-filter p)])
         (paint-set-color-filter! p #f)
         (close-color? (filter-pixel held (rgb 20 40 60)) (rgb 235 215 195) 1))))
   (test-case "new filter composes into image filter graph"
     (with-skia ([cf (make-probe-color-filter 'rgb-table)]
                 [imf (make-color-filter-image-filter cf)]
                 [p (make-paint #:color 'red #:image-filter imf #:antialias? #f)]
                 [s (make-surface 8 8)])
       (draw-rect (surface-canvas s) 0 0 8 8 p)
       (close-color? (surface-pixel s 4 4) (rgb 0 255 255) 1)))
   (test-case "picture retains new filters after closure"
     (define cf (make-table-argb-color-filter #:red inverse-table))
     (with-skia ([pic (call-with-picture 8 8
                       (lambda (c)
                         (with-skia ([p (make-paint #:color 'red #:color-filter cf)])
                           (draw-rect c 0 0 8 8 p))))]
                 [s (make-surface 8 8)])
       (skia-close! cf) (draw-picture (surface-canvas s) pic)
       (close-color? (surface-pixel s 4 4) (rgb 0 0 0) 1)))
   (test-case "closed and cross-thread filters reject including lerp endpoints"
     (with-skia ([a (make-luma-color-filter)] [b (make-luma-color-filter)])
       (define ch (make-channel))
       (thread (lambda ()
                 (channel-put ch
                   (with-handlers ([exn:fail? (lambda (_) #t)])
                     (make-lerp-color-filter 0 a b) #f))))
       (check-true (channel-get ch))
       (skia-close! b)
       (check-exn exn:fail? (lambda () (make-lerp-color-filter 0 a b)))))
   (test-case "direct SVG and vector-only PDF reject color-filter effects"
     (with-skia ([cf (make-probe-color-filter 'rgb-table)])
       (check-exn exn:fail:output-audit?
         (lambda () (output->bytes/audit (filtered-page cf) 'svg #:policy 'error)))
       (check-exn exn:fail:output-audit?
         (lambda () (output->bytes/audit (filtered-page cf) 'pdf #:policy 'vector-only)))))
   (test-case "output groups select bounded raster for both vector formats"
     (for ([format '(pdf svg)])
       (with-skia ([cf (make-probe-color-filter 'contrast)])
         (define result #f)
         (define page
           (make-output-page 48 32
             (lambda (c)
               (set! result
                 (draw-output-group c 0 0 48 32
                   (lambda (local)
                     (with-skia ([p (make-paint #:color 'red #:color-filter cf)])
                       (draw-rect local 0 0 48 32 p))) #:scale 2)))))
         (define-values (bs report) (output->bytes/audit page format #:policy 'error))
         (check-true (positive? (bytes-length bs)))
         (check-false (output-audit-report-blocking? report))
         (check-eq? (output-group-report-strategy result) 'raster))))
   (test-case "runtime child provenance survives optimized lerp endpoint"
     (with-skia ([effect (make-runtime-effect "half4 main(half4 c) { return c; }" #:kind 'color-filter)]
                 [runtime (runtime-effect->color-filter effect)]
                 [table (make-table-argb-color-filter)] [cf (make-lerp-color-filter 0 table runtime)])
       (define report (analyze-output-page (filtered-page cf) 'svg))
       (check-not-false (member 'runtime-color-filter
                               (map output-audit-event-feature (output-audit-report-events report))))))
   (test-case "trusted SKP roundtrip retains table operation"
     (with-skia ([cf (make-probe-color-filter 'rgb-table)]
                 [pic (call-with-picture 8 8
                        (lambda (c)
                          (with-skia ([p (make-paint #:color 'red #:color-filter cf)])
                            (draw-rect c 0 0 8 8 p))))]
                 [loaded (picture-from-bytes (picture->bytes pic) #:trusted? #t)]
                 [s (make-surface 8 8)])
       (draw-picture (surface-canvas s) loaded)
       (close-color? (surface-pixel s 4 4) (rgb 0 255 255) 1)))))
