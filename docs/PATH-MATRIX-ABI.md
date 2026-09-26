# Pinned path/matrix ABI audit

Baseline: SkiaSharp 3.119.1, Skia submodule
`40f75dc0051d141913c07c20d4c19590c7da0cb7`. This audit is source evidence, not a
claim that the new native calls have been run on the maintainer's machine.

## Two different matrix boundaries

`sk_path_transform`, `sk_path_transform_to_dest`, `sk_shader_with_local_matrix`
and `sk_pathmeasure_get_matrix` use `sk_matrix_t`: nine consecutive floats,
36 bytes, row-major `(xx xy tx yx yy ty p0 p1 p2)`. The shim calls `AsMatrix` /
`ToMatrix`, which explicitly map these named fields to/from `SkMatrix`.

`sk_canvas_get_matrix`, `sk_canvas_set_matrix` and `sk_canvas_concat` instead
use `sk_matrix44_t`: sixteen floats, 64 bytes. Do not pass a nine-float object.
More subtly, the shim's `AsM44` / `ToM44` are reinterpretations of **SkM44**.
SkM44's actual `fMat` storage is column-major. The row-major comment/field names
in the C header therefore do not describe how this pinned canvas shim consumes
the words. The bridge labels its storage by columns/rows rather than repeating
the misleading field names. Its affine word order is:

```text
xx yx 0 0 | xy yy 0 0 | 0 0 1 0 | tx ty 0 1
```

Translation is at byte offsets 48 and 52, not 12 and 28. The doctor first calls
the *existing* `canvas-translate!` and checks its new matrix readback, then checks
new setter raster placement. Tests also read an independently created native
asymmetric shear. These are important: a wrong but self-consistent read/write
conversion could pass a naive round-trip test.

The host-C mirror asserts the two layouts and selected offsets. It does not
link Skia or prove native field interpretation; the independent native tests
are still required.

## Iterators and lifetime

The shim's forceClose and isCloseLine are C **int**, not bool. Next returns an
enum/int and writes at most four points. Only the initialized points for that
verb are read. Conic weight is read only for conic; closing-line state is read
only for a normal line. The end verb is not returned as a segment.

A path remains validated and held by `call-with-owned` for the complete native
iteration. A scoped temporary always destroys the iterator. No user callbacks
run during iteration, and no lazy access to the source survives. Records,
point lists and the sequence's backing list are ordinary immutable Racket data.
The raw iterator is available in this pinned ABI; upstream calls it deprecated,
so a future native upgrade must re-audit this dependency.

Path transforms either mutate a checked source or populate a new owned path.
Shader-local transforms return a referenced shader through `new-owned` and use
`sk_shader_unref`; they retain native dependencies, not caller-owned wrappers.
Measurement output is inspected only on a successful native result.

## Primary sources

- [C canvas declarations](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_canvas.h)
- [Canvas shim](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_canvas.cpp)
- [C layouts](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_types.h)
- [ABI conversion helpers](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_types_priv.h)
- [SkM44 storage and asM33](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/core/SkM44.h)
- [C path/iterator/measure declarations](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_path.h)
- [Path iterator semantics](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/core/SkPath.h)
- [Path/measurement shim](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_path.cpp)
- [Shader declarations](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_shader.h)
- [SVG serializer limitations](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/svg/SkSVGDevice.cpp)
