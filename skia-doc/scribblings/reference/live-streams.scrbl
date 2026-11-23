#lang scribble/manual

@(require (for-label racket/base racket/contract racket/port skia skia/live-streams))

@title[#:tag "skia-live-streams"]{Live Port Input and Output}

@defmodule[skia/live-streams #:no-declare]
@(declare-exporting skia skia/live-streams #:use-sources (skia/live-streams))

A @deftech{live port operation} exchanges chunks with a Racket port while native
work is in progress. The image, picture, and byte-copy operations do not first
buffer the complete encoded transfer as the @secref["skia-buffered-ports"]
adapters do. Document output is different: it records complete pictures and
performs an @tech{output preflight} export before writing to the port. The call is
synchronous: it returns after native work and cleanup have finished. No persistent port-backed
image or codec is returned.

The caller must give the operation exclusive use of its ports until it returns.
Only one live port operation can be active at a time, even when different Racket
threads use different ports. A concurrent attempt raises an exception rather
than waiting; port callbacks must not start another live operation either.
The implementation services port I/O outside native ownership scopes and does
not promise callbacks on the initiating Racket thread.

The native callback bridge is installed once for the whole process. A second
Racket place or independent module instance cannot install another provider;
its initialization attempt raises an exception. Separate places therefore do
not provide independent live-port bridges within one process.

The positive exact @racket[#:limit] must not exceed @racket[2147483647] or
@racket[current-skia-byte-limit]. It bounds logical transfer/storage quantities,
not the total native heap. Decoding still allocates pixels, and document
recording can require substantial additional storage. Streaming output is not a
constant-memory authoring guarantee.

A cancellation event is checked during I/O. Cancellation and failures can leave
partly consumed input or partly written output. They do not roll back bytes or
restore port positions. Ports remain open by default. Once the live transfer is launched,
a true close option makes cleanup close the selected ports after native teardown,
including on failure. If validation or document drawing fails before launch, the
operation does not close the ports. Native output streams are distinct from
Racket ports and follow the rules in @secref["skia-native-publication"].

@defproc[(live-streams-check!)
          void?]{
Initializes and checks the live-stream support library and its native bridge.
If either cannot be loaded or initialized, the function raises an exception.
This includes an attempt to claim callbacks already installed by another place
or module instance, as described above.
Calling it from a callback servicing an ongoing live-port operation also raises
an exception.
Successful initialization does not establish support for every image format or
requested decoding operation.
}

@defproc[(live-streams-available?)
          boolean?]{
Calls @racket[live-streams-check!] and returns @racket[#t] on success. Returns
@racket[#f] when that check raises an ordinary failure exception. This availability
probe can initialize native libraries; it is not a pure type predicate.
}

@local-table-of-contents[#:style 'immediate-only]

@section{Reading and Copying Ports}

Input begins at the port's current position. A supplied @racket[#:length] is a
nonnegative exact length within the byte limit for this input, not the total
size of an enclosing file. Seekable input requires an explicit length and a
port that supports exact positions and seeking; positions used by the operation
are relative to the starting position. A false seekable option does not promise
that every native format can be decoded sequentially. These constructors return
a decoded first image or picture, not a resumable port-backed decoder.

@defproc[(image-from-port [input input-port?]
          [#:length length (or/c exact-nonnegative-integer? #f) #f]
          [#:seekable? seekable? boolean? #f]
          [#:normalize-origin? normalize? boolean? #t]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)]
          [#:close? close? boolean? #f] [#:cancel-evt cancel (or/c evt? #f) #f])
          image?]{
Decodes the first image from live input and returns an independently owned CPU
image. The pixels are RGBA8888 with @tech{premultiplied alpha}, using the color
space reported by the native codec. There is no destination color-space option.

The default applies the @tech{encoded orientation}; disabling it preserves
encoded pixel coordinates. Unlike @racket[image-from-port/buffered], this call
finishes pixel decoding before returning. Unsupported decoding and incomplete
required input raise exceptions. The port need not remain open after successful return.
Use @racket[codec-from-port/buffered] for explicit animation-frame access.
}

@defproc[(picture-from-port [input input-port?]
          [#:trusted? trusted? boolean? #f]
          [#:width width (or/c real? #f) #f] [#:height height (or/c real? #f) #f]
          [#:length length (or/c exact-nonnegative-integer? #f) #f]
          [#:seekable? seekable? boolean? #f]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)]
          [#:close? close? boolean? #f] [#:cancel-evt cancel (or/c evt? #f) #f])
          picture?]{
Loads a picture from trusted live SKP input. The explicit trust decision and
paired nominal-size overrides have the meaning specified for
@racket[picture-from-bytes]. Successful loading does not keep the port attached
to the picture. Header validation is not safe deserialization of untrusted data.
}

@defproc[(copy-port/streaming [input input-port?] [output output-port?]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)]
          [#:close-input? close-input? boolean? #f]
          [#:close-output? close-output? boolean? #f]
          [#:cancel-evt cancel (or/c evt? #f) #f])
          exact-nonnegative-integer?]{
Copies input through EOF to a distinct output port and returns the number of
bytes written. Use it when the transfer needs the live interface's byte limit,
cancellation event, or close-on-exit options. For an ordinary port-to-port copy,
@racket[copy-port] from @racketmodname[racket/port] is simpler and does not
require Skia's native callback bridge.

The two close options concern their respective ports. Cancellation,
quota errors, or I/O errors can leave a written prefix. This operation uses the
live native bridge even though it performs no image decoding.

@racketblock[
(define input (open-input-bytes #"chunked output"))
(define output (open-output-bytes))
(define count
  (copy-port/streaming input output #:close-input? #t))
(define result (get-output-bytes output))
(close-output-port output)
(list count result)
]

The result contains the byte count and @racket[#"chunked output"].
}

@section{Writing Images and Pictures}

The live image writers use the options and defaults of @racket[image->encoded-bytes].
Non-@racket[#f] options for other formats raise an exception. JPEG quality must
be an exact integer; WebP quality can be fractional. Color-space conversion
and ICC-profile metadata follow @secref["skia-encoding-options"].
See @secref["skia-encoding-destinations"] for a comparison with byte-string and
file output, including what remains at the destination after a failure.

@defproc[(image->port [image image?] [output output-port?]
          [format (or/c 'png 'jpeg 'webp)]
          [#:quality quality (or/c #f (real-in 0 100)) #f]
          [#:png-compression compression (or/c #f (integer-in 0 9)) #f]
          [#:jpeg-downsample downsample (or/c #f 'yuv-420 'yuv-422 'yuv-444) #f]
          [#:jpeg-alpha alpha (or/c #f 'ignore 'blend-on-black) #f]
          [#:webp-lossless? lossless? boolean? #f]
          [#:color-space space (or/c color-space? #f) #f]
          [#:icc-profile profile (or/c bytes? #f) #f]
          [#:icc-description description (or/c string? #f) #f]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)]
          [#:close? close? boolean? #f] [#:cancel-evt cancel (or/c evt? #f) #f])
          exact-nonnegative-integer?]{
Encodes a CPU-compatible image directly to a Racket port and returns the bytes
written. GPU-dependent images are rejected instead of read back automatically.
The writer obtains its own raster reference; the caller's image remains owned
by the caller. The live close and cancellation rules apply to the output port.
A native or port failure can leave an incomplete encoded file.
}

@defproc[(picture->port [picture picture?] [output output-port?]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)]
          [#:close? close? boolean? #f] [#:cancel-evt cancel (or/c evt? #f) #f])
          exact-nonnegative-integer?]{
Serializes a CPU-compatible picture as SKP to a Racket port and returns the
bytes written. It does not produce SVG or PDF. The caller retains ownership of
the picture. A failed write can leave a partial SKP stream; no rollback is
performed. The SKP compatibility and trust cautions in @racket[picture->bytes]
also apply.
}

@section{Writing Documents}

Use these writers when the destination is already a port or native stream.
They share the format and metadata options of byte-string and file export.
For page limits, annotation support, and failure behavior, see @secref["skia-reference-documents-output"].

@defproc[(output->port [source (or/c output-page? (cons/c output-page? (listof output-page?)))]
          [output output-port?] [format (or/c 'pdf 'svg)]
          [#:title title string? ""] [#:description description string? ""]
          [#:id-prefix prefix (or/c string? #f) #f]
          [#:encoding-quality quality (or/c (integer-in 0 101) #f) #f]
          [#:pdfa? pdfa? boolean? #f]
          [#:policy policy (or/c 'report 'error 'vector-only) 'error]
          [#:text-mode mode (or/c 'auto 'native 'outline) 'auto]
          [#:raster-dpi dpi (real-in 1 9600) 144]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)]
          [#:close? close? boolean? #f] [#:cancel-evt cancel (or/c evt? #f) #f])
          exact-nonnegative-integer?]{
Exports output pages to a Racket port and returns the byte count. PDF accepts
one through 1024 pages; SVG requires exactly one. Each application drawing
callback runs once to record its page. The recorded commands are preflighted
against the selected @tech{output policy} and then replayed to write the document.
An authoring or preflight failure writes no bytes to the destination. Later
failures while writing can leave partial output.

The text-mode and DPI rules are those of @racket[output->bytes]. The automatic
mode uses native text for PDF and outlines for SVG. SVG output includes physical
point dimensions. Title, description, SVG ID prefix, PDF encoding quality, and
PDF/A options have the same defaults and restrictions as @racket[output->bytes]. @tech{Named destinations} cannot be authored on
the intermediate picture-recording canvas; use direct document output when such
annotations are required.

The default @racket['error] policy rejects features classified as needing
@tech{raster fallback}, unsupported, unknown, or discarded. The @racket['vector-only] policy
rejects every feature not classified as vector, including embedded raster images.
The @racket['report] policy does not reject those classifications, but this
function returns only a byte count, not the internally collected audit report.
These policies do not make arbitrary effects portable or add automatic raster
fallback. Native and port failures can still raise under any policy.
}

@section[#:tag "skia-native-publication"]{Writing to Native Output Streams}

The following writers append at the destination stream's current end and return
the bytes written by this call, not the accumulated total. At the start of the call,
the remaining capacity is the smaller of the stream's stored limit and
@racket[current-skia-byte-limit], minus bytes already written. The call raises an
exception if no capacity remains.

The writer has exclusive use of the stream until it finishes. Attempts to access
the stream's native data or close it during that time raise an exception. A failure
after the writer takes exclusive use can leave partial output and prevent further
use; close that stream instead of retrying on it.
Successful writing leaves the stream open. No close or cancellation keyword
is provided by these three native-stream operations.

@defproc[(image-write-stream! [image image?] [stream skia-output-stream?]
          [format (or/c 'png 'jpeg 'webp)]
          [#:quality quality (or/c #f (real-in 0 100)) #f]
          [#:png-compression compression (or/c #f (integer-in 0 9)) #f]
          [#:jpeg-downsample downsample (or/c #f 'yuv-420 'yuv-422 'yuv-444) #f]
          [#:jpeg-alpha alpha (or/c #f 'ignore 'blend-on-black) #f]
          [#:webp-lossless? lossless? boolean? #f]
          [#:color-space space (or/c color-space? #f) #f]
          [#:icc-profile profile (or/c bytes? #f) #f]
          [#:icc-description description (or/c string? #f) #f])
          exact-nonnegative-integer?]{
Encodes a CPU-compatible image to a memory or file output stream. All encoding
options follow @racket[image->encoded-bytes], including format restrictions.
The caller retains ownership of both resources.
}

@defproc[(picture-write-stream! [picture picture?] [stream skia-output-stream?])
          exact-nonnegative-integer?]{
Serializes a CPU-compatible picture to a memory or file output stream.
The operation uses the same SKP representation and compatibility limitations as
@racket[picture->bytes]. It does not clear preexisting destination bytes.
}

@defproc[(output-write-stream!
          [source (or/c output-page? (cons/c output-page? (listof output-page?)))]
          [stream skia-output-stream?] [format (or/c 'pdf 'svg)]
          [#:title title string? ""] [#:description description string? ""]
          [#:id-prefix prefix (or/c string? #f) #f]
          [#:encoding-quality quality (or/c (integer-in 0 101) #f) #f]
          [#:pdfa? pdfa? boolean? #f]
          [#:policy policy (or/c 'report 'error 'vector-only) 'error]
          [#:text-mode mode (or/c 'auto 'native 'outline) 'auto]
          [#:raster-dpi dpi (real-in 1 9600) 144])
          exact-nonnegative-integer?]{
Writes one through 1024 PDF pages or one SVG page to a native output stream.
The required format argument selects the document format. Options, physical-size
handling, record-once preflight, and restrictions on named destinations follow
@racket[output->port], using the stream's budget. Automatic text mode is native
for PDF and outline for SVG. The caller owns the stream, which remains open
after successful writing.
}
