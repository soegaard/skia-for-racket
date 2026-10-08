# Streams and buffered ports — 0.75a

Stage **0.75a** uses package version **`0.75`**. Native Skia remains
SkiaSharp 3.119.1 / m119. These APIs are exported by `streams.rkt` and
`stream-inputs.rkt`, and re-exported by `main.rkt` (`skia`). Requiring the modules
neither loads Skia nor opens files or ports.

## The split

**0.75a** supplies owned native memory/file input streams, native dynamic-memory
output, position/length/seek/duplicate/fork operations, copied native data,
codec/typeface/trusted-picture stream input, and explicitly buffered Racket-port
conveniences. No Racket callback is installed in a Skia stream.

**0.75b** is the remaining live-I/O stage: native file output and stream consumers
for image encoding, picture output and PDF/SVG publication; the managed bridge to
live Racket ports; retained callback lifetime, reentry/thread rules, cancellation
and deferred error transport; and partial versus atomic publication. Whole-input
buffering in 0.75a does not count as completion of that bridge.

## Native resources

```racket
(require skia)

(make-memory-input-stream bytes #:limit [limit (current-skia-byte-limit)])
(make-file-input-stream filename #:limit [limit (current-skia-byte-limit)])
(make-memory-output-stream #:limit [limit (current-skia-byte-limit)])
(skia-input-stream? value)
(skia-output-stream? value)
```

Every stream participates in `skia-resource?`, `skia-closed?`, `skia-close!`,
`call-with-skia-resource` and `with-skia`. Handles are opaque, Racket-thread-affine,
and CPU resources even when created in an active GPU context. There is no raw
pointer ingress, no no-copy mutable memory constructor, and no change to GPU
transfer or rendering policy. Explicit close is deterministic; the ordinary
native-resource finalizer is only a fallback.

A memory input takes a native copy. Later mutation or collection of the caller's
byte string cannot change that input. Empty streams are supported. Each stream
captures a positive byte limit no larger than
`min(2147483647, (current-skia-byte-limit))`; subsequent operations also obey the
current, possibly smaller global limit. This is a bound on logical stream size,
not a bound on total process memory, native decoder allocations, or aggregate
storage retained by several streams. Native and Racket copies can coexist.

A file input opens an existing regular file directly using the pinned native
file-stream API. It does **not** snapshot its contents. The file and its path
must not be modified, truncated, removed or replaced while this stream or its
native consumers are live. Validation checks size and regular-file status before
opening, then checks native length/position; this is not an atomic defense against
concurrent filesystem replacement. Native filesystem calls are synchronous and
are not interrupted by the buffered port cancellation event. The native API's
platform filename encoding applies; Racket supplies the absolute path bytes.

## Reading and navigation

```racket
(input-stream-length stream)
(input-stream-position stream)
(input-stream-at-end? stream)
(input-stream-read-bytes stream count)
(input-stream-peek-bytes stream count)
(input-stream-skip! stream count)
(input-stream-seek! stream position)
(input-stream-rewind! stream)
(input-stream-move! stream signed-offset)
(input-stream-duplicate stream)
(input-stream-fork stream)
(input-stream->bytes stream)
```

Counts and positions are exact nonnegative integers. Reads return independent
bytes, which may be shorter at the end; a positive-size request at EOF returns
`eof`. A zero-size read returns `#""`, including at EOF. `peek` leaves the cursor
unchanged; a native stream that cannot peek raises rather than simulating support
with a destructive read. A short native read can signify EOF or an I/O error;
this ABI has no separate error query, so the wrapper does not claim to distinguish
them. `skip!` returns the actual number skipped.

Length and position are in bytes. `seek!`, `rewind!` and `move!` return `void`;
out-of-range seeks are rejected before native mutation rather than accepting
Skia's endpoint clamping. Relative offsets must fit the platform C `long` (which
is 32 bits on Windows x64). A failed native seek does not promise rollback.

`duplicate` and `fork` both return separately owned streams. A duplicate starts
at byte zero; a fork starts at the source's current position. Neither advances
the source, and either can outlive its explicit closure. File copies retain the
same backing-file stability requirements. Native input types without the required
length/position/duplication capabilities are not accepted by these constructors.

`input-stream->bytes` consumes the remaining bytes from the current cursor. Its
nonempty path uses `sk_data_new_from_stream`, copies the resulting SkData, and
releases it. It requires an exact native read; truncation can advance the cursor
before failure and is not rolled back. For an independent whole-stream snapshot,
read a temporary duplicate instead.

## Memory output

```racket
(output-stream-write-bytes! stream bytes [start 0] [end #f])
(output-stream-bytes-written stream)
(output-stream->bytes stream)
(output-stream-detach-input! stream)
```

The only output stream in 0.75a is a native dynamic-memory stream. Byte slices use
an exclusive end; `#f` means the end of the byte string. A write checks the full
resulting size **before** native allocation and returns the number written. A
quota rejection leaves the writer intact. An unexpected native write failure can
be partial, so it closes the stream instead of leaving an apparently healthy
writer.

`output-stream->bytes` returns a copied, nondestructive snapshot, including empty
output. `output-stream-detach-input!` transfers the current native blocks into a
new owned input positioned at zero and resets the writer to empty. The detached
input remains valid after the writer is closed or reused. No native pointer to a
block is exposed.

```racket
(with-skia ([out (make-memory-output-stream #:limit 4096)])
  (output-stream-write-bytes! out #"hello ")
  (output-stream-write-bytes! out #"streams")
  (with-skia ([in (output-stream-detach-input! out)])
    (input-stream-skip! in 6)
    (displayln (input-stream->bytes in)))) ; prints streams
```

## Native consumers and ownership

```racket
(codec-from-stream input)
(typeface-from-stream input #:index [index 0])
(picture-from-stream input #:trusted? [trusted? #f]
                           #:width [width #f] #:height [height #f])
```

These constructors read a private **duplicate from byte zero**, not from the
caller's current cursor. The caller's input is never consumed or closed, and its
cursor remains unchanged. To treat a port's current position as the start of an
image/font/picture, use a buffered adapter below.

The codec and typeface C constructors consume their private duplicate, including
on failure. The returned native resource retains whatever input storage it needs.
On macOS, the pinned m119 CoreText native stream loader rejects TTC collection
member selection. For TTC input only, `typeface-from-stream` therefore reads a
bounded independent duplicate and delegates to the existing `typeface-from-bytes`
TTC-to-standalone-SFNT conversion. That case is **buffered**, not a native stream
through the final font constructor; ordinary SFNT fonts use the native stream
path on every platform. The caller's input position and ownership are unchanged.
Closing the original input wrapper is safe; for native files this does not remove
the caller's obligation to keep the backing file stable. The codec works with the
existing metadata, animation and one-shot decode APIs. Scanline and incremental
sessions are still stage 0.76, not simulated here.

Picture loading borrows its duplicate synchronously. It keeps the existing
`#:trusted? #t` requirement and cheap SKP header checks; these do not sandbox SKP
or embedded SkSL. Width and height overrides must be supplied together. Imported
pictures retain **unknown/deserialized provenance** in document audits. Loading
via a stream cannot turn opaque SKP into certified vector content.

## Explicitly buffered Racket adapters

```racket
(buffered-port->input-stream in #:limit [limit (current-skia-byte-limit)]
                               #:close? [close? #f] #:cancel-evt [cancel #f])
(codec-from-port/buffered in #:limit [limit (current-skia-byte-limit)]
                            #:close? [close? #f] #:cancel-evt [cancel #f])
(typeface-from-port/buffered in #:index [index 0]
                               #:limit [limit (current-skia-byte-limit)]
                               #:close? [close? #f] #:cancel-evt [cancel #f])
(image-from-port/buffered in #:limit [limit (current-skia-byte-limit)]
                            #:close? [close? #f] #:cancel-evt [cancel #f])
(picture-from-port/buffered in #:trusted? [trusted? #f]
                              #:width [width #f] #:height [height #f]
                              #:limit [limit (current-skia-byte-limit)]
                              #:close? [close? #f] #:cancel-evt [cancel #f])
(output-stream-write-port/buffered stream out
                                  #:close? [close? #f] #:cancel-evt [cancel #f])
```

Input adapters read from the port's current position to EOF **before entering any
Skia operation**. Seekable and nonseekable ports are accepted, short reads are
accumulated, and binary special values are rejected. A one-byte over-limit probe
distinguishes exact-limit EOF from excess input: a quota failure consumes at most
`limit + 1` bytes. It does not restore the port position.

The output adapter first copies the complete native memory stream, releases its
native borrow, then writes that snapshot to the Racket output port in bounded
chunks, handling partial writes. It returns the number written. It neither drains
nor resets the native stream. This is **buffered publication**, not native-to-port
live streaming, and a port failure can still leave a partial prefix. No atomic
publication guarantee is added. Existing buffered file/document exporters retain
their existing behavior. Borrowed output ports are not explicitly flushed by this
adapter; the caller controls any further flushing and closing.

Ports are borrowed by default. `#:close? #t` closes an accepted port on success,
I/O failure, quota failure, cancellation or a nonlocal exit. Validation errors
before accepting the port (such as a bad limit/event/index or missing picture
trust) do not take ownership. A close error after successful I/O propagates; when
an earlier operation raised, cleanup preserves that original raised value.
Native stream snapshot validation precedes output-port acceptance.

`#:cancel-evt` is `#f` or an event. Readiness cancels between chunks and while
waiting for a port to become ready; ordinary breaks can also escape. Neither
mechanism rolls back consumed/written bytes or preempts a custom port callback
that fails to return. A caller must not use or close a borrowed port concurrently
during a transfer. After buffering finishes, native consumers retain no Racket
port, and subsequent native decode/font operations are not cancellable by this
event. Live callbacks, reentry and cross-thread transport are deferred to 0.75b.

## Validation and CI

```bash
python tools/validate-streams.py --racket /path/to/racket
python tools/validate-streams.py --racket /path/to/racket --regressions none
```

Full is the standalone default. Feature-only mode does not run or compile the
global regression graph, but **always** compiles and runs the 35 stream pure and
39 stream native cases, the example, and the native stream doctor. It also checks
source checksums, the inventory, the numeric package version, and the independent
byte/pixel inspector. `streams.json`, three binary captures, inspection output,
commands and complete logs are retained under a new `output/streams-0.75a-*`
directory. Generated font fixtures are used internally, not distributed as font
files.

The doctor checks memory writes/detach, duplicate/fork position semantics, direct
native file input, codec pixels after input-wrapper closure, and fixture-font
metadata after input-wrapper closure. Python inspector fixtures and mocked runner
tests are not native execution evidence.

`streams.yml` is reusable/manual, not a new push-triggered workflow. Acceptance
passes its selected regression scope and requires all Linux 8.18/9.3 and Windows
9.3 stream jobs through `Acceptance required`. The registered full regression
runner also covers stream tests in the central portability lanes, including
macOS. A feature-only green Acceptance run still needs a separate green central
CI run. 0.75a has no GPU/display claim and no new document renderer matrix.

## Compiler-free 0.75b additions

See [LIVE-STREAMS.md](LIVE-STREAMS.md) for operation-scoped live Racket ports,
native file output and audited image/SKP/PDF/SVG publication. The bridge uses
Racket CS OS-thread/asynchronous-callback facilities, not a locally compiled
helper. The 0.75a APIs, Windows path fix and macOS TTC handling remain unchanged.
Memory snapshots/detach reject file output streams. Mutable output streams are
exclusively leased during encoding and poisoned on publication failure; explicit
close remains available afterward. No retained live-port codec/font object escapes.
