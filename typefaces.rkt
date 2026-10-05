#lang racket/base
;; 0.68a: immutable typeface data and owned font-style sets. No SkFont mutation.
(require ffi/unsafe racket/list racket/vector
         "private/core.rkt" "private/native.rkt" "private/lifetime.rkt"
         "private/check.rkt" "private/typeface-util.rkt"
         (submod "private/core.rkt" typeface-internals))
(provide typeface-from-bytes font-manager-typeface-from-bytes
         font-style? make-font-style font-style-weight font-style-width font-style-slant
         font-style-entry? font-style-entry-index font-style-entry-name font-style-entry-style
         font-style-set? make-empty-font-style-set font-manager-style-set font-manager-style-set-ref
         font-style-set-count font-style-set-ref font-style-set-styles
         font-style-set-typeface font-style-set-match typeface-style
         typeface-postscript-name typeface-fixed-pitch? typeface-glyph-count typeface-units-per-em
         font-table-tag font-table-tag->bytes typeface-table-tags typeface-table-size typeface-table-bytes
         typeface-kerning-pair-adjustments typeface->font-bytes)

(define (font-style-set? v) (font-style-set-resource? v))
(define (set-h who v)
  (unless (font-style-set? v) (raise-argument-error who "font-style-set?" v))
  (font-style-set-resource-handle v))
(define (new-set who create)
  (make-font-style-set-record (new-owned who 'font-style-set create sk_fontstyleset_unref)))
(define (new-face who create)
  (make-typeface-record (new-owned who 'typeface create sk_typeface_unref)))

(define (from-bytes who fm data index)
  (define i (typeface-index who index))
  (define mh (and fm (font-manager-h who fm)))
  ;; Check the manager before either native allocation or copying a large input.
  (when mh (call-with-owned who (list mh) (lambda (_) (void))))
  (define copied (typeface-input-bytes who data))
  ;; Pinned m119's CoreText loader rejects nonzero TTC indices; index zero uses
  ;; a singular-descriptor API that rejected the valid generated TTC during
  ;; host acceptance. Rewrap the selected member into an exact standalone SFNT
  ;; on macOS; other backends still exercise native TTC selection directly.
  (define-values (submitted native-index)
    (if (and (eq? (system-type 'os) 'macosx) (ttc-font-collection? copied))
        (values (ttc-member->sfnt who copied i) 0)
        (values copied i)))
  (skia-check!)
  (call-with-native-temporary
   who 'font-data
   (lambda () (sk_data_new_with_copy submitted (bytes-length submitted))) sk_data_unref
   (lambda (dp)
     (begin0
       (if mh
           (call-with-owned who (list mh)
             (lambda (mp) (new-face who (lambda () (sk_fontmgr_create_from_data mp dp native-index)))))
           (new-face who (lambda () (sk_typeface_create_from_data dp native-index))))
       (void/reference-sink copied submitted)))))
(define (typeface-from-bytes data #:index [index 0])
  (from-bytes 'typeface-from-bytes #f data index))
(define (font-manager-typeface-from-bytes manager data #:index [index 0])
  ;; Unlike the private optional-manager helper, the public manager is required.
  (font-manager-h 'font-manager-typeface-from-bytes manager)
  (from-bytes 'font-manager-typeface-from-bytes manager data index))

(define (make-empty-font-style-set)
  (skia-check!)
  (new-set 'make-empty-font-style-set sk_fontstyleset_create_empty))
(define (font-manager-style-set manager family)
  (define who 'font-manager-style-set)
  (define h (font-manager-h who manager))
  (define name (typeface-family-bytes who family))
  (call-with-owned who (list h)
    (lambda (mp)
      ;; matchFamily promises a non-null empty set for a missing family.
      (begin0 (new-set who (lambda () (sk_fontmgr_match_family mp name)))
        (void/reference-sink name)))))
(define (font-manager-style-set-ref manager index)
  (define who 'font-manager-style-set-ref)
  (define i (typeface-index who index))
  (call-with-owned who (list (font-manager-h who manager))
    (lambda (mp)
      (define count (typeface-count who (sk_fontmgr_count_families mp)))
      (unless (< i count)
        (raise-arguments-error who "family index out of range" "index" i "count" count))
      (new-set who (lambda () (sk_fontmgr_create_styleset mp i))))))
(define (set-count who sp) (typeface-count who (sk_fontstyleset_get_count sp)))
(define (font-style-set-count styles)
  (define who 'font-style-set-count)
  (call-with-owned who (list (set-h who styles)) (lambda (sp) (set-count who sp))))
(define (check-index who sp i)
  (define count (set-count who sp))
  (unless (< i count)
    (raise-arguments-error who "style index out of range" "index" i "count" count)))
(define (native-slant who value)
  (case value [(0) 'upright] [(1) 'italic] [(2) 'oblique]
    [else (error who "invalid native font slant: ~a" value)]))
(define (read-entry who sp i)
  (call-with-native-temporary
   who 'font-style (lambda () (sk_fontstyle_new 400 5 0)) sk_fontstyle_delete
   (lambda (style)
     (call-with-native-temporary
      who 'native-string sk_string_new_empty sk_string_destructor
      (lambda (name)
        (sk_fontstyleset_get_style sp i style name)
        (define value (make-font-style #:weight (sk_fontstyle_get_weight style)
                                      #:width (sk_fontstyle_get_width style)
                                      #:slant (native-slant who (sk_fontstyle_get_slant style))))
        (define label (string->immutable-string (copy-sk-string who name)))
        (typeface-budget who (+ 16 (bytes-length (string->bytes/utf-8 label))))
        (make-font-style-entry-record i label value))))))
(define (font-style-set-ref styles index)
  (define who 'font-style-set-ref)
  (define i (typeface-index who index))
  (call-with-owned who (list (set-h who styles))
    (lambda (sp) (check-index who sp i) (read-entry who sp i))))
(define (font-style-set-styles styles)
  (define who 'font-style-set-styles)
  (call-with-owned who (list (set-h who styles))
    (lambda (sp)
      (define count (set-count who sp))
      (typeface-budget who (* count 16))
      (define charged (* count 16))
      (vector->immutable-vector
       (for/vector ([i (in-range count)])
         (define entry (read-entry who sp i))
         (set! charged (+ charged (bytes-length (string->bytes/utf-8 (font-style-entry-name entry)))))
         (typeface-budget who charged)
         entry)))))
(define (font-style-set-typeface styles index)
  (define who 'font-style-set-typeface)
  (define i (typeface-index who index))
  (call-with-owned who (list (set-h who styles))
    (lambda (sp)
      (check-index who sp i)
      (new-face who (lambda () (sk_fontstyleset_create_typeface sp i))))))
(define (font-style-set-match styles [pattern (make-font-style)])
  (define who 'font-style-set-match)
  (check-font-style who pattern)
  (call-with-owned who (list (set-h who styles))
    (lambda (sp)
      (and (positive? (set-count who sp))
           (call-with-native-temporary
            who 'font-style
            (lambda () (sk_fontstyle_new (font-style-weight pattern) (font-style-width pattern)
                                         (choice who (font-style-slant pattern) font-slant-values)))
            sk_fontstyle_delete
            (lambda (fp) (new-face who (lambda () (sk_fontstyleset_match_style sp fp)))))))))

(define (typeface-style face)
  (define who 'typeface-style)
  (call-with-owned who (list (typeface-h who face))
    (lambda (tp)
      (make-font-style #:weight (sk_typeface_get_font_weight tp)
                       #:width (sk_typeface_get_font_width tp)
                       #:slant (native-slant who (sk_typeface_get_font_slant tp))))))
(define (typeface-postscript-name face)
  (define who 'typeface-postscript-name)
  (call-with-owned who (list (typeface-h who face))
    (lambda (tp)
      (call-with-native-temporary
       who 'native-string (lambda () (sk_typeface_get_post_script_name tp)) sk_string_destructor
       (lambda (sp)
         ;; The shim discards getPostScriptName's boolean, leaving an empty
         ;; SkString when unavailable. It nevertheless returns an owned string.
         (define name (copy-sk-string who sp))
         (and (positive? (string-length name)) (string->immutable-string name)))))))
(define (typeface-fixed-pitch? face)
  (call-with-owned 'typeface-fixed-pitch? (list (typeface-h 'typeface-fixed-pitch? face))
                   sk_typeface_is_fixed_pitch))
(define (typeface-glyph-count face)
  (define who 'typeface-glyph-count)
  (call-with-owned who (list (typeface-h who face))
    (lambda (tp) (typeface-count who (sk_typeface_count_glyphs tp)))))
(define (typeface-units-per-em face)
  (define who 'typeface-units-per-em)
  (call-with-owned who (list (typeface-h who face))
    (lambda (tp)
      (define n (typeface-count who (sk_typeface_get_units_per_em tp)))
      (and (positive? n) n))))

(define (table-tags who tp)
  (define n (typeface-count who (sk_typeface_count_tables tp) 4))
  (if (zero? n) #()
      (let ([buf (malloc n _uint32 'atomic)])
        (define written (sk_typeface_get_table_tags tp buf))
        (unless (= n written) (error who "native table count changed: ~a to ~a" n written))
        (define tags (for/list ([i (in-range n)]) (ptr-ref buf _uint32 i)))
        (unless (= n (length (remove-duplicates tags))) (error who "duplicate native table tags"))
        (vector->immutable-vector (list->vector tags)))))
(define (table-size who tp tag)
  (define n (sk_typeface_get_table_size tp tag))
  ;; getTableSize uses 0 for both absent and zero-byte tables. Consult the
  ;; tag list only in that case; do not turn an absent table into empty data.
  (and (or (positive? n) (for/or ([t (in-vector (table-tags who tp))]) (= t tag))) n))
(define (typeface-table-tags face)
  (define who 'typeface-table-tags)
  (call-with-owned who (list (typeface-h who face)) (lambda (tp) (table-tags who tp))))
(define (typeface-table-size face tag)
  (define who 'typeface-table-size)
  (define t (font-table-tag tag))
  (call-with-owned who (list (typeface-h who face)) (lambda (tp) (table-size who tp t))))
(define (typeface-table-bytes face tag #:start [start 0] #:end [end #f])
  (define who 'typeface-table-bytes)
  (define t (font-table-tag tag))
  ;; Structural argument errors must not be hidden by an absent table.
  (unless (exact-nonnegative-integer? start)
    (raise-argument-error who "exact-nonnegative-integer? for #:start" start))
  (unless (or (not end) (and (exact-nonnegative-integer? end) (>= end start)))
    (raise-argument-error who "#f or an exact end index not before start" end))
  (call-with-owned who (list (typeface-h who face))
    (lambda (tp)
      (define size (table-size who tp t))
      (and size
           (let-values ([(first stop) (typeface-slice who size start end)])
             (define n (- stop first))
             (cond
               [(zero? n) #""]
               [(and (zero? first) (= stop size))
                ;; Query and budget BEFORE asking native code to copy a table.
                (call-with-native-temporary
                 who 'font-table (lambda () (sk_typeface_copy_table_data tp t)) sk_data_unref
                 (lambda (dp)
                   (unless (= (sk_data_get_size dp) n) (error who "native table size changed"))
                   (bytes->immutable-bytes (copy-native-data who dp))))]
               [else
                (define out (make-bytes n 0))
                (define got (sk_typeface_get_table_data tp t first n out))
                (unless (= got n) (error who "short native table read: expected ~a, got ~a" n got))
                (bytes->immutable-bytes out)]))))))

(define (typeface-kerning-pair-adjustments face glyphs)
  (define who 'typeface-kerning-pair-adjustments)
  (define gs (typeface-glyphs who glyphs))
  (define n (length gs))
  (call-with-owned who (list (typeface-h who face))
    (lambda (tp)
      (define count (typeface-count who (sk_typeface_count_glyphs tp)))
      (for ([g (in-list gs)])
        (unless (< g count)
          (raise-arguments-error who "glyph ID is outside this typeface" "glyph" g "glyph count" count)))
      (cond
        [(< n 2) #()]
        [else
         (define input (malloc n _uint16 'atomic))
         (define output (malloc (sub1 n) _int32 'atomic))
         (for ([g (in-list gs)] [i (in-naturals)]) (ptr-set! input _uint16 i g))
         ;; False leaves the adjustment array undefined. NEVER read it then.
         (and (sk_typeface_get_kerning_pair_adjustments tp input n output)
              (vector->immutable-vector
               (for/vector ([i (in-range (sub1 n))]) (ptr-ref output _int32 i))))]))))
(define (typeface->font-bytes face)
  (define who 'typeface->font-bytes)
  ;; Reuse the bounded stream-copy helper already used by HarfBuzz; it closes
  ;; the native stream before returning. This is not live Racket-port streaming.
  (call-with-owned who (list (typeface-h who face))
    (lambda (tp)
      (define-values (data index) (typeface-font-bytes who tp))
      (typeface-index who index)
      (values (bytes->immutable-bytes data) index))))
