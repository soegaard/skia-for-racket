# Native scanline decoding — 0.76b

Stage **0.76b** keeps numeric package version **`0.76`**, SkiaSharp **3.119.1**
(m119), and minimum Racket **8.18**. The API is exported by `codec-scanlines.rkt`
and re-exported by `main.rkt` (`skia`). Importing these modules does not load Skia,
open files, or change cache settings. No C/C++ compiler, native helper, GPU, or
live-port worker is added.

## What a session owns

A session owns a **private native codec**. It is not the caller's ordinary
`codec?`, so another codec operation cannot restart its cursor. It participates
in `skia-resource?`, `skia-closed?`, `skia-close!`, `call-with-skia-resource`, and
`with-skia`. Close is deterministic and idempotent on the owning Racket thread;
the existing native handle finalizer is a fallback, not the preferred cleanup.
All live session operations, including state inspection, require its creator
thread. The resource predicate itself does not inspect native state.

No caller pixel buffer is lent to Skia. Each read allocates checked, zeroed native
scratch storage; the native call borrows it synchronously, and cleanup frees it
before returning. Only successfully decoded rows are copied into a detached,
immutable batch. Skia retains no destination address between calls. This differs
from the retained-destination problem planned for incremental decoding in 0.76c.

## Construction

```racket
(codec-scanline-from-bytes bytes
                          #:scale [scale 1]
                          #:color-type [color-type 'rgba-8888]
                          #:alpha-type [alpha-type 'unpremul]
                          #:color-space [color-space 'srgb])
(codec-scanline-from-stream input
                           #:scale [scale 1]
                           #:color-type [color-type 'rgba-8888]
                           #:alpha-type [alpha-type 'unpremul]
                           #:color-space [color-space 'srgb])
(codec-scanline-from-port/buffered in
                                  #:scale [scale 1]
                                  #:color-type [color-type 'rgba-8888]
                                  #:alpha-type [alpha-type 'unpremul]
                                  #:color-space [color-space 'srgb]
                                  #:limit [limit (current-skia-byte-limit)]
                                  #:close? [close? #f]
                                  #:cancel-evt [cancel-evt #f])
(codec-scanline-session? value)
```

The byte constructor takes an independent native copy through the existing codec
constructor. Later mutation of the input byte string is harmless. The stream
constructor consumes a **private duplicate positioned at zero**, not the caller's
current cursor. The caller's stream remains open and unchanged; it can be closed
while the session lives. For a native file stream, the backing file must remain
stable for the lifetime of its consumers. This is native file access, not a file
snapshot. See [STREAMS.md](STREAMS.md).

The `/buffered` constructor reads from the port's current position to EOF before
native decoding. It preserves the existing short-I/O, quota, cancellation, and
optional-close rules. It is **not a retained live-port decoder**. Invalid scale or
pixel-description arguments fail before the port is accepted. Cancellation applies
to buffering, not subsequent synchronous native scanline calls.

`#:scale` uses native `codec-scaled-dimensions` negotiation. It need not produce
exactly `scale * source-size`; a codec without native scaling returns its original
size, and scales at least one do not request upscaling. The suggested dimensions
are then passed to the real native scanline-start function, whose success is still
required. There is no resampling, full-decode, or crop fallback. Scale validation
uses the actual rounded C-float representation, including rejection of underflow
to zero. See [CODEC-QUERIES.md](CODEC-QUERIES.md).

Destination formats and alpha types are described by `image-info`; color spaces
are detached descriptors (`#f`, `'srgb`, `'linear-srgb`, or checked ICC bytes), not
live resource handles. A structurally valid image description is not a promise
that a particular native decoder supports that conversion. Unsupported modes,
scales, and conversions fail explicitly. The native codec retains the destination
color-space reference after successful start. Default output is sRGB RGBA8888
with unpremultiplied alpha. `#f` requests no destination color-space conversion
rather than implicitly labeling the pixels sRGB.

Only **frame zero and full-width rows** are exposed. Horizontal native subsets
are deliberately outside this stage; use native row skipping for vertical
selection. EXIF orientation remains source metadata: rows are in encoded-pixel
coordinates before EXIF rotation/reflection. Native bottom-up row order is handled
separately. A scaled bottom-up request whose target height differs from the source
height is rejected, rather than inventing a mapping outside the pinned native
contract. Existing one-shot and animation APIs are unchanged.

### Native start errors

```racket
(exn:fail:codec-scanline? value)
(exn:fail:codec-scanline-result exception)
(exn:fail:codec-scanline-native-code exception)
```

A non-success return from native scanline start raises this `exn:fail` subtype,
with the native integer result and its symbolic name (for example `unimplemented`,
`invalid-conversion`, or `invalid-scale`). Malformed source data rejected before
scanline start, ownership/argument errors, and wrapper invariant failures use the
existing exception conventions; not every constructor error has this subtype.
The private codec is released on failure. The pinned PNG decoder used by the
acceptance fixtures rejects scanline mode; no successful PNG scanline decode is
manufactured by calling another decoder API.

## Metadata, cursor and state

```racket
(codec-scanline-state session)
(codec-scanline-info session)
(codec-scanline-source-info session)
(codec-scanline-order session)
(codec-scanline-position session)
(codec-scanline-next-row session)
(codec-scanline-output-row session input-row)
```

`codec-scanline-info` returns detached destination `image-info`, including native
negotiated dimensions and the requested storage interpretation.
`codec-scanline-source-info` returns the original detached `encoded-image-info`.
Values already obtained survive session closure. Except for
`codec-scanline-state`, live metadata access rejects a closed session.

The state is one of:

| State | Meaning |
|---|---|
| `ready` | Native start succeeded and rows remain. |
| `complete` | All encoded rows were consumed or skipped successfully. This does **not** mean all pixels were returned to the caller. |
| `incomplete` | A native read decoded fewer rows than requested. Terminal: close the session rather than resuming it. |
| `failed` | A valid native skip failed, or an invariant/exception occurred after native cursor mutation. Terminal. |
| `closed` | The owning codec handle has been released. |

`codec-scanline-order` is `'top-down` or `'bottom-up`. Unknown native order values
raise; they are not interpreted as top-down. Position is the count of requested
or skipped **input-order** rows. The native codec advances it by the requested
count even if a read returns fewer rows or a valid skip fails. Position therefore
does not certify successful pixel decoding.

`codec-scanline-next-row` returns the logical Y coordinate of the next row, or
`#f` after successful completion. At EOF the wrapper does **not** call native
`nextScanline`, whose mapping requires an in-range row. The accessor rejects
terminal incomplete/failed states.

`codec-scanline-output-row` maps an input-order row index to its logical Y using
the real native mapping and verifies it against the known order. It accepts only
exact integers from zero through target height minus one, does not advance the
cursor, and rejects incomplete/failed/closed sessions.

## Read and skip

```racket
(codec-scanline-read! session [count 1] #:row-bytes [row-bytes #f])
(codec-scanline-skip! session count)
```

A read requests an exact **positive** number of rows, not exceeding the remaining
rows. It returns one `scanline-batch`. Asking to read past EOF, asking for zero,
or specifying an invalid stride is an error before native cursor mutation; a
request is never silently clamped. An omitted stride uses the tight row width.
A supplied stride must be at least that width and aligned to bytes per pixel.
Padding begins at zero and stays zero in the accepted native paths.

Skipping takes a nonnegative exact count within the remaining rows, returns `#t`
on native success or `#f` on native failure, and does not return pixels. A zero
skip is a validated no-op, including in `complete`; it does not bypass lifetime
or terminal-failure checks. Native failure makes the session `failed`.

Each operation checks `current-skia-byte-limit`, the limit captured at session
creation, and the existing native layout bounds. These are logical/per-allocation
bounds, not a bound on aggregate process memory: input copies, native codec
allocations, scratch storage, retained batches, and optional converted buffers
can coexist. The existing codec constructor's dimension/input budgets still
apply even when only small row batches are requested.

Argument/quota rejection before native consumption leaves the session usable.
An exception after a native operation has advanced the cursor marks it failed;
there is no attempt to roll back the decoder.

## Detached batches and bottom-up input

```racket
(scanline-batch? value)
(scanline-batch-info batch)
(scanline-batch-row-bytes batch)
(scanline-batch-first-row batch)
(scanline-batch-requested-count batch)
(scanline-batch-decoded-count batch)
(scanline-batch-bytes batch)
(scanline-batch-complete? batch)
(scanline-batch->raster-buffer batch)
```

The batch constructor is private. Bytes and metadata are detached and immutable;
no batch owns a native handle. Bytes contain exactly `row-bytes * decoded-count`
bytes, including zero row padding, and are always ordered by **increasing logical
Y within that batch**. `first-row` gives the smallest Y represented; batch
`image-info` height equals the decoded count. A batch with zero decoded rows has
empty bytes, height zero, and `first-row = #f`.

For a complete 5-row bottom-up image, a two-row first read has:

```text
input position before: 0
logical next row before: 4
requested / decoded: 2 / 2
batch first-row: 3
batch bytes: logical row 3, then logical row 4
input position after: 2
logical next row after: 2
```

Skia reverses each requested bottom-up chunk, not only full-image reads. On a
short read, its fill is at the beginning of that allocation. For the same image
truncated after its first two encoded rows, a five-row request returns only rows
3 and 4, requested count 5, decoded count 2, position 5, state `incomplete`.
**The three native default-filled rows are not included as decoded pixels.** A
short read may reflect incomplete or erroneous input; the integer return value
cannot distinguish those causes. It is not an incremental-progress result.

`scanline-batch-complete?` means decoded count equals requested count for this
batch, not that a complete image was returned. `scanline-batch->raster-buffer`
creates independently owned mutable native storage and copies the batch into it.
It rejects a zero-row batch, respects current allocation/sample checks, and never
repositions the session. Its caller must close the resulting raster buffer.

## Example: row processing without whole-image staging

```racket
(require skia)

(with-skia ([input (make-file-input-stream "photo.jpg")]
            [scan (codec-scanline-from-stream input #:scale 1/2)])
  (skia-close! input) ; the codec has its own stream duplicate
  (let loop ()
    (when (eq? (codec-scanline-state scan) 'ready)
      (define left (- (image-info-height (codec-scanline-info scan))
                      (codec-scanline-position scan)))
      (define batch (codec-scanline-read! scan (min 16 left)))
      ;; Consume (scanline-batch-bytes batch) at its explicit first-row.
      (printf "row ~a: ~a of ~a requested rows\n"
              (scanline-batch-first-row batch)
              (scanline-batch-decoded-count batch)
              (scanline-batch-requested-count batch))
      (unless (scanline-batch-complete? batch)
        (error 'example "input ended before all requested rows decoded"))
      (loop))))
```

This does not imply that JPEG or other native decoders never retain internal
whole-image data. It means the wrapper does not call the complete-pixel decoder
or allocate a whole-image destination as an undisclosed fallback.

## Validation and CI

```bash
python tools/validate-codec-scanlines.py --racket /path/to/racket
python tools/validate-codec-scanlines.py --racket /path/to/racket --regressions none
```

Full is the standalone default. Both modes always compile and run the **32 pure
and 47 native** focused cases, the public example, the native doctor, and the
independent inspector. Only `full` compiles/runs the global regression graph.
Skipped global regressions are reported as `not-run`, not as passing.

Native evidence includes original procedural top-down/bottom-up BMPs, truncated
BMPs, native JPEG with and without EXIF orientation, unsupported PNG scanline
mode, row maps, complete/partial/empty batches, skip failure, cursor state, and
zero-padding checks. Pillow independently decodes complete BMP/JPEG fixtures;
JPEG half-size comparisons use native reduced JPEG decoding, not a resized
full-image oracle. Synthetic Python fixtures test the inspector and are not
native Skia execution evidence.

The existing `codec-queries.yml` jobs run the scanline validator in focused mode
only after query acceptance succeeds. The query validator owns the job's selected
global-regression scope, preventing a second full-suite run. Both query and
scanline evidence are retained, and all jobs remain required by Acceptance.
The central installed-package regression matrix also includes these suites.
The CI source job keeps the existing Python inspector requirements installation.
No new top-level workflow, required GPU lane, or document renderer is added.

## Pinned implementation references

- C declarations: `mono/skia`, commit `40f75dc0051d141913c07c20d4c19590c7da0cb7`,
  `include/c/sk_codec.h`.
- Native public contract: the same commit, `include/codec/SkCodec.h`.
- Requested-count cursor advancement and partial fill:
  `src/codec/SkCodec.cpp`, `getScanlines`, `skipScanlines`, `fillIncompleteImage`.
- Bottom-up chunk placement and truncated row counts:
  `src/codec/SkBmpStandardCodec.cpp`, `decodeRows`.

Incremental decoding and any retained destination/partial-input continuation
remain **0.76c**. Horizontal subset decoding, arbitrary later animation frames,
and long-lived callback-backed port sessions are not claimed by this stage.
