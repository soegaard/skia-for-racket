#lang racket/base

;;;
;;; Global Caches Example
;;;

;; Reports native cache and memory statistics without changing cache policy.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;;;
;;; Imports and Exports
;;;

(require "../main.rkt")
;; Read-only example: no limit or cache policy is changed merely to inspect it.
;;;
;;; Drawing Data and Helpers
;;;

; summary : hash?
;;   Captures the current global cache statistics without changing cache policy.
(define summary (skia-cache-statistics))
(printf "Global font cache: ~a bytes; resource cache: ~a bytes\n"
        (hash-ref summary 'font-bytes-used) (hash-ref summary 'resource-bytes-used))
; details : memory-statistics?
;;   Captures the bounded detailed native memory statistics.
(define details (skia-memory-statistics #:detailed? #t))
(printf "Native statistics: ~a entries, ~a omitted\n"
        (vector-length (memory-statistics-entries details))
        (memory-statistics-dropped-count details))
