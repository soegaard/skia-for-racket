#lang racket/base
(require "../main.rkt")
;; Read-only example: no limit or cache policy is changed merely to inspect it.
(define summary (skia-cache-statistics))
(printf "Global font cache: ~a bytes; resource cache: ~a bytes\n"
        (hash-ref summary 'font-bytes-used) (hash-ref summary 'resource-bytes-used))
(define details (skia-memory-statistics #:detailed? #t))
(printf "Native statistics: ~a entries, ~a omitted\n"
        (vector-length (memory-statistics-entries details))
        (memory-statistics-dropped-count details))
