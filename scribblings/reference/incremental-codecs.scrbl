#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/codec-incremental))

@title[#:tag "skia-incremental-codecs"]{Incremental Image Decoding}

@defmodule[skia/codec-incremental #:no-declare]
@(declare-exporting skia skia/codec-incremental #:use-sources (skia/codec-incremental))

An @deftech{incremental decoding session} accepts explicitly fed encoded bytes
and retains a native decoder and destination between steps. It does not read a
Racket port or keep arbitrary port callbacks. It decodes the first frame at the
encoded dimensions and orientation, without subset selection, scaling, or a
fallback to one-shot decoding.

Input and decoded pixels can both remain resident. Incremental decoding is not
a promise of constant memory. The supported destination is byte RGBA8888 or
BGRA8888, with premultiplied or unpremultiplied alpha. Floating-point destinations
are not accepted by this interface.

Progressive input is supported for PNG at complete chunk boundaries. Partial PNG
chunks can be accepted by feed without yet becoming visible to the native codec.
Other formats are exposed only once the input is declared final, and their native
incremental support may still be rejected. No input is spliced or re-encoded to
simulate a decoder capability.

The session is an @tech{owned resource} tied to its creating Racket thread.
Only the type predicate is independent of that thread. The state query also
works after closure; other operations require an open resource. Closing destroys
the decoder before releasing pixels it might retain. Progress and snapshots are
detached and survive session closure.

@defproc[(codec-incremental-session? [v any/c])
          boolean?]{
Returns @racket[#t] for an incremental session, including a closed wrapper,
and @racket[#f] otherwise.
}

@defproc[(make-codec-incremental
          [#:color-type color-type (or/c 'rgba-8888 'bgra-8888) 'rgba-8888]
          [#:alpha-type alpha-type (or/c 'premul 'unpremul) 'unpremul]
          [#:color-space space (or/c #f 'srgb 'linear-srgb bytes?) 'srgb]
          [#:row-bytes row-bytes (or/c exact-positive-integer? #f) #f]
          [#:limit limit exact-positive-integer? (current-skia-byte-limit)])
          codec-incremental-session?]{
Returns a session in @racket['awaiting-input] state with no decoded destination.
The destination color-space description follows @racket[make-image-info]. A supplied stride
must be positive, divisible by four, and at most @racket[2147483647]. Its lower
bound relative to the image width is checked when the header reveals dimensions.
A false stride selects tight storage then.

The limit must not exceed @racket[2147483647] or @racket[current-skia-byte-limit].
It bounds retained encoded input and destination allocations separately; it is
not their combined heap budget. Later operations also honor a lowered current
limit. The constructor requires native incremental support from the live-stream
bridge, but does not start a port operation or decode pixels.
}

@defproc[(codec-incremental-feed! [session codec-incremental-session?] [data bytes?]
          [#:final? final? boolean? #f])
          exact-nonnegative-integer?]{
Appends a copy of @racket[data] and returns the number of bytes accepted.
Mutation of @racket[data] after return does not affect the session. Feeding does
not itself decode pixels. Empty input is allowed; an empty final feed seals an
existing prefix. No further feed is permitted once input is final or the session
is terminal.

A quota rejection leaves the retained prefix and final flag unchanged. Invalid
PNG framing discovered after appending can instead fail the session. A final
prefix may be truncated: declaring final means no more input will arrive, not
that the image is valid or complete. PNG chunk visibility is reflected separately
from accepted input size in @racket[codec-incremental-statistics].
}

@defproc[(codec-incremental-step! [session codec-incremental-session?]
          [#:cancel-evt cancel (or/c evt? #f) #f])
          incremental-progress?]{
Attempts header construction, native incremental start, or continued decoding
and returns detached progress. No new native attempt is made when neither the
visible input size nor final flag has changed since the previous attempt.
Once started, the same destination is retained between calls. Before native use,
all destination bytes, including padding, are initialized to zero.

A native incomplete-input result means @racket['needs-input] before a final feed
and terminal @racket['incomplete] afterward. Native success means complete;
other native failures mean failed. Terminal calls return the existing progress
without retrying or reopening the decoder. Wrapper exceptions mark failure,
release retained storage, and raise rather than returning fictitious native
success. A byte-limit failure before the decoding attempt need not make the
session terminal.

The cancellation event is polled before entering the native ownership scope.
This is cancellation between steps, not interruption midway through an atomic
native decode. A ready event cancels a nonterminal session; terminal progress
is preserved. No partial-input decode is substituted for an unsupported format.

@racketblock[
(with-skia ([surface (make-surface 3 2 #:background 'blue)]
            [session (make-codec-incremental)])
  (define encoded (surface->png-bytes surface))
  (codec-incremental-feed! session (subbytes encoded 0 1))
  (define first (codec-incremental-step! session))
  (codec-incremental-feed! session (subbytes encoded 1) #:final? #t)
  (define final (codec-incremental-step! session))
  (list (incremental-progress-state first)
        (incremental-progress-state final)))
]

The first step needs more input. A successful complete PNG decode then reports
@racket['complete]; consumers must inspect progress rather than assume success.
}

@defproc[(codec-incremental-cancel! [session codec-incremental-session?])
          incremental-progress?]{
Cancels a nonterminal session, releases its decoder and destination, and
returns progress with state and result @racket['cancelled]. Repeated cancellation
of a terminal session preserves its existing progress; it does not change a
completed result into cancellation. The resource wrapper remains open until
explicitly closed or released by its resource scope.
}

@defproc[(codec-incremental-state [session codec-incremental-session?])
          (or/c 'awaiting-input 'needs-input 'complete 'incomplete 'failed 'cancelled 'closed)]{
Returns the session state. Awaiting-input is the initial state. Needs-input
allows more feed/step calls. Complete, incomplete, failed, and cancelled are
terminal and require a new session to retry. Closing the resource causes this
query to return @racket['closed].
}

@defproc[(codec-incremental-info [session codec-incremental-session?])
          (or/c image-info? #f)]{
Returns the detached output description once dimensions are known, or
@racket[#f] beforehand. Metadata availability alone does not establish successful
incremental start or a usable snapshot.
}

@defproc[(codec-incremental-origin [session codec-incremental-session?])
          (or/c #f 'top-left 'top-right 'bottom-right 'bottom-left
                'left-top 'right-top 'right-bottom 'left-bottom)]{
Returns the encoded orientation once known, or @racket[#f] beforehand. Neither
incremental decoding nor snapshot conversion applies this orientation to pixels.
}

@defproc[(codec-incremental-statistics [session codec-incremental-session?])
          (and/c hash? immutable?)]{
Returns a detached immutable hash with diagnostic counters. Keys
@racket['header-attempts], @racket['start-calls], @racket['decode-calls], and
@racket['pixel-allocations] count native work. Keys @racket['input-bytes] and
@racket['visible-input-bytes] distinguish accepted data from the prefix exposed
to the decoder, and @racket['input-final?] reports whether input is sealed.
Keys @racket['stream-creations] and @racket['stream-destructions] count the private
native inputs; @racket['decoder-retained?] reports decoder retention, and
@racket['pixel-bytes] reports currently retained destination storage.

Input counts remain as diagnostics after retained input storage is discarded;
they are not current allocation sizes. The returned hash is a snapshot, not a
live view or a guarantee of exact native heap use.
}

@section{Progress and Pixel Snapshots}

An @deftech{incremental progress value} separates session state, a native or
wrapper result, and the native initialized-row report. A row report of
@racket[#f] means unknown, not zero. All allocated destination memory is
initialized before use; that fact does not make uncompleted rows valid image
content. Interlaced decoding may revisit pixels, so a progress value is not a
promise that each previously visited row is final.

@defproc[(incremental-progress? [v any/c])
          boolean?]{
Returns @racket[#t] for detached incremental progress and @racket[#f] otherwise.
}

@defproc[(incremental-progress-state [progress incremental-progress?])
          (or/c 'awaiting-input 'needs-input 'complete 'incomplete 'failed 'cancelled)]{
Returns the session state captured when the progress value was made.
}

@defproc[(incremental-progress-result [progress incremental-progress?])
          (or/c 'not-started 'success 'incomplete-input 'error-in-input 'invalid-conversion
                'invalid-scale 'invalid-parameters 'invalid-input 'could-not-rewind
                'internal-error 'unimplemented 'wrapper-error 'cancelled)]{
Returns the most recent native result name, or @racket['not-started],
@racket['wrapper-error], or @racket['cancelled] for the corresponding wrapper
condition. The same incomplete-input result has different states depending on
whether more input is allowed.
}

@defproc[(incremental-progress-initialized-rows [progress incremental-progress?])
          (or/c exact-nonnegative-integer? #f)]{
Returns the native initialized-row report when meaningful, or @racket[#f].
Successful decoding reports the full output height. Incomplete input uses the
native report only when supplied and valid; other failures do not invent a count.
The count is not an EXIF-normalized coordinate or a byte offset.
}

@defproc[(codec-incremental-snapshot [session codec-incremental-session?])
          incremental-snapshot?]{
Returns a detached immutable copy of the whole destination, including padding,
with its pixel description and current progress. Native incremental start must
have succeeded and the destination must still be retained. The copy must fit
the effective byte limit. The operation does not run another decoding step.

A snapshot can describe incomplete output; its existence is not success.
Completion or a reported terminal native failure can leave pixels available,
whereas cancellation or a wrapper exception may release them. Snapshot data
remains valid after the session closes and is unaffected by later decoding.
}

@defproc[(incremental-snapshot? [v any/c])
          boolean?]{
Returns @racket[#t] for an incremental pixel snapshot and @racket[#f] otherwise.
}

@defproc[(incremental-snapshot-info [snapshot incremental-snapshot?])
          image-info?]{
Returns the detached full-destination pixel description.
}

@defproc[(incremental-snapshot-row-bytes [snapshot incremental-snapshot?])
          exact-positive-integer?]{
Returns the destination stride, including row padding.
}

@defproc[(incremental-snapshot-bytes [snapshot incremental-snapshot?])
          (and/c bytes? immutable?)]{
Returns immutable storage bytes. Their length is stride times destination
height. Rows remain in encoded coordinates, with no orientation normalization.
}

@defproc[(incremental-snapshot-progress [snapshot incremental-snapshot?])
          incremental-progress?]{
Returns the progress captured with these pixels, not the session's later progress.
}

@defproc[(incremental-snapshot->raster-buffer [snapshot incremental-snapshot?])
          raster-buffer?]{
Copies the snapshot into an independently owned raster buffer, preserving its
format and stride. Storage validation and allocation can fail. The operation
does not require complete progress and therefore does not certify a complete
image. It neither advances the decoder nor applies encoded orientation.

@racketblock[
(with-skia ([surface (make-surface 3 2 #:background 'blue)]
            [session (make-codec-incremental)])
  (codec-incremental-feed! session (surface->png-bytes surface) #:final? #t)
  (define progress (codec-incremental-step! session))
  (unless (eq? (incremental-progress-state progress) 'complete)
    (error 'decode "incomplete image: ~a" (incremental-progress-result progress)))
  (define snapshot (codec-incremental-snapshot session))
  (skia-close! session)
  (with-skia ([buffer (incremental-snapshot->raster-buffer snapshot)]
              [image (raster-buffer->image buffer)])
    (list (image-width image) (image-height image))))
]

The detached snapshot remains usable after the session closes.
}
