# Retained incremental decoding — 0.76c

Milestone **0.76c** uses package version **`0.76`** and the pinned SkiaSharp
3.119.1 / m119 ABI. The public API is in `codec-incremental.rkt` and re-exported
by `main.rkt` (`skia`). Requiring it does not load Skia or create a stream.
No additional native library, C/C++ compiler, or CMake is required.

## Purpose and scope

An incremental session retains **one native decoder and one private destination
allocation** between successful incremental start and subsequent incomplete
steps. Applications feed copied encoded bytes, explicitly advance decoding, and
request independent snapshots. Pixel snapshots can exist before all encoded
input has arrived. Neither the wrapper nor its inspector substitutes a one-shot
pixel decode, scanline decode, full decode-and-crop, resampling, or re-encoding.

This initial API is intentionally bounded: first frame, full-size image, encoded
coordinates, and RGBA8888 or BGRA8888 storage with premultiplied or
unpremultiplied alpha. Scaling, subsets, float destinations, animation sessions,
and long-lived live-port-backed codec objects are not part of this API. The
one-shot, query, scanline, buffered-port, and live operation APIs are unchanged.

**Partial PNG input is chunk-framed.** The pinned libpng-backed Skia decoder
resumes reliably at complete PNG chunk boundaries. `feed!` accepts arbitrary
fragment sizes, but withholds a trailing partial chunk from native code. It does
not decode or rewrite that chunk. A PNG containing a single large IDAT can
therefore require most of the input before any pixels are available. The bounded
input prefix is retained; this is not a constant-memory networking abstraction.

Formats other than PNG are withheld until the input is explicitly final. At that
point the native codec's actual incremental mode is attempted. Unsupported modes
are reported as native failures; there is no fallback merely to obtain pixels.

## Constructing and feeding a session

```racket
(make-codec-incremental
 #:color-type [color-type 'rgba-8888]
 #:alpha-type [alpha-type 'unpremul]
 #:color-space [color-space 'srgb]
 #:row-bytes [row-bytes #f]
 #:limit [limit (current-skia-byte-limit)])

(codec-incremental-session? value)
(codec-incremental-feed! session bytes #:final? [final? #f])
```

The constructor returns an ordinary `skia-resource?`. Use `with-skia`,
`call-with-skia-resource`, or `skia-close!` for deterministic release. An abandoned
session also has the existing resource finalizer as fallback. Explicit close is
idempotent and destroys the codec **before** releasing memory retained by it.

`#:color-type` is `'rgba-8888` or `'bgra-8888`; `#:alpha-type` is `'premul` or
`'unpremul`. `#:color-space` is an existing detached description: `'srgb`,
`'linear-srgb`, complete ICC bytes, or `#f` for untagged output. Actual conversion
must be supported by the native codec. No unsupported format is silently
substituted. Image dimensions are determined from the encoded header, not supplied
by the caller.

`#:row-bytes #f` selects tight packing. An explicit stride must be positive,
4-byte-aligned and large enough for a row once the header is known. The full
allocation, including padding, is initialized to zero before native start. Width
and height are each bounded by the existing 32768-pixel wrapper limit.

`#:limit` is a positive integer no greater than
`min(2147483647, (current-skia-byte-limit))`. The complete retained input and the
complete destination allocation are each bounded by that captured limit and the
current, possibly smaller global limit when allocating or advancing. This is
**not an aggregate RAM guarantee**: both allocations, snapshots, temporary copies,
and Skia's own internal decoder/color allocations can coexist. Native internal
allocations are not bounded by this wrapper's logical byte limits.

`codec-incremental-feed!` returns the number of bytes appended. It copies the
input; later mutation of the caller's byte string has no effect. It performs no
pixel decoding. `#:final? #t` means no more input will arrive; an empty final feed
is allowed. A quota rejection occurs before changing the retained prefix or its
final flag. A detected malformed/over-limit PNG chunk declaration poisons the
session and raises. Input to a terminal session or a second feed after sealing
is rejected.

## Advancing and cancelling

```racket
(codec-incremental-step! session #:cancel-evt [cancel-evt #f])
(codec-incremental-cancel! session)
(codec-incremental-state session)
```

`step!` synchronously advances the native decoder using the currently visible
input. It returns an immutable `incremental-progress?` value. Calling it again
without new visible input or a final-input change returns cached progress without
another native call. A feed that ends inside a PNG chunk can therefore leave the
progress unchanged.

Before enough header data exists, native codec construction may be retried from
byte zero using a fresh private stream. **After incremental start succeeds, the
same codec and pixel allocation remain in use**; no constructor restart is used
to simulate progress. The session reports diagnostic counts for this distinction.

| State | Meaning |
|---|---|
| `awaiting-input` | Created, but no step has examined the input. |
| `needs-input` | Current native input is incomplete; more bytes may be fed. |
| `complete` | Native incremental pixel decoding returned success. |
| `incomplete` | Input was marked final, but native decoding remains incomplete. |
| `failed` | Unsupported mode, corrupt/invalid input, or a wrapper/native error. |
| `cancelled` | Cancelled before completion; decoder and pixel allocation released. |
| `closed` | Resource explicitly closed or already retired. |

Completion, final incompleteness, and native failure retire the native decoder
and its source. An initialized destination can remain available for a labelled
snapshot until close. Cancellation releases that destination as well. Calling
`cancel!` on a terminal session returns its existing progress; it does not change
a completed result. `step!` on an open terminal session is idempotent. Closed
sessions reject operations except their state/lifetime predicates.

`#:cancel-evt` accepts `#f` or an event. Readiness is polled before entering the
atomic native step, so user event guards do not run inside Skia. Cancellation is
**cooperative between steps**. It does not interrupt a native call or preempt
arbitrary computation. This memory-fed API never blocks waiting for future input;
the application controls when to obtain and feed more bytes.

Result symbols use the existing codec names rather than guessed exception text.
Before any prefix is visible, `incomplete-input` means the wrapper needs more
bytes; no native call is claimed. Statistics distinguish that case. After a
native attempt, its result code is preserved. They include `success`, `incomplete-input`, `unimplemented`,
`invalid-input`, `invalid-conversion`, and the other existing codec result names.
Argument, limit, unexpected-native-value and internal wrapper errors can raise;
errors after native mutation release unsafe state and mark the session failed.

**Native pixel success is not a whole-file integrity certificate.** A decoder may
finish the requested pixels before reading a PNG IEND, CRC, or trailing bytes.
`complete` does not promise all encoded bytes were consumed or validated. An
application that needs container-level validation must perform it separately.

## Progress is not a completed-row percentage

```racket
(incremental-progress? value)
(incremental-progress-state progress)
(incremental-progress-result progress)
(incremental-progress-initialized-rows progress)
```

On native success, the row count is the destination height. On native
`incomplete-input`, it is the native initialized-row count when supplied, or `#f`
when unavailable. Before pixel initialization, on other errors, and on
cancellation, it can be `#f`.

For an interlaced PNG, **initialized rows are not necessarily finished rows**.
Later passes can update rows that were already initialized; the count can reach
the image height while the result remains incomplete. Only the native success
result establishes pixel completion. Do not interpret this number as a generic
percentage, an immutable prefix, or a guarantee that partial pixels are final.

## Metadata and diagnostic snapshots

```racket
(codec-incremental-info session)       ; detached image-info, or #f before header
(codec-incremental-origin session)     ; encoded-origin symbol, or #f
(codec-incremental-statistics session) ; immutable hash of logical counters
```

The output uses **encoded-pixel coordinates**. Orientation metadata is reported,
not silently applied; rotating individual partial snapshots would require an
explicit application-level transformation.

Statistics include `header-attempts`, `start-calls`, `decode-calls`,
`pixel-allocations`, `input-bytes`, `visible-input-bytes`, `input-final?`,
`stream-creations`, `stream-destructions`, `decoder-retained?` and `pixel-bytes`.
These are wrapper operation/lifetime counters, not pointer identities, native
memory measurements, or proof of performance. Logical input counters survive
retirement even after the retained storage is discarded.

## Independent partial and complete pixels

```racket
(codec-incremental-snapshot session)
(incremental-snapshot? value)
(incremental-snapshot-info snapshot)
(incremental-snapshot-row-bytes snapshot)
(incremental-snapshot-bytes snapshot)
(incremental-snapshot-progress snapshot)
(incremental-snapshot->raster-buffer snapshot)
```

A snapshot is available only after a successful incremental start and while the
initialized destination still exists. It copies the **entire allocation**,
including row padding, into immutable bytes, together with a detached image
information value and the current progress. It contains no borrowed native
address. Subsequent decoding, session close, or garbage collection cannot change
it. Unwritten destination bytes remain initialized, not uninitialized native
memory. Partial pixels may still be provisional, as described above.

The snapshot-to-raster conversion creates an independently owned raster buffer.
It intentionally accepts a partial snapshot; the application is responsible for
checking its attached progress before treating it as complete. Existing raster,
image and document APIs can then use that buffer. A failed or incomplete decode
never acquires successful status merely by converting its snapshot.

## Example: explicitly fed encoded chunks

```racket
(require skia)

;; chunks is a finite list of byte strings from a trusted application-level
;; input source. The final marker is a source policy, not a decoder inference.
(define (decode-chunks chunks)
  (with-skia ([session (make-codec-incremental)])
    (let loop ([remaining chunks])
      (cond
        [(null? remaining)
         (codec-incremental-feed! session #"" #:final? #t)
         (codec-incremental-step! session)]
        [else
         (codec-incremental-feed! session (car remaining)
                                  #:final? (null? (cdr remaining)))
         (define progress (codec-incremental-step! session))
         (cond
           [(eq? (incremental-progress-state progress) 'needs-input)
            (unless (null? (cdr remaining)) (loop (cdr remaining)))]
           [else (void)])]))
    (unless (eq? (codec-incremental-state session) 'complete)
      (error 'decode-chunks "decode did not complete: ~a"
             (codec-incremental-state session)))
    (codec-incremental-snapshot session)))
```

A complete snapshot can outlive `with-skia`. The application need not feed
trailing bytes after the native decoder reaches pixel completion. It should not
assume those unused bytes were validated. `examples/codec-incremental.rkt` is a
self-contained executable example using procedural PNG chunks.

## Callback provider and lifetime

The existing compiler-free live-stream module owns Skia's process-global managed
stream callback tables. Incremental sources **reuse those tables**, routing their
registered non-null context to bounded memory-only operations. Null-context live
port callbacks keep their prior behavior. No retained Racket port or arbitrary
user callback is attached to an incremental native decoder.

Input callback exceptions never unwind through native frames. They are retained
as data, return a valid native failure value, and are raised only after the
native call returns. The context registry retains input storage and its cursor,
not the session or its owned handle; it therefore does not prevent abandoned
session finalization. Stream destruction unregisters/frees the context before
input storage is discarded. The private destination is exclusively owned by the
session, and only detached copies are public.

The existing provider requires **64-bit Racket CS with OS threads** and one
managed-callback provider/place per process. Sessions enforce creator Racket-
thread affinity. Two suspended sessions can coexist, and an ordinary live-port
operation can run while a memory decoder is suspended; the real native tests
exercise both. This is not a new claim of unrestricted places or parallel use of
thread-affine native resources.

## Validation and acceptance

```bash
python tools/validate-codec-incremental.py --racket /path/to/racket
python tools/validate-codec-incremental.py --racket /path/to/racket --regressions none
```

Full regressions remain the standalone default. Focused mode always compiles and
runs **36 pure cases and 38 native cases**, the example and the native doctor.
The inspector checks a six-step normal PNG, seven-pass Adam7 PNG, snapshots before
completion, native start/allocation/advance counters, exact completed pixels,
initialized padding, final truncation, unsupported BMP incremental mode,
cancellation, stream destruction and live-provider coexistence.

Pillow independently decodes the complete fixture images and checks the PNG
framing/CRC and raw pixel/state evidence. The existing Python requirements suffice;
no GPU or independent document renderer is required for this stage. Encoded and
raw captures, reports and command logs are retained in a fresh
`output/codec-incremental-0.76c-*` directory. Synthetic Python fixtures and mocked
validator tests are explicitly separate from native execution evidence.

The existing codec workflow adds a focused incremental step after query and
scanline acceptance. The query gate owns any job-wide full regressions; the
incremental step uses `--regressions none`. Central installed-package CI includes
the new native/pure suites, including macOS. No new automatic workflow or native
compiler dependency is added.

## Pinned upstream references

- `include/c/sk_codec.h`: incremental start and advance C entry points.
- `include/codec/SkCodec.h`: retained destination, incomplete result and initialized-row semantics.
- `src/codec/SkPngCodec.cpp`: chunk-level resumption and normal/interlaced row handling.
- `src/xamarin/sk_managedstream.cpp`: process-global managed stream callback table.

All references use `mono/skia` commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7`, the existing m119 comparison pin.
