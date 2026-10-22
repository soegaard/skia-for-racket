#lang scribble/manual

@(require scribble/eval
          (for-label racket/base racket/contract skia/native-capabilities skia))

@(define abi-eval (make-base-eval))
@(abi-eval '(require skia/native-capabilities))

@title[#:tag "skia-native-libraries"]{Native Libraries and Capabilities}

@defmodule[skia/native-capabilities #:no-declare]
@(declare-exporting skia skia/native-capabilities #:use-sources (skia/native-capabilities))

Use these functions to diagnose native-library installation and compatibility
problems. @racket[skia-check!] checks Skia, while @racket[harfbuzz-check!] checks
the separate library used for text shaping. Both load the selected native
library and raise an exception if it is unavailable or incompatible.

Importing a public Racket library or reading the installed ABI catalogue does
not perform these checks. The ABI describes the native functions and data
layouts expected by the bindings. Compatible layouts and available function
symbols do not by themselves establish that a GPU backend can be created or
that it uses hardware acceleration.

The loaded Racket modules select the Skia library on first native use. CPU and
GPU operations then use that same library. Set @envvar{RACKET_SKIA_LIBRARY}
before first use to select an explicit library file. Otherwise, the search tries
the packaged platform library, then the system library search. Library selection
and compatibility-check results are cached; changing an environment variable
afterward does not switch the selected library.

@local-table-of-contents[#:style 'immediate-only]

@section{Skia Compatibility Checks}

@(declare-exporting skia)

The native installer supplies SkiaSharp 3.119.1 libraries based on Skia m119.
Use @racket[skia-native-version] to inspect the loaded library's milestone and
increment. That value does not report the SkiaSharp package version or establish
which drawing operations a document writer supports.

@defproc[(skia-check!)
          void?]{
Loads the selected library, checks its supported ABI and Racket foreign-structure layouts, and
resolves the required CPU entry points. If the library cannot be loaded, its ABI
or structure layouts are incompatible, or a required CPU entry point is missing,
the function raises an exception with loader or compatibility diagnostics.
It does not create a surface, open a window, probe all optional GPU symbols, or certify a
working GPU backend.
}

@defproc[(skia-available?)
          boolean?]{
Runs @racket[skia-check!] and returns @racket[#t] on success. An ordinary failure exception is
caught and produces @racket[#f]. Calling this function can load the native library
and check compatibility; it does not merely check whether a file exists.
Use @racket[skia-check!] to receive the diagnostic exception instead of @racket[#f].
}

@defproc[(skia-native-version)
          string?]{
Returns the loaded library's milestone and increment as a string such as @racket["119.0"], after
@racket[skia-check!] succeeds. This is not the NuGet package version and does not uniquely
identify the binary or its optional backend configuration.
}

@defproc[(skia-native-library-path)
          path-string?]{
Returns the name or path used to load the selected library, after @racket[skia-check!] succeeds.
This need not be the fully resolved path of the file actually loaded.
}

@section{HarfBuzz Compatibility Checks}

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
shaping entry points. If the library cannot be loaded, its version is incompatible,
or a required shaping entry point is missing, the function raises an exception.
The function does not locate fonts, shape text, or guarantee font coverage.
}

@defproc[(harfbuzz-available?)
          boolean?]{
Runs @racket[harfbuzz-check!] and returns @racket[#t] on success or @racket[#f] after catching
an ordinary failure exception. Use the checking function when the reason for failure is needed.
}

@defproc[(harfbuzz-native-version)
          string?]{
Returns the loaded native HarfBuzz version as a dotted major/minor/micro string
after @racket[harfbuzz-check!] succeeds. This is not the package version.
}

@defproc[(harfbuzz-native-library-path)
          path-string?]{
Returns the name or path used to load the selected HarfBuzz library, after
@racket[harfbuzz-check!] succeeds.
This need not be the fully resolved path of the file actually loaded.
}

@section{Installed ABI Catalogue}

The catalogue describes the native interfaces supported by this version of the
Racket package. Use it to inspect compatibility requirements without loading
Skia. To inspect the library actually loaded, use the diagnostics below.

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
          (listof (and/c hash? immutable?))]{
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
Checks library compatibility with @racket[skia-check!] and returns an immutable
hash table describing the selected library and the checks that succeeded.
Use this report when diagnosing which native library was selected and whether
it matches the package's expected interface.

The report has the following keys:

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Key} @bold{Value and meaning})
  (list @racket['schema] @elem{@racket[1], the report format version.})
  (list @racket['default_package_version]
        @elem{A string: the configured @racket[native-package-version].})
  (list @racket['library_request]
        @elem{A string: the name or path used to load the library, as in
              @racket[skia-native-library-path].})
  (list @racket['milestone]
        @elem{An exact nonnegative integer: the native milestone.})
  (list @racket['increment]
        @elem{An exact nonnegative integer: the native increment.})
  (list @racket['native_version]
        @elem{A string combining milestone and increment, as in
              @racket[skia-native-version].})
  (list @racket['pointer_bytes]
        @elem{An exact positive integer: the size of a native pointer in bytes.})
  (list @racket['profile]
        @elem{An immutable hash table: the matching supported ABI profile from
              @racket[native-abi-profiles].})
  (list @racket['required_cpu_symbols_resolved]
        @elem{@racket[#t]: all required CPU function symbols were found.})
  (list @racket['racket_layouts_checked]
        @elem{@racket[#t]: the Racket foreign-structure layouts passed the ABI checks.})
  (list @racket['required_cpu_symbol_count]
        @elem{An exact nonnegative integer: the number of required CPU symbols checked.})
  (list @racket['package_identity_from_version_functions]
        @elem{@racket[#f]: the native version does not uniquely identify the package.})
  (list @racket['optional_gpu_symbols_probed]
        @elem{@racket[#f]: optional GPU symbols were not checked by this operation.})
  (list @racket['backend_creation_verified]
        @elem{@racket[#f]: GPU backend creation was not tested.})
  (list @racket['hardware_acceleration_verified]
        @elem{@racket[#f]: hardware acceleration was not tested.}))]

The three GPU flags mean that the corresponding properties have not been
verified, not that GPU support is unavailable. This operation does not render
anything or create a GPU context.
}

@defproc[(skia-native-symbol-inventory [names (listof symbol?)])
          (listof (and/c hash? immutable?))]{
Runs @racket[skia-check!], then checks the requested symbol addresses in that same loaded library.
Results preserve input order, including duplicates. Each immutable result hash
table has a @racket['name] key whose value is the symbol's name as a string, and
an @racket['available] key whose boolean value indicates whether the symbol was
found. The requested symbols are looked up but not called.

An address does not establish the function signature, ownership contract, presence of a real
implementation rather than a stub, or usable hardware. This operation does not bypass the
supported-ABI checks or return raw pointers.
}
