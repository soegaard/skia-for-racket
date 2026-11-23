#lang racket/base

;;;
;;; Runtime Shader Effects
;;;

;; Compiles SkSL effects, reflects uniforms and children, and constructs shader, filter, or blender
;; instances.
;; This public runtime layer checks user-supplied effect data before allocating and connecting the
;; corresponding native resources.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe racket/list
         "private/core.rkt" "private/check.rkt" "private/types.rkt"
         "private/native.rkt" "private/lifetime.rkt" "matrix.rkt"
         (prefix-in meta: "private/runtime-util.rkt")
         (prefix-in raw: (submod "private/core.rkt" runtime-internals)))
(provide runtime-effect? make-runtime-effect runtime-effect-kind runtime-effect-source
         runtime-effect-uniform-byte-size runtime-effect-uniforms runtime-effect-children
         runtime-effect-uniform-bytes
         runtime-effect->shader runtime-effect->color-filter runtime-effect->blender
         runtime-uniform? runtime-uniform-name runtime-uniform-offset runtime-uniform-type
         runtime-uniform-count runtime-uniform-byte-size runtime-uniform-array?
         runtime-uniform-color? runtime-uniform-half-precision?
         runtime-child? runtime-child-name runtime-child-kind runtime-child-index
         exn:fail:skia-sksl? exn:fail:skia-sksl-kind
         exn:fail:skia-sksl-source exn:fail:skia-sksl-diagnostics
         blender? make-blend-mode-blender paint-blender paint-set-blender!)

;; Predicates and immutable reflection snapshots never enter native code.

;;;
;;; Effect, Uniform, Child, and Diagnostic Accessors
;;;

; runtime-effect? : any/c -> boolean?
;   Returns #t for a runtime-effect resource and #f otherwise.
(define runtime-effect? raw:runtime-effect-resource?)

; blender? : any/c -> boolean?
;   Returns #t for a blender resource and #f otherwise.
(define blender? raw:blender-resource?)

; runtime-uniform? : any/c -> boolean?
;   Returns #t for a detached runtime-uniform description and #f otherwise.
(define runtime-uniform? meta:runtime-uniform?)

; runtime-uniform-name : runtime-uniform? -> string?
;   Returns the immutable, nonempty uniform name used by binding dictionaries.
(define runtime-uniform-name meta:runtime-uniform-name)

; runtime-uniform-offset : runtime-uniform? -> exact-nonnegative-integer?
;   Returns the byte offset in the effect uniform buffer.
(define runtime-uniform-offset meta:runtime-uniform-offset)

; runtime-uniform-type : runtime-uniform? -> (or/c 'float 'float2 'float3 'float4 'float2x2
;   'float3x3 'float4x4 'int 'int2 'int3 'int4)
;   Returns the reflected numeric type.
(define runtime-uniform-type meta:runtime-uniform-type)

; runtime-uniform-count : runtime-uniform? -> exact-positive-integer?
;   Returns the array length, or one for a nonarray uniform.
(define runtime-uniform-count meta:runtime-uniform-count)

; runtime-uniform-byte-size : runtime-uniform? -> exact-positive-integer?
;   Returns the complete byte size, including all array elements.
(define runtime-uniform-byte-size meta:runtime-uniform-byte-size)

; runtime-uniform-array? : runtime-uniform? -> boolean?
;   Returns whether the declaration is an array.
(define runtime-uniform-array? meta:runtime-uniform-array?)

; runtime-uniform-color? : runtime-uniform? -> boolean?
;   Returns whether the declaration has layout(color).
(define runtime-uniform-color? meta:runtime-uniform-color?)

; runtime-uniform-half-precision? : runtime-uniform? -> boolean?
;   Returns whether the declaration carries the half-precision flag.
(define runtime-uniform-half-precision? meta:runtime-uniform-half-precision?)

; runtime-child? : any/c -> boolean?
;   Returns #t for a detached runtime-child description and #f otherwise.
(define runtime-child? meta:runtime-child?)

; runtime-child-name : runtime-child? -> string?
;   Returns the immutable, nonempty child name used by the child-binding hash.
(define runtime-child-name meta:runtime-child-name)

; runtime-child-kind : runtime-child? -> (or/c 'shader 'color-filter 'blender)
;   Returns the required resource kind.
(define runtime-child-kind meta:runtime-child-kind)

; runtime-child-index : runtime-child? -> exact-nonnegative-integer?
;   Returns the zero-based reflected slot index.
(define runtime-child-index meta:runtime-child-index)

; exn:fail:skia-sksl? : any/c -> boolean?
;   Returns #t for an SkSL compilation exception and #f otherwise.
(define exn:fail:skia-sksl? meta:exn:fail:skia-sksl?)

; exn:fail:skia-sksl-kind : exn:fail:skia-sksl? -> (or/c 'shader 'color-filter 'blender)
;   Returns the stage requested by the unsuccessful compilation.
(define exn:fail:skia-sksl-kind meta:exn:fail:skia-sksl-kind)

; exn:fail:skia-sksl-source : exn:fail:skia-sksl? -> string?
;   Returns the copied source string supplied to the compiler.
(define exn:fail:skia-sksl-source meta:exn:fail:skia-sksl-source)

; exn:fail:skia-sksl-diagnostics : exn:fail:skia-sksl? -> string?
;   Returns the immutable native compiler diagnostics.
(define exn:fail:skia-sksl-diagnostics meta:exn:fail:skia-sksl-diagnostics)


;;;
;;; Effect Ownership and Native Reflection
;;;

; checked-effect : symbol? any/c -> runtime-effect?
;   Checks the public runtime-effect wrapper before metadata or handle access.
(define (checked-effect who e)
  (unless (runtime-effect? e) (raise-argument-error who "runtime-effect?" e))
  e)

; effect-h : symbol? runtime-effect? -> (or/c owned? domain-resource?)
;   Retrieves the managed native handle from a checked runtime effect.
(define (effect-h who e)
  (raw:runtime-effect-resource-handle (checked-effect who e)))

; blender-h : symbol? blender? -> (or/c owned? domain-resource?)
;   Checks the blender wrapper and retrieves its managed native handle.
(define (blender-h who b)
  (unless (blender? b) (raise-argument-error who "blender?" b))
  (raw:blender-resource-handle b))

; runtime-effect-kind : runtime-effect? -> (or/c 'shader 'color-filter 'blender)
;   Returns the stage for which the effect was compiled.
(define (runtime-effect-kind e)
  (raw:runtime-effect-resource-kind (checked-effect 'runtime-effect-kind e)))

; runtime-effect-source : runtime-effect? -> (and/c string? immutable?)
;   Returns the stored immutable source string.
(define (runtime-effect-source e)
  (raw:runtime-effect-resource-source (checked-effect 'runtime-effect-source e)))

; runtime-effect-uniform-byte-size : runtime-effect? -> exact-nonnegative-integer?
;   Returns the size of the reflected uniform buffer in bytes.
(define (runtime-effect-uniform-byte-size e)
  (raw:runtime-effect-resource-byte-size (checked-effect 'runtime-effect-uniform-byte-size e)))

; runtime-effect-uniforms : runtime-effect? -> (listof runtime-uniform?)
;   Returns the stored ordered list of detached uniform descriptions.
(define (runtime-effect-uniforms e)
  (raw:runtime-effect-resource-uniforms (checked-effect 'runtime-effect-uniforms e)))

; runtime-effect-children : runtime-effect? -> (listof runtime-child?)
;   Returns the stored ordered list of detached child-slot descriptions.
(define (runtime-effect-children e)
  (raw:runtime-effect-resource-children (checked-effect 'runtime-effect-children e)))

; runtime-count : symbol? exact-nonnegative-integer? exact-positive-integer? ->
;   exact-nonnegative-integer?
;   Bounds native reflection counts by the ABI integer range and logical metadata byte budget.
(define (runtime-count who count record-size)
  (unless (and (exact-nonnegative-integer? count) (<= count #x7fffffff)
               (<= (* count record-size) (current-skia-byte-limit)))
    (error who "native reflection count is invalid or exceeds current-skia-byte-limit"))
  count)

; reflect-effect : symbol? cpointer? -> (values integer? list? list?)
;   Copies and validates uniform and child reflection metadata without borrowing native string
;   views.
(define (reflect-effect who ep)
  (define total (sk_runtimeeffect_get_uniform_byte_size ep))
  (unless (and (zero? (modulo total 4)) (<= total (current-skia-byte-limit)))
    (error who "native uniform size is misaligned or exceeds current-skia-byte-limit"))
  (define nu (runtime-count who (sk_runtimeeffect_get_uniforms_size ep)
                             (ctype-sizeof _sk-runtime-uniform)))
  (define nc (runtime-count who (sk_runtimeeffect_get_children_size ep)
                             (ctype-sizeof _sk-runtime-child)))
  ;; Bound a logical metadata payload, not a promise to bound Skia's total heap.
  (define charged (+ (* nu (ctype-sizeof _sk-runtime-uniform))
                     (* nc (ctype-sizeof _sk-runtime-child))))
  (when (> charged (current-skia-byte-limit))
    (error who "reflection metadata exceeds current-skia-byte-limit"))
  (define (charge-name! name)
    (set! charged (+ charged (bytes-length (string->bytes/utf-8 name))))
    (when (> charged (current-skia-byte-limit))
      (error who "reflection metadata exceeds current-skia-byte-limit")))
  (raw:call-with-native-temporary
   who 'runtime-name sk_string_new_empty sk_string_destructor
   (lambda (np)
     (define uniforms
       (for/list ([i (in-range nu)])
         (define u (make-sk-runtime-uniform 0 0 0 0 0 0))
         (sk_runtimeeffect_get_uniform_from_index ep i u)
         ;; Do not read the borrowed C++ string_view words in U.
         (sk_runtimeeffect_get_uniform_name ep i np)
         (define name (raw:copy-sk-string who np))
         (charge-name! name)
         (meta:checked-runtime-uniform
          who name (sk-runtime-uniform-offset u) (sk-runtime-uniform-type u)
          (sk-runtime-uniform-count u) (sk-runtime-uniform-flags u) total)))
     (define children
       (for/list ([i (in-range nc)])
         (define child (make-sk-runtime-child 0 0 0 0))
         (sk_runtimeeffect_get_child_from_index ep i child)
         (sk_runtimeeffect_get_child_name ep i np)
         (define name (raw:copy-sk-string who np))
         (charge-name! name)
         (meta:checked-runtime-child who name (sk-runtime-child-type child)
                                     (sk-runtime-child-index child))))
     (meta:validate-runtime-layout who total uniforms children)
     (values total uniforms children))))

; make-runtime-effect : string? [#:kind (or/c 'shader 'color-filter 'blender)] -> runtime-effect?
;   Compiles a nonempty, NUL-free SkSL source string for the selected stage and returns an owned
;   effect.
(define (make-runtime-effect source #:kind [kind 'shader])
  (define who 'make-runtime-effect)
  (meta:runtime-kind who kind)
  (define-values (text encoded) (meta:runtime-source who source))
  (define compile
    (case kind [(shader) sk_runtimeeffect_make_for_shader]
               [(color-filter) sk_runtimeeffect_make_for_color_filter]
               [(blender) sk_runtimeeffect_make_for_blender]))
  (skia-check!)
  (define h
    (raw:call-with-native-temporary
     who 'sksl-source
     (lambda () (sk_string_new_with_copy encoded (bytes-length encoded)))
     sk_string_destructor
     (lambda (sp)
       (raw:call-with-native-temporary
        who 'sksl-diagnostic sk_string_new_empty sk_string_destructor
        (lambda (error-ptr)
          (new-owned
           who 'runtime-effect
           (lambda ()
             (or (compile sp error-ptr)
                 (meta:raise-sksl-error kind text (raw:copy-sk-string who error-ptr))))
           sk_runtimeeffect_unref))))))
  (with-handlers ([(lambda (_) #t) (lambda (e) (owned-close! who h) (raise e))])
    (define-values (size uniforms children)
      (call-with-owned who (list h) (lambda (ep) (reflect-effect who ep))))
    (raw:make-runtime-effect-record h kind text size uniforms children)))


;;;
;;; Uniform Packing and Instance Construction
;;;

; runtime-effect-uniform-bytes : runtime-effect? hash? -> (and/c bytes? immutable?)
;   Packs checked bindings into an immutable byte string using the retained uniform layout.
(define (runtime-effect-uniform-bytes e bindings)
  (checked-effect 'runtime-effect-uniform-bytes e)
  ;; This is a pure diagnostic/packing operation on the stored snapshot. It
  ;; also remains usable after E is closed. Factories still require a live E.
  (meta:runtime-pack-uniforms 'runtime-effect-uniform-bytes
                             (runtime-effect-uniform-byte-size e)
                             (runtime-effect-uniforms e) bindings))

; native-local-matrix : symbol? (or/c #f matrix?) -> (or/c #f sk-matrix?)
;   Converts an optional affine transform after checking that its inverse is representable.
(define (native-local-matrix who m)
  (cond
    [(not m) #f]
    [else
     (unless (matrix? m) (raise-argument-error who "#f or affine matrix?" m))
     (unless (matrix-invert m)
       (raise-arguments-error who "local matrix must have a representable inverse" "matrix" m))
     (make-sk-matrix (matrix-xx m) (matrix-xy m) (matrix-x0 m)
                     (matrix-yx m) (matrix-yy m) (matrix-y0 m) 0.0 0.0 1.0)]))

; runtime-child-handles : symbol? runtime-effect? any/c -> (listof (or/c owned? domain-resource?))
;   Requires every child binding with its declared kind and returns handles in native declaration
;   order.
(define (runtime-child-handles who e bindings)
  (define children (runtime-effect-children e))
  (define table (meta:runtime-bindings who 'child (map runtime-child-name children) bindings))
  (for/list ([child (in-list children)])
    (define value (hash-ref table (runtime-child-name child)))
    ;; A null native child has implicit fallback behavior. Require every child
    ;; explicitly instead: no missing binding or wrong type reaches the C shim.
    (case (runtime-child-kind child)
      [(shader) (raw:shader-h who value)]
      [(color-filter) (raw:color-filter-h who value)]
      [(blender) (blender-h who value)])))

; make-runtime-instance : symbol? runtime-effect? symbol? any/c any/c any/c procedure? procedure? ->
;   any/c
;   Packs uniforms and creates an owned pipeline instance while retaining all child handles.
(define (make-runtime-instance who e kind bindings children local-matrix create wrap)
  (define eh (effect-h who e))
  (unless (eq? kind (runtime-effect-kind e))
    (raise-arguments-error who "effect was compiled for a different pipeline stage"
                           "expected" kind "effect kind" (runtime-effect-kind e)))
  (define lm (native-local-matrix who local-matrix))
  (call-with-owned who (list eh) (lambda (_) (void)))
  (define uniforms (meta:runtime-pack-uniforms who (runtime-effect-uniform-byte-size e)
                                              (runtime-effect-uniforms e) bindings))
  (define chs (runtime-child-handles who e children))
  (unless (<= (* (length chs) (ctype-sizeof _pointer)) (current-skia-byte-limit))
    (error who "runtime child pointer array exceeds current-skia-byte-limit"))
  (call-with-owned
   who (cons eh chs)
   (lambda (ep . cps)
     (raw:call-with-native-temporary
      who 'runtime-uniform-data
      (lambda () (sk_data_new_with_copy uniforms (bytes-length uniforms)))
      sk_data_unref
      (lambda (dp)
        (define array (and (pair? cps) (malloc (length cps) _pointer 'atomic)))
        (for ([cp (in-list cps)] [i (in-naturals)]) (ptr-set! array _pointer i cp))
        ;; The shim refs SkData and all child flattenables. Adoption happens
        ;; while the parent/children are held, so none can become dangling.
        (begin0 (wrap who (lambda () (create ep dp array (length cps) lm)))
          (void/reference-sink array cps lm uniforms)))))))

; runtime-effect->shader : runtime-effect? [#:uniforms hash?] [#:children hash?] [#:local-matrix
;   (or/c matrix? #f)] -> shader?
;   Returns an owned shader instance of an open shader-kind effect.
(define (runtime-effect->shader e #:uniforms [uniforms (hash)] #:children [children (hash)]
                                #:local-matrix [local-matrix #f])
  (make-runtime-instance 'runtime-effect->shader e 'shader uniforms children local-matrix
                         sk_runtimeeffect_make_shader raw:new-shader))

; runtime-effect->color-filter : runtime-effect? [#:uniforms hash?] [#:children hash?] ->
;   color-filter?
;   Returns an owned color-filter instance.
(define (runtime-effect->color-filter e #:uniforms [uniforms (hash)] #:children [children (hash)])
  (make-runtime-instance
   'runtime-effect->color-filter e 'color-filter uniforms children #f
   (lambda (ep dp cp n _matrix) (sk_runtimeeffect_make_color_filter ep dp cp n))
   raw:new-color-filter))


;;;
;;; Blender Factories
;;;

; new-blender : symbol? procedure? -> blender?
;   Initializes the native library and adopts a new owned blender.
(define (new-blender who create)
  (skia-check!)
  (raw:make-blender-record (new-owned who 'blender create sk_blender_unref)))

; runtime-effect->blender : runtime-effect? [#:uniforms hash?] [#:children hash?] -> blender?
;   Returns an owned blender instance.
(define (runtime-effect->blender e #:uniforms [uniforms (hash)] #:children [children (hash)])
  (make-runtime-instance
   'runtime-effect->blender e 'blender uniforms children #f
   (lambda (ep dp cp n _matrix) (sk_runtimeeffect_make_blender ep dp cp n))
   new-blender))

; make-blend-mode-blender : (or/c 'clear 'src 'dst 'src-over 'dst-over 'src-in 'dst-in 'src-out
;   'dst-out 'src-atop 'dst-atop 'xor 'plus 'modulate 'screen 'overlay 'darken 'lighten 'color-dodge
;   'color-burn 'hard-light 'soft-light 'difference 'exclusion 'multiply 'hue 'saturation 'color
;   'luminosity) -> blender?
;   Returns an owned blender implementing the selected blend mode.
(define (make-blend-mode-blender mode)
  (define value (choice 'make-blend-mode-blender mode blend-values))
  (new-blender 'make-blend-mode-blender (lambda () (sk_blender_new_mode value))))

; paint-set-blender! : paint? (or/c blender? #f) -> void?
;   Replaces the paint's blender with a retained native reference, or restores implicit source-over
;   when blender is false.
(define (paint-set-blender! p blender)
  (define who 'paint-set-blender!)
  (define ph (raw:paint-h who p))
  (define bh (and blender (blender-h who blender)))
  (call-with-owned
   who (if bh (list ph bh) (list ph))
   (lambda (pp . bs) (sk_paint_set_blender pp (if bh (car bs) #f)))))

; paint-blender : paint? -> (or/c blender? #f)
;   Returns an independently owned reference to an explicit paint blender, or #f for the implicit
;   source-over case.
(define (paint-blender p)
  (define who 'paint-blender)
  (call-with-owned
   who (list (raw:paint-h who p))
   (lambda (pp)
     ;; The C shim uses refBlender().release(): already one owned reference.
     ;; NULL denotes Skia's implicit SrcOver, not a missing/error resource.
     (define bp (sk_paint_get_blender pp))
     (and bp (new-blender who (lambda () bp))))))
