# Persistent pictures and picture shaders

A `picture?` is an owned, immutable recorded drawing. It is not a bitmap and does
not keep the Racket drawing callback. The persistence API serializes that native
drawing to an SKP byte stream and reconstructs another ordinary `picture?` from
it. Import `(require skia)` or `(require skia/pictures)`.

## Record, save, and reload

```racket
#lang racket/base
(require skia)

(with-skia ([original
             (call-with-picture 240 140
               (lambda (canvas)
                 (with-skia ([paint (make-paint #:color 'blue)])
                   (draw-rounded-rect canvas 10 10 220 120 16 16 paint))))])
  (save-picture original "drawing.skp" #:exists 'replace)
  (with-skia ([loaded (picture-from-file "drawing.skp" #:trusted? #t)]
              [image (picture->image loaded 480 280)])
    (save-image image "drawing.png" 'png #:exists 'replace)))
```

The original and loaded pictures are independent owned resources. Closing one,
its recorder, or its original drawing resources does not close the other.
`picture->bytes` returns independent mutable bytes; the loader snapshots its
input and makes a native SKData copy. Mutating the caller's input after loading
does not change the loaded drawing. Resource queries, serialization, and shader
creation use the existing creator-thread and closed-resource checks.

`save-picture` defaults to `#:exists 'error`. `'replace` explicitly permits
replacement. Serialization must succeed before a same-directory temporary file
is written and renamed over the target. Failure before publication leaves an
existing target unchanged. Temporary files are cleaned up on exits. This is
atomic publication, not a durability guarantee across a power failure.

## Native loading is explicitly trusted

Both loaders default to `#:trusted? #f` and raise until the caller supplies
`#:trusted? #t`. **Do not apply that flag to arbitrary downloaded or user-supplied
SKPs.** The pinned native deserializer permits embedded SkSL programs; decoding
can involve shader compilation and native allocations. The C shim does not
expose custom decoding callbacks or an option to disable SkSL.

The wrapper checks the byte limit, header, version range, finite ordered cull
rectangle, and standard payload-kind marker before native decoding. These are
framing checks, not a payload validator, sandbox, shader timeout, or memory quota
for native reconstruction. Native decode failure raises an exception; successful
decoding is not proof that a stream is safe or visually equivalent everywhere.

`current-skia-byte-limit` bounds the supplied encoded bytes and the copied
serialized result. File input is read in bounded chunks. It does **not** cap all
native memory used while recording, decoding, encoding embedded images,
serializing, building an R-tree, or sampling a picture shader.

The pinned m119 writer uses **SKP version 103**. Its reader accepts stream versions
82 through 103; the SKP format version is not Skia milestone 119. The stream uses
the native byte order. Compatibility across Skia upgrades, architectures, fonts,
and graphics configurations is not promised. Keep the original authoring inputs
and include the library/native version and your own content/version key in cache
invalidation. Native object IDs are not suitable cache keys.

## Metadata and coordinate conventions

```racket
(picture-cull-bounds picture)                    ; immutable #(x y width height)
(picture-unique-id picture)                      ; nonzero native uint32 ID
(picture-approximate-op-count picture)           ; shallow estimate
(picture-approximate-op-count picture #:nested? #t)
(picture-approximate-bytes-used picture)
```

Each query requires a live picture on its creator thread. Returned numbers and
bounds are detached and remain usable after closure. Operation counts reflect
native optimization and optional nested accounting, not a count of Racket calls.
The byte estimate is not a complete accounting of referenced image/font/shader
storage or peak allocations. IDs identify native objects within a process; a
fresh process can reuse the same numeric ID for unrelated content.

**Cull bounds are not an exact painted bounding box or an implicit clip.** They
are the caller's promise about where the recording can draw; native recording or
replay is allowed to discard work outside that promise. Explicitly clip drawing
when clipping is required. Nonzero cull origins remain part of the original
coordinate system. Neither loading nor `draw-picture` recenters them.

The existing `picture-width` / `picture-height` are nominal placement extents.
For live recordings they remain the extents supplied to the Racket recording
API. SKP stores the native cull rectangle, not these separate Racket fields.
Consequently, loaded pictures default to the native cull rectangle's width and
height. Empty pictures can have zero native/nominal extent; they can be replayed
without resizing but cannot be scaled by `draw-picture` or `picture->image`.

Supply both nominal dimensions when the cache must retain a different placement
extent, especially after R-tree construction tightens the native cull:

```racket
(picture-from-bytes bytes #:trusted? #t #:width 640 #:height 360)
(picture-from-file "drawing.skp" #:trusted? #t #:width 640 #:height 360)
```

The optional dimensions must be finite and nonnegative and must be supplied
together. They affect placement scaling only; they do not rewrite commands,
change native cull bounds, or translate the drawing. Persist those nominal
values in your own cache metadata when needed.

## Optional R-tree-backed recording

```racket
(call-with-picture width height draw #:spatial-index 'rtree)
(picture-recorder-begin-recording! recorder x y width height
                                 #:spatial-index 'rtree)
```

The default is `'none`; those are the only two accepted choices. The R-tree can
help native replay select operations intersecting a clip. The native factory is
invoked synchronously and released immediately; the recorder owns the resulting
hierarchy. Existing recording, protected-scope, expiration, and thread rules are
unchanged. Reusing a recorder resets its provenance for either index choice.

Skia can tighten a tree-backed picture's native cull bounds at finish. Nominal
Racket extents are preserved. Native SKP loading reconstructs an ordinary
recording: **the previous in-memory R-tree is not restored from the stream**.
No replay performance improvement is promised without a workload-specific
benchmark. Directly replaying a loaded picture into another recording also does
not magically recover its missing audit provenance.

## Picture shaders

```racket
(make-picture-shader picture
                     #:tile-x 'repeat #:tile-y 'mirror
                     #:sampling 'linear
                     #:local-matrix (matrix-rotate-degrees 20)
                     #:tile-rect '(0 0 64 48))
```

The result is an ordinary owned `shader?`, usable in `make-paint`, paint setters,
shader composition, or a runtime shader's child binding. The shader retains the
native picture; closing the original picture wrapper does not invalidate it.
The auditor separately copies its symbolic feature summary, not native pointers
or a strong reference to the original wrapper.

Tile modes are `'clamp` (default), `'repeat`, `'mirror`, and `'decal` independently
on each axis. Sampling is `'nearest` (default) or `'linear`. This selects native
picture-shader sampling, not arbitrary `SkSamplingOptions` or a fixed cache DPI.
The optional tile rectangle is a nonempty finite `(x y width height)` list or
vector in picture coordinates; omitted tiles use native cull bounds. A tile can
include transparent padding or select a subset. The affine local matrix changes
sampling coordinates without moving the destination geometry. It must have a
representable inverse. General `matrix3?` / `matrix4?` values are not accepted
here; those belong to the canvas matrix API.

The backend may render/cache the picture into raster storage while sampling it.
This is not a promise of vector tiling or path-style antialiasing at every scale.
Recorded links do not become clickable instances of a sampled tile. Add document
annotations on the receiving canvas instead.

## Output auditing and PDF/SVG

A live recording preserves the feature provenance collected by the public
wrapper. A loaded SKP has no such trusted Racket history. Its
`deserialized-picture` feature is **`unknown` on every backend**, including inside
explicit raster groups. No public API accepts an unverified JSON summary as a
certificate of the bytes. Re-recording or using the loaded picture in a shader
preserves that unknown feature.

Strict `'error` and `'vector-only` exports therefore reject loaded pictures before
publication. A caller can deliberately use `'report` to submit a trusted stream
to a backend and retain its blocking report. That does not repair unsupported
operations or certify visual fidelity. For a deliberately flattened result,
render the trusted picture to an image outside the audited document callback and
embed that image, accepting the loss of interactivity and vector/text semantics.
That is a change of representation, not recovered provenance.

A live `picture-shader` is conservatively `needs-raster` for PDF/SVG; use
`draw-rasterized` around its destination drawing. Within that group it becomes
`rasterized`. A shader carrying recorded annotations gets the separate
`picture-shader-annotation` / `discarded` finding, which rasterization does not
resolve. Loaded-picture shaders also retain `deserialized-picture` / `unknown`.

The example registry deliberately has two policies: its roundtrip page submits
a known simple imported stream with `'report`, while the indexed and sampled
pages use strict exports. The combined PDF has the expected blocking unknown
finding from its roundtrip page. Do not confuse this expected diagnostic with
an exception in the test runner.

## Native source basis and limits

The implementation targets `mono/skia` revision
`40f75dc0051d141913c07c20d4c19590c7da0cb7`:
`include/c/sk_picture.h`, `src/c/sk_picture.cpp`, `src/core/SkPicture.cpp`,
`src/core/SkPicturePriv.h`, `src/core/SkPictureRecorder.cpp`, and
`include/core/SkSerialProcs.h`, `src/core/SkPictureRecord.cpp`, and
`src/shaders/SkPictureShader.cpp`.

The default native serializer handles image and typeface resources using its
built-in policies; this layer exposes no custom resource callbacks, external
asset resolver, cross-platform font embedding guarantee, deterministic-byte
cache identity, or archival format. Validate important images, text, colors,
annotations, and backend-specific effects in the actual deployment environment.
