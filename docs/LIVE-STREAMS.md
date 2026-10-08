# Compiler-free live ports and native publication — 0.75b

These APIs use the existing precompiled SkiaSharp 3.119.1 / m119 library.
**No C/C++ compiler, CMake, or additional native library is required.** The
numeric package version remains `0.75`. The older compiler-dependent 0.75b
bundle is superseded; do not install it alongside this implementation.

The scheduling core is promoted from the standalone pure-FFI probe whose 25
native cases the user reported passing on macOS with Racket 9.3.0.2 / Chez.
That earlier result is not execution evidence for these new integration paths.
The installer and validator below keep compilation, native tests, the retained
probe, and independent document inspection separate.

## Requirements and lifetime

`live-streams-check!` initializes and checks the private FFI import registry and
callback tables. `live-streams-available?` returns whether that check succeeds.
Both may load the pinned library; merely requiring `skia` does not initialize
the live callback tables or start a worker. Live operations require 64-bit
Racket CS with `os-thread-enabled?` true. Other 0.75a APIs keep their existing
requirements. There is no silent buffered fallback on an unsupported runtime.

Native work runs through `call-in-os-thread`. The `#:async-apply` dispatcher
only enqueues the FFI-provided callback thunk. A protected ordinary Racket
service thread executes it outside atomic mode and returns its actual result
to the waiting OS worker. Port callbacks inherit the caller's parameter values,
but **not its thread identity**. They cannot use caller-thread-affine Skia
resources. Reentering a live operation is rejected. Concurrent live operations
are rejected instead of queued indefinitely.

The service thread, not the initiating thread, owns final cleanup. It finishes
native operations and destruction callbacks before releasing private references,
mutable-output leases, or owned ports. Caller breaks, ordinary escapes, caller
termination, and caller-custodian shutdown must not abandon a callback thunk.
A custom port that terminates the service thread, exits the process, or never
returns is outside the supported contract. Terminating the whole place/process
is not recoverable cancellation.

Skia's managed input/output callback tables are process-global. This module
claims a stable process-global registration once and rejects a second module
instance/place attempting to replace it. A noncooperating native provider that
overwrites those tables cannot be detected reliably. Do not run this bridge,
the former C++ bridge, or the standalone probe's own callback installer in the
same process. The retained test probe runs in a separate process for this reason.

## Live input

```racket
(require skia)
(image-from-port in
  #:length [length #f] #:seekable? [seekable? #f]
  #:normalize-origin? [normalize? #t]
  #:limit [limit (current-skia-byte-limit)]
  #:close? [close? #f] #:cancel-evt [cancel #f])
(picture-from-port in #:trusted? [trusted? #f]
  #:width [width #f] #:height [height #f]
  #:length [length #f] #:seekable? [seekable? #f]
  #:limit [limit (current-skia-byte-limit)]
  #:close? [close? #f] #:cancel-evt [cancel #f])
(copy-port/streaming in out
  #:limit [limit (current-skia-byte-limit)]
  #:close-input? [close-input? #f] #:close-output? [close-output? #f]
  #:cancel-evt [cancel #f])
```

Live input starts at the port's current position. Input is requested as needed
by native Skia; it is not read into a complete encoded byte string first.
Nonseekable/chunked binary ports are supported where the native consumer supports
them. Short reads accumulate according to Skia's synchronous read contract.
Custom ports must not return special non-byte values.

`#:length`, when supplied, describes the logical view from the initial position;
a shorter input is an error rather than a successful decode. Seeking is never
silently inferred. `#:seekable? #t` requires an explicit length and a port with
working exact byte-position/seek behavior; native offsets are relative to the
initial position. Unsupported rewind/duplicate/fork requests are not simulated
by reading the whole input into memory. Formats needing unsupported stream
capabilities may therefore be rejected explicitly.

`image-from-port` performs one complete decode and returns an ordinary,
independently owned premultiplied RGBA image, retaining the native codec's color
space. The existing orientation normalization helper implements the default
`#:normalize-origin? #t`. It does not return an incremental session or retain
the Racket port. Encoded bytes and decoded pixel storage are each constrained
by the selected logical byte limit; copies can coexist, so this is not a bound
on peak process memory or on all native allocations.

`picture-from-port` requires `#:trusted? #t` before any input I/O. It checks the
bounded native SKP header before deserialization and returns an owned picture.
The header check does not sandbox SKP/SkSL. Width and height overrides must be
supplied together. Imported pictures remain `deserialized-picture`/unknown in
output audits; streaming does not recover lost authoring provenance.

`copy-port/streaming` returns the number of bytes published. Its output may begin
before input reaches EOF. Individual input/output copies are bounded to 64 KiB.
An unknown-length input may consume one extra byte to detect a quota violation.

Retained live-port-backed codec/typeface objects are deliberately not exposed.
Use 0.75a native streams or explicitly buffered adapters for retained consumers.

## Live encoded output

```racket
(image->port image out format
  #:quality [quality 90] #:png-compression [compression 6]
  #:jpeg-downsample [downsample 'yuv-420] #:jpeg-alpha [alpha 'ignore]
  #:webp-lossless? [lossless? #f]
  #:limit [limit (current-skia-byte-limit)]
  #:close? [close? #f] #:cancel-evt [cancel #f])
(picture->port picture out
  #:limit [limit (current-skia-byte-limit)]
  #:close? [close? #f] #:cancel-evt [cancel #f])
```

`format` is `png`, `jpeg`, or `webp`. Both operations return the number of bytes
written. Output comes from native encoder/serializer calls, not a complete
Racket encoded-byte buffer. Image encoding obtains an independent native raster
reference, preserving its native color/alpha storage and color-space tag rather
than routing all formats through an RGBA8 staging buffer. Materializing a lazy
CPU image can allocate pixels. Custom ICC override/description options remain
with the existing byte exporters; they are not silently accepted or discarded.

Image and picture inputs use the existing CPU-only lifetime gate. GPU-backed
or GPU-dependent content must be explicitly detached first. No hidden GPU
readback is added. The worker uses independent immutable native references,
never an unprotected borrowed pointer to a public wrapper. Its service releases
those references after native completion, with private finalizers as a fallback
for abandonment before launch or an unclaimed result.

## Audited document publication

```racket
(output->port pages out format
  #:policy [policy 'error] #:text-mode [mode 'auto]
  #:raster-dpi [dpi 144]
  #:limit [limit (current-skia-byte-limit)]
  #:close? [close? #f] #:cancel-evt [cancel #f])
```

`pages` is an `output-page?` or nonempty list. PDF accepts at most 1024 pages;
SVG requires exactly one. The return value is the physical number of published
bytes, including the bounded SVG root transformation. SVG uses point dimensions
and a matching viewBox, like the common physical-page API.

Application drawing callbacks execute once on the calling Racket thread into
owned pictures. The exact retained commands are then preflighted against the
actual PDF/SVG audit policy before any destination bytes are published. The
preflight replays library-owned `draw-picture` callbacks, not application
authoring. Native publication subsequently replays those immutable pictures on
the OS worker. A preflight error leaves the destination untouched.

This is streamed *encoded publication*, not constant-memory document authoring.
Pictures and dependencies are retained until publication finishes. Approximate
picture byte totals are charged against the logical limit but do not include
all referenced/native memory. The preflight can allocate a temporary empty
native document; it does not first generate the final encoded document.

The input callback receives a recording canvas, not a PDF/SVG canvas. URL
annotations survive native picture replay. Named destinations/links reject at
the existing recording boundary instead of disappearing silently. `auto` text
uses outlines for SVG and native PDF text. Unsupported effects, explicit raster
groups, imported-SKP provenance, and GPU exclusions follow the existing audit.
Rich metadata, custom SVG ID rewriting, named document destinations, and PDF/A
settings remain with the established exporters. No unsupported option is silently
ignored. A successful audit is not itself a visual or PDF/A certificate.

Only the native-produced SVG root header is buffered for physical-unit rewriting,
with a 16 KiB header limit. The rest streams normally. A temporary transformed
chunk can include that header plus a 64 KiB native chunk; port writes are still
bounded. The actual transformed byte count is checked before publication.

## Native output streams

```racket
(make-file-output-stream filename
  #:exists [exists 'error] #:limit [limit (current-skia-byte-limit)])
(output-stream-flush! stream)
(image-write-stream! image stream format
  #:quality [quality 90] #:png-compression [compression 6]
  #:jpeg-downsample [downsample 'yuv-420] #:jpeg-alpha [alpha 'ignore]
  #:webp-lossless? [lossless? #f])
(picture-write-stream! picture stream)
(output-write-stream! pages stream
  #:policy [policy 'error] #:text-mode [mode 'auto] #:raster-dpi [dpi 144])
```

File outputs participate in the existing stream resource/close interface.
`output-stream-write-bytes!` works for file and memory outputs. Memory snapshot
and detach operations reject files before any native memory-stream cast.
`output-stream-flush!` invokes native flush; this ABI has no durability/fsync or
separate flush-error acknowledgement guarantee.

The publication consumers accept native memory/file writers. `output-write-stream!`
is explicitly PDF-only; use `output->port` for SVG's physical root rewriting.
A private port sink forwards bounded native output into the native writer.
The writer's remaining logical budget is enforced before each chunk, without
building the whole encoded payload in memory.

Mutable native outputs are exclusively leased. Public use and close reject while
publication is active, and the lease keeps the underlying owner alive. Failed
or cancelled publication poisons the output: later operations reject until it is
explicitly closed. It is not silently reset or reused after a partial write.

The native file constructor truncates the destination. `exists='error'` performs
a prior existence check, not an atomic O_EXCL guarantee. The caller must control
the path against replacement/races. Use existing buffered/temporary-file exporters
when atomic publication matters. Native filename encoding follows the pinned
platform API; no new universal path-encoding promise is made.

## Errors, cancellation, and port ownership

Ports are borrowed by default and are not explicitly flushed. A selected owned
port is closed by the protected service on success, port/native failure,
cancellation, or caller termination, after native work finishes. Argument/source
validation or document authoring/preflight failure occurs before port ownership
is accepted. A close error after success propagates; an earlier error takes
precedence. Arbitrary raised values, including `#f`, are preserved.

Cancellation is cooperative through `#:cancel-evt`, breaks, and caller-death
observation. It interrupts port-readiness waits and is checked between chunks.
It cannot preempt arbitrary native computation or a custom callback that never
returns. No Racket exception is unwound through C++ frames; callbacks record the
first error and return a native failure result, while cleanup continues.

After publication starts, an exception or cancellation can leave a partial
prefix in either a port or a native file/memory writer. No rollback/atomicity is
claimed. The existing explicitly buffered/atomic publication APIs are unchanged.

## Validation and CI

```bash
python tools/validate-live-streams.py --racket /path/to/racket --require-renderers
python tools/validate-live-streams.py --racket /path/to/racket --regressions none --require-renderers
```

The focused integrated suites contain **26 pure and 42 native cases**. The
validator also executes the retained **25 real native probe cases** in a separate
process, then checks native bytes, codec/encoder output, links, vector structure,
physical PDF/SVG dimensions, and independent renderings. Full global regressions
remain the standalone default. `none` never skips focused tests or the probe and
never reports omitted regressions as passed. Logs and reports are retained in a
fresh `output/live-streams-0.75b-*` directory.

The existing streams.yml workflow runs 0.75a and then feature-only 0.75b acceptance.
Linux requires Poppler/librsvg; unavailable Windows renderers are explicitly
reported, not counted as rendered passes. Central CI's installed-package native
suite includes the integration tests on Linux/macOS/Windows. There are still
three top-level workflows. This stage adds no native compiler command or helper
build; pre-existing CI ABI-mirror checks are unchanged.

`api/live-stream-ffi.json` records all 50 raw callouts: 44 from the pinned include/c
inventory and 6 explicitly attributed Xamarin managed-stream exports. The main
inventory includes the standard imports and leaves the extensions separate;
`tools/live_stream_ffi.py` rejects signature or symbol-set drift. Declaration
coverage is not native execution evidence.
