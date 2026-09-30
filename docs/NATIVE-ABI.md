# Native ABI policy and diagnostics — 0.47

## Scope and defaults

The accepted input baseline is commit
`1cd0599a463c00aa50dcdef1a3f1114ca12cdf10`. This release keeps the default
SkiaSharp package at **3.119.1**, the expected default native version at
**119.0**, and HarfBuzzSharp at **8.3.1.2**. It does not enable an m153 runtime,
Graphite, Direct3D, a new GPU fallback, or a different ownership policy.

`private/native-default-version.txt` is the single operational Skia package
pin read by the Racket metadata layer and both Unix and Windows installers.
`private/native-abi.json` records supported ABI profiles, layout sizes,
version-sensitive contracts and the separately pinned investigation candidate.
Release histories and regression expectations intentionally retain literal
historical versions; they are not alternate sources of the installation pin.

The current profile admits milestone 119 with a nonnegative increment, as the
previous milestone gate did, and explicitly requires eight-byte pointers. This
is a declared ABI-family policy, not independent authentication of a binary or
proof that every build reporting 119 has identical semantics. The required
symbol preflight, existing C mirrors and real rendering tests still matter.

## Loading and guarantees

Importing `skia`, the optional GPU modules, or `skia/native-capabilities` does
not load a native library or GUI. Metadata reads are local, installed source
file reads. There is no network access in the Racket loader.

The first actual native use selects one library through a shared `delay/sync`.
Selection preserves the existing explicit `RACKET_SKIA_LIBRARY` override,
platform native directory and system-library fallback. An explicit override
never falls through to a different library. Only the two scalar version
functions are called before profile selection. An unsupported ABI raises
`exn:fail:native-abi` before versioned graphics structures are passed to it.
There is no environment switch to bypass this check.

CPU preflight checks the sizes of all 26 declared Racket FFI structures against
the profile, then resolves the complete original CPU binding registry. Its
pre-allocation/destructor-resolution contract is unchanged. The layout check
measures **our declarations**; it cannot introspect an arbitrary shared
library's private C++ layouts. Existing independent C mirror tests remain.

All six optional GPU registries now use the exact same checked FFI library
handle. They do not reopen its filename. They retain their independent lazy
symbol checks, so missing Metal or other optional symbols cannot become new
CPU-only requirements. Retained-resource affinity, owner-thread rules,
submission, completion and teardown are untouched.

The profile's `contracts` section documents why m119-specific representation
choices remain. It does not automatically adapt them to another milestone.
Adding a profile requires implementing and reviewing those adapters first.

## Explicit diagnostic API

```racket
#lang racket/base
(require skia/native-capabilities)

;; Pure metadata, without loading libSkiaSharp:
(native-abi-profiles)
(native-abi-catalog)
native-package-version

;; Explicitly load/preflight the selected supported library:
(define capabilities (skia-native-capabilities))
(hash-ref capabilities 'native_version)
(hash-ref capabilities 'profile)

;; Addresses are resolved but these named functions are NOT invoked:
(skia-native-symbol-inventory
 '(sk_version_get_milestone sk_graphite_backend_is_available))
```

`skia-native-capabilities` returns an immutable hash with default package pin,
bootstrap native version, pointer width, selected profile, library request,
CPU preflight count and layout-check flags. It does not claim to derive the
loaded NuGet package identity from native version functions. A system-library
request is not an independently resolved absolute library path.

The backend and hardware verification flags are false because this diagnostic
does not create or render through a backend. `optional_gpu_symbols_probed` is
false for this particular report, not a claim about everything previously done
in the process. An inventory call returns a list of immutable hashes with
string `name` and Boolean `available` fields. Its input must be a list of
symbols. Address availability does not establish a signature, implementation,
device, rendering result or acceleration.

`native-abi-catalog` returns immutable nested metadata. `native-abi-profiles`
returns its supported profiles. The raw handle and the profile-selection
functions remain private plumbing, not a public graphics API.

## Isolated binary investigation

The tool is for **trusted native binaries only**. Loading a DLL/shared library
executes its native initializers; a subprocess is crash containment, not a
security sandbox for hostile code.

```sh
python3 tools/native-abi-lab.py \
  --candidate --racket "$RACKET" \
  --output output/native-abi-candidate-$(date +%Y%m%d-%H%M%S)
```

This selects the exact catalogued **4.153.1** package for the Python host's
supported architecture. The package identity/version and fixed native member
are checked. Size bounds, duplicate relevant members, native symlinks and
DTD/entity manifests are checked before the fixed member is extracted.
Unrelated archive paths are never extracted. The download uses HTTPS with
bounded retries. The tool never writes into the installed native directory.

For an offline package add `--archive /path/to/package.nupkg`. An optional
`--sha256` checks a digest obtained independently. The recorded archive and
library hashes alone are provenance observations, not independent authenticity.
Native archives/binaries are not copied into retained CI artifacts.

A disposable Python child calls the two scalar version functions and resolves
the actual declarations from all seven source registries. For the reviewed
candidate milestone, it may additionally call the documented scalar Graphite
compiled-backend query. It never invokes an inventoried graphics function,
creates a GPU context, or passes a graphics structure.

The candidate gate then runs the selected **real Racket executable** against
the candidate and requires the typed unsupported-milestone rejection. An
unreadable binary, missing bootstrap symbol, crash, timeout, wrong milestone or
ordinary loader failure is a failure, not an acceptable rejection. The output
must be a new directory to prevent stale success reuse. Reports and child logs
are retained on errors.

To inventory a supported or unknown local binary without downloading:

```sh
python3 tools/native-abi-lab.py \
  --library /absolute/path/to/libSkiaSharp.dylib \
  --output output/native-abi-local-$(date +%Y%m%d-%H%M%S)
```

A successful local inventory is `observed-not-a-runtime-validation`. A
successful candidate negative gate is
`passed-investigation-candidate-rejected`. Neither means the candidate can
render through this wrapper. No auto-migration is performed.

## Validation and CI

The existing required matrix and aggregate are retained. Every installed
package lane records the native ABI doctor's positive baseline preflight.
The Linux x64/Racket 9.3 CPU lane additionally runs the candidate investigation
and real-Racket negative gate, without `continue-on-error` or optional skips.
Other CPU lanes and both required EGL lanes continue testing the original
native pin. Existing EGL workload sizes and report schemas are unchanged.

New source cases comprise 30 pure Racket cases and 10 native Racket cases.
`tools/test-native-abi.py` has Python policy/archive/reader tests, real
subprocess tests using tiny compiled **C fixtures**, and full-checkout
integration assertions. C fixtures are not Skia and cannot establish Skia
compatibility. The source CI lane explicitly installs its C compiler.

Local acceptance, from the checkout after applying the delivery:

```sh
export RACKET="/Applications/Racket v9.3.0.2/bin/racket"
export RACO="/Applications/Racket v9.3.0.2/bin/raco"
export PYTHONDONTWRITEBYTECODE=1
python3 tools/test-native-abi.py &&
"$RACO" make main.rkt native-capabilities.rkt tools/native-abi-doctor.rkt run-tests.rkt &&
"$RACKET" tools/native-abi-doctor.rkt &&
"$RACKET" run-tests.rkt &&
python3 tools/native-abi-lab.py --candidate --racket "$RACKET" \
  --output "output/native-abi-0.47-$(date +%Y%m%d-%H%M%S)" &&
SKIA_SOURCE_SUMS_MODE=check bash tools/validate-gpu.sh &&
python3 tools/update-source-sums.py --check
```

The desktop GPU validator retains its existing interactive/visual inspection
requirements. A local run is not a hosted macOS/Windows/Linux matrix result.
The delivery's Python/C-fixture checks have executed; Racket expansion, real
Skia candidate probing, baseline rendering and the new CI matrix require host
execution. Do not relabel those unexecuted checks as passed.
