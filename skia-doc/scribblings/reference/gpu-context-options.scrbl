#lang scribble/manual

@(require scribble/eval
          (for-label racket/base racket/contract skia/gpu skia/gpu-context-options))

@(define options-eval (make-base-eval))
@(options-eval '(require skia/gpu-context-options))

@title[#:tag "skia-gpu-context-options"]{GPU Context Options}

@defmodule[skia/gpu-context-options #:no-declare]
@(declare-exporting skia/gpu skia/gpu-context-options
                    #:use-sources (skia/gpu-context-options))

Use context options to set cache budgets or other context-wide rendering
settings. Create the value with @racket[make-gpu-context-options] and pass it
as @racket[#:options] to @racket[make-gpu-context]. These settings apply to the
context, not to an individual surface or drawing operation.

If you do not need a particular setting, omit @racket[#:options] to use Skia's
native defaults. Constructing an options value is not a required step in
creating a context.

A @deftech{GPU context options} value is an immutable Racket structure containing
requests used when constructing a @tech{GPU context}. Constructing or inspecting
options does not load Skia or probe a backend.

Passing @racket[#f] as @racket[#:options] to @racket[make-gpu-context] uses Skia's
native defaults. Passing an options value supplies the settings stored in that
value, including the defaults from @racket[make-gpu-context-options]. Options
are requests: backend support and driver workarounds can affect which requests
take effect. The API does not report the effective settings.
@racket[gpu-context-info] records the requested options, while
@racket[gpu-cache-info] reports the active context's cache usage and limit.

@section{Construction}

@defproc[(gpu-context-options? [v any/c]) boolean?]{
Returns @racket[#t] for a GPU context options value.
}

@defproc[(make-gpu-context-options
          [#:avoid-stencil-buffers? avoid-stencil? boolean? #f]
          [#:runtime-program-cache-size programs (integer-in 1 2147483647) 256]
          [#:glyph-cache-texture-maximum-bytes glyph-bytes
           (integer-in 1 18446744073709551615) 8388608]
          [#:allow-path-mask-caching? cache-paths? boolean? #t]
          [#:manual-mipmapping? manual-mipmaps? boolean? #f]
          [#:buffer-map-threshold threshold (integer-in -1 2147483647) -1])
          gpu-context-options?]{
Creates an immutable options value with the following requests:

@itemlist[
 @item{The @racket[avoid-stencil?] argument requests alternatives to stencil buffers.}
 @item{The @racket[programs] argument bounds the runtime program or pipeline cache
       by entry count. Zero is not accepted.}
 @item{The @racket[glyph-bytes] argument specifies the glyph-cache texture byte
       budget. It is not a limit on total GPU memory or process memory.}
 @item{The @racket[cache-paths?] argument permits path-mask caching.}
 @item{The @racket[manual-mipmaps?] argument requests Skia's manual mipmap
       construction path where applicable.}
 @item{The @racket[threshold] argument selects the buffer-mapping threshold.
       A value of @racket[-1] delegates the choice to the native platform;
       nonnegative values are explicit thresholds.}]

Skia copies the supplied settings during context construction. These settings
cannot be changed on an existing context by constructing another options value.

@examples[#:eval options-eval
  (define defaults (make-gpu-context-options))
  (eval:check (gpu-context-options-runtime-program-cache-size defaults) 256)
  (eval:check (gpu-context-options-buffer-map-threshold defaults) -1)
  (define smaller (make-gpu-context-options #:runtime-program-cache-size 64))
  (eval:check (gpu-context-options-runtime-program-cache-size smaller) 64)
  (eval:check (gpu-context-options-runtime-program-cache-size defaults) 256)
]
}

@section{Inspection and Serialization}

@defproc[(gpu-context-options-avoid-stencil-buffers? [options gpu-context-options?]) boolean?]{
Returns the stored request to avoid stencil buffers.
}

@defproc[(gpu-context-options-runtime-program-cache-size [options gpu-context-options?])
          (integer-in 1 2147483647)]{
Returns the requested program-cache entry limit, not the current entry count.
}

@defproc[(gpu-context-options-glyph-cache-texture-maximum-bytes [options gpu-context-options?])
          (integer-in 1 18446744073709551615)]{
Returns the requested glyph-cache texture byte budget, not measured memory use.
}

@defproc[(gpu-context-options-allow-path-mask-caching? [options gpu-context-options?]) boolean?]{
Returns whether the stored request permits path-mask caching.
}

@defproc[(gpu-context-options-manual-mipmapping? [options gpu-context-options?]) boolean?]{
Returns the stored request for manual mipmap construction.
}

@defproc[(gpu-context-options-buffer-map-threshold [options gpu-context-options?])
          (integer-in -1 2147483647)]{
Returns the stored threshold, including @racket[-1] for native platform selection.
}

@defproc[(gpu-context-options->jsexpr [options gpu-context-options?])
          (and/c hash? immutable?)]{
Returns an immutable JSON-compatible hash table with keys
@racket['avoid_stencil_buffers], @racket['runtime_program_cache_size],
@racket['glyph_cache_texture_maximum_bytes], @racket['allow_path_mask_caching],
@racket['manual_mipmapping], and @racket['buffer_map_threshold]. These are the
stored requests. The operation does not consult a native context or report
whether a driver honored them.
}

@close-eval[options-eval]
