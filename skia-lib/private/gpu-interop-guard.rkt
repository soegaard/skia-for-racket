#lang racket/base

;;;
;;; GPU Interoperation Guard
;;;

;; Tracks scopes in which reentrant Skia GPU access is forbidden.
;; Prevents unsafe GPU calls during application interoperation callbacks.

;; Dynamic protection for the advanced same-context GL handoff. Native GL
;; callbacks are application code and must not reenter Skia GPU execution.
(provide current-external-gl? current-gl-borrow? current-external-native? check-skia-gpu-access!)

; current-external-native? : parameter?
;   Marks application-native interoperation callbacks that must not reenter Skia GPU operations.
(define current-external-native? (make-parameter #f))

; current-external-gl? : parameter?
;   Shares the external-native reentry guard with the GL interoperation API.
(define current-external-gl? (make-parameter #f))

; current-gl-borrow? : parameter?
;   Marks a live GL resource borrow whose restrictions apply to nested operations.
(define current-gl-borrow? (make-parameter #f))

; check-skia-gpu-access! : symbol? -> void?
;   Rejects Skia GPU work while an external native callback owns the interoperation scope.
(define (check-skia-gpu-access! who)
  (when (current-external-native?)
    (error who "Skia GPU access is not allowed inside an external native-device callback"))
  (when (current-external-gl?)
    (error who "Skia GPU access is not allowed inside an external OpenGL callback")))
