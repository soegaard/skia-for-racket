#lang scribble/manual

@(require
          (for-label racket/base racket/contract skia skia/graphics))

@title[#:tag "skia-graphics"]{Global Caches and Memory Statistics}

@defmodule[skia/graphics #:no-declare]
@(declare-exporting skia skia/graphics #:use-sources (skia/graphics))

The @racketmodname[skia/graphics] library exposes Skia's process-global CPU
graphics state, including cache controls and bounded memory reports. These
interfaces are separate from the Racket garbage collector, total process memory,
and a GPU context's resource cache. Cache limits are settings, not a hard cap on
all native allocations. Purging a cache does not close application-owned
surfaces, images, fonts, or paints.

Global graphics calls are rejected from live-port service callbacks and while a
live stream operation is active. Native calls are synchronized individually.
Cache values are read separately and may change between reads, so the results
need not describe the same moment. This also applies to @racket[skia-cache-statistics].

@local-table-of-contents[#:style 'immediate-only]

@section{Initialization}

@defproc[(skia-initialize!)
          void?]{
Explicitly initializes Skia's global graphics state. Ordinary resource operations already
perform the required native-library compatibility checks; this is not a substitute for
checking ownership or a guarantee that a GPU backend is available.
}

@section{Cache Queries and Limits}

@defproc[(skia-font-cache-used)
          exact-nonnegative-integer?]{
Returns the current font-cache byte usage. Byte results must be representable as the native
unsigned size type. The query does not purge the cache.
}

@defproc[(skia-font-cache-limit)
          exact-nonnegative-integer?]{
Returns the current font-cache byte limit. Byte results must be representable as the native
unsigned size type. The query does not purge the cache.
}

@defproc[(skia-font-cache-count-used)
          (integer-in 0 2147483647)]{
Returns the current number of font-cache entries. The query does not purge the cache.
}

@defproc[(skia-font-cache-count-limit)
          (integer-in 0 2147483647)]{
Returns the current upper limit on the number of font-cache entries. The query does not
purge the cache.
}

@defproc[(skia-resource-cache-used)
          exact-nonnegative-integer?]{
Returns the current resource-cache byte usage. Byte results must be representable as the native
unsigned size type. The query does not purge the cache.
}

@defproc[(skia-resource-cache-limit)
          exact-nonnegative-integer?]{
Returns the current resource-cache total-byte limit. Byte results must be representable as the
native unsigned size type. The query does not purge the cache.
}

@defproc[(skia-resource-cache-single-allocation-limit)
          exact-nonnegative-integer?]{
Returns the current single-allocation byte limit for the resource cache. Byte results must be
representable as the native unsigned size type. The query does not purge the cache.
}

@defproc[(skia-set-font-cache-limit! [limit exact-nonnegative-integer?])
          exact-nonnegative-integer?]{
Sets the font-cache byte limit and returns its previous setting. The result is not bytes freed,
current usage, or the newly installed limit. Byte limits must fit the native unsigned size type.
Settings affect the loaded library globally; restore a temporary change explicitly. The wrapper
adds no scope that automatically restores it.
}

@defproc[(skia-set-font-cache-count-limit! [limit (integer-in 0 2147483647)])
          (integer-in 0 2147483647)]{
Sets the upper limit on the number of font-cache entries to @racket[limit] and returns the
previous count limit. The result is not the current entry count or the newly installed limit.
Settings affect the loaded library globally; restore a temporary change explicitly. The wrapper
adds no scope that automatically restores it.
}

@defproc[(skia-set-resource-cache-limit! [limit exact-nonnegative-integer?])
          exact-nonnegative-integer?]{
Sets the resource-cache total-byte limit and returns its previous setting. The result is not
bytes freed, current usage, or the newly installed limit. Byte limits must fit the native
unsigned size type. Settings affect the loaded library globally; restore a temporary change
explicitly. The wrapper adds no scope that automatically restores it.
}

@defproc[(skia-set-resource-cache-single-allocation-limit! [limit exact-nonnegative-integer?])
          exact-nonnegative-integer?]{
Sets the resource-cache single-allocation byte limit and returns its previous setting. The
result is not bytes freed, current usage, or the newly installed limit. Byte limits must fit the
native unsigned size type. Settings affect the loaded library globally; restore a temporary
change explicitly. The wrapper adds no scope that automatically restores it.
}


@defproc[(skia-cache-statistics)
          (and/c hash? immutable?)]{
Returns current cache observations in an immutable hash table. The keys are @racket['scope],
@racket['atomic?], @racket['font-bytes-used], @racket['font-byte-limit],
@racket['font-count-used], @racket['font-count-limit], @racket['resource-bytes-used],
@racket['resource-byte-limit], and @racket['resource-single-allocation-byte-limit]. The scope is
@racket['process-global-skia-caches] and @racket['atomic?] is false.

The fields come from separate native queries. They should not be treated as one simultaneous
measurement or summed as a complete account of process memory.
}

@section{Purging Caches}

@defproc[(skia-purge-font-cache!)
          void?]{
Requests purging of the font cache. The operation does not return a freed-byte count or promise
that every cache entry can be discarded. It does not close owned resources or purge a GPU
context's cache.
}

@defproc[(skia-purge-resource-cache!)
          void?]{
Requests purging of the resource cache. The operation does not return a freed-byte count or
promise that every cache entry can be discarded. It does not close owned resources or purge a
GPU context's cache.
}

@defproc[(skia-purge-all-caches!)
          void?]{
Requests purging of the global caches. The operation does not return a freed-byte count or
promise that every cache entry can be discarded. It does not close owned resources or purge a
GPU context's cache.
}

@section[#:tag "skia-memory-statistics"]{Bounded Memory Reports}

A memory report contains @tt{memory-statistic} structures. Each entry describes
an observed value, which is an unsigned 64-bit integer or an immutable string.

@defproc[(skia-memory-statistics [#:detailed? detailed? boolean? #f] [#:dump-wrapped?
          dump-wrapped? boolean? #f] [#:max-entries max-entries (integer-in 0 65536) 4096]
          [#:string-limit string-limit (integer-in 0 65536) 4096] [#:byte-limit byte-limit
          exact-nonnegative-integer? 1048576])
          memory-statistics?]{
Collects a native memory report for process-global Skia caches. The flags request
detailed reporting and inclusion of wrapped objects. Names, units, and string values depend on
the native backend; they are not a fixed allocation inventory.

The entry limit bounds the number of entries stored in the report.
@racket[#:string-limit] limits each copied string's UTF-8 byte length;
@racket[#:byte-limit] limits their combined byte length.
The expression @racket[(+ (*
max-entries 128) byte-limit)] must fit @racket[current-skia-byte-limit]. Zero limits are valid.
Oversized entries are omitted and counted, not shortened into apparently complete values.
If collection detects a missing string, invalid UTF-8, or a numeric statistic
that is not an unsigned 64-bit integer, the function releases the native
reporting resources and raises an exception.

The reported values need not describe the same moment and do not account for all
process memory. The callback provider is process-global; a second module instance
or place cannot replace an already claimed provider table. The same
provider is shared with GPU memory reporting, but this function's report has CPU-cache scope.
No application callback runs while Skia is collecting the entries.
}

@defproc[(memory-statistics? [v any/c])
          boolean?]{
Returns @racket[#t] for a memory report, including a GPU-context report using the same
data representation.
}

@defproc[(memory-statistics-entries [report memory-statistics?])
          (and/c (vectorof memory-statistic?) immutable?)]{
Returns the report's entries in native observation order as an immutable vector.
}

@defproc[(memory-statistics-detailed? [report memory-statistics?])
          boolean?]{
Returns the requested detailed-reporting flag, not a completeness guarantee.
}

@defproc[(memory-statistics-dump-wrapped? [report memory-statistics?])
          boolean?]{
Returns whether inclusion of wrapped native objects was requested.
}

@defproc[(memory-statistics-truncated? [report memory-statistics?])
          boolean?]{
Reports whether any observed entry was omitted because of the configured bounds.
}

@defproc[(memory-statistics-dropped-count [report memory-statistics?])
          exact-nonnegative-integer?]{
Returns the number of omitted observed entries, not bytes omitted or all allocations absent from
the native report.
}

@defproc[(memory-statistics-string-bytes [report memory-statistics?])
          exact-nonnegative-integer?]{
Returns the total number of UTF-8 bytes stored for names, value names, units, and string values.
Numeric values are not counted as strings.
}

@defproc[(memory-statistics-scope [report memory-statistics?])
          (or/c 'process-global-skia-caches 'gpu-context-skia-resources)]{
Returns the origin of the report. A GPU report is not a report of all process-global CPU caches.
}

@defproc[(memory-statistics->jsexpr [report memory-statistics?])
          (and/c hash? immutable?)]{
Returns a JSON-compatible hash table with scope, an explicit false atomic flag, requested
options, truncation information, string-byte count, and a list of entries. Entry kinds and scope
symbols become strings. The conversion does not query native memory again.
}

@defproc[(memory-statistic? [v any/c])
          boolean?]{
Returns @racket[#t] for a @tt{memory-statistic} structure and @racket[#f] otherwise.
}

@defproc[(memory-statistic-kind [entry memory-statistic?])
          (or/c 'numeric 'string)]{
Returns @racket['numeric] or @racket['string], indicating the type of the stored value.
}

@defproc[(memory-statistic-name [entry memory-statistic?])
          (and/c string? immutable?)]{
Returns the copied native object or category name.
}

@defproc[(memory-statistic-value-name [entry memory-statistic?])
          (and/c string? immutable?)]{
Returns the copied name of the reported value.
}

@defproc[(memory-statistic-units [entry memory-statistic?])
          (or/c #f (and/c string? immutable?))]{
Returns copied units for a numeric entry, or @racket[#f] for a string entry.
}

@defproc[(memory-statistic-value [entry memory-statistic?])
          (or/c (integer-in 0 #xffffffffffffffff)
                (and/c string? immutable?))]{
Returns the stored unsigned 64-bit integer or immutable string, according to
@racket[memory-statistic-kind].
}
