# Runtime-effect ABI and ownership

Pinned source: mono/skia `40f75dc0051d141913c07c20d4c19590c7da0cb7`, corresponding
to the installed SkiaSharp 3.119.1 package. This pass adds 18 required callouts:
three compilers, one effect destructor, seven reflection queries, three instance
factories, and four blender/paint operations. Totals are 319 Skia and 27 HarfBuzz.

## Reflection records

The two C records contain an initial C++ `std::string_view` representation, then
ordinary scalar fields. The wrapper deliberately does **not** interpret or
dereference the view's two machine words. Name strings are obtained through the
separate native `get_uniform_name` / `get_child_name` functions and copied before
the effect can close. This avoids depending on pointer/length ordering inside
the particular C++ standard library.

| Record / field | 64-bit bytes or offset | 32-bit bytes or offset |
|---|---:|---:|
| Uniform record size | 40 | 24 |
| Uniform offset field | 16 | 8 |
| Uniform type | 24 | 12 |
| Uniform count | 28 | 16 |
| Uniform flags | 32 | 20 |
| Child record size | 24 | 16 |
| Child type | 16 | 8 |
| Child index | 20 | 12 |

`tools/check-runtime-abi.c` checks a host-C layout mirror. It is not a check of
the actual installed binary. Native reflection tests additionally use a mixed
uniform program with offsets 0, 4, 16, 24, 40, 44 and total size 60.

The unchecked native from-name functions are not bound: the pinned shim can
dereference a null result for an unknown name. This wrapper validates counts,
queries only in-range indices, and resolves user-provided names in Racket.

## Uniform and local-matrix memory

Every runtime numeric component occupies four bytes, including `half`. Float3
and arrays have no GPU-style stride padding. Integer values are signed int32;
matrix uniforms are column-major. The Racket packer uses actual reflected offsets
and native endianness and rejects unexpected layout/flags before copying data.

The shader factory's separate `localMatrix` argument uses the existing nine-float,
row-major geometry M33, not the canvas M44 and not the matrix-uniform byte order.
It is temporary for the synchronous call.

## Resource lifetime

A compiled effect is one ref-counted owned resource. Reflection failure closes
it before propagating the exception. Temporary compiler/error/name SkStrings
are scoped. Compilation failures preserve copied source and error text.

Uniform bytes are copied to native SkData. Each factory refs that data and all
child flattenables, so the C pointer array is transient. The Racket effect and
child handles are checked and held during construction. No Racket-managed byte
buffer, list, vector, or native iterator is retained by Skia.

A resulting shader, color filter, or blender retains the compiled program and
its bound inputs. Closing their original Racket wrappers is safe after successful
construction. Native paint setters retain the supplied blender. The paint getter
returns `refBlender().release()`, already one owned reference, not a borrowed
pointer. `#f` denotes the paint's implicit source-over default.

The common resource implementation recognizes runtime-effect and blender records;
`with-skia` and explicit/GC cleanup use the existing ownership cells. Only the
immutable reflection/source snapshots may be read after close or cross-thread.
Native construction, drawing, and destruction remain thread-confined.
