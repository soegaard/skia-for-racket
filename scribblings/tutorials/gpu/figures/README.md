# GPU Tutorial Figures

- [metal-reference.png](metal-reference.png) is the committed Metal rendering of
  the shared tutorial scene.
- [metal-reference-placeholder.png](metal-reference-placeholder.png) is the
  explicit fallback illustration used when the real reference is unavailable.

[../eval.rkt](../eval.rkt) chooses and captions these assets. The drawing comes
from [../scene.rkt](../scene.rkt), and [../gpu-offscreen.rkt](../gpu-offscreen.rkt)
provides the explicit Metal rendering entry point. These images do not imply
that a normal manual build initializes or tests a GPU backend.
