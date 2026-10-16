#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/pictures))

@title[#:tag "skia-pictures"]{Pictures}

@defmodule[skia/pictures #:no-declare]
@(declare-exporting skia skia/pictures #:use-sources (skia/pictures))

A @deftech{picture} is an immutable recording of drawing commands and their
retained drawing data. Replaying a picture sends those commands to a canvas;
it does not call the Racket function that originally recorded them. A picture
can contain image drawing as well as geometry and text. Recording pixels does
not turn them into vector geometry.

A @deftech{picture recorder} owns a recording canvas while recording is active.
A finished picture owns its recording independently of the recorder and of the
caller's paints and paths. Closing those wrappers does not discard the picture.
Retaining a GPU-backed dependency does not remove its context or thread rules.
The ordinary CPU examples do not imply that such a recording is portable
between GPU contexts or serializable without readback.

@local-table-of-contents[#:style 'immediate-only]

@section{Recording}

@defproc[(picture? [v any/c]) boolean?]{
Returns @racket[#t] for a picture, including a closed picture, and @racket[#f] otherwise.
}

@defproc[(picture-recorder? [v any/c]) boolean?]{
Returns @racket[#t] for a picture recorder and @racket[#f] otherwise.
}

@defproc[(make-picture-recorder) picture-recorder?]{
Returns an owned recorder with no active recording. The recorder may be reused
after successfully finishing a recording. Closing it discards any unfinished
recording; closing does not return a picture.
}

@defproc[(picture-recorder-recording? [recorder picture-recorder?]) boolean?]{
Reports the recorder's recording flag. Beginning a recording sets the flag;
successfully finishing clears it. This is a stored-state query, not a test that
the native resource remains open. Use @racket[skia-closed?] for the latter.
}

@defproc[(picture-recorder-begin-recording!
          [recorder picture-recorder?] [x real?] [y real?]
          [width (and/c real? (>=/c 0))] [height (and/c real? (>=/c 0))]
          [#:spatial-index spatial-index (or/c 'none 'rtree) 'none]) canvas?]{
Begins a recording and returns its borrowed canvas. The recorder must be open
and must not already be recording. Coordinates, extents, and computed right
and bottom coordinates must be drawing scalars. Zero extents are permitted.
The rectangle is a culling bound, not a promise that drawing outside it will
be preserved or clipped in a particular way. Add an explicit canvas clip when
clipping is required.

The default @racket['none] records without a spatial index. The @racket['rtree]
option builds a spatial index for playback and may tighten the native culling
bounds. Neither option changes the nominal width and height stored in the
returned picture. The origin is not translated to zero.

Use the returned canvas only for this active recording; do not close it
independently or reuse it across recordings. Finishing or closing the recorder
ends the current recording's use of the canvas.
}

@defproc[(picture-recorder-finish-recording!
          [recorder picture-recorder?]) picture?]{
Finishes the active recording and returns an owned picture. The recorder must
be open and recording, and no protected canvas-state or layer scope may remain
active. The nominal picture dimensions are those supplied when recording began.
Finishing does not close the recorder. Native failure raises an exception rather
than returning a false picture.
}

@defproc[(call-with-picture [width (integer-in 1 32768)]
                            [height (integer-in 1 32768)]
                            [proc (-> canvas? any)]
                            [#:spatial-index spatial-index (or/c 'none 'rtree) 'none]) picture?]{
Records @racket[proc] on a fresh canvas with culling bounds at the origin and
returns the finished picture. The callback's results are discarded. The
recorder is released on success or escape; the returned picture is not released.
Do not retain the callback's canvas for later drawing.

Unlike the lower-level begin operation, this helper requires exact positive
integer extents and applies the usual @racket[(* 4 width height)] byte-limit
check, even though it records commands rather than allocating a raster page.

@racketblock[
(with-skia ([picture
             (call-with-picture 40 20
               (lambda (canvas)
                 (with-skia ([paint (make-paint #:color 'blue)])
                   (draw-rect canvas 0 0 40 20 paint))))]
            [surface (make-surface 100 40 #:background 'white)])
  (draw-picture (surface-canvas surface) picture #:x 10 #:y 10)
  (save-png surface "recording.png" #:exists 'replace))
]

@reference-figure["recording.png"
                  "A recorded blue rectangle replayed onto a larger white surface with a margin around it."]

The paint has already been closed when the picture is replayed.
}

@section{Playback and Inspection}

@defproc[(picture-width [picture picture?]) (and/c real? (>=/c 0))]{
Returns the stored nominal width. This detached metadata remains readable after
closure. It is not a measurement of visible ink or a fresh native culling query.
}

@defproc[(picture-height [picture picture?]) (and/c real? (>=/c 0))]{
Returns the stored nominal height, with the same distinction from native bounds
as @racket[picture-width].
}

@defproc[(draw-picture [canvas canvas?] [picture picture?]
                      [#:x x real? 0] [#:y y real? 0]
                      [#:width width (or/c #f (and/c real? (>=/c 0))) #f]
                      [#:height height (or/c #f (and/c real? (>=/c 0))) #f]) void?]{
Replays the picture with a translation and optional scaling. Both size keywords
must be supplied together or both omitted. When supplied, they scale the nominal
picture dimensions to the requested dimensions; the two axes can scale by
different factors. Scaling a picture with a zero nominal dimension raises an
exception. Requested zero extents are otherwise accepted.

The current transform and clip still apply. The temporary translation and scale
are restored afterward, including on escape; drawing already performed is not
undone. The operation does not subtract a nonzero native cull origin, center the
picture, or promise a purely vector representation on a document backend.


@racketblock[
(with-skia ([surface (make-surface 220 110 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([child
               (call-with-picture 35 35
                 (lambda (pc)
                   (with-skia ([orange (make-paint #:color "#EFA02B")])
                     (draw-circle pc 18 18 13 orange))))])
    (with-skia ([parent
                 (call-with-picture 100 60
                   (lambda (pc)
                     (with-skia ([blue (make-paint #:color "#326DE6")])
                       (draw-rounded-rect pc 0 0 100 60 12 12 blue))
                     (draw-picture pc child #:x 10 #:y 12)
                     (draw-picture pc child #:x 55 #:y 12)))])
      (draw-picture canvas parent #:x 60 #:y 25))))
]
@reference-figure["picture-nested-stage10.png"
                  "A parent picture records a blue rounded rectangle and two replays of a nested orange-circle picture."]
}

@defproc[(picture->image [picture picture?] [width (integer-in 1 32768)]
                         [height (integer-in 1 32768)]
                         [#:background background color? 'transparent]) image?]{
Replays a CPU-compatible picture into a new raster image with the given pixel
dimensions and color-specification background. Playback scales the picture as
in @racket[draw-picture]. The temporary surface is released and the returned
image is independently owned. Raster dimensions and storage must fit the normal
surface limits. GPU readback is not implicit.


@racketblock[
(with-skia ([surface (make-surface 220 110 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([picture
               (call-with-picture 50 35
                 (lambda (pc)
                   (with-skia ([blue (make-paint #:color (rgba 50 109 230 180))])
                     (draw-circle pc 25 18 15 blue))))]
              [image (picture->image picture 160 90 #:background "#F4D35E")])
    (draw-image canvas image 30 10)))
]
@reference-figure["picture-image-background-stage10.png"
                  "A translucent recorded blue circle is rasterized onto an explicit yellow background."]
}

@defproc[(picture-cull-bounds [picture picture?])
          (and/c (vector/c real? real? real? real?) immutable?)]{
Returns a detached four-element vector containing the native culling rectangle's
x coordinate, y coordinate, width, and height. The picture must be open. These
bounds can differ from the nominal dimensions, especially with an R-tree index;
they are not an exact visible-ink bound.
}

@defproc[(picture-unique-id [picture picture?]) exact-positive-integer?]{
Returns the native picture identifier. It identifies the current native object,
not its contents, and is not a persistent identifier for serialized data.
}

@defproc[(picture-approximate-op-count [picture picture?]
                                      [#:nested? nested? boolean? #f])
          exact-nonnegative-integer?]{
Returns the native estimate of the number of recorded operations. When
@racket[nested?] is true, the estimate includes operations in nested pictures.
It is not a count of Racket callback invocations or a timing prediction.
}

@defproc[(picture-approximate-bytes-used [picture picture?]) exact-nonnegative-integer?]{
Returns the native estimate of picture storage. It is not the serialized byte
length, a complete accounting of retained resources, or a process-memory limit.
}

@section[#:tag "skia-picture-storage"]{Trusted Picture Storage}

Native picture data, also called SKP, is a backend-specific recording format,
not an image interchange format or a stable archival format. It may contain
executable SkSL. The loaders require @racket[#:trusted? #t]; that declaration
is the caller's trust decision, not a sandbox or a security validation performed
by the library. Do not load untrusted SKP data.

The framing check accepts the @tt{skiapict} header, native-endian versions 82
through 103, finite ordered culling coordinates, and the standard payload kind.
Input must contain at least 29 bytes and fit @racket[current-skia-byte-limit].
Passing these checks does not establish that the payload is safe or decodable.
The native decoder may still reject it.

@defproc[(picture->bytes [picture picture?]) (and/c bytes? (not/c immutable?))]{
Returns an independent mutable SKP byte string for an open CPU-compatible
picture. The copied result is limited by @racket[current-skia-byte-limit]; this
does not bound all native allocations during serialization. Resource-backed
content may impose additional serialization restrictions.
}

@defproc[(picture-from-bytes [data bytes?]
                            [#:trusted? trusted? boolean? #f]
                            [#:width width (or/c #f (and/c real? (>=/c 0))) #f]
                            [#:height height (or/c #f (and/c real? (>=/c 0))) #f]) picture?]{
Returns an owned picture decoded from a copied snapshot of trusted SKP data.
Later mutation of @racket[data] does not modify the picture. The caller must
explicitly pass @racket[#:trusted? #t]; the default raises an exception.

Without overrides, the native cull width and height become the nominal size.
Both overrides must be given together and must be nonnegative drawing scalars.
They change only the nominal size used by scaled playback, not the recorded
commands, cull rectangle, or coordinate origin. Supplying the original nominal
size can preserve placement when reloading an R-tree recording.

@racketblock[
(with-skia ([picture
             (call-with-picture 20 20
               (lambda (canvas)
                 (with-skia ([paint (make-paint #:color 'blue)])
                   (draw-rect canvas 0 0 20 20 paint))))])
  (define data (picture->bytes picture))
  (with-skia ([copy (picture-from-bytes data #:trusted? #t
                                      #:width 20 #:height 20)])
    (list (picture-width copy) (picture-height copy))))
]
}

@defproc[(picture-from-file [filename path-string?]
                           [#:trusted? trusted? boolean? #f]
                           [#:width width (or/c #f (and/c real? (>=/c 0))) #f]
                           [#:height height (or/c #f (and/c real? (>=/c 0))) #f]) picture?]{
Reads a bounded snapshot from a binary file and decodes it as in
@racket[picture-from-bytes]. The file is not retained or kept open. Trust is
checked before reading; file, framing, size, and native decoding errors raise
exceptions. Width and height have the same paired-override meaning.
}

@defproc[(save-picture [picture picture?] [filename path-string?]
                       [#:exists exists (or/c 'error 'replace) 'error]) void?]{
Serializes the picture and publishes the completed SKP file. The destination's
parent directory must already exist. The default refuses an existing destination;
@racket['replace] permits replacement. A temporary file in the same directory
is renamed only after serialization and writing succeed. The helper removes an
unpublished temporary file on escape; it does not create parent directories.
}

@section{Picture Shaders}

@defproc[(make-picture-shader [picture picture?]
                             [#:tile-x tile-x (or/c 'clamp 'repeat 'mirror 'decal) 'clamp]
                             [#:tile-y tile-y (or/c 'clamp 'repeat 'mirror 'decal) 'clamp]
                             [#:sampling sampling (or/c 'nearest 'linear) 'nearest]
                             [#:local-matrix matrix (or/c matrix? #f) #f]
                             [#:tile-rect tile (or/c list? vector? #f) #f]) shader?]{
Returns an owned shader that samples the recorded picture. The shader retains
the picture independently of its wrapper. A supplied local affine matrix must
have a representable inverse. A tile rectangle contains x, y, width, and height,
with positive extents and drawing-scalar coordinates; omitting it uses the native
picture bounds. Tile modes and sampling control repeated picture sampling, not
the geometry of a later drawing operation. Picture-shader use can rasterize the
recording and does not guarantee vector output.

@racketblock[
(with-skia ([picture
             (call-with-picture 36 36
               (lambda (canvas)
                 (with-skia ([blue (make-paint #:color "#326DE6")]
                             [orange (make-paint #:color "#EFA02B")])
                   (draw-rect canvas 0 0 36 36 blue)
                   (draw-circle canvas 18 18 10 orange))))]
            [shader (make-picture-shader picture #:tile-x 'repeat #:tile-y 'repeat)]
            [paint (make-paint #:shader shader)]
            [surface (make-surface 180 100 #:background 'white)])
  (draw-rect (surface-canvas surface) 0 0 180 100 paint))
]

@reference-figure["picture-shader.png"
                  "A repeated picture shader tiles an orange circle on a blue square across the surface."]


@racketblock[
(with-skia ([surface (make-surface 220 110 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([picture
               (call-with-picture 36 36
                 (lambda (pc)
                   (with-skia ([blue (make-paint #:color "#326DE6")]
                               [orange (make-paint #:color "#EFA02B")])
                     (draw-rect pc 0 0 36 36 blue)
                     (draw-circle pc 10 18 8 orange))))]
              [shader (make-picture-shader picture #:tile-x 'mirror #:tile-y 'mirror)]
              [paint (make-paint #:shader shader)])
    (draw-rect canvas 0 0 220 110 paint)))
]
@reference-figure["picture-shader-mirror-stage10.png"
                  "A picture shader mirrors an off-center orange circle across repeated blue tiles."]
}

@section{Additional Visual Examples}

@racketblock[
(with-skia ([picture
             (call-with-picture 40 30
               (lambda (canvas)
                 (with-skia ([blue (make-paint #:color "#326DE6")]
                             [orange (make-paint #:color "#EFA02B")])
                   (draw-rect canvas 0 0 40 30 blue)
                   (draw-circle canvas 20 15 9 orange))))]
            [surface (make-surface 180 120 #:background 'white)])
  (draw-picture (surface-canvas surface) picture
                #:x 25 #:y 15 #:width 130 #:height 90))
]
@reference-figure["picture-scaled.png"
                  "A recorded blue rectangle with an orange circle replayed at a larger requested width and height."]

@racketblock[
(with-skia ([picture
             (call-with-picture 40 30
               (lambda (canvas)
                 (with-skia ([blue (make-paint #:color "#326DE6")]
                             [orange (make-paint #:color "#EFA02B")])
                   (draw-rect canvas 0 0 40 30 blue)
                   (draw-circle canvas 20 15 9 orange))))]
            [image (picture->image picture 130 90 #:background 'white)]
            [surface (make-surface 180 120 #:background 'white)])
  (draw-image (surface-canvas surface) image 25 15))
]
@reference-figure["picture-rasterized.png"
                  "The same recorded blue-and-orange scene rasterized into an image at a requested pixel size."]
