#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/fonts))

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
@tech{shaping}, bidirectional reordering, @tech{font fallback}, or paragraph wrapping.
Use @racket[shape-text] for a single @tech{shaped run} and @racket[layout-mixed-text]
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


@racketblock[
(with-skia ([surface (make-surface 280 105 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([normal (make-font #:size 36)]
              [bold (make-font #:size 36 #:embolden? #t)]
              [paint (make-paint #:color "#20344E")])
    (draw-simple-text canvas "Skia" 15 42 normal paint)
    (draw-simple-text canvas "Skia" 15 92 bold paint)))
]
@reference-figure["font-embolden-stage10.png"
                  "The word Skia is shown normally and again with the font embolden flag enabled."]
}

@section[#:tag "skia-font-metrics"]{Font Metrics}

@deftech{Font metrics} describe the selected font, not the visible extent of a particular
string. Distances are scaled to the font's drawing size. Vertical coordinates
are relative to the baseline, with negative coordinates above it in the usual
downward-positive canvas. Font data and native backends determine the values;
zero can indicate that a metric is unavailable.

The @deftech{baseline} is the reference line from which vertical font metrics
are measured. The @deftech{ascent} and @deftech{descent} are the font's vertical
coordinates used for line spacing, normally negative and positive, respectively.
The @deftech{leading} is the recommended additional spacing between lines.

@bold{Conceptual diagram.} The baseline is the origin for vertical font metrics.
For the measured font below, ascent @math{a} is above that origin and normally
negative, while descent @math{d} is below it and normally positive. Moving a
drawing baseline @math{b} moves all three guides to @math{b+a}, @math{b}, and
@math{b+d}; it does not change the metrics themselves.

@reference-figure["concept-font-metrics.png"
                  "A measured Hgx specimen is drawn against its baseline, negative ascent guide, positive descent guide, downward y axis, and cap-height and x-height guides. Labels show the actual measured ascent and descent for the font."]

The top and bottom metrics are separate native extents. Neither those guides
nor ascent and descent are the ink bounds of this particular string; use
@racket[simple-text-bounds] when string geometry is required.

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

@subsection{Metrics, Baselines, and Advance}

The following guide draws the same @racket[font-get-metrics] and
@racket[measure-simple-text] values used by the program.  The descenders in
@racket["glyph"] extend below the baseline but remain above the font's descent
guide; the advance is the next origin, not an ink bound.

@racketblock[
(with-skia ([surface (make-surface 420 205 #:background 'white)]
            [font (make-font #:size 58)]
            [text-paint (make-paint #:color "#20344E")]
            [ascent-paint (make-paint #:color "#D64F45" #:style 'stroke)]
            [baseline-paint (make-paint #:color "#326DE6" #:style 'stroke)]
            [descent-paint (make-paint #:color "#2C9B6F" #:style 'stroke)]
            [advance-paint (make-paint #:color "#8255C7" #:style 'stroke)]
            [label-font (make-font #:size 12)]
            [label-paint (make-paint #:color "#526070")])
  (define canvas (surface-canvas surface))
  (define text "glyph")
  (define x 35)
  (define baseline 120)
  (define metrics (font-get-metrics font))
  (define ascent (+ baseline (font-metrics-ascent metrics)))
  (define descent (+ baseline (font-metrics-descent metrics)))
  (define advance (measure-simple-text font text))
  (draw-line canvas 22 ascent 235 ascent ascent-paint)
  (draw-line canvas 22 baseline 235 baseline baseline-paint)
  (draw-line canvas 22 descent 235 descent descent-paint)
  (draw-simple-text canvas text x baseline font text-paint)
  (draw-line canvas x 160 (+ x advance) 160 advance-paint)
  (draw-simple-text canvas "ascent" 250 (+ ascent 4) label-font label-paint)
  (draw-simple-text canvas "baseline" 250 (+ baseline 4) label-font label-paint)
  (draw-simple-text canvas "descent" 250 (+ descent 4) label-font label-paint)
  (draw-simple-text canvas "advance" 35 183 label-font label-paint))
]
@reference-figure["font-metrics-guides.png"
                  "The word glyph is drawn between colored ascent, baseline, and descent guides, with a separate horizontal guide ending at its measured advance."]

@section{Simple Text and Character Mapping}

An @deftech{advance} is the displacement of the next glyph origin. It is not
an ink bound: a space can have an advance without visible ink, while a glyph
can extend to either side of its advance interval. These simple operations use
one typeface and the input character order. A newline does not request a new
baseline; paragraph line breaking is provided by @racket[layout-text].

@defproc[(draw-simple-text [canvas canvas?] [text string?] [x real?] [y real?]
                  [font font?] [paint paint?]) void?]{
Draws unshaped text with the @tech{baseline} origin at coordinates @racket[x] and
@racket[y], using @racket[font] and @racket[paint]. The coordinates must be
drawing scalars. The canvas transform and clip apply. The operation does not
close its arguments. It is suitable only when direct character-to-glyph mapping
and ordinary advances are sufficient.

The baseline-relative metric diagram in @secref["skia-font-metrics"] explains
why @racket[y] is a baseline origin rather than the top of the ink, and why an
advance is not a string's ink width.

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

@reference-figure["simple-text.png"
                  "The word Skia drawn in black on a white background using a 24-unit font."]
}

@defproc[(measure-simple-text [font font?] [text string?] [#:paint paint (or/c paint? #f) #f]) real?]{
Returns the horizontal @tech{advance} of the unshaped text in local drawing units.
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

@bold{Conceptual diagram.} An advance interval tells the next drawing origin
where to go. It is not an ink rectangle: the right panel's trailing space
extends the measured advance while adding no visible glyph ink. A simple-text
bounds result @math{(bx, by, bw, bh)} is translated by its drawing origin, so
its target rectangle is @math{(origin-x+bx, baseline-y+by, bw, bh)}.

@reference-figure["concept-text-advance.png"
                  "Two baseline-aligned A specimens compare blue advance intervals with red measured ink bounds. The second specimen has a visibly longer advance marked as a trailing-space annotation but the same ink rectangle."]

@racketblock[
(with-skia ([surface (make-surface 250 90 #:background 'white)]
            [font (make-font #:size 40)]
            [text-paint (make-paint #:color 'black)]
            [bounds-paint (make-paint #:color 'red #:style 'stroke #:stroke-width 1)]
            [baseline-paint (make-paint #:color "#888888" #:style 'stroke #:stroke-width 1)])
  (define x 25)
  (define y 62)
  (define-values (bx by bw bh) (simple-text-bounds font "Skia"))
  (draw-line (surface-canvas surface) 10 y 235 y baseline-paint)
  (draw-simple-text (surface-canvas surface) "Skia" x y font text-paint)
  (draw-rect (surface-canvas surface) (+ x bx) (+ y by) bw bh bounds-paint))
]

@reference-figure["font-bounds.png"
                  "The word Skia in black, with a gray baseline and a red rectangle around its measured ink bounds."]
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

The converted outline can be filled or stroked like any other path. Both rows
below come from @racket[simple-text-path] for the same text and font; neither
row is native text drawing.

@racketblock[
(with-skia ([surface (make-surface 360 190 #:background 'white)]
            [font (make-font #:size 52)]
            [fill-paint (make-paint #:color "#326DE6")]
            [stroke-paint (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 2)]
            [label-font (make-font #:size 12)]
            [label-paint (make-paint #:color "#526070")])
  (define canvas (surface-canvas surface))
  (with-skia ([filled (simple-text-path font "path" 20 78)]
              [stroked (simple-text-path font "path" 20 170)])
    (draw-simple-text canvas "filled monochrome outline" 20 20 label-font label-paint)
    (draw-path canvas filled fill-paint)
    (draw-simple-text canvas "stroked monochrome outline" 20 110 label-font label-paint)
    (draw-path canvas stroked stroke-paint)))
]
@reference-figure["simple-text-path-outlines.png"
                  "Two copies of path converted with simple-text-path: a filled blue monochrome outline above and the same orange stroked outline below."]
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

@racketblock[
(with-skia ([surface (make-surface 140 100 #:background 'white)]
            [font (make-font #:size 70)]
            [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 2)])
  (define outlines (font-glyph-paths font (font-text->glyphs font "A")))
  (define outline (vector-ref outlines 0))
  (when outline
    (call-with-skia-resource outline
      (lambda (path)
        (with-canvas-state (surface-canvas surface)
          (canvas-translate! (surface-canvas surface) 35 78)
          (draw-path (surface-canvas surface) path paint))))))
]

@reference-figure["glyph-outline.png"
                  "The glyph A drawn only as its blue vector outline."]
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


@racketblock[
(with-skia ([surface (make-surface 320 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([font (make-font #:size 30)]
              [gray (make-paint #:color "#A0A7B0")]
              [blue (make-paint #:color "#326DE6")]
              [rule (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 2)])
    (define text "Skia for Racket")
    (draw-simple-text canvas text 15 55 font gray)
    (define-values (count width) (font-break-text font text 145))
    (draw-simple-text canvas (substring text 0 count) 15 55 font blue)
    (draw-line canvas 15 70 (+ 15 width) 70 rule)))
]
@reference-figure["font-break-prefix-stage10.png"
                  "The longest prefix fitting a width is colored blue, with a blue rule showing its measured advance."]
}

@section{Additional Visual Examples}

@racketblock[
(with-skia ([surface (make-surface 250 130 #:background 'white)]
            [font (make-font #:size 18)]
            [paint (make-paint #:color "#20344E")])
  (draw-simple-text (surface-canvas surface) "Skia" 15 30 font paint)
  (font-set-size! font 30)
  (draw-simple-text (surface-canvas surface) "Skia" 15 72 font paint)
  (font-set-size! font 44)
  (draw-simple-text (surface-canvas surface) "Skia" 100 112 font paint))
]
@reference-figure["font-sizes.png"
                  "The word Skia drawn three times at increasing font sizes."]

@racketblock[
(with-skia ([surface (make-surface 260 100 #:background 'white)]
            [normal (make-font #:size 34)] [wide (make-font #:size 34)]
            [paint (make-paint #:color "#20344E")])
  (font-set-scale-x! wide 1.7)
  (draw-simple-text (surface-canvas surface) "Skia" 15 42 normal paint)
  (draw-simple-text (surface-canvas surface) "Skia" 15 86 wide paint))
]
@reference-figure["font-scale-x.png"
                  "The word Skia at normal width above a horizontally stretched version produced by font scale-x."]

@racketblock[
(with-skia ([surface (make-surface 260 100 #:background 'white)]
            [normal (make-font #:size 34)] [skewed (make-font #:size 34)]
            [paint (make-paint #:color "#20344E")])
  (font-set-skew-x! skewed 0.4)
  (draw-simple-text (surface-canvas surface) "Skia" 15 42 normal paint)
  (draw-simple-text (surface-canvas surface) "Skia" 15 86 skewed paint))
]
@reference-figure["font-skew-x.png"
                  "The word Skia at normal slant above a visibly skewed version produced by font skew-x."]
