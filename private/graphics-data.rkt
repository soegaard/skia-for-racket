#lang racket/base

;;;
;;; Graphics Memory Statistics
;;;

;; Collects bounded, detached memory-statistics records and scope metadata.
;; Provides pure result data for native graphics diagnostics.

;; Detached data and argument/collector checks; no Skia initialization or I/O.
(require ffi/unsafe racket/vector "check.rkt")
(provide cache-byte-limit cache-count-limit memory-options
         memory-statistic? memory-statistic-kind memory-statistic-name
         memory-statistic-value-name memory-statistic-units memory-statistic-value
         memory-statistics? memory-statistics-entries memory-statistics-detailed?
         memory-statistics-dump-wrapped? memory-statistics-truncated?
         memory-statistics-dropped-count memory-statistics-string-bytes
         memory-statistics-scope memory-statistics->jsexpr
         make-memory-collector collector-room collector-full? collector-drop!
         collector-add! collector-finish)

; size-max : exact-positive-integer?
;   Bounds byte budgets by the unsigned size_t range of the running platform.
(define size-max (sub1 (expt 2 (* 8 (ctype-sizeof _size)))))

; cache-byte-limit : symbol? exact-nonnegative-integer? -> exact-nonnegative-integer?
;   Checks a nonnegative byte limit that can cross the native size_t boundary without truncation.
(define (cache-byte-limit who value)
  (unless (and (exact-nonnegative-integer? value) (<= value size-max))
    (raise-argument-error who "exact nonnegative integer representable as size_t" value))
  value)

; cache-count-limit : symbol? exact-nonnegative-integer? -> exact-nonnegative-integer?
;   Checks a nonnegative cache count within the native signed 32-bit range.
(define (cache-count-limit who value)
  (unless (and (exact-nonnegative-integer? value) (<= value #x7fffffff))
    (raise-argument-error who "exact integer from 0 through 2147483647" value))
  value)

; memory-options : symbol? any/c any/c any/c any/c any/c -> void?
;   Checks snapshot flags and cumulative entry/string budgets before installing native memory
;   callbacks.
(define (memory-options who detailed? wrapped? entries string-limit byte-limit)
  (for ([v (in-list (list detailed? wrapped?))])
    (unless (boolean? v) (raise-argument-error who "boolean?" v)))
  (for ([v (in-list (list entries string-limit byte-limit))])
    (unless (exact-nonnegative-integer? v)
      (raise-argument-error who "exact nonnegative snapshot limit" v)))
  (unless (and (<= entries 65536) (<= string-limit 65536)
               (<= byte-limit (current-skia-byte-limit))
               (<= (+ (* entries 128) byte-limit) (current-skia-byte-limit)))
    (error who "snapshot limits exceed per-string/entry caps or current-skia-byte-limit"))
  (void))
(struct memory-statistic (kind name value-name units value) #:transparent)
;; Fields:
;;   kind: 'numeric or 'string. name and value-name: copied immutable names. units: immutable unit
;;   string for numeric values, otherwise #f. value: unsigned 64-bit integer or immutable string
;;   matching kind.

(struct memory-statistics (entries detailed? dump-wrapped? truncated? dropped-count string-bytes)
  #:transparent)
;; Fields:
;;   entries: immutable vector in callback arrival order. detailed? and dump-wrapped?: selected dump
;;   options. truncated?: whether limits dropped data. dropped-count: dropped entries. string-bytes:
;;   accounted copied string bytes. The report contains no native views.

;; Preserve the existing global report shape. The subtype carries only a
;; detached scope tag; parent predicates/accessors work for both report kinds.
(struct scoped-memory-statistics memory-statistics (scope) #:transparent)
;; Fields:
;;   scope: detached symbol identifying the reported native resource scope. Inherited fields retain
;;   the ordinary memory-statistics shape.

; memory-statistics-scope : memory-statistics? -> (or/c 'process-global-skia-caches
;   'gpu-context-skia-resources)
;   Returns the origin of the report.
(define (memory-statistics-scope report)
  (unless (memory-statistics? report)
    (raise-argument-error 'memory-statistics-scope "memory-statistics?" report))
  (if (scoped-memory-statistics? report)
      (scoped-memory-statistics-scope report)
      'process-global-skia-caches))
(struct memory-collector (limit byte-limit detailed? wrapped? [rows #:mutable]
                                [count #:mutable] [bytes #:mutable] [dropped #:mutable]))
;; Fields:
;;   limit and byte-limit: entry and copied-string budgets. detailed? and wrapped?: requested dump
;;   options. rows: accepted entries, newest first. count and bytes: accepted-entry and string-byte
;;   totals. dropped: rejected-entry count.
;;   All counters and rows mutate only during capture; collector-finish reverses rows into detached
;;   arrival order.

; make-memory-collector : any/c any/c any/c any/c -> memory-collector?
;   Starts an empty bounded collector with independent entry and copied-string budgets.
(define (make-memory-collector limit byte-limit detailed? wrapped?)
  (memory-collector limit byte-limit detailed? wrapped? '() 0 0 0))

; collector-room : memory-collector? -> any
;   Reports the unspent copied-string byte budget for the next native statistic.
(define (collector-room c) (- (memory-collector-byte-limit c) (memory-collector-bytes c)))

; collector-full? : memory-collector? -> boolean?
;   Reports whether the accepted-entry limit prevents storing another statistic.
(define (collector-full? c) (>= (memory-collector-count c) (memory-collector-limit c)))

; collector-drop! : memory-collector? -> any
;   Counts an omitted statistic without consuming accepted-entry or string-byte budget.
(define (collector-drop! c) (set-memory-collector-dropped! c (add1 (memory-collector-dropped c))))

; collector-add! : memory-collector? any/c bytes? bytes? any/c any/c -> void?
;   Validates copied callback values and stores an immutable statistic only if both budgets permit
;   it.
(define (collector-add! c kind name key units value)
  ;; Arguments have already been bounded/copied by the private callback. Store
  ;; immutable strings, so returned evidence cannot alias native storage.
  (unless (and (memq kind '(numeric string)) (bytes? name) (bytes? key)
               (if (eq? kind 'numeric)
                   (and (bytes? units) (exact-nonnegative-integer? value) (<= value
                     #xffffffffffffffff))
                   (and (not units) (bytes? value))))
    (error 'memory-statistics "invalid private statistic"))
  (define n (+ (bytes-length name) (bytes-length key)
               (if units (bytes-length units) (bytes-length value))))
  (cond [(or (collector-full? c) (> n (collector-room c))) (collector-drop! c)]
        [else
         (define (text b) (string->immutable-string (bytes->string/utf-8 b #f)))
         (define entry (memory-statistic kind (text name) (text key)
                                         (and units (text units))
                                         (if units value (text value))))
         (set-memory-collector-rows! c (cons entry (memory-collector-rows c)))
         (set-memory-collector-count! c (add1 (memory-collector-count c)))
         (set-memory-collector-bytes! c (+ n (memory-collector-bytes c)))])
  (void))

; collector-finish : memory-collector? [#:scope any/c] -> any
;   Returns a detached immutable-vector report in callback arrival order with truncation and scope
;   evidence.
(define (collector-finish c #:scope [scope 'process-global-skia-caches])
  (unless (memq scope '(process-global-skia-caches gpu-context-skia-resources))
    (raise-argument-error 'collector-finish "known native memory-statistics scope" scope))
  (define constructor
    (if (eq? scope 'process-global-skia-caches)
        memory-statistics
        (lambda (entries detailed? wrapped? truncated? dropped bytes)
          (scoped-memory-statistics entries detailed? wrapped? truncated? dropped bytes scope))))
  (constructor (vector->immutable-vector (list->vector (reverse (memory-collector-rows c))))
                     (memory-collector-detailed? c) (memory-collector-wrapped? c)
                     (positive? (memory-collector-dropped c)) (memory-collector-dropped c)
                     (memory-collector-bytes c)))

; memory-statistics->jsexpr : memory-statistics? -> (and/c hash? immutable?)
;   Returns a detached JSON-compatible hash with scope, an explicit false atomic flag, requested
;   options, truncation information, string-byte count, and a list of entries.
(define (memory-statistics->jsexpr report)
  (unless (memory-statistics? report)
    (raise-argument-error 'memory-statistics->jsexpr "memory-statistics?" report))
  (hasheq 'scope (symbol->string (memory-statistics-scope report)) 'atomic #f
          'detailed (memory-statistics-detailed? report)
          'dump_wrapped (memory-statistics-dump-wrapped? report)
          'truncated (memory-statistics-truncated? report)
          'dropped_count (memory-statistics-dropped-count report)
          'string_bytes (memory-statistics-string-bytes report)
          'entries
          (for/list ([entry (in-vector (memory-statistics-entries report))])
            (hasheq 'kind (symbol->string (memory-statistic-kind entry))
                    'name (memory-statistic-name entry) 'value_name (memory-statistic-value-name
                      entry)
                    'units (memory-statistic-units entry) 'value (memory-statistic-value entry)))))
