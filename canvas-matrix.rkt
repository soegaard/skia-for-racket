#lang racket/base

;;;
;;; Projective Canvas Transforms
;;;

;; Reads and applies 3-by-3 and 4-by-4 canvas transformation matrices.
;; This public adapter joins detached projective matrices to the native canvas API and its scoped
;; state restoration.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe "matrix.rkt" "projective-matrix.rkt"
         "private/core.rkt" "private/native.rkt" "private/types.rkt"
         "private/audit-trace.rkt" (submod "private/core.rkt" path-matrix-internals))
(provide canvas-matrix4 canvas-set-matrix4! canvas-concat-matrix4!
         canvas-set-matrix3! canvas-concat-matrix3!
         call-with-canvas-matrix with-canvas-matrix)

;; Pinned m119 canvas calls reinterpret sk_matrix44_t as a column-major SkM44.
;; The public vectors are row-major. Do NOT copy them directly into this ABI.
; native-matrix4 : symbol? matrix4? -> sk-m44?
;;   Converts the public row-major matrix to Skia's column-major native storage.
(define (native-matrix4 who m)
  (unless (matrix4? m) (raise-argument-error who "matrix4?" m))
  (apply make-sk-m44
         (for*/list ([column (in-range 4)] [row (in-range 4)]) (matrix4-ref m row column))))
; from-native-matrix4 : cpointer? -> matrix4?
;;   Copies a native column-major matrix into a validated public row-major value.
(define (from-native-matrix4 native)
  (vector->matrix4
   (for*/vector ([row (in-range 4)] [column (in-range 4)])
     (ptr-ref native _float (+ (* column 4) row)))))
; read-native-matrix : cpointer? -> matrix4?
;;   Reads the current transform from a live native canvas.
(define (read-native-matrix cp)
  (define native (native-matrix4 'canvas-matrix4 matrix4-identity))
  (sk_canvas_get_matrix cp native)
  (from-native-matrix4 native))
; canvas-matrix4 : canvas? -> matrix4?
;;   Returns the full native canvas matrix as a detached row-major value.
(define (canvas-matrix4 c)
  ;; call-on-canvas validates owner, thread, and borrowed-canvas lifetime first.
  (call-on-canvas 'canvas-matrix4 c '() read-native-matrix))
; set-matrix : symbol? canvas? matrix4? -> void?
;;   Replaces the canvas transform while recording non-affine use for output auditing.
(define (set-matrix who c m)
  (define native (native-matrix4 who m))
  (call-on-canvas who c '()
    (lambda (cp)
      (call-with-audit-matrix (not (matrix4-affine-2d? m))
        (lambda () (sk_canvas_set_matrix cp native))))))
; concat-matrix : symbol? canvas? matrix4? -> void?
;;   Concatenates a local transform, restoring the previous matrix if native arithmetic overflows.
(define (concat-matrix who c m)
  (define native (native-matrix4 who m))
  (call-on-canvas who c '()
    (lambda (cp)
      (define before (read-native-matrix cp))
      ;; Reject an unrepresentable mathematical result before changing canvas
      ;; state. The actual multiply is still Skia's native current*local call.
      (matrix4-compose before m)
      (call-with-audit-matrix (or (not (matrix4-affine-2d? before))
                                 (not (matrix4-affine-2d? m)))
        (lambda () (sk_canvas_concat cp native)))
      ;; Native float intermediates can overflow even when an exact dot product
      ;; cancels to a finite result. Never leave that invalid matrix installed.
      (with-handlers ([exn:fail:contract?
                       (lambda (e)
                         (sk_canvas_set_matrix cp (native-matrix4 who before))
                         (raise-arguments-error who
                           "native matrix product is non-finite; previous transform restored"
                           "detail" (exn-message e)))])
        (read-native-matrix cp)
        (void)))))
; canvas-set-matrix4! : canvas? matrix4? -> void?
;;   Replaces the canvas matrix.
(define (canvas-set-matrix4! c m) (set-matrix 'canvas-set-matrix4! c m))
; canvas-concat-matrix4! : canvas? matrix4? -> void?
;;   Concatenates the matrix as current times local, so the supplied transform acts first on
;;   subsequently drawn local geometry.
(define (canvas-concat-matrix4! c m) (concat-matrix 'canvas-concat-matrix4! c m))
; canvas-set-matrix3! : canvas? matrix3? -> void?
;;   Replaces the canvas matrix.
(define (canvas-set-matrix3! c m)
  (unless (matrix3? m) (raise-argument-error 'canvas-set-matrix3! "matrix3?" m))
  (set-matrix 'canvas-set-matrix3! c (matrix3->matrix4 m)))
; canvas-concat-matrix3! : canvas? matrix3? -> void?
;;   Concatenates the matrix as current times local, so the supplied transform acts first on
;;   subsequently drawn local geometry.
(define (canvas-concat-matrix3! c m)
  (unless (matrix3? m) (raise-argument-error 'canvas-concat-matrix3! "matrix3?" m))
  (concat-matrix 'canvas-concat-matrix3! c (matrix3->matrix4 m)))
; call-with-canvas-matrix : canvas? (or/c matrix? matrix3? matrix4?) (-> any) [#:replace? boolean?]
;   -> any
;;   Calls the zero-argument function under a protected canvas-state scope.
(define (call-with-canvas-matrix c m thunk #:replace? [replace? #f])
  (define who 'call-with-canvas-matrix)
  (define full
    (cond [(matrix4? m) m] [(matrix3? m) (matrix3->matrix4 m)]
          [(matrix? m) (matrix->matrix4 m)]
          [else (raise-argument-error who "matrix?, matrix3?, or matrix4?" m)]))
  (unless (boolean? replace?) (raise-argument-error who "boolean?" replace?))
  (unless (and (procedure? thunk) (procedure-arity-includes? thunk 0))
    (raise-argument-error who "procedure callable with zero arguments" thunk))
  (define-values (required allowed) (procedure-keywords thunk))
  (unless (null? required)
    (raise-argument-error who "procedure with no required keywords" thunk))
  ;; Reuse the protected save floor, exception cleanup, continuation barrier,
  ;; and multiple-value behavior of the existing ordinary state scope.
  (call-with-canvas-state c
    (lambda ()
      ((if replace? canvas-set-matrix4! canvas-concat-matrix4!) c full)
      (thunk))))
; with-canvas-matrix : syntax (canvas matrix [#:replace? boolean] body ...)
;;   Runs body forms under the same protected transform scope as call-with-canvas-matrix.
(define-syntax with-canvas-matrix
  (syntax-rules ()
    [(_ c m #:replace? replace? body ...)
     (call-with-canvas-matrix c m (lambda () body ...) #:replace? replace?)]
    [(_ c m body ...) (call-with-canvas-matrix c m (lambda () body ...))]))
(module* testing #f (provide native-matrix4 from-native-matrix4))
