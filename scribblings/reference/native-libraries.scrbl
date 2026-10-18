#lang scribble/manual

@(require scribble/eval
          (for-label racket/base racket/contract skia/native-capabilities skia))

@(define abi-eval (make-base-eval))
@(abi-eval '(require skia/native-capabilities))

@title[#:tag "skia-native-libraries"]{Native Libraries and Capabilities}

@defmodule[skia/native-capabilities #:no-declare]
@(declare-exporting skia skia/native-capabilities #:use-sources (skia/native-capabilities))

Native availability checks explicitly load and preflight libraries. Importing a public library or
reading the installed ABI catalogue does not establish native availability. Symbol presence, ABI
compatibility, successful backend creation, and hardware acceleration are separate claims.

The Skia library is selected once per process-local module instance and shared with its lazy GPU
registries. Set @envvar{RACKET_SKIA_LIBRARY} before the first native use to select an explicit
library file. The default search uses the packaged platform library and the system library
search. Selection and preflight results are cached; changing an environment variable afterward
is not a supported library-switching operation.

@local-table-of-contents[#:style 'immediate-only]

@section{Skia Preflight}

@(declare-exporting skia)

@defproc[(skia-check!)
          void?]{
Loads the selected library, checks its supported ABI and Racket foreign-structure layouts, and
resolves the required CPU entry points. Failures raise with loader or compatibility diagnostics.
It does not create a surface, open a window, probe all optional GPU symbols, or certify a
working GPU backend.
}

@defproc[(skia-available?)
          boolean?]{
Runs @racket[skia-check!] and returns @racket[#t] on success. An ordinary failure exception is
caught and produces @racket[#f]. This is an active load/preflight attempt, not a
side-effect-free search for a filename. Use @racket[skia-check!] to receive the
diagnostic exception instead of @racket[#f].
}

@defproc[(skia-native-version)
          string?]{
Returns the loaded library's milestone and increment as a string such as @racket["119.0"], after
preflight. This is not the NuGet package version and does not uniquely identify the binary or
its optional backend configuration.
}

@defproc[(skia-native-library-path)
          path-string?]{
Returns the name or path used to load the selected library, after preflight.
This need not be the fully resolved path of the file actually loaded.
}

@section{HarfBuzz Preflight}

@(declare-exporting skia)

HarfBuzz is selected separately from Skia. Set @envvar{RACKET_HARFBUZZ_LIBRARY} before its first
use to override the library path. The supported library is HarfBuzzSharp 8.3.1.2 with native
HarfBuzz version 8.3.1. A successful Skia check alone does not establish shaping support.

@defthing[harfbuzz-package-version string?]{
The expected HarfBuzzSharp package version, @racket["8.3.1.2"]. Reading this immutable string
does not load or verify a library.
}

@defproc[(harfbuzz-check!)
          void?]{
Loads the selected HarfBuzz library, verifies its native version, and resolves the required
shaping entry points. Incompatible versions or missing symbols raise. The function does not
locate fonts, shape text, or guarantee font coverage.
}

@defproc[(harfbuzz-available?)
          boolean?]{
Runs @racket[harfbuzz-check!] and returns @racket[#t] on success or @racket[#f] after catching
an ordinary failure exception. Use the checking function when the reason for failure is needed.
}

@defproc[(harfbuzz-native-version)
          string?]{
Returns the loaded native HarfBuzz version as a dotted major/minor/micro string after preflight,
not the package version.
}

@defproc[(harfbuzz-native-library-path)
          path-string?]{
Returns the name or path used to load the selected HarfBuzz library, after preflight.
This need not be the fully resolved path of the file actually loaded.
}

@section{Installed ABI Catalogue}

@subsection{Default Package}

@(declare-exporting skia)

@defthing[native-package-version string?]{
The default SkiaSharp package version configured in the installed Skia package, as an immutable
string. It is available without native loading. It describes the default package selection, not
necessarily a file selected by an override.
}

@subsection{Catalogue Queries}

@(declare-exporting skia/native-capabilities #:use-sources (skia/native-capabilities))

@defproc[(native-abi-catalog)
          (and/c hash? immutable?)]{
Returns the immutable installed ABI catalogue. Nested hash tables and strings are immutable too. It
records supported ABI profiles, layout sizes, and reviewed expectations. Reading it loads no
native library and performs no network request. A profile in the catalogue is a compatibility
policy, not a runtime observation.
}

@defproc[(native-abi-profiles)
          (listof hash?)]{
Returns the supported profiles from the installed catalogue as immutable hash tables. The
list is not a list of libraries found on the machine. It does not verify optional entry points
or backend creation.
}

@examples[#:eval abi-eval
  (eval:check (immutable? (native-abi-catalog)) #t)
  (eval:check (pair? (native-abi-profiles)) #t)]

@close-eval[abi-eval]

@section{Loaded-Library Diagnostics}

@(declare-exporting skia/native-capabilities #:use-sources (skia/native-capabilities))

@defproc[(skia-native-capabilities)
          (and/c hash? immutable?)]{
Runs Skia preflight and returns its report with the selected library name or path, native version,
supported profile, pointer size, and required CPU symbol/layout results. The flags for optional GPU symbol
probing, backend creation, and hardware acceleration remain false: this operation has not
established those properties. The version functions do not certify package identity. The report
is not a rendering test.
}

@defproc[(skia-native-symbol-inventory [names (listof symbol?)])
          (listof hash?)]{
Runs Skia preflight, then checks the requested symbol addresses in that same loaded library.
Results preserve input order, including duplicates. Each immutable result hash table contains a string
@racket['name] and boolean @racket['available]. Missing symbols yield false; they are not
invoked.

An address does not establish the function signature, ownership contract, presence of a real
implementation rather than a stub, or usable hardware. This operation does not bypass the
supported-ABI checks or return raw pointers.
}
