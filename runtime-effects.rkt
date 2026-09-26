#lang racket/base
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
(define runtime-effect? raw:runtime-effect-resource?)
(define blender? raw:blender-resource?)
(define runtime-uniform? meta:runtime-uniform?)
(define runtime-uniform-name meta:runtime-uniform-name)
(define runtime-uniform-offset meta:runtime-uniform-offset)
(define runtime-uniform-type meta:runtime-uniform-type)
(define runtime-uniform-count meta:runtime-uniform-count)
(define runtime-uniform-byte-size meta:runtime-uniform-byte-size)
(define runtime-uniform-array? meta:runtime-uniform-array?)
(define runtime-uniform-color? meta:runtime-uniform-color?)
(define runtime-uniform-half-precision? meta:runtime-uniform-half-precision?)
(define runtime-child? meta:runtime-child?)
(define runtime-child-name meta:runtime-child-name)
(define runtime-child-kind meta:runtime-child-kind)
(define runtime-child-index meta:runtime-child-index)
(define exn:fail:skia-sksl? meta:exn:fail:skia-sksl?)
(define exn:fail:skia-sksl-kind meta:exn:fail:skia-sksl-kind)
(define exn:fail:skia-sksl-source meta:exn:fail:skia-sksl-source)
(define exn:fail:skia-sksl-diagnostics meta:exn:fail:skia-sksl-diagnostics)

(define (checked-effect who e)
  (unless (runtime-effect? e) (raise-argument-error who "runtime-effect?" e))
  e)
(define (effect-h who e)
  (raw:runtime-effect-resource-handle (checked-effect who e)))
(define (blender-h who b)
  (unless (blender? b) (raise-argument-error who "blender?" b))
  (raw:blender-resource-handle b))

(define (runtime-effect-kind e)
  (raw:runtime-effect-resource-kind (checked-effect 'runtime-effect-kind e)))
(define (runtime-effect-source e)
  (raw:runtime-effect-resource-source (checked-effect 'runtime-effect-source e)))
(define (runtime-effect-uniform-byte-size e)
  (raw:runtime-effect-resource-byte-size (checked-effect 'runtime-effect-uniform-byte-size e)))
(define (runtime-effect-uniforms e)
  (raw:runtime-effect-resource-uniforms (checked-effect 'runtime-effect-uniforms e)))
(define (runtime-effect-children e)
  (raw:runtime-effect-resource-children (checked-effect 'runtime-effect-children e)))

(define (runtime-count who count record-size)
  (unless (and (exact-nonnegative-integer? count) (<= count #x7fffffff)
               (<= (* count record-size) (current-skia-byte-limit)))
    (error who "native reflection count is invalid or exceeds current-skia-byte-limit"))
  count)

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

(define (runtime-effect-uniform-bytes e bindings)
  (checked-effect 'runtime-effect-uniform-bytes e)
  ;; This is a pure diagnostic/packing operation on the stored snapshot. It
  ;; also remains usable after E is closed. Factories still require a live E.
  (meta:runtime-pack-uniforms 'runtime-effect-uniform-bytes
                             (runtime-effect-uniform-byte-size e)
                             (runtime-effect-uniforms e) bindings))

(define (native-local-matrix who m)
  (cond
    [(not m) #f]
    [else
     (unless (matrix? m) (raise-argument-error who "#f or affine matrix?" m))
     (unless (matrix-invert m)
       (raise-arguments-error who "local matrix must have a representable inverse" "matrix" m))
     (make-sk-matrix (matrix-xx m) (matrix-xy m) (matrix-x0 m)
                     (matrix-yx m) (matrix-yy m) (matrix-y0 m) 0.0 0.0 1.0)]))

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

(define (runtime-effect->shader e #:uniforms [uniforms (hash)] #:children [children (hash)]
                                #:local-matrix [local-matrix #f])
  (make-runtime-instance 'runtime-effect->shader e 'shader uniforms children local-matrix
                         sk_runtimeeffect_make_shader raw:new-shader))

(define (runtime-effect->color-filter e #:uniforms [uniforms (hash)] #:children [children (hash)])
  (make-runtime-instance
   'runtime-effect->color-filter e 'color-filter uniforms children #f
   (lambda (ep dp cp n _matrix) (sk_runtimeeffect_make_color_filter ep dp cp n))
   raw:new-color-filter))

(define (new-blender who create)
  (skia-check!)
  (raw:make-blender-record (new-owned who 'blender create sk_blender_unref)))

(define (runtime-effect->blender e #:uniforms [uniforms (hash)] #:children [children (hash)])
  (make-runtime-instance
   'runtime-effect->blender e 'blender uniforms children #f
   (lambda (ep dp cp n _matrix) (sk_runtimeeffect_make_blender ep dp cp n))
   new-blender))

(define (make-blend-mode-blender mode)
  (define value (choice 'make-blend-mode-blender mode blend-values))
  (new-blender 'make-blend-mode-blender (lambda () (sk_blender_new_mode value))))

(define (paint-set-blender! p blender)
  (define who 'paint-set-blender!)
  (define ph (raw:paint-h who p))
  (define bh (and blender (blender-h who blender)))
  (call-with-owned
   who (if bh (list ph bh) (list ph))
   (lambda (pp . bs) (sk_paint_set_blender pp (if bh (car bs) #f)))))

(define (paint-blender p)
  (define who 'paint-blender)
  (call-with-owned
   who (list (raw:paint-h who p))
   (lambda (pp)
     ;; The C shim uses refBlender().release(): already one owned reference.
     ;; NULL denotes Skia's implicit SrcOver, not a missing/error resource.
     (define bp (sk_paint_get_blender pp))
     (and bp (new-blender who (lambda () bp))))))
