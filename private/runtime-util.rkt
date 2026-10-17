#lang racket/base

;;;
;;; Runtime Effect Reflection
;;;

;; Validates SkSL source, uniform layouts, child bindings, and packed uniform values.
;; Provides detached reflection data and error reporting for runtime effects.

(require racket/list "check.rkt")
(provide runtime-source runtime-kind checked-runtime-uniform checked-runtime-child
         validate-runtime-layout runtime-bindings runtime-pack-uniforms
         runtime-uniform? runtime-uniform-name runtime-uniform-offset
         runtime-uniform-type runtime-uniform-count runtime-uniform-byte-size
         runtime-uniform-array? runtime-uniform-color? runtime-uniform-half-precision?
         runtime-child? runtime-child-name runtime-child-kind runtime-child-index
         exn:fail:skia-sksl? exn:fail:skia-sksl-kind
         exn:fail:skia-sksl-source exn:fail:skia-sksl-diagnostics raise-sksl-error)

;;;
;;; Detached Reflection Records
;;;

;; These snapshots contain no foreign pointers and are safe after effect closure.
(struct runtime-uniform (name offset type count flags byte-size)
  #:transparent #:constructor-name uniform-record)
;; Fields:
;;   name: nonempty immutable declaration-name string. offset: nonnegative four-byte-aligned
;;   buffer offset. type: one of uniform-types below. count: positive array element count, or 1
;;   for a non-array. flags: bitmask of #x01 array, #x02 layout(color), and #x10 half precision.
;;   byte-size: 4 * count * the type's scalar component count, including half-precision values.
;;   The interval [offset, offset + byte-size) lies inside the effect's uniform buffer. Records
;;   occur in contiguous offset order; vectors and arrays use declaration order, and flattened
;;   matrices use SkSL column-major order. Color applies only to float3/float4; half excludes ints.

(struct runtime-child (name kind index)
  #:transparent #:constructor-name child-record)
;; Fields:
;;   name: nonempty immutable declaration-name string. kind: 'shader, 'color-filter, or 'blender.
;;   index: nonnegative signed-int native binding index. Indices are contiguous from zero, and
;;   bindings are passed in index order, not hash iteration order. Child and uniform names are
;;   unique across the effect's complete reflection layout.

(struct exn:fail:skia-sksl exn:fail (kind source diagnostics) #:transparent)
;; Fields:
;;   kind: effect kind being compiled. source: submitted SkSL string. diagnostics: copied compiler
;;   diagnostic string. Inherited fields retain exception context; no native diagnostic buffer
;;   escapes.


; runtime-uniform-array? : runtime-uniform? -> boolean?
;;   Returns whether the declaration is an array.
(define (runtime-uniform-array? u)
  (not (zero? (bitwise-and (runtime-uniform-flags u) #x01))))
; runtime-uniform-color? : runtime-uniform? -> boolean?
;;   Returns whether the declaration has layout(color).
(define (runtime-uniform-color? u)
  (not (zero? (bitwise-and (runtime-uniform-flags u) #x02))))
; runtime-uniform-half-precision? : runtime-uniform? -> boolean?
;;   Returns whether the declaration carries the half-precision flag.
(define (runtime-uniform-half-precision? u)
  (not (zero? (bitwise-and (runtime-uniform-flags u) #x10))))

;;;
;;; Source Validation and Compilation Failures
;;;

; runtime-kind : symbol? any/c -> symbol?
;;   Checks the shader, color-filter, or blender role requested for a runtime effect.
(define (runtime-kind who v)
  (unless (memq v '(shader color-filter blender))
    (raise-argument-error who "'shader, 'color-filter, or 'blender" v))
  v)

; runtime-source : symbol? string? -> (values string? bytes?)
;;   Snapshots nonempty NUL-free SkSL source and its UTF-8 encoding within the current byte budget.
(define (runtime-source who source)
  (unless (string? source) (raise-argument-error who "string?" source))
  (when (or (zero? (string-length source))
            (> (string-length source) (current-skia-byte-limit)))
    (raise-arguments-error who "SkSL source is empty or exceeds current-skia-byte-limit"
                           "characters" (string-length source)))
  (define text (string->immutable-string source))
  (when (regexp-match? #rx"\u0000" text)
    (raise-arguments-error who "SkSL source contains NUL" "source" text))
  (define encoded (string->bytes/utf-8 text))
  (when (> (bytes-length encoded) (current-skia-byte-limit))
    (raise-arguments-error who "UTF-8 SkSL source exceeds current-skia-byte-limit"
                           "bytes" (bytes-length encoded)))
  (values text encoded))

; raise-sksl-error : symbol? string? string? -> none/c
;;   Raises the structured SkSL compilation exception with immutable native diagnostics.
(define (raise-sksl-error kind source diagnostics)
  (define text (string->immutable-string diagnostics))
  (raise
   (exn:fail:skia-sksl
    (format "make-runtime-effect: SkSL ~a compilation failed\n~a" kind text)
    (current-continuation-marks) kind source text)))

;;;
;;; Reflected Layout Validation
;;;

; uniform-types : (vectorof symbol?)
;;   Maps native uniform type codes 0 through 10 to reflected numeric type symbols; ordering matches
;;   type-components.
(define uniform-types
  '#(float float2 float3 float4 float2x2 float3x3 float4x4 int int2 int3 int4))
; type-components : (vectorof exact-positive-integer?)
;;   Gives scalar counts for the corresponding uniform-types entries, including flattened matrix
;;   components.
(define type-components '#(1 2 3 4 4 9 16 1 2 3 4))
; uniform-type-index : symbol? symbol? -> exact-nonnegative-integer?
;;   Finds a reflected numeric type's native index or rejects an unknown type.
(define (uniform-type-index who t)
  (or (for/or ([v (in-vector uniform-types)] [i (in-naturals)]) (and (eq? v t) i))
      (raise-argument-error who "reflected numeric uniform type" t)))

; checked-name : symbol? string? -> string?
;;   Snapshots a nonempty NUL-free reflected uniform or child name.
(define (checked-name who name)
  (unless (and (string? name) (positive? (string-length name))
               (not (regexp-match? #rx"\u0000" name)))
    (raise-argument-error who "nonempty NUL-free name string" name))
  (string->immutable-string name))

; checked-runtime-uniform : symbol? string? exact-nonnegative-integer? exact-integer?
;   exact-positive-integer? exact-nonnegative-integer? exact-nonnegative-integer? ->
;   runtime-uniform?
;;   Checks native type, flags, count, alignment, and buffer range before constructing a reflected
;;   uniform record.
(define (checked-runtime-uniform who name offset type-code count flags total)
  (unless (and (exact-integer? type-code) (<= 0 type-code 10))
    (error who "unexpected native uniform type ~a" type-code))
  (unless (and (exact-nonnegative-integer? flags)
               (zero? (bitwise-and flags (bitwise-not #x13))))
    (error who "unexpected native runtime-uniform flags ~a" flags))
  (unless (and (exact-positive-integer? count) (<= count #x7fffffff)
               (or (not (zero? (bitwise-and flags 1))) (= count 1)))
    (error who "invalid native uniform array count ~a" count))
  (define size (* 4 count (vector-ref type-components type-code)))
  (unless (and (exact-nonnegative-integer? total)
               (exact-nonnegative-integer? offset) (zero? (modulo offset 4))
               (<= (+ offset size) total))
    (error who "native uniform range is outside the uniform buffer"))
  (when (and (not (zero? (bitwise-and flags 2))) (not (memv type-code '(2 3))))
    (error who "layout(color) uniform is not float3/float4"))
  (when (and (not (zero? (bitwise-and flags #x10))) (>= type-code 7))
    (error who "integer uniform was reported as half precision"))
  (uniform-record (checked-name who name) offset (vector-ref uniform-types type-code)
                  count flags size))

; checked-runtime-child : symbol? string? exact-integer? exact-nonnegative-integer? -> runtime-child?
;;   Checks a reflected child's shader/filter/blender kind and native index before retaining its
;;   immutable name.
(define (checked-runtime-child who name type-code index)
  (unless (and (exact-integer? type-code) (<= 0 type-code 2))
    (error who "unexpected native child kind ~a" type-code))
  (unless (and (exact-nonnegative-integer? index) (<= index #x7fffffff))
    (error who "invalid native child index ~a" index))
  (child-record (checked-name who name) (vector-ref '#(shader color-filter blender) type-code)
                index))

; validate-runtime-layout : symbol? exact-nonnegative-integer? (listof runtime-uniform?) (listof
;   runtime-child?) -> void?
;;   Requires unique names, gap-free packed four-byte uniform components, full buffer coverage, and
;;   contiguous child indices in reflection order.
(define (validate-runtime-layout who total uniforms children)
  (unless (and (exact-nonnegative-integer? total) (zero? (modulo total 4))
               (<= total (current-skia-byte-limit)))
    (error who "native uniform buffer exceeds the byte limit or is misaligned"))
  (define names (make-hash))
  (define (unique! name)
    (when (hash-has-key? names name) (error who "duplicate reflected name ~s" name))
    (hash-set! names name #t))
  (define end
    (for/fold ([end 0]) ([u (in-list uniforms)])
      (unless (runtime-uniform? u) (raise-argument-error who "runtime-uniform?" u))
      (unique! (runtime-uniform-name u))
      ;; m119 packs every scalar (including half) into four bytes, without
      ;; std140 vector/array padding. Validate the actual reflected offsets.
      (unless (= end (runtime-uniform-offset u))
        (error who "native uniform layout has a gap or overlap at ~s" (runtime-uniform-name u)))
      (+ end (runtime-uniform-byte-size u))))
  (unless (= end total) (error who "native uniform layout does not cover its buffer"))
  (for ([child (in-list children)] [i (in-naturals)])
    (unless (runtime-child? child) (raise-argument-error who "runtime-child?" child))
    (unique! (runtime-child-name child))
    (unless (= i (runtime-child-index child))
      (error who "native child indices are not contiguous")))
  (void))

;; Snapshot caller dictionaries outside the native ownership critical section.
;; Both symbols and strings are convenient, but two keys normalizing to the
;; same spelling must not silently overwrite each other.
;;;
;;; Binding Normalization and Packed Uniforms
;;;

; runtime-bindings : symbol? symbol? (listof string?) hash? -> hash?
;;   Normalizes symbol or string binding keys to immutable strings, rejecting unknown, duplicate, or
;;   missing reflected names.
(define (runtime-bindings who label names input)
  (unless (hash? input) (raise-argument-error who "hash? with uniform/child names as keys" input))
  (define out
    (for/fold ([out (hash)]) ([(key value) (in-hash input)])
      (define name
        (cond [(symbol? key) (symbol->string key)]
              [(string? key) (string->immutable-string key)]
              [else (raise-argument-error who "symbol or string binding key" key)]))
      (unless (member name names)
        (raise-arguments-error who "unknown binding" "category" label "name" name))
      (when (hash-has-key? out name)
        (raise-arguments-error who "duplicate normalized binding name" "category" label "name" name))
      (hash-set out name value)))
  (for ([name (in-list names)])
    (unless (hash-has-key? out name)
      (raise-arguments-error who "missing required binding" "category" label "name" name)))
  out)

; uniform-components : symbol? runtime-uniform? any/c -> list?
;;   Normalizes a scalar or flat list/vector to the exact reflected component count, without
;;   reordering vectors, matrices, or arrays.
(define (uniform-components who u value)
  (define n (quotient (runtime-uniform-byte-size u) 4))
  (cond
    [(and (= n 1) (not (runtime-uniform-array? u))) (list value)]
    [else
     (define xs
       (cond [(list? value) value] [(vector? value) (vector->list value)]
             [else (raise-arguments-error who "uniform requires a flat list or vector"
                                          "name" (runtime-uniform-name u) "components" n)]))
     (unless (= (length xs) n)
       (raise-arguments-error who "wrong uniform component count"
                              "name" (runtime-uniform-name u) "expected" n "given" (length xs)))
     xs]))

; runtime-pack-uniforms : symbol? exact-nonnegative-integer? (listof runtime-uniform?) hash? -> bytes?
;;   Packs checked signed integers or native floats at reflected offsets in host byte order and
;;   returns immutable uniform bytes.
(define (runtime-pack-uniforms who total uniforms input)
  (validate-runtime-layout who total uniforms '())
  (define values-by-name (runtime-bindings who 'uniform (map runtime-uniform-name uniforms) input))
  (define out (make-bytes total 0))
  (for ([u (in-list uniforms)])
    (define int? (>= (uniform-type-index who (runtime-uniform-type u)) 7))
    (define xs (uniform-components who u (hash-ref values-by-name (runtime-uniform-name u))))
    (for ([v (in-list xs)] [at (in-range (runtime-uniform-offset u)
                                       (+ (runtime-uniform-offset u) (runtime-uniform-byte-size u))
                                       4)])
      (define encoded
        (cond
          [int?
           (unless (and (exact-integer? v) (<= (- (expt 2 31)) v (sub1 (expt 2 31))))
             (raise-arguments-error who "integer uniform requires a signed 32-bit exact integer"
                                    "name" (runtime-uniform-name u) "value" v))
           (integer->integer-bytes v 4 #t (system-big-endian?))]
          [else (real->floating-point-bytes (scalar who v) 4 (system-big-endian?))]))
      (bytes-copy! out at encoded)))
  (bytes->immutable-bytes out))
