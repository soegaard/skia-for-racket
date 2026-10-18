#lang scribble/manual

@(require (for-label racket/base racket/contract skia
                     skia/streams skia/file-streams skia/stream-inputs))

@title[#:tag "skia-streams"]{Native Streams and Buffered Ports}

@defmodule[skia/streams #:no-declare]
@(declare-exporting skia skia/streams #:use-sources (skia/streams))

Use a native stream when you need file-backed input for a constructor such as
@racket[codec-from-stream], or need to read, seek, and copy native stream bytes
explicitly. For ordinary image loading from a filename or byte string, the
direct image constructors are simpler. To connect a Racket port, use the
@seclink["skia-buffered-ports"]{buffered adapters} here or the
@seclink["skia-live-streams"]{live-port interfaces}.

A @deftech{native stream} reads or writes bytes through Skia. Input streams have
independent cursors; output streams accumulate bytes in memory or write to a file.
They are @tech{owned resource}s, not Racket ports. Closing a stream releases its
native storage or file handle. Operations require an open stream on its owning
thread, except for the type predicates.

Stream constructors accept a positive exact @racket[#:limit] no greater than
@racket[2147483647] or @racket[current-skia-byte-limit]. Later operations use the
smaller of the captured limit and the current byte limit. Input operations check
the whole stream length, not only the unread suffix. Output operations check the
accumulated size. These limits do not bound every native allocation.

@local-table-of-contents[#:style 'immediate-only]

@section{Input Streams}

@(declare-exporting skia skia/streams #:use-sources (skia/streams))

@defproc[(skia-input-stream? [v any/c])
          boolean?]{
Returns @racket[#t] for a native input stream, including a closed one, and
@racket[#f] otherwise. A Racket input port is not a native stream.
}

@defproc[(make-memory-input-stream
          [data bytes?]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)])
          skia-input-stream?]{
Returns an input stream at byte position zero containing a copy of @racket[data].
Empty data is accepted. Later mutation of @racket[data] does not affect the stream.
The input length must fit @racket[limit].
}

@defproc[(make-file-input-stream
          [filename path-string?]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)])
          skia-input-stream?]{
Opens an existing regular file at position zero. The path must not contain NUL,
and the file size must fit @racket[limit]. This is a file-backed stream, not an
immutable snapshot of the file's contents. The caller must keep the file stable
while using the stream or resources constructed from its duplicates. Native
open or capability failures raise an exception.
}

@defproc[(input-stream-length [stream skia-input-stream?])
          exact-nonnegative-integer?]{
Returns the total byte length, independently of the current cursor.
}

@defproc[(input-stream-position [stream skia-input-stream?])
          exact-nonnegative-integer?]{
Returns the current zero-based byte position. The position may equal the length.
}

@defproc[(input-stream-at-end? [stream skia-input-stream?])
          boolean?]{
Returns @racket[#t] when the cursor equals the length or the native stream
reports end-of-input. It does not read another byte.
}

@defproc[(input-stream-read-bytes [stream skia-input-stream?] [count exact-nonnegative-integer?])
          (or/c bytes? eof-object?)]{
Reads up to @racket[count] bytes and advances the cursor by the returned byte
count. A positive request at end-of-input returns @racket[eof]. A zero request
returns an empty byte string, including at end-of-input. A native read that
makes no progress without reporting end-of-input raises an exception.

The requested count itself must fit the effective stream limit, even when fewer
bytes remain. The result is an independent byte string, not borrowed storage.
}

@defproc[(input-stream-peek-bytes [stream skia-input-stream?] [count exact-nonnegative-integer?])
          (or/c bytes? eof-object?)]{
Like @racket[input-stream-read-bytes], without advancing the cursor. An
unsupported or failed native peek raises an exception instead of reading and
then attempting to restore the cursor.
}

@defproc[(input-stream-skip! [stream skia-input-stream?] [count exact-nonnegative-integer?])
          exact-nonnegative-integer?]{
Skips up to @racket[count] remaining bytes and returns the number skipped.
The request must fit the effective stream limit. Skipping at end-of-input or
requesting zero bytes returns zero.
}

@defproc[(input-stream-seek! [stream skia-input-stream?] [position exact-nonnegative-integer?])
          void?]{
Moves to the absolute byte position @racket[position], which must not exceed
the stream length. A failed seek raises an exception; it does not promise to
restore the previous position.
}

@defproc[(input-stream-rewind! [stream skia-input-stream?])
          void?]{
Moves the stream cursor to byte position zero. A failed rewind raises an exception.
}

@defproc[(input-stream-move! [stream skia-input-stream?] [offset exact-integer?])
          void?]{
Moves by the signed byte @racket[offset] relative to the current position.
The new position must lie from zero through the stream length. The offset must
also fit the platform's signed C @tt{long}; that range is not necessarily the
same as the pointer-sized integer range. A failed move raises an exception.
}

@defproc[(input-stream-duplicate [stream skia-input-stream?])
          skia-input-stream?]{
Creates another input stream with the same length and backing kind.

The new stream is independently owned and starts at position zero. The original
cursor is unchanged. Closing either wrapper does not close the other. A duplicate
of a file stream is not a promise
of copied file contents.

@racketblock[
(with-skia ([input (make-memory-input-stream #"abcdef")])
  (input-stream-seek! input 2)
  (with-skia ([duplicate (input-stream-duplicate input)]
              [fork (input-stream-fork input)])
    (list (input-stream->bytes duplicate)
          (input-stream->bytes fork)
          (input-stream-position input))))
]

The result is a list containing @racket[#"abcdef"], @racket[#"cdef"], and
@racket[2]: consuming either copy does not advance the original.
}

@defproc[(input-stream-fork [stream skia-input-stream?])
          skia-input-stream?]{
Like @racket[input-stream-duplicate], but starts at the original stream's
current position. The new cursor is independent and the full stream length is
preserved; a fork is not a suffix-only stream.
}

@defproc[(input-stream->bytes [stream skia-input-stream?])
          bytes?]{
Reads the entire unread suffix into an independent byte string and advances
the cursor to the end on success. An empty suffix returns an empty byte string,
not @racket[eof]. A short native read, such as from a truncated backing file,
raises an exception and may already have advanced the cursor.
}

@section{Output Streams}

@(declare-exporting skia skia/streams #:use-sources (skia/streams))

@defproc[(skia-output-stream? [v any/c])
          boolean?]{
Returns @racket[#t] for a native output stream, including a closed one, and
@racket[#f] otherwise. The predicate does not distinguish memory and file output.
}

@defproc[(make-memory-output-stream
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)])
          skia-output-stream?]{
Returns an empty memory output stream. Its byte count starts at zero. Closing
it does not return its contents; copy or detach them before closing.
}

@defproc[(output-stream-write-bytes! [stream skia-output-stream?] [data bytes?]
          [start exact-nonnegative-integer? 0] [end (or/c exact-nonnegative-integer? #f) #f])
          exact-nonnegative-integer?]{
Writes the slice from @racket[start], inclusive, to @racket[end], exclusive,
and returns its byte count. A false end means the byte-string length. The range
must satisfy @math{0 <= start <= end <= length}. The data is copied for the write.
The entire resulting stream size must fit its effective limit.

A validation error occurs before writing. A failed native write may have written
a prefix; it closes the stream and raises an exception. File output is not rolled
back. Both memory and file output streams are accepted.
}

@defproc[(output-stream-bytes-written [stream skia-output-stream?])
          exact-nonnegative-integer?]{
Returns the current accumulated byte count. A memory-stream detach resets this
count; it is not a lifetime total across detach operations.
}

@defproc[(output-stream->bytes [stream skia-output-stream?])
          (and/c bytes? (not/c immutable?))]{
Copies all bytes from a memory output stream without clearing it.

The returned byte string is mutable. File output streams are rejected. Later
writes to the stream do not change the returned bytes, and mutating those bytes
does not change the stream.
}

@defproc[(output-stream-detach-input! [stream skia-output-stream?])
          skia-input-stream?]{
Detaches a memory output stream's contents into an independently owned input
stream at position zero. The output remains open, empty, and reusable. File
output streams are rejected. The input survives closure or reuse of the output.

@racketblock[
(with-skia ([output (make-memory-output-stream)])
  (output-stream-write-bytes! output #"first")
  (with-skia ([input (output-stream-detach-input! output)])
    (output-stream-write-bytes! output #"second")
    (list (input-stream->bytes input) (output-stream->bytes output))))
]

The result contains @racket[#"first"] and @racket[#"second"].
}

@subsection{File Output}

@defmodule[skia/file-streams #:no-declare]
@(declare-exporting skia skia/file-streams #:use-sources (skia/file-streams))

@defproc[(make-file-output-stream [filename path-string?]
          [#:exists exists (or/c 'error 'replace) 'error]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)])
          skia-output-stream?]{
Opens a native file writer. The parent directory must exist, the target must
not be a directory, and the path must not contain NUL. The default rejects an
existing file or symbolic link; @racket['replace] permits truncation.

Opening the native writer can create or truncate the destination immediately.
This interface does not guarantee atomic exclusive creation. It writes directly
to the destination, without a temporary file or rollback on failure.
The caller must control the path during the operation.
Use @racket[output-stream-flush!] or close the stream to flush buffered output;
no durability guarantee is implied.
}

@defproc[(output-stream-flush! [stream skia-output-stream?])
          void?]{
Requests a native flush of a memory or file output stream. The stream remains
open and its accumulated count is unchanged. Flushing does not make file writing
atomic or guarantee that data has reached durable storage.
}

@section[#:tag "skia-buffered-ports"]{Buffered Racket Ports}

@(declare-exporting skia skia/streams #:use-sources (skia/streams))

The buffered adapters finish their Racket port I/O outside native resource
borrows. Input buffering reads from the port's current position through EOF;
it does not preserve the cursor. Output buffering takes a complete byte snapshot
before invoking port callbacks. These operations do not retain live port callbacks.

The optional cancellation event is checked while transferring and waiting for
progress. Cancellation, breaks, and I/O failures can leave partial I/O; consumed
or written bytes are not restored. Binary input containing a special value is
rejected. With @racket[#:close? #t], the port is closed when the transfer scope
ends, on success or failure. Argument validation before entering that scope does
not take ownership of the port. The default leaves it open.

@defproc[(buffered-port->input-stream [input input-port?]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)]
          [#:close? close? boolean? #f] [#:cancel-evt cancel (or/c evt? #f) #f])
          skia-input-stream?]{
Buffers the unread port contents and returns a new memory input stream at zero.
The limit is a bound on buffered input. A one-byte probe distinguishes an exact
limit followed by EOF from excess input; a limit failure can consume up to
@racket[(add1 limit)] bytes. Native stream construction occurs after buffering.
The returned stream owns its copied bytes, not the input port.
}

@defproc[(output-stream-write-port/buffered [stream skia-output-stream?] [output output-port?]
          [#:close? close? boolean? #f] [#:cancel-evt cancel (or/c evt? #f) #f])
          exact-nonnegative-integer?]{
Copies all contents of a memory output stream to the Racket output port and
returns the number of bytes written. The native stream remains open and is not
cleared. File output streams are rejected. The close option concerns the Racket
port, not the native stream. A failure while making the initial snapshot does
not take ownership of the port.
}

@section[#:tag "skia-stream-consumers"]{Constructing Resources from Streams}

@defmodule[skia/stream-inputs #:no-declare]
@(declare-exporting skia skia/stream-inputs #:use-sources (skia/stream-inputs))

The resource constructors in this section read from byte zero through a private
duplicate, not from the caller's current cursor. They leave the original stream open and
its cursor unchanged, including on construction failure. A successful resource
remains usable after the original stream closes. A file-backed duplicate still
requires a stable backing file.

@defproc[(codec-from-stream [stream skia-input-stream?])
          codec?]{
Returns an image codec using a private duplicate of @racket[stream]. The codec
owns its input independently. Invalid or unsupported encoded data raises an
exception; this constructor does not decode the complete image.
}

@defproc[(typeface-from-stream [stream skia-input-stream?]
          [#:index index (integer-in 0 2147483647) 0])
          typeface?]{
Returns a typeface from the stream's font data. The index selects a zero-based
collection member, including on macOS; it does not request fallback to a different
face. Invalid data or an unsupported member raises an exception. The typeface
has its own native ownership, independent of the caller's stream wrapper.
}

@defproc[(picture-from-stream [stream skia-input-stream?]
          [#:trusted? trusted? boolean? #f]
          [#:width width (or/c real? #f) #f] [#:height height (or/c real? #f) #f])
          picture?]{
Deserializes trusted SKP data using a private duplicate. The caller must supply
@racket[#:trusted? #t]; the default rejects the request before parsing. Trust is
an assertion by the caller, not a safety check or sandbox. Nominal size overrides
follow @racket[picture-from-bytes]: supply both dimensions or neither. The result
owns its decoded data and does not recenter the stored coordinate system.
}

@defproc[(codec-from-port/buffered [input input-port?]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)]
          [#:close? close? boolean? #f] [#:cancel-evt cancel (or/c evt? #f) #f])
          codec?]{
Buffers the unread port contents using @racket[buffered-port->input-stream],
then constructs a codec. No port callback remains attached to the codec.
}

@defproc[(typeface-from-port/buffered [input input-port?]
          [#:index index (integer-in 0 2147483647) 0]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)]
          [#:close? close? boolean? #f] [#:cancel-evt cancel (or/c evt? #f) #f])
          typeface?]{
Buffers the unread font data, then constructs the selected collection member
as in @racket[typeface-from-stream]. The index is checked before reading the port.
The buffered-port limit, cancellation, and close rules apply.
}

@defproc[(image-from-port/buffered [input input-port?]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)]
          [#:close? close? boolean? #f] [#:cancel-evt cancel (or/c evt? #f) #f])
          image?]{
Buffers the unread encoded data and constructs an image as in
@racket[image-from-bytes]. This is not the orientation-normalizing live
@racket[image-from-port] operation. The image owns its encoded-data snapshot;
later decoding does not require the input port.
}

@defproc[(picture-from-port/buffered [input input-port?]
          [#:trusted? trusted? boolean? #f]
          [#:width width (or/c real? #f) #f] [#:height height (or/c real? #f) #f]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)]
          [#:close? close? boolean? #f] [#:cancel-evt cancel (or/c evt? #f) #f])
          picture?]{
Buffers trusted SKP input and constructs a picture as in
@racket[picture-from-stream]. Trust and paired size overrides are checked before
port reading. The buffered-port limit, cancellation, and close rules apply.
}
