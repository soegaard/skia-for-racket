#lang racket/base

;;;
;;; Global Graphics Caches
;;;

;; Queries and configures native font and resource caches and requests explicit cache purges.
;; This public diagnostics layer reports process-wide graphics state separately from individual CPU
;; or GPU resources.

;;;
;;; Imports and Exports
;;;

;; 0.77a: explicit controls for the loaded library's global CPU caches.
(require "private/native.rkt" "private/graphics-data.rkt" "private/graphics-trace-native.rkt"
         (only-in "private/check.rkt" current-skia-byte-limit))
(provide skia-font-cache-used
         skia-font-cache-limit
         skia-font-cache-count-used
         skia-font-cache-count-limit
         skia-resource-cache-used
         skia-resource-cache-limit
         skia-resource-cache-single-allocation-limit
         skia-set-font-cache-limit!
         skia-set-font-cache-count-limit!
         skia-set-resource-cache-limit!
         skia-set-resource-cache-single-allocation-limit!
         skia-initialize!
         skia-purge-font-cache!
         skia-purge-resource-cache!
         skia-purge-all-caches!
         skia-cache-statistics
         skia-memory-statistics
         memory-statistic? memory-statistic-kind memory-statistic-name
         memory-statistic-value-name memory-statistic-units memory-statistic-value
         memory-statistics? memory-statistics-entries memory-statistics-detailed?
         memory-statistics-dump-wrapped? memory-statistics-truncated?
         memory-statistics-dropped-count memory-statistics-string-bytes
         memory-statistics-scope memory-statistics->jsexpr)

;;;
;;; Cache Usage and Limit Queries
;;;

; skia-font-cache-used : -> exact-nonnegative-integer?
;   Returns the current font-cache byte usage.
(define (skia-font-cache-used)
  (call-global-cache-native 'skia-font-cache-used
    (lambda ()
      (cache-byte-limit
       'skia-font-cache-used
       (sk_graphics_get_font_cache_used)))))

; skia-font-cache-limit : -> exact-nonnegative-integer?
;   Returns the current font-cache byte limit.
(define (skia-font-cache-limit)
  (call-global-cache-native 'skia-font-cache-limit
    (lambda ()
      (cache-byte-limit
       'skia-font-cache-limit
       (sk_graphics_get_font_cache_limit)))))

; skia-font-cache-count-used : -> (integer-in 0 2147483647)
;   Returns the current number of font-cache entries.
(define (skia-font-cache-count-used)
  (call-global-cache-native 'skia-font-cache-count-used
    (lambda ()
      (cache-count-limit
       'skia-font-cache-count-used
       (sk_graphics_get_font_cache_count_used)))))

; skia-font-cache-count-limit : -> (integer-in 0 2147483647)
;   Returns the current upper limit on the number of font-cache entries.
(define (skia-font-cache-count-limit)
  (call-global-cache-native 'skia-font-cache-count-limit
    (lambda ()
      (cache-count-limit
       'skia-font-cache-count-limit
       (sk_graphics_get_font_cache_count_limit)))))

; skia-resource-cache-used : -> exact-nonnegative-integer?
;   Returns the current resource-cache byte usage.
(define (skia-resource-cache-used)
  (call-global-cache-native 'skia-resource-cache-used
    (lambda ()
      (cache-byte-limit
       'skia-resource-cache-used
       (sk_graphics_get_resource_cache_total_bytes_used)))))

; skia-resource-cache-limit : -> exact-nonnegative-integer?
;   Returns the current resource-cache total-byte limit.
(define (skia-resource-cache-limit)
  (call-global-cache-native 'skia-resource-cache-limit
    (lambda ()
      (cache-byte-limit
       'skia-resource-cache-limit
       (sk_graphics_get_resource_cache_total_byte_limit)))))

; skia-resource-cache-single-allocation-limit : -> exact-nonnegative-integer?
;   Returns the current single-allocation byte limit for the resource cache.
(define (skia-resource-cache-single-allocation-limit)
  (call-global-cache-native 'skia-resource-cache-single-allocation-limit
    (lambda ()
      (cache-byte-limit
       'skia-resource-cache-single-allocation-limit
       (sk_graphics_get_resource_cache_single_allocation_byte_limit)))))

;;;
;;; Cache Limit Configuration
;;;

; skia-set-font-cache-limit! : exact-nonnegative-integer? -> exact-nonnegative-integer?
;   Sets the font-cache byte limit and returns its previous setting.
(define (skia-set-font-cache-limit! value)
  (cache-byte-limit 'skia-set-font-cache-limit! value)
  ;; The native result is the previous setting, not usage or bytes freed.
  (call-global-cache-native 'skia-set-font-cache-limit!
    (lambda ()
      (cache-byte-limit
       'skia-set-font-cache-limit!
       (sk_graphics_set_font_cache_limit value)))))

; skia-set-font-cache-count-limit! : (integer-in 0 2147483647) -> (integer-in 0 2147483647)
;   Sets the upper limit on the number of font-cache entries to limit and returns the previous
;   count limit.
(define (skia-set-font-cache-count-limit! value)
  (cache-count-limit 'skia-set-font-cache-count-limit! value)
  ;; The native result is the previous setting, not usage or bytes freed.
  (call-global-cache-native 'skia-set-font-cache-count-limit!
    (lambda ()
      (cache-count-limit
       'skia-set-font-cache-count-limit!
       (sk_graphics_set_font_cache_count_limit value)))))

; skia-set-resource-cache-limit! : exact-nonnegative-integer? -> exact-nonnegative-integer?
;   Sets the resource-cache total-byte limit and returns its previous setting.
(define (skia-set-resource-cache-limit! value)
  (cache-byte-limit 'skia-set-resource-cache-limit! value)
  ;; The native result is the previous setting, not usage or bytes freed.
  (call-global-cache-native 'skia-set-resource-cache-limit!
    (lambda ()
      (cache-byte-limit
       'skia-set-resource-cache-limit!
       (sk_graphics_set_resource_cache_total_byte_limit value)))))

; skia-set-resource-cache-single-allocation-limit! : exact-nonnegative-integer? ->
;   exact-nonnegative-integer?
;   Sets the resource-cache single-allocation byte limit and returns its previous setting.
(define (skia-set-resource-cache-single-allocation-limit! value)
  (cache-byte-limit 'skia-set-resource-cache-single-allocation-limit! value)
  ;; The native result is the previous setting, not usage or bytes freed.
  (call-global-cache-native 'skia-set-resource-cache-single-allocation-limit!
    (lambda ()
      (cache-byte-limit
       'skia-set-resource-cache-single-allocation-limit!
       (sk_graphics_set_resource_cache_single_allocation_byte_limit value)))))

;;;
;;; Global Initialization and Cache Purging
;;;

; skia-initialize! : -> void?
;   Explicitly initializes Skia's global graphics state.
(define (skia-initialize!)
  (call-global-cache-native 'skia-initialize!
    (lambda () (sk_graphics_init) (void))))

; skia-purge-font-cache! : -> void?
;   Requests purging of the font cache.
(define (skia-purge-font-cache!)
  (call-global-cache-native 'skia-purge-font-cache!
    (lambda () (sk_graphics_purge_font_cache) (void))))

; skia-purge-resource-cache! : -> void?
;   Requests purging of the resource cache.
(define (skia-purge-resource-cache!)
  (call-global-cache-native 'skia-purge-resource-cache!
    (lambda () (sk_graphics_purge_resource_cache) (void))))

; skia-purge-all-caches! : -> void?
;   Requests purging of the global caches.
(define (skia-purge-all-caches!)
  (call-global-cache-native 'skia-purge-all-caches!
    (lambda () (sk_graphics_purge_all_caches) (void))))

;;;
;;; Cache and Memory Reports
;;;

; skia-cache-statistics : -> (and/c hash? immutable?)
;   Returns current cache observations in an immutable hash.
(define (skia-cache-statistics)
  ;; Individually synchronized native queries, NOT an atomic joint snapshot.
  (hasheq 'scope 'process-global-skia-caches 'atomic? #f
          'font-bytes-used (skia-font-cache-used)
          'font-byte-limit (skia-font-cache-limit)
          'font-count-used (skia-font-cache-count-used)
          'font-count-limit (skia-font-cache-count-limit)
          'resource-bytes-used (skia-resource-cache-used)
          'resource-byte-limit (skia-resource-cache-limit)
          'resource-single-allocation-byte-limit (skia-resource-cache-single-allocation-limit)))

; skia-memory-statistics : [#:detailed? boolean?] [#:dump-wrapped? boolean?] [#:max-entries
;   (integer-in 0 65536)] [#:string-limit (integer-in 0 65536)] [#:byte-limit
;   exact-nonnegative-integer?] -> memory-statistics?
;   Collects a detached native memory report for process-global Skia caches.
(define (skia-memory-statistics #:detailed? [detailed? #f] #:dump-wrapped? [wrapped? #f]
                                #:max-entries [max-entries 4096]
                                #:string-limit [string-limit 4096]
                                #:byte-limit [byte-limit 1048576])
  (memory-options 'skia-memory-statistics detailed? wrapped? max-entries string-limit byte-limit)
  (global-memory-statistics/native detailed? wrapped? max-entries string-limit byte-limit))
