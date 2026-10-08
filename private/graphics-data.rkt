#lang racket/base
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
(define size-max (sub1 (expt 2 (* 8 (ctype-sizeof _size)))))
(define (cache-byte-limit who value)
  (unless (and (exact-nonnegative-integer? value) (<= value size-max))
    (raise-argument-error who "exact nonnegative integer representable as size_t" value))
  value)
(define (cache-count-limit who value)
  (unless (and (exact-nonnegative-integer? value) (<= value #x7fffffff))
    (raise-argument-error who "exact integer from 0 through 2147483647" value))
  value)
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
(struct memory-statistics (entries detailed? dump-wrapped? truncated? dropped-count string-bytes)
  #:transparent)
(define (memory-statistics-scope report)
  (unless (memory-statistics? report)
    (raise-argument-error 'memory-statistics-scope "memory-statistics?" report))
  'process-global-skia-caches)
(struct memory-collector (limit byte-limit detailed? wrapped? [rows #:mutable]
                                [count #:mutable] [bytes #:mutable] [dropped #:mutable]))
(define (make-memory-collector limit byte-limit detailed? wrapped?)
  (memory-collector limit byte-limit detailed? wrapped? '() 0 0 0))
(define (collector-room c) (- (memory-collector-byte-limit c) (memory-collector-bytes c)))
(define (collector-full? c) (>= (memory-collector-count c) (memory-collector-limit c)))
(define (collector-drop! c) (set-memory-collector-dropped! c (add1 (memory-collector-dropped c))))
(define (collector-add! c kind name key units value)
  ;; Arguments have already been bounded/copied by the private callback. Store
  ;; immutable strings, so returned evidence cannot alias native storage.
  (unless (and (memq kind '(numeric string)) (bytes? name) (bytes? key)
               (if (eq? kind 'numeric)
                   (and (bytes? units) (exact-nonnegative-integer? value) (<= value #xffffffffffffffff))
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
(define (collector-finish c)
  (memory-statistics (vector->immutable-vector (list->vector (reverse (memory-collector-rows c))))
                     (memory-collector-detailed? c) (memory-collector-wrapped? c)
                     (positive? (memory-collector-dropped c)) (memory-collector-dropped c)
                     (memory-collector-bytes c)))
(define (memory-statistics->jsexpr report)
  (unless (memory-statistics? report)
    (raise-argument-error 'memory-statistics->jsexpr "memory-statistics?" report))
  (hasheq 'scope "process-global-skia-caches" 'atomic #f
          'detailed (memory-statistics-detailed? report)
          'dump_wrapped (memory-statistics-dump-wrapped? report)
          'truncated (memory-statistics-truncated? report)
          'dropped_count (memory-statistics-dropped-count report)
          'string_bytes (memory-statistics-string-bytes report)
          'entries
          (for/list ([entry (in-vector (memory-statistics-entries report))])
            (hasheq 'kind (symbol->string (memory-statistic-kind entry))
                    'name (memory-statistic-name entry) 'value_name (memory-statistic-value-name entry)
                    'units (memory-statistic-units entry) 'value (memory-statistic-value entry)))))
