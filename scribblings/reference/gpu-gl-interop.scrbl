#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/gpu skia/gpu-gl-interop))

@title[#:tag "skia-gpu-gl-interop"]{OpenGL Interoperation}

@defmodule[skia/gpu-gl-interop #:no-declare]
@(declare-exporting skia/gpu-gl-interop #:use-sources (skia/gpu-gl-interop))

These operations temporarily hand the current OpenGL command stream or
host-owned OpenGL storage across the Skia boundary. They require the exact
active OpenGL context and its function resolver. OpenGL object names are
interpreted only in that current context; equal integer names do not establish
resource sharing between contexts.

The API does not adopt external GL objects, expose Skia-owned texture names, or
infer sharing groups. Nested external-resource handoffs are rejected.

@section{External OpenGL Commands}

@defproc[(call-with-gpu-external-gl [context gpu-context?] [proc (-> any)]
                                    [#:wait? wait? boolean? #f]) any]{
Flushes and submits queued Skia work, then calls @racket[proc] while the same
native OpenGL context remains current. The callback's multiple values are
returned. With @racket[wait?] false, ordering uses the same command stream but
does not promise CPU completion of preceding work; true requests that completion
before the callback.

The callback must keep the native context current and must not reenter Skia GPU
operations. On exit, including exceptional exit, the wrapper invalidates Skia's
cached GL state. It does not save or restore the host's complete GL program,
vertex-array, blend, viewport, texture, sampler, or pixel-transfer state. Host
code must establish the state it needs.
}

@section{Borrowed Framebuffers}

@defproc[(call-with-gpu-gl-framebuffer
          [context gpu-context?] [framebuffer (integer-in 1 #xffffffff)]
          [width (integer-in 1 #x7fffffff)] [height (integer-in 1 #x7fffffff)]
          [proc (-> canvas? any)]
          [#:origin origin (or/c 'bottom-left 'top-left) 'bottom-left]
          [#:color-space space (or/c color-space? #f) #f]
          [#:wait? wait? boolean? #t]) any]{
Temporarily wraps a host-owned framebuffer and calls @racket[proc] with an
ordinary borrowed Skia canvas. The framebuffer and its attachments remain owned
by the host; the callback receives neither a surface nor a native pointer. The
canvas expires when the call returns, even if an enclosing context activation
continues. The callback's multiple values are preserved.

The supported target is deliberately narrow: a nonzero complete single-sampled
framebuffer whose sole draw output is a level-zero, nonlayered
@tt{GL_TEXTURE_2D} with @tt{GL_RGBA8}, identity swizzle, base level zero, and no
comparison mode. It must also have a matching single-sampled eight-bit stencil
renderbuffer. The wrapper queries and verifies those properties; @racket[width]
and @racket[height] must match the actual attachments.

The color-space argument describes the pixels; it does not convert their
existing values. The target uses RGBA pixels with premultiplied alpha. The callback
must leave the canvas save/layer stack balanced. Cleanup restores an unbalanced stack
before reporting the error, but drawing already performed is not rolled back.
Issued work is submitted even when the callback raises. The default waits before
returning the host storage; false requests only same-context ordered reuse.
}

@section{Owned Copies of Host Textures}

@defproc[(gpu-copy-gl-texture
          [context gpu-context?] [texture (integer-in 1 #xffffffff)]
          [width (integer-in 1 #x7fffffff)] [height (integer-in 1 #x7fffffff)]
          [#:origin origin (or/c 'bottom-left 'top-left) 'bottom-left]
          [#:premultiplied? premultiplied? boolean? #t]
          [#:color-space space (or/c color-space? #f) #f]
          [#:wait? wait? boolean? #t]) gpu-image?]{
Validates and temporarily borrows the host's level-zero @tt{GL_RGBA8} 2D texture,
then copies it on the GPU into a new Skia-owned image. The returned image does
not alias the host texture and follows the ordinary GPU-image lifetime and
context restrictions. No CPU readback occurs.

The original texture must have identity swizzle, base level zero, and no compare
mode. The @racket[premultiplied?] argument describes its input alpha representation;
@racket[space] describes its color interpretation. The owned destination uses
the regular premultiplied GPU-surface path. With the default wait, the host may
reuse or delete its texture after successful return without changing the copy.
A false wait retains only the same-context command-stream ordering contract.

The wrapper restores the small set of GL bindings it temporarily changes and
invalidates Skia's state cache afterward. It does not claim to restore every GL
state variable. A pending GL error, changed current context, unsupported storage,
or failed native wrapper is an error rather than a CPU fallback.
}
