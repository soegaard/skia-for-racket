# Live FFI callback probe

This directory isolates the live-port callback boundary from the full Skia
integration. It supplies reproducible inputs and checks callback execution,
partial transfers, interruption, and cleanup.

| File | Contents |
| --- | --- |
| [fixtures.py](fixtures.py) | Generates a 32-by-24 four-color RGBA image, an uncompressed PNG, and a deterministic 200,003-byte stream payload. These are inputs, not evidence of native execution. |
| [probe.rkt](probe.rkt) | Loads the selected probe library, runs callback tests, saves binary artifacts, and publishes transfer/destruction counts in a JSON receipt. |

[tools/live_ffi_probe.py](../../tools/live_ffi_probe.py) orchestrates this probe.
Actual Skia integration is covered separately by
[live-stream-native-test.rkt](../live-stream-native-test.rkt) and
[tools/validate-live-streams.py](../../tools/validate-live-streams.py).

The caller supplies the library, fixture directory, output directory, and
invocation token. Generated data belongs in that output directory, not here.
