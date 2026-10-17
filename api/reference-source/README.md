# Archived Reference source fixture

This directory contains a preserved source snapshot used to test Reference
coverage validation, not an alternative implementation of the public API.

- [gpu.rkt.b64](gpu.rkt.b64) is a Base64-encoded historical `gpu.rkt` snapshot.
  The `R4bSourceAdditionTests` in [test-reference.py](../../tools/test-reference.py)
  use it to check direct exports, keyword signatures, and pinned Git blob
  integrity, including rejection of missing or corrupt snapshots.

The current public inventory reflects the GPU export directly. This archived
fixture is not current execution evidence and should not be reformatted or
regenerated as part of source-style cleanup. See the parent
[API inventory guide](../README.md) for current manifests.
