#lang scribble/manual

@(require (for-label racket/base racket/contract racket/class racket/draw
                     skia/gpu skia/gpu-egl skia/gpu-racket-gl))

@title[#:tag "skia-gpu-opengl-hosts"]{OpenGL Hosts}

An OpenGL @tech{GPU context} needs a host that can make the matching native
OpenGL context current. The operations here either construct an owned EGL host
or adapt an existing host. They do not create a presentation window, swap
buffers, or turn a host-owned context into a package-owned one.

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
@racket['desktop]. Missing EGL facilities, a mismatched device, context creation
failure, or Ganesh construction failure raises; there is no GLX, GUI, different
backend, or CPU fallback. The returned context follows the ownership, thread,
shutdown, and close rules in @secref["skia-gpu-contexts"].

The owned adapter saves and restores a previously current native binding around
activation. It owns its EGL context and optional pbuffer, and destroys them only
after Ganesh has been destroyed. It does not treat each context as permission to
terminate an EGL display owned by unrelated native code.
}

@defproc[(make-current-egl-gpu-provider) gpu-provider?]{
Captures the currently bound desktop-EGL context as a borrowed GPU provider.
Call this on the intended owner thread while the desktop OpenGL API, EGL context,
and its draw/read surfaces are current. The result can be passed to
@racket[make-gpu-context].

The provider saves and restores native binding state during each activation but
does not create, destroy, initialize, or terminate the host's EGL objects. The
host must keep them valid until the resulting GPU context is closed. Capturing a
package-owned EGL context as a second Ganesh domain is rejected. This operation
does not claim that the external host is headless or display-server-free.
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
