#lang racket/base

;;;
;;; Typeface Data and Font Style Sets
;;;

;; Loads typefaces, queries font styles and tables, and copies native font data.
;; This public font-resource layer extends font-manager lookup with owned style sets and detached
;; typeface metadata.

;;;
;;; Imports and Exports
;;;

;; 0.68a: immutable typeface data and owned font-style sets. No SkFont mutation.
(require ffi/unsafe racket/list racket/vector
         "private/core.rkt" "private/native.rkt" "private/lifetime.rkt"
         "private/check.rkt" "private/typeface-util.rkt"
         (submod "private/core.rkt" typeface-internals))
(provide typeface-from-bytes
         font-manager-typeface-from-bytes
         font-style?
         make-font-style
         font-style-weight
         font-style-width
         font-style-slant
         font-style-entry?
         font-style-entry-index
         font-style-entry-name
         font-style-entry-style
         font-style-set?
         make-empty-font-style-set
         font-manager-style-set
         font-manager-style-set-ref
         font-style-set-count
         font-style-set-ref
         font-style-set-styles
         font-style-set-typeface
         font-style-set-match
         typeface-style
         typeface-postscript-name
         typeface-fixed-pitch?
         typeface-glyph-count
         typeface-units-per-em
         font-table-tag
         font-table-tag->bytes
         typeface-table-tags
         typeface-table-size
         typeface-table-bytes
         typeface-kerning-pair-adjustments
         typeface->font-bytes)

; font-style-set? : any/c -> boolean?
;   Returns #t for an owned font-style-set resource and #f otherwise.
(define (font-style-set? v) (font-style-set-resource? v))

; set-h : symbol? font-style-set? -> (or/c owned? domain-resource?)
;   Checks a font-style-set wrapper and retrieves its managed native handle.
(define (set-h who v)
  (unless (font-style-set? v) (raise-argument-error who "font-style-set?" v))
  (font-style-set-resource-handle v))

; new-set : symbol? procedure? -> font-style-set?
;   Adopts a newly owned native font-style set.
(define (new-set who create)
  (make-font-style-set-record (new-owned who 'font-style-set create sk_fontstyleset_unref)))

; new-face : symbol? procedure? -> typeface?
;   Adopts a newly owned native typeface.
(define (new-face who create)
  (make-typeface-record (new-owned who 'typeface create sk_typeface_unref)))

; from-bytes : symbol? (or/c #f font-manager?) bytes? exact-nonnegative-integer? -> typeface?
;   Copies font data and selects a collection member, rewrapping TTC members for the macOS loader.
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
             (lambda (mp)
               (new-face who (lambda () (sk_fontmgr_create_from_data mp dp native-index)))))
           (new-face who (lambda () (sk_typeface_create_from_data dp native-index))))
       (void/reference-sink copied submitted)))))

;;;
;;; Copied Font Input
;;;

; typeface-from-bytes : bytes? [#:index (integer-in 0 2147483647)] -> typeface?
;   Creates an owned typeface from copied font data.
(define (typeface-from-bytes data #:index [index 0])
  (from-bytes 'typeface-from-bytes #f data index))

; font-manager-typeface-from-bytes : font-manager? bytes? [#:index (integer-in 0 2147483647)] ->
;   typeface?
;   Like typeface-from-bytes, but loads through manager.
(define (font-manager-typeface-from-bytes manager data #:index [index 0])
  ;; Unlike the private optional-manager helper, the public manager is required.
  (font-manager-h 'font-manager-typeface-from-bytes manager)
  (from-bytes 'font-manager-typeface-from-bytes manager data index))


;;;
;;; Font Style Sets
;;;

; make-empty-font-style-set : -> font-style-set?
;   Creates an owned style set with no entries.
(define (make-empty-font-style-set)
  (skia-check!)
  (new-set 'make-empty-font-style-set sk_fontstyleset_create_empty))

; font-manager-style-set : font-manager? string? -> font-style-set?
;   Returns an owned set of styles for family in manager.
(define (font-manager-style-set manager family)
  (define who 'font-manager-style-set)
  (define h (font-manager-h who manager))
  (define name (typeface-family-bytes who family))
  (call-with-owned who (list h)
    (lambda (mp)
      ;; matchFamily promises a non-null empty set for a missing family.
      (begin0 (new-set who (lambda () (sk_fontmgr_match_family mp name)))
        (void/reference-sink name)))))

; font-manager-style-set-ref : font-manager? (integer-in 0 2147483647) -> font-style-set?
;   Returns an owned style set for the zero-based family index in manager.
(define (font-manager-style-set-ref manager index)
  (define who 'font-manager-style-set-ref)
  (define i (typeface-index who index))
  (call-with-owned who (list (font-manager-h who manager))
    (lambda (mp)
      (define count (typeface-count who (sk_fontmgr_count_families mp)))
      (unless (< i count)
        (raise-arguments-error who "family index out of range" "index" i "count" count))
      (new-set who (lambda () (sk_fontmgr_create_styleset mp i))))))

; set-count : symbol? cpointer? -> exact-nonnegative-integer?
;   Reads and validates the native font-style count.
(define (set-count who sp) (typeface-count who (sk_fontstyleset_get_count sp)))

; font-style-set-count : font-style-set? -> exact-nonnegative-integer?
;   Returns the number of entries in the open style set.
(define (font-style-set-count styles)
  (define who 'font-style-set-count)
  (call-with-owned who (list (set-h who styles)) (lambda (sp) (set-count who sp))))

; check-index : symbol? cpointer? exact-nonnegative-integer? -> void?
;   Checks a validated nonnegative style index against the native set's count.
(define (check-index who sp i)
  (define count (set-count who sp))
  (unless (< i count)
    (raise-arguments-error who "style index out of range" "index" i "count" count)))

; native-slant : symbol? exact-integer? -> (or/c 'upright 'italic 'oblique)
;   Converts a native font-slant enumeration, rejecting unknown values.
(define (native-slant who value)
  (case value [(0) 'upright] [(1) 'italic] [(2) 'oblique]
    [else (error who "invalid native font slant: ~a" value)]))

; read-entry : symbol? cpointer? exact-nonnegative-integer? -> font-style-entry?
;   Copies an indexed style and label into a detached, budget-checked entry.
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

; font-style-set-ref : font-style-set? (integer-in 0 2147483647) -> font-style-entry?
;   Returns a detached description of the indexed style.
(define (font-style-set-ref styles index)
  (define who 'font-style-set-ref)
  (define i (typeface-index who index))
  (call-with-owned who (list (set-h who styles))
    (lambda (sp) (check-index who sp i) (read-entry who sp i))))

; font-style-set-styles : font-style-set? -> (vectorof font-style-entry?)
;   Returns an immutable vector of all style descriptions in enumeration order.
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

; font-style-set-typeface : font-style-set? (integer-in 0 2147483647) -> typeface?
;   Returns an owned typeface for the indexed style.
(define (font-style-set-typeface styles index)
  (define who 'font-style-set-typeface)
  (define i (typeface-index who index))
  (call-with-owned who (list (set-h who styles))
    (lambda (sp)
      (check-index who sp i)
      (new-face who (lambda () (sk_fontstyleset_create_typeface sp i))))))

; font-style-set-match : font-style-set? [font-style?] -> (or/c typeface? #f)
;   Returns an owned typeface matching pattern in the set.
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


;;;
;;; Typeface Metadata
;;;

; typeface-style : typeface? -> font-style?
;   Returns a detached style description for the actual face.
(define (typeface-style face)
  (define who 'typeface-style)
  (call-with-owned who (list (typeface-h who face))
    (lambda (tp)
      (make-font-style #:weight (sk_typeface_get_font_weight tp)
                       #:width (sk_typeface_get_font_width tp)
                       #:slant (native-slant who (sk_typeface_get_font_slant tp))))))

; typeface-postscript-name : typeface? -> (or/c (and/c string? immutable?) #f)
;   Returns a copied PostScript name, or #f when the native name is unavailable or empty.
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

; typeface-fixed-pitch? : typeface? -> boolean?
;   Reports the face's fixed-pitch property.
(define (typeface-fixed-pitch? face)
  (call-with-owned 'typeface-fixed-pitch? (list (typeface-h 'typeface-fixed-pitch? face))
                   sk_typeface_is_fixed_pitch))

; typeface-glyph-count : typeface? -> exact-nonnegative-integer?
;   Returns the number of glyphs in the face, not the number of supported Unicode characters.
(define (typeface-glyph-count face)
  (define who 'typeface-glyph-count)
  (call-with-owned who (list (typeface-h who face))
    (lambda (tp) (typeface-count who (sk_typeface_count_glyphs tp)))))

; typeface-units-per-em : typeface? -> (or/c exact-positive-integer? #f)
;   Returns the font's design units per em, or #f when the native value is zero.
(define (typeface-units-per-em face)
  (define who 'typeface-units-per-em)
  (call-with-owned who (list (typeface-h who face))
    (lambda (tp)
      (define n (typeface-count who (sk_typeface_get_units_per_em tp)))
      (and (positive? n) n))))


;;;
;;; Font Tables and Raw Data
;;;

; table-tags : symbol? cpointer? -> vector?
;   Copies unique native font-table tags in native enumeration order after bounding the allocation.
(define (table-tags who tp)
  (define n (typeface-count who (sk_typeface_count_tables tp) 4))
  (if (zero? n) #()
      (let ([buf (malloc n _uint32 'atomic)])
        (define written (sk_typeface_get_table_tags tp buf))
        (unless (= n written) (error who "native table count changed: ~a to ~a" n written))
        (define tags (for/list ([i (in-range n)]) (ptr-ref buf _uint32 i)))
        (unless (= n (length (remove-duplicates tags))) (error who "duplicate native table tags"))
        (vector->immutable-vector (list->vector tags)))))

; table-size : symbol? cpointer? exact-nonnegative-integer? -> (or/c #f exact-nonnegative-integer?)
;   Distinguishes an absent font table from a present zero-byte table.
(define (table-size who tp tag)
  (define n (sk_typeface_get_table_size tp tag))
  ;; getTableSize uses 0 for both absent and zero-byte tables. Consult the
  ;; tag list only in that case; do not turn an absent table into empty data.
  (and (or (positive? n) (for/or ([t (in-vector (table-tags who tp))]) (= t tag))) n))

; typeface-table-tags : typeface? -> (vectorof (integer-in 0 4294967295))
;   Returns an immutable vector of available table tags.
(define (typeface-table-tags face)
  (define who 'typeface-table-tags)
  (call-with-owned who (list (typeface-h who face)) (lambda (tp) (table-tags who tp))))

; typeface-table-size : typeface? (or/c (integer-in 0 4294967295) bytes? string?) -> (or/c
;   exact-nonnegative-integer? #f)
;   Returns the byte length of the selected table, or #f when absent.
(define (typeface-table-size face tag)
  (define who 'typeface-table-size)
  (define t (font-table-tag tag))
  (call-with-owned who (list (typeface-h who face)) (lambda (tp) (table-size who tp t))))

; typeface-table-bytes : typeface? (or/c (integer-in 0 4294967295) bytes? string?) [#:start
;   exact-nonnegative-integer?] [#:end (or/c exact-nonnegative-integer? #f)] -> (or/c (and/c bytes?
;   immutable?) #f)
;   Returns a copied immutable byte string from start inclusive to end exclusive, or #f for an
;   absent table.
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

; typeface-kerning-pair-adjustments : typeface? (or/c (listof (integer-in 0 65535)) (vectorof
;   (integer-in 0 65535))) -> (or/c (vectorof exact-integer?) #f)
;   Returns an immutable vector of adjustments for successive glyph pairs, measured in font design
;   units, or #f when native pair adjustments are unavailable.
(define (typeface-kerning-pair-adjustments face glyphs)
  (define who 'typeface-kerning-pair-adjustments)
  (define gs (typeface-glyphs who glyphs))
  (define n (length gs))
  (call-with-owned who (list (typeface-h who face))
    (lambda (tp)
      (define count (typeface-count who (sk_typeface_count_glyphs tp)))
      (for ([g (in-list gs)])
        (unless (< g count)
          (raise-arguments-error who "glyph ID is outside this typeface"
                                 "glyph" g "glyph count" count)))
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

; typeface->font-bytes : typeface? -> (values (and/c bytes? immutable?) (integer-in 0 2147483647))
;   Returns copied font data and its collection index as two values.
(define (typeface->font-bytes face)
  (define who 'typeface->font-bytes)
  ;; Reuse the bounded stream-copy helper already used by HarfBuzz; it closes
  ;; the native stream before returning. This is not live Racket-port streaming.
  (call-with-owned who (list (typeface-h who face))
    (lambda (tp)
      (define-values (data index) (typeface-font-bytes who tp))
      (typeface-index who index)
      (values (bytes->immutable-bytes data) index))))
