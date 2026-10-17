# Direct3D 12 ABI probes

These probes compare 64-bit Direct3D declarations with native layout and calling
conventions. They are validation tools, not the renderer.

| File | Contents |
| --- | --- |
| [CMakeLists.txt](CMakeLists.txt) | Builds the layout executable and shared by-value fixture; adds SDK GUID checks on Windows. |
| [check.c](check.c) | Checks the context mirror, SDK adapter/queue structures, offsets, and enum values. |
| [guid.cpp](guid.cpp) | Compares COM interface GUIDs with Windows SDK declarations. |
| [byvalue.c](byvalue.c) | Exports an echo function taking the context structure by value to expose argument-passing mistakes. |

[check-d3d12-call.rkt](../check-d3d12-call.rkt) calls the shared fixture through
Racket's FFI. [ci-d3d12.py](../ci-d3d12.py) and
[validate-d3d12.py](../validate-d3d12.py) coordinate the Windows workflow.
Non-Windows mirror checks cannot establish Windows SDK compatibility. Keep
build products in the selected build/evidence directory.
