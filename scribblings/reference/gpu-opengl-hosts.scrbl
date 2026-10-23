#lang scribble/manual

@(require (for-label racket/base racket/contract racket/class racket/draw
                     skia/gpu skia/gpu-egl skia/gpu-racket-gl))

@title[#:tag "skia-gpu-opengl-hosts"]{OpenGL Hosts}

For headless OpenGL drawing on Linux, use @racket[make-egl-gpu-context] to
create both a native host and its Skia @tech{GPU context}. When an application
already owns an OpenGL context, use an adapter below to create a provider for
@racket[make-gpu-context] instead.

The host must make the matching native OpenGL context current during Skia
operations. These adapters do not create a presentation window or swap buffers.
Adapting an existing host does not transfer ownership of it to the package.

@section{Owned and Borrowed EGL Hosts}

@defmodule[skia/gpu-egl #:no-declare]
@(declare-exporting skia/gpu-egl #:use-sources (skia/gpu-egl))

@defproc[(make-egl-gpu-context
          [#:platform platform (or/c 'surfaceless 'device) 'surfaceless]
          [#:device-index device-index exact-nonnegative-integer? 0]
          [#:surface surface (or/c 'surfaceless 'pbuffer) 'surfaceless]
          [#:options options (or/c gpu-context-options? #f) #f]
          [#:gl-interface interface (or/c 'default 'auto 'desktop) 'default])
         gpu-context?]{
Creates an owned desktop-OpenGL context through EGL. This is the package's
headless OpenGL construction route on Linux. Importing the library does not load
EGL or create a context; native platform loading begins when this function is
called.

The @racket['surfaceless] platform requests EGL's surfaceless platform. The
@racket['device] platform selects an enumerated EGL device by
@racket[device-index]. A nonzero device index is rejected with the surfaceless
platform. The binding surface is either no surface or a one-by-one pbuffer; the
pbuffer is not an application render target or a window.

The constructor creates desktop OpenGL, not OpenGL ES. Consequently its explicit
interface selection is limited to @racket['default], @racket['auto], and
@racket['desktop]. If required EGL facilities are missing, the selected device
cannot be used, or the native EGL or Skia context cannot be created, the
constructor raises an exception. There is no GLX, GUI, different-backend, or CPU fallback.
The returned context follows the ownership, thread,
shutdown, and close rules in @secref["skia-gpu-contexts"].

The owned adapter saves and restores a previously current native binding around
activation. It owns its EGL context and optional pbuffer, and destroys them only
after the native Skia context has been destroyed. It does not terminate an EGL
display owned by unrelated native code.
}

@defproc[(make-current-egl-gpu-provider) gpu-provider?]{
Captures the currently bound desktop-EGL context as a borrowed GPU provider.
Call this on the intended owner thread while the desktop OpenGL API, EGL context,
and its draw/read surfaces are current. The result can be passed to
@racket[make-gpu-context].

The provider saves and restores native binding state during each activation but
does not create, destroy, initialize, or terminate the host's EGL objects. The
host must keep them valid until the resulting GPU context is closed. Capturing a
package-owned EGL context to create a second Skia GPU context for the same host
is rejected. The external host may depend on a window or display server even
though this adapter creates neither.
}

@section{Racket OpenGL Hosts}

@defmodule[skia/gpu-racket-gl #:no-declare]
@(declare-exporting skia/gpu-racket-gl #:use-sources (skia/gpu-racket-gl))

@defproc[(make-racket-gl-provider [gl (is-a?/c gl-context<%>)]) gpu-provider?]{
Adapts an existing Racket @racket[gl-context<%>] as an OpenGL GPU provider. The
context must report that it is usable and must expose a current native OpenGL
context when captured. The returned provider borrows @racket[gl]; it does not own
the host window, event loop, or swap operation.

Provider activation uses the host's @racket[call-as-current] operation and checks
both the Racket and native current-context identities. The adapter also supplies
the function resolver needed by explicit GL-interface assembly and external GL
interop. The provider and contexts made from it retain the ordinary creating-
thread restrictions. Closing a Skia GPU context does not close @racket[gl].
}
