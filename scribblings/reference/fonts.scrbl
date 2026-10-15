#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/fonts))

@title[#:tag "skia-fonts"]{Fonts and Text Measurement}

@(declare-exporting skia)

A @deftech{font} combines a @tech{typeface} with a size, horizontal scale,
skew, and rendering settings. Fonts are mutable @tech{owned resource}s.
Native font operations require open resources on their owning thread unless
an entry only inspects a detached metrics value.

A @deftech{glyph ID} is a typeface-specific index, not a Unicode code point.
Glyph zero is the missing-glyph index. A glyph ID from one face must not be
interpreted as the same glyph in another face.

The simple text and glyph-query functions do not perform contextual
shaping, bidirectional reordering, font fallback, or paragraph wrapping.
Use @racket[shape-text] for a single shaped run and @racket[layout-mixed-text]
for mixed-direction text and font fallback.

@local-table-of-contents[#:style 'immediate-only]

@section{Font Construction and Settings}

@defproc[(font? [v any/c]) boolean?]{
Returns @racket[#t] for a font resource and @racket[#f] otherwise. Closure does not change the result.
}

@defproc[(make-font [face (or/c typeface? #f) #f]
                [#:size size (and/c real? (>/c 0)) 12]
                [#:scale-x scale-x (and/c real? (>/c 0)) 1]
                [#:skew-x skew-x real? 0]
                [#:edging edging (or/c 'alias 'antialias 'subpixel-antialias) 'antialias]
                [#:hinting hinting (or/c 'none 'slight 'normal 'full) 'normal]
                [#:subpixel? subpixel? boolean? #f]
                [#:linear-metrics? linear-metrics? boolean? #f]
                [#:embolden? embolden? boolean? #f]
                [#:embedded-bitmaps? embedded-bitmaps? boolean? #f]
                [#:force-auto-hinting? force-auto-hinting? boolean? #f]
                [#:baseline-snap? baseline-snap? boolean? #t]) font?]{
Creates an owned mutable font. The size is measured in local drawing units,
not necessarily device pixels or typographic points. Size, horizontal scale,
and skew must be @tech{drawing scalar}s. Size and horizontal scale must be
positive; skew is a shear factor, not an angle.

The font retains the supplied face through a native reference. Closing the
caller's face wrapper does not invalidate the font. With @racket[#f], the
constructor creates a default typeface and manages that private wrapper too.
No fallback chain is installed in the resulting font.

Edging selects aliased, grayscale-antialiased, or subpixel-antialiased glyph
edges. Subpixel positioning is a separate option. Hinting and the other flags
request native font behavior; a target or font backend may limit their effect.
The corresponding query and setter functions describe each setting.

@racketblock[
(with-skia ([face (make-typeface)]
            [font (make-font face #:size 24)])
  (skia-close! face)
  (font-size font))
]

The font remains usable after the supplied wrapper is closed. The surrounding
scope releases both wrappers; repeated closure of the face is harmless.
}

@defproc[(font-size [font font?]) real?]{
Returns the font's size in local drawing units.
}

@defproc[(font-set-size! [font font?] [value (and/c real? (>/c 0))]) void?]{
Sets the font's size in local drawing units. The new size must be a positive drawing scalar.
Existing shapers and text blobs keep their captured font settings.
}

@defproc[(font-scale-x [font font?]) real?]{
Returns the font's horizontal scale factor.
}

@defproc[(font-set-scale-x! [font font?] [value (and/c real? (>/c 0))]) void?]{
Sets the font's horizontal scale factor. The new factor must be a positive drawing scalar.
Existing shapers and text blobs keep their captured font settings.
}

@defproc[(font-skew-x [font font?]) real?]{
Returns the font's horizontal shear factor.
}

@defproc[(font-set-skew-x! [font font?] [value real?]) void?]{
Sets the font's horizontal shear factor. The factor must be a drawing scalar; it is not an angle.
Existing shapers and text blobs keep their captured font settings.
}

@defproc[(font-edging [font font?]) (or/c 'alias 'antialias 'subpixel-antialias)]{
Returns the font's requested glyph-edge rendering mode.
}

@defproc[(font-set-edging! [font font?] [value (or/c 'alias 'antialias 'subpixel-antialias)]) void?]{
Sets the font's requested glyph-edge rendering mode. This controls edge coverage, not whether
glyph origins use subpixel positions.
Existing shapers and text blobs keep their captured font settings.
}

@defproc[(font-hinting [font font?]) (or/c 'none 'slight 'normal 'full)]{
Returns the font's requested hinting level.
}

@defproc[(font-set-hinting! [font font?] [value (or/c 'none 'slight 'normal 'full)]) void?]{
Sets the font's requested hinting level. Hinting adapts glyph rendering to the device grid; its
effect depends on the font backend.
Existing shapers and text blobs keep their captured font settings.
}

@defproc[(font-subpixel? [font font?]) boolean?]{
Reports whether subpixel glyph positioning is requested.
}

@defproc[(font-set-subpixel! [font font?] [enabled? boolean?]) void?]{
Sets whether subpixel glyph positioning is requested.
This does not select a different typeface or reshape an existing run.
}

@defproc[(font-linear-metrics? [font font?]) boolean?]{
Reports whether linear scaling of metrics is requested instead of hinted metric adjustments.
}

@defproc[(font-set-linear-metrics! [font font?] [enabled? boolean?]) void?]{
Sets whether linear scaling of metrics is requested instead of hinted metric adjustments.
This does not select a different typeface or reshape an existing run.
}

@defproc[(font-embolden? [font font?]) boolean?]{
Reports whether synthetic glyph emboldening is requested.
}

@defproc[(font-set-embolden! [font font?] [enabled? boolean?]) void?]{
Sets whether synthetic glyph emboldening is requested.
This does not select a different typeface or reshape an existing run.
}

@section[#:tag "skia-font-metrics"]{Font Metrics}

Font metrics describe the selected font, not the visible extent of a particular
string. Distances are scaled to the font's drawing size. Vertical coordinates
are relative to the baseline, with negative coordinates above it in the usual
downward-positive canvas. Font data and native backends determine the values;
zero can indicate that a metric is unavailable.

@defproc[(font-get-metrics [font font?]) font-metrics?]{
Returns a detached metrics snapshot. Later font mutation or closure does
not change the snapshot. Metrics do not include the canvas transform or the
paint's effects; use @racket[simple-text-bounds] for a particular simple string.

@racketblock[
(define metrics
  (with-skia ([font (make-font #:size 24)])
    (font-get-metrics font)))
(list (font-metrics-ascent metrics) (font-metrics-descent metrics))
]
}

@defproc[(font-metrics? [v any/c]) boolean?]{
Returns @racket[#t] for a detached font-metrics value and @racket[#f] otherwise.
}

@defproc[(font-metrics-top [metrics font-metrics?]) real?]{
Returns the native top extent relative to the baseline, not the ascent used for line spacing.
}

@defproc[(font-metrics-ascent [metrics font-metrics?]) real?]{
Returns the native ascent coordinate, normally negative above the baseline.
}

@defproc[(font-metrics-descent [metrics font-metrics?]) real?]{
Returns the native descent coordinate, normally positive below the baseline.
}

@defproc[(font-metrics-bottom [metrics font-metrics?]) real?]{
Returns the native bottom extent relative to the baseline, not the descent used for line spacing.
}

@defproc[(font-metrics-leading [metrics font-metrics?]) real?]{
Returns the recommended additional spacing between lines.
}

@defproc[(font-metrics-average-character-width [metrics font-metrics?]) real?]{
Returns the native average-character-width metric, not an average computed from a supplied string.
}

@defproc[(font-metrics-max-character-width [metrics font-metrics?]) real?]{
Returns the native maximum-character-width metric.
}

@defproc[(font-metrics-x-min [metrics font-metrics?]) real?]{
Returns the native leftmost horizontal font extent.
}

@defproc[(font-metrics-x-max [metrics font-metrics?]) real?]{
Returns the native rightmost horizontal font extent.
}

@defproc[(font-metrics-x-height [metrics font-metrics?]) real?]{
Returns the font's x-height metric as a distance.
}

@defproc[(font-metrics-cap-height [metrics font-metrics?]) real?]{
Returns the font's capital-height metric as a distance.
}

@defproc[(font-metrics-underline-thickness [metrics font-metrics?]) (or/c real? #f)]{
Returns underline thickness, or @racket[#f] when its native validity flag is absent.
}

@defproc[(font-metrics-underline-position [metrics font-metrics?]) (or/c real? #f)]{
Returns the underline position relative to the baseline, or @racket[#f] when unavailable.
}

@defproc[(font-metrics-strikeout-thickness [metrics font-metrics?]) (or/c real? #f)]{
Returns strikeout thickness, or @racket[#f] when its native validity flag is absent.
}

@defproc[(font-metrics-strikeout-position [metrics font-metrics?]) (or/c real? #f)]{
Returns the strikeout position relative to the baseline, or @racket[#f] when unavailable.
}

@defproc[(font-metrics-spacing [metrics font-metrics?]) real?]{
Returns the native recommended baseline spacing reported with the metrics.
}

@section{Simple Text and Character Mapping}

An @deftech{advance} is the displacement of the next glyph origin. It is not
an ink bound: a space can have an advance without visible ink, while a glyph
can extend to either side of its advance interval. These simple operations use
one typeface and the input character order. A newline does not request a new
baseline; paragraph line breaking is provided by @racket[layout-text].

@defproc[(draw-simple-text [canvas canvas?] [text string?] [x real?] [y real?]
                  [font font?] [paint paint?]) void?]{
Draws unshaped text with the baseline origin at coordinates @racket[x] and
@racket[y], using @racket[font] and @racket[paint]. The coordinates must be
drawing scalars. The canvas transform and clip apply. The operation does not
close its arguments. It is suitable only when direct character-to-glyph mapping
and ordinary advances are sufficient.

Outline output uses @racket[simple-text-path] and has that operation's
monochrome-outline limitations. Complex-script shaping, kerning and ligature
substitution require the shaped-text operations.

@racketblock[
(with-skia ([surface (make-surface 240 80 #:background 'white)]
            [font (make-font #:size 24)]
            [paint (make-paint #:color 'black)])
  (draw-simple-text (surface-canvas surface) "Skia" 16 48 font paint)
  (save-png surface "simple-text.png" #:exists 'replace))
]
}

@defproc[(measure-simple-text [font font?] [text string?] [#:paint paint (or/c paint? #f) #f]) real?]{
Returns the horizontal advance of the unshaped text in local drawing units.
This is not the width of visible ink and does not apply the canvas transform.
The optional paint is forwarded to native measurement; it does not turn this
operation into shaped-text measurement.
}

@defproc[(simple-text-bounds [font font?] [text string?]
                     [#:paint paint (or/c paint? #f) #f]) (values real? real? real? real?)]{
Returns the unshaped text's bounds as four values: x, y, width, and height,
relative to a baseline origin at zero. Negative x or y values are possible.
The optional paint participates in native bounds measurement; the result does
not include a canvas transform or clip and is not a guarantee about every
filter's final output extent.

@racketblock[
(with-skia ([font (make-font #:size 24)])
  (define advance (measure-simple-text font "A "))
  (define-values (x y width height) (simple-text-bounds font "A "))
  (list advance (list x y width height)))
]

The result reports both spacing and bounds; they need not have the same width.
}

@defproc[(font-char->glyph [font font?] [character (or/c char? (integer-in 0 #xd7ff) (integer-in
          #xe000 #x10ffff))]) (integer-in 0 #xffff)]{
Maps one Unicode scalar to its glyph ID in the font's typeface. A missing
mapping returns zero. The result is not a shaped cluster and does not describe
fallback, combining marks, or contextual forms.
}

@defproc[(font-text->glyphs [font font?] [text string?]) (vectorof (integer-in 0 #xffff))]{
Maps UTF-8 text directly to glyph IDs without shaping or fallback. A missing
mapping yields glyph zero. The nonempty result is a new mutable vector; the
empty result is an empty vector. The native glyph buffer is bounded by
@racket[current-skia-byte-limit].
}

@defproc[(font-glyph-path [font font?] [glyph (integer-in 0 #xffff)]) (or/c skia-path? #f)]{
Returns an owned monochrome glyph-outline path, or @racket[#f] when the
font supplies no outline for the glyph. A bitmap-only glyph need not have a
path. The returned path incorporates font size, scale, and skew and remains
usable after the font is closed. It has not been placed at a text position.
}

@defproc[(simple-text-path [font font?] [text string?] [x real? 0] [y real? 0]) skia-path?]{
Returns an owned path for the unshaped string placed at the given baseline
origin. Coordinates must be drawing scalars. The font is not closed or mutated.
The result contains monochrome outlines; it is not a general conversion of
bitmap or color glyph rendering into vectors.
}

@section{Additional Font Controls and Glyph Queries}

@defmodule[skia/fonts #:no-declare]
@(declare-exporting skia skia/fonts #:use-sources (skia/fonts))

The additional font-control and glyph-query bindings are also provided by
@racketmodname[skia/fonts]. Batch
glyph queries return immutable vectors of copied measurements. Their glyph
inputs may be lists or vectors of unsigned 16-bit IDs, but each ID must also
be less than the current typeface's glyph count. Query payloads are bounded by
@racket[current-skia-byte-limit]; this is not a limit on all native font caches.

@defproc[(font-embedded-bitmaps? [font font?]) boolean?]{
Reports whether use of embedded glyph bitmaps is requested.
}

@defproc[(font-set-embedded-bitmaps! [font font?] [enabled? boolean?]) void?]{
Sets the request for use of embedded glyph bitmaps.
Its visible effect depends on the target transform and font backend.
}

@defproc[(font-force-auto-hinting? [font font?]) boolean?]{
Reports whether use of the font backend's automatic hinter is requested.
}

@defproc[(font-set-force-auto-hinting! [font font?] [enabled? boolean?]) void?]{
Sets the request for use of the font backend's automatic hinter.
Its visible effect depends on the target transform and font backend.
}

@defproc[(font-baseline-snap? [font font?]) boolean?]{
Reports whether baseline snapping to device pixels is requested.
}

@defproc[(font-set-baseline-snap! [font font?] [enabled? boolean?]) void?]{
Sets the request for baseline snapping to device pixels.
Its visible effect depends on the target transform and font backend.
}

@defproc[(font-typeface [font font?]) typeface?]{
Returns an independently owned reference to the current typeface, not a
borrowed field of the font. Closing or changing the font does not invalidate
the returned wrapper.
}

@defproc[(font-set-typeface! [font font?] [face typeface?]) void?]{
Replaces the font's typeface, retaining its own native reference. The
supplied face must be open; @racket[#f] is not accepted. Font size and rendering
settings are retained. Existing shapers and text blobs keep their snapshots.

@racketblock[
(with-skia ([font (make-font #:size 24)]
            [face (font-typeface font)])
  (skia-close! font)
  (typeface-family-name face))
]
}

@defproc[(font-glyph-widths [font font?] [glyphs (or/c (listof (integer-in 0 #xffff)) (vectorof
          (integer-in 0 #xffff)))]
                     [#:paint paint (or/c paint? #f) #f]) (vectorof real?)]{
Returns one advance width per supplied glyph, without kerning or contextual
positioning. The optional paint is passed to native measurement. An empty
input returns an empty vector.
}

@defproc[(font-glyph-bounds [font font?] [glyphs (or/c (listof (integer-in 0 #xffff)) (vectorof
          (integer-in 0 #xffff)))]
                     [#:paint paint (or/c paint? #f) #f]) (vectorof (list/c real? real? real?
                     real?))]{
Returns one x/y/width/height list per glyph in an immutable vector. Each
bound is relative to that glyph's own origin, not a position in a string.
The optional paint participates in native bounds measurement.
}

@defproc[(font-glyph-widths+bounds [font font?] [glyphs (or/c (listof (integer-in 0 #xffff))
          (vectorof (integer-in 0 #xffff)))]
                     [#:paint paint (or/c paint? #f) #f]) (values (vectorof real?) (vectorof
                     (list/c real? real? real? real?)))]{
Returns the advance-width vector and bounds vector as two values, using
the same native query and semantics as @racket[font-glyph-widths] and
@racket[font-glyph-bounds]. Both vectors are empty for empty input.
}

@defproc[(font-glyph-positions [font font?] [glyphs (or/c (listof (integer-in 0 #xffff)) (vectorof
          (integer-in 0 #xffff)))]
                     [#:origin origin (or/c (list/c real? real?) (vector/c real? real?)) '(0 0)])
                     (vectorof (list/c real? real?))]{
Returns glyph origins obtained by accumulating ordinary advances from
@racket[origin]. Both origin coordinates must be drawing scalars. This does
not apply shaping, pair kerning, or a canvas transform.
}

@defproc[(font-glyph-x-positions [font font?] [glyphs (or/c (listof (integer-in 0 #xffff))
          (vectorof (integer-in 0 #xffff)))]
                     [#:origin origin real? 0]) (vectorof real?)]{
Returns horizontal glyph origins accumulated from the drawing scalar
@racket[origin]. The result is the x-coordinate counterpart of
@racket[font-glyph-positions], not a shaped text layout.
}

@defproc[(font-glyph-paths [font font?] [glyphs (or/c (listof (integer-in 0 #xffff)) (vectorof
          (integer-in 0 #xffff)))]) (vectorof (or/c skia-path? #f))]{
Returns an immutable vector of independently owned glyph-outline paths,
with @racket[#f] for glyphs without paths. Each outline includes the native
per-glyph transform, including font size, scale, and skew. The container is a
detached value, but every path it contains has its own resource lifetime.
Partial results are released if construction fails.

@racketblock[
(with-skia ([font (make-font #:size 24)])
  (define outlines (font-glyph-paths font (font-text->glyphs font "Ab")))
  (dynamic-wind
    void
    (lambda ()
      (for/list ([path (in-vector outlines)])
        (and path (call-with-values (lambda () (path-bounds path)) list))))
    (lambda ()
      (for ([path (in-vector outlines)] #:when path) (skia-close! path)))))
]
}

@defproc[(font-break-text [font font?] [text string?] [max-width (and/c real? (>=/c 0))]
                     [#:paint paint (or/c paint? #f) #f]) (values exact-nonnegative-integer? real?)]{
Returns the number of Racket characters in the longest leading unshaped prefix
that fits @racket[max-width], followed by its measured width. The count is not
a UTF-8 byte offset. The width must be a nonnegative @tech{drawing scalar}.

The boundary need not be a word or grapheme boundary. This is not Unicode line
breaking or shaping-aware wrapping. An empty input returns 0 and 0.0.

@racketblock[
(with-skia ([font (make-font #:size 24)])
  (define text "AéB")
  (define-values (count width) (font-break-text font text 40))
  (list (substring text 0 count) width))
]
}
