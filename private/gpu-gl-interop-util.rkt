#lang racket/base

;;;
;;; OpenGL Interoperation Validation
;;;

;; Checks external GL identifiers and texture target options.
;; Prepares backend-specific inputs before importing application GL resources.

(provide check-gl-name check-gl-extent gl-origin-value check-gl-borrow-options)
; check-gl-name : symbol? exact-integer? -> exact-integer?
;;   Checks an unsigned GL object name before it crosses the native boundary.
(define (check-gl-name who value)
  (unless (and (exact-integer? value) (<= 1 value #xffffffff))
    (raise-argument-error who "nonzero uint32 OpenGL object name" value)) value)
; check-gl-extent : symbol? any/c any/c -> void?
;;   Validates positive imported GL resource dimensions within native integer and byte-budget
;;   limits.
(define (check-gl-extent who width height)
  (for ([v (in-list (list width height))])
    (unless (and (exact-integer? v) (<= 1 v #x7fffffff))
      (raise-argument-error who "positive signed-32-bit pixel extent" v))))
; gl-origin-value : symbol? any/c -> exact-nonnegative-integer?
;;   Maps the public top-left/bottom-left origin choice to the pinned native origin enum.
(define (gl-origin-value who origin)
  (case origin [(top-left) 0] [(bottom-left) 1]
    [else (raise-argument-error who "'top-left or 'bottom-left" origin)]))
; check-gl-borrow-options : symbol? exact-integer? any/c any/c any/c boolean? -> void?
;;   Checks GL object identity, dimensions, origin, and synchronization flag before borrowing.
(define (check-gl-borrow-options who name width height origin wait?)
  (check-gl-name who name) (check-gl-extent who width height)
  (gl-origin-value who origin)
  (unless (boolean? wait?) (raise-argument-error who "boolean? for wait?" wait?)))
