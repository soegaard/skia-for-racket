#lang racket/base
;; Dynamic protection for the advanced same-context GL handoff. Native GL
;; callbacks are application code and must not reenter Skia GPU execution.
(provide current-external-gl? current-gl-borrow? current-external-native? check-skia-gpu-access!)
(define current-external-native? (make-parameter #f))
(define current-external-gl? (make-parameter #f))
(define current-gl-borrow? (make-parameter #f))
(define (check-skia-gpu-access! who)
  (when (current-external-native?)
    (error who "Skia GPU access is not allowed inside an external native-device callback"))
  (when (current-external-gl?)
    (error who "Skia GPU access is not allowed inside an external OpenGL callback")))
