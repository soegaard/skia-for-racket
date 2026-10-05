#lang racket/base
;; 0.68b: checked SkFont options and unshaped glyph queries.
(require ffi/unsafe racket/list racket/vector
         "private/core.rkt" "private/native.rkt" "private/types.rkt"
         "private/lifetime.rkt" "private/check.rkt" "private/font-query-util.rkt"
         (submod "private/core.rkt" font-query-internals))
(provide font-embedded-bitmaps? font-set-embedded-bitmaps!
         font-force-auto-hinting? font-set-force-auto-hinting!
         font-baseline-snap? font-set-baseline-snap!
         font-typeface font-set-typeface!
         font-glyph-widths font-glyph-bounds font-glyph-widths+bounds
         font-glyph-positions font-glyph-x-positions font-glyph-paths
         font-break-text)

(define (font-embedded-bitmaps? f)
  (font-native-get 'font-embedded-bitmaps? f sk_font_is_embedded_bitmaps))
(define (font-set-embedded-bitmaps! f value)
  (font-native-set! 'font-set-embedded-bitmaps! f
                    (boolean 'font-set-embedded-bitmaps! value) sk_font_set_embedded_bitmaps))
(define (font-force-auto-hinting? f)
  (font-native-get 'font-force-auto-hinting? f sk_font_is_force_auto_hinting))
(define (font-set-force-auto-hinting! f value)
  (font-native-set! 'font-set-force-auto-hinting! f
                    (boolean 'font-set-force-auto-hinting! value) sk_font_set_force_auto_hinting))
(define (font-baseline-snap? f)
  (font-native-get 'font-baseline-snap? f sk_font_is_baseline_snap))
(define (font-set-baseline-snap! f value)
  (font-native-set! 'font-set-baseline-snap! f
                    (boolean 'font-set-baseline-snap! value) sk_font_set_baseline_snap))

(define (font-typeface f)
  (define who 'font-typeface)
  (call-with-owned who (list (font-h who f))
    (lambda (fp)
      ;; The pinned shim returns an OWNED reference, not a borrowed pointer.
      (make-typeface-record
       (new-owned who 'typeface (lambda () (sk_font_get_typeface fp)) sk_typeface_unref)))))

(define (font-set-typeface! f face)
  (define who 'font-set-typeface!)
  ;; Explicit non-null typefaces only. Use (make-typeface) to select a default.
  (call-with-owned who (list (font-h who f) (typeface-h who face))
    (lambda (fp tp)
      ;; m119 calls setTypeface(sk_ref_sp(...)); the font retains its own ref.
      (sk_font_set_typeface fp tp)
      ;; Drop only our private construction-time default wrapper, never face.
      (define old-owner (font-owner f))
      (set-font-owner! f #f)
      (when old-owner (skia-close! old-owner))
      (void))))

(define (check-face-glyphs who fp gs)
  (unless (zero? (vector-length gs))
    (call-with-native-temporary
     who 'font-query-typeface (lambda () (sk_font_get_typeface fp)) sk_typeface_unref
     (lambda (tp)
       (define count (sk_typeface_count_glyphs tp))
       (unless (and (exact-nonnegative-integer? count) (<= count 65536))
         (error who "invalid native typeface glyph count: ~a" count))
       (for ([g (in-vector gs)])
         (unless (< g count)
           (raise-arguments-error who "glyph ID is outside this font's typeface"
                                  "glyph" g "glyph count" count)))))))
(define (glyph-array gs)
  ;; getPaths calls back into Racket and can allocate/collect. Pin the native
  ;; input buffer so its address cannot move while Skia is iterating it.
  (define out (malloc (vector-length gs) _uint16 'atomic-interior))
  (for ([g (in-vector gs)] [i (in-naturals)]) (ptr-set! out _uint16 i g))
  out)
(define (floats->vector who ptr count)
  (vector->immutable-vector
   (for/vector ([i (in-range count)]) (scalar who (ptr-ref ptr _float i)))))

(define (query-widths+bounds who f glyphs p widths? bounds?)
  (define gs (font-query-glyphs who glyphs (+ 18 (if widths? 12 0) (if bounds? 48 0))))
  (call-with-font+paint
   who f p
   (lambda (fp pp)
     (check-face-glyphs who fp gs)
     (define n (vector-length gs))
     (cond
       [(zero? n) (values #() #())]
       [else
        (define input (glyph-array gs))
        (define widths (and widths? (malloc n _float 'atomic)))
        (define bounds (and bounds? (malloc (* n 4) _float 'atomic)))
        (sk_font_get_widths_bounds fp input n widths bounds pp)
        (define ws (if widths? (floats->vector who widths n) #()))
        (define bs
          (if bounds?
              (vector->immutable-vector
               (for/vector ([i (in-range n)])
                 (define j (* 4 i))
                 (define left (scalar who (ptr-ref bounds _float j)))
                 (define top (scalar who (ptr-ref bounds _float (+ j 1))))
                 (define right (scalar who (ptr-ref bounds _float (+ j 2))))
                 (define bottom (scalar who (ptr-ref bounds _float (+ j 3))))
                 ;; Match simple-text-bounds: x, y, width, height, not LTRB.
                 (list left top (nonnegative-scalar who (- right left))
                       (nonnegative-scalar who (- bottom top)))))
              #()))
        (void/reference-sink gs input widths bounds)
        (values ws bs)]))))
(define (font-glyph-widths+bounds f glyphs #:paint [p #f])
  (query-widths+bounds 'font-glyph-widths+bounds f glyphs p #t #t))
(define (font-glyph-widths f glyphs #:paint [p #f])
  (define-values (widths bounds) (query-widths+bounds 'font-glyph-widths f glyphs p #t #f))
  widths)
(define (font-glyph-bounds f glyphs #:paint [p #f])
  (define-values (widths bounds) (query-widths+bounds 'font-glyph-bounds f glyphs p #f #t))
  bounds)

(define (font-glyph-positions f glyphs #:origin [origin '(0 0)])
  (define who 'font-glyph-positions)
  (define xy (font-query-origin who origin))
  (define gs (font-query-glyphs who glyphs 42))
  (call-with-owned who (list (font-h who f))
    (lambda (fp)
      (check-face-glyphs who fp gs)
      (define n (vector-length gs))
      (cond
        [(zero? n) #()]
        [else
         (define input (glyph-array gs))
         (define output (malloc (* n 2) _float 'atomic))
         ;; The C shim DEREFERENCES origin, so even zero origin is non-null.
         (define start (make-sk-point (car xy) (cadr xy)))
         (sk_font_get_pos fp input n output start)
         (define result
           (vector->immutable-vector
            (for/vector ([i (in-range n)])
              (list (scalar who (ptr-ref output _float (* i 2)))
                    (scalar who (ptr-ref output _float (+ 1 (* i 2))))))))
         (void/reference-sink gs input output start)
         result]))))
(define (font-glyph-x-positions f glyphs #:origin [origin 0])
  (define who 'font-glyph-x-positions)
  (define x (scalar who origin))
  (define gs (font-query-glyphs who glyphs 30))
  (call-with-owned who (list (font-h who f))
    (lambda (fp)
      (check-face-glyphs who fp gs)
      (define n (vector-length gs))
      (cond
        [(zero? n) #()]
        [else
         (define input (glyph-array gs))
         (define output (malloc n _float 'atomic))
         (sk_font_get_xpos fp input n output x)
         (define result (floats->vector who output n))
         (void/reference-sink gs input output)
         result]))))

;; A synchronous internal callback, never an application-supplied procedure.
;; Explicit pointer retention lasts through the complete native invocation.
(define (font-glyph-paths f glyphs)
  (define who 'font-glyph-paths)
  (define gs (font-query-glyphs who glyphs 66))
  (call-with-owned who (list (font-h who f))
    (lambda (fp)
      (check-face-glyphs who fp gs)
      (define n (vector-length gs))
      (cond
        [(zero? n) #()]
        [else
         (define input (glyph-array gs))
         (define charged (* n 66))
         (define (copy-path borrowed matrix)
           (unless matrix (error who "native glyph callback returned a null transform"))
           (define points (sk_path_count_points borrowed))
           (define verbs (sk_path_count_verbs borrowed))
           (unless (and (exact-nonnegative-integer? points) (exact-nonnegative-integer? verbs))
             (error who "native glyph callback returned invalid path counts"))
           ;; Conservative charge for copied controls, verbs, and path wrappers.
           ;; Skia caches/temporary allocations are outside this wrapper limit.
           (set! charged (+ charged (* points 32) (* verbs 4)))
           (font-query-budget who charged)
           (define p (make-path))
           (with-handlers ([(lambda (_) #t) (lambda (value) (skia-close! p) (raise value))])
             (call-with-owned who (list (path-h who p))
               (lambda (out)
                 (sk_path_set_filltype out (sk_path_get_filltype borrowed))
                 ;; getPaths supplies canonical outlines PLUS a transform.
                 ;; Ignoring this matrix loses font size/scale/skew semantics.
                 (sk_path_add_path_matrix out borrowed matrix 0)))
             p))
         (define result
           (collect-glyph-path-results
            who n
            (lambda (receive)
              (define keeper (box #f))
              (define callback
                (function-ptr receive
                  (_fun #:atomic? #t #:keep keeper _pointer _pointer _pointer -> _void)))
              (dynamic-wind void
                (lambda () (sk_font_get_paths fp input n callback #f))
                (lambda () (set-box! keeper #f)))
              (void/reference-sink keeper callback receive input gs))
            copy-path skia-close!))
         result]))))

(define (font-break-text f text max-width #:paint [p #f])
  (define who 'font-break-text)
  (define width (nonnegative-scalar who max-width))
  (define utf8 (font-query-text who text))
  (call-with-font+paint
   who f p
   (lambda (fp pp)
     (cond
       [(zero? (bytes-length utf8)) (values 0 0.0)]
       [else
        (define measured (malloc _float 'atomic))
        (ptr-set! measured _float 0.0)
        (define count
          (sk_font_break_text fp utf8 (bytes-length utf8) text-encoding-utf8 width measured pp))
        (define result-width (nonnegative-scalar who (ptr-ref measured _float)))
        (define chars (font-break-prefix-length who utf8 count))
        (void/reference-sink utf8 measured)
        (values chars result-width)]))))
