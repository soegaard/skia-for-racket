#lang scribble/manual

@(require
          (for-label racket/base racket/contract skia skia/graphics
                     (only-in skia/gpu-diagnostics gpu-memory-statistics)))

@title[#:tag "skia-graphics"]{Global Caches and Memory Statistics}

@defmodule[skia/graphics #:no-declare]
@(declare-exporting skia skia/graphics #:use-sources (skia/graphics))

Use @racketmodname[skia/graphics] to inspect cache usage, change cache limits,
request cache cleanup, or collect more detailed memory reports. These operations
affect Skia's process-global CPU caches, not the Racket garbage collector or a
GPU context's resource cache. Cache limits are settings, not a hard cap on all
native allocations, and cache usage is only part of total process memory.

Global graphics calls raise an exception from live-port service callbacks and
while a @tech{live port operation} is active. Native calls are synchronized individually.
Cache values are read separately and may change between reads, so the results
need not describe the same moment. This also applies to @racket[skia-cache-statistics].

@local-table-of-contents[#:style 'immediate-only]

@section{Initialization}

@defproc[(skia-initialize!)
          void?]{
Initializes Skia's global graphics state. Use it to perform initialization during
application startup, before drawing begins. Repeated calls are safe.

Use @racket[skia-check!] instead when you only want to check native-library
availability and compatibility. Those checks, which ordinary resource operations
also perform, are separate from this initialization. This function does not
create a GPU context.
}

@section{Cache Queries and Limits}

Cache queries report current usage or configured limits. Changing a limit affects
all code using the loaded Skia library. Each setter returns the previous limit;
restore it explicitly after a temporary change.

Byte-limit setters accept values from zero through @racket[#xffffffff] on 32-bit
platforms, or through @racket[#xffffffffffffffff] on 64-bit platforms. Larger
values raise an exception.

@defproc[(skia-font-cache-used)
          exact-nonnegative-integer?]{
Returns the current font-cache byte usage.
}

@defproc[(skia-font-cache-limit)
          exact-nonnegative-integer?]{
Returns the current font-cache byte limit.
}

@defproc[(skia-font-cache-count-used)
          (integer-in 0 2147483647)]{
Returns the current number of font-cache entries.
}

@defproc[(skia-font-cache-count-limit)
          (integer-in 0 2147483647)]{
Returns the current upper limit on the number of font-cache entries.
}

@defproc[(skia-resource-cache-used)
          exact-nonnegative-integer?]{
Returns the current resource-cache byte usage.
}

@defproc[(skia-resource-cache-limit)
          exact-nonnegative-integer?]{
Returns the current resource-cache total-byte limit.
}

@defproc[(skia-resource-cache-single-allocation-limit)
          exact-nonnegative-integer?]{
Returns the current single-allocation byte limit for the resource cache.
}

@defproc[(skia-set-font-cache-limit! [limit exact-nonnegative-integer?])
          exact-nonnegative-integer?]{
Sets the font-cache byte limit and returns the previous limit.
}

@defproc[(skia-set-font-cache-count-limit! [limit (integer-in 0 2147483647)])
          (integer-in 0 2147483647)]{
Sets the upper limit on the number of font-cache entries to @racket[limit] and returns the
previous count limit.
}

@defproc[(skia-set-resource-cache-limit! [limit exact-nonnegative-integer?])
          exact-nonnegative-integer?]{
Sets the resource-cache total-byte limit and returns the previous limit.
}

@defproc[(skia-set-resource-cache-single-allocation-limit! [limit exact-nonnegative-integer?])
          exact-nonnegative-integer?]{
Sets the resource-cache single-allocation byte limit and returns the previous limit.
}


@defproc[(skia-cache-statistics)
          (and/c hash? immutable?)]{
Returns current cache observations in an immutable hash table. The keys are @racket['scope],
@racket['atomic?], @racket['font-bytes-used], @racket['font-byte-limit],
@racket['font-count-used], @racket['font-count-limit], @racket['resource-bytes-used],
@racket['resource-byte-limit], and @racket['resource-single-allocation-byte-limit]. The scope is
@racket['process-global-skia-caches] and @racket['atomic?] is false.

As with the individual queries, the fields need not describe the same moment.
They should not be summed as a complete account of process memory.
}

@section{Purging Caches}

Use these functions to request that Skia discard cached data. Some entries may
remain in use and cannot be discarded. Purging does not close application-owned
surfaces, images, fonts, or paints, and does not affect a GPU context's cache.
The functions return @racket[(void)], not a count of bytes freed.

@defproc[(skia-purge-font-cache!)
          void?]{
Requests purging of the font cache.
}

@defproc[(skia-purge-resource-cache!)
          void?]{
Requests purging of the resource cache.
}

@defproc[(skia-purge-all-caches!)
          void?]{
Requests purging of all process-global Skia caches.
}

@section[#:tag "skia-memory-statistics"]{Bounded Memory Reports}

Use a memory report to investigate the cache categories and individual values
reported by Skia. If you only need current cache totals and limits,
@racket[skia-cache-statistics] provides a simpler summary.

A report contains @tt{memory-statistic} structures. Each entry describes an
observed value, which is an unsigned 64-bit integer or an immutable string.
Names, units, and string values depend on the native backend. Reports need not
describe a single moment and do not account for all process memory.

@defproc[(skia-memory-statistics [#:detailed? detailed? boolean? #f] [#:dump-wrapped?
          dump-wrapped? boolean? #f] [#:max-entries max-entries (integer-in 0 65536) 4096]
          [#:string-limit string-limit (integer-in 0 65536) 4096] [#:byte-limit byte-limit
          exact-nonnegative-integer? 1048576])
          memory-statistics?]{
Collects a memory report for process-global Skia caches.

@racket[#:detailed?] requests a more detailed breakdown of the reported memory
use, not a complete inventory of allocations. @racket[#:dump-wrapped?] requests
inclusion of objects supplied from outside Skia, which Skia calls wrapped objects.
Those objects may also be accounted for by the code that supplied them.

The entry limit bounds the number of entries stored in the report.
@racket[#:string-limit] limits each copied string's UTF-8 byte length;
@racket[#:byte-limit] limits their combined byte length.
For the allocation check, the function budgets 128 bytes per permitted entry
in addition to the string budget. The expression
@racket[(+ (* max-entries 128) byte-limit)] must not exceed
@racket[(current-skia-byte-limit)]; otherwise, the function raises an exception.
The 128-byte allowance is used for this check, not as a measurement of an entry's
actual memory use. Zero limits are valid.

Entries that exceed the entry or string limits are omitted and counted;
strings are not shortened to fit.
If collection detects a missing string, invalid UTF-8, or a numeric statistic
that is not an unsigned 64-bit integer, the function releases the native
reporting resources and raises an exception.

Memory reporting can be initialized by only one instance of the reporting
module in a process. If another Racket place or a separately instantiated copy
of the module attempts to initialize it afterward, the call raises an exception.
This restriction is shared with @racket[gpu-memory-statistics], though the two
functions report on different caches. This function reports only on CPU caches.
No application callback runs while Skia collects the entries.
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
Returns whether detailed reporting was requested.
}

@defproc[(memory-statistics-dump-wrapped? [report memory-statistics?])
          boolean?]{
Returns whether inclusion of objects supplied from outside Skia was requested.
}

@defproc[(memory-statistics-truncated? [report memory-statistics?])
          boolean?]{
Reports whether any observed entry was omitted because of the configured bounds.
}

@defproc[(memory-statistics-dropped-count [report memory-statistics?])
          exact-nonnegative-integer?]{
Returns the number of observed entries omitted because of the configured limits.
}

@defproc[(memory-statistics-string-bytes [report memory-statistics?])
          exact-nonnegative-integer?]{
Returns the total number of UTF-8 bytes stored for names, value names, units, and string values.
Numeric values are not counted as strings.
}

@defproc[(memory-statistics-scope [report memory-statistics?])
          (or/c 'process-global-skia-caches 'gpu-context-skia-resources)]{
Returns @racket['process-global-skia-caches] for a report from
@racket[skia-memory-statistics], or @racket['gpu-context-skia-resources] for a
report from @racket[gpu-memory-statistics].
}

@defproc[(memory-statistics->jsexpr [report memory-statistics?])
          (and/c hash? immutable?)]{
Returns a JSON-compatible hash table containing the report's scope, requested
options, truncation information, string-byte count, and entries. The
@racket['atomic] field is @racket[#f] because the observations need not describe
the same moment. Entry kinds and scope symbols become strings. The conversion
does not query native memory again.
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
