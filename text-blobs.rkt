#lang racket/base
(require ffi/unsafe racket/list racket/vector
         "private/core.rkt" "private/native.rkt" "private/types.rkt"
         "private/lifetime.rkt" "private/check.rkt" "private/text-run-data.rkt"
         "private/text-run-util.rkt" "private/path-matrix.rkt" "matrix.rkt"
         (only-in "geometry-primitives.rkt" atlas-transform? atlas-transform-coefficients)
         (submod "private/core.rkt" text-blob-internals))
(provide text-blob-builder? make-text-blob-builder text-blob-builder-run-count
         text-blob-builder-add-run! text-blob-builder-add-horizontal-run!
         text-blob-builder-add-positioned-run! text-blob-builder-add-transformed-run!
         text-blob-builder-add-shaped-run! text-blob-builder-finish!
         text-blob-run-count text-blob-runs text-blob-run-font text-blob-intercepts
         text-run-info? text-run-info-positioning text-run-info-glyphs
         text-run-info-positions text-run-info-transforms text-run-info-utf8 text-run-info-clusters
         positioned-glyphs->path shaped-run->text-blob/on-path draw-shaped-run/on-path)

(define (text-blob-builder? v) (text-blob-builder-resource? v))
(define (builder-h who b)
  (unless (text-blob-builder? b) (raise-argument-error who "text-blob-builder?" b))
  (text-blob-builder-resource-handle b))
(define (make-text-blob-builder)
  (skia-check!)
  (make-text-blob-builder-record
   (new-owned 'make-text-blob-builder 'text-blob-builder
              sk_textblob_builder_new sk_textblob_builder_delete)
   (box '()) (box 0)))
(define (text-blob-builder-run-count b)
  (call-with-owned 'text-blob-builder-run-count (list (builder-h 'text-blob-builder-run-count b))
    (lambda (_) (length (unbox (text-blob-builder-resource-runs b))))))
(define (check-face-glyphs who fp gs)
  (call-with-native-temporary
   who 'typeface-from-font (lambda () (sk_font_get_typeface fp)) sk_typeface_unref
   (lambda (tp)
     (define n (sk_typeface_count_glyphs tp))
     (unless (exact-nonnegative-integer? n) (error who "invalid native glyph count"))
     (for ([g (in-list gs)])
       (unless (< g n)
         (raise-arguments-error who "glyph ID is outside this font's typeface" "glyph" g "glyph count" n))))))
(define (copy-font who fp)
  (call-with-native-temporary
   who 'typeface-from-font (lambda () (sk_font_get_typeface fp)) sk_typeface_unref
   (lambda (tp) (copy-font-for-shaper who fp tp))))
(define (glyph-buffer gs)
  (and (pair? gs)
       (let ([buf (malloc (length gs) _uint16 'atomic)])
         (for ([g (in-list gs)] [i (in-naturals)]) (ptr-set! buf _uint16 i g))
         buf)))
(define (default-positions who fp gs origin)
  (define n (length gs))
  (define input (glyph-buffer gs))
  (define output (malloc (* n 2) _float 'atomic))
  (define at (make-sk-point (car origin) (cadr origin)))
  (sk_font_get_pos fp input n output at)
  (begin0
    (for/list ([i (in-range n)])
      (list (scalar who (ptr-ref output _float (* i 2)))
            (scalar who (ptr-ref output _float (add1 (* i 2))))))
    (void/reference-sink input output at)))
(define (allocate-run! bp fp kind n coords origin text rb)
  (define bytes (and text (bytes-length text)))
  (case kind
    [(default)
     (if text
         (sk_textblob_builder_alloc_run_text bp fp n (car origin) (cadr origin) bytes #f rb)
         (sk_textblob_builder_alloc_run bp fp n (car origin) (cadr origin) #f rb))]
    [(horizontal)
     (if text
         (sk_textblob_builder_alloc_run_text_pos_h bp fp n (cadr origin) bytes #f rb)
         (sk_textblob_builder_alloc_run_pos_h bp fp n (cadr origin) #f rb))]
    [(positioned)
     (if text
         (sk_textblob_builder_alloc_run_text_pos bp fp n bytes #f rb)
         (sk_textblob_builder_alloc_run_pos bp fp n #f rb))]
    [(transformed)
     (if text
         (sk_textblob_builder_alloc_run_text_rsxform bp fp n bytes #f rb)
         (sk_textblob_builder_alloc_run_rsxform bp fp n #f rb))]))
(define (fill-run! who rb kind gs coords text clusters)
  (define gp (sk-textblob-runbuffer-glyphs rb))
  (define pp (sk-textblob-runbuffer-pos rb))
  (define tp (sk-textblob-runbuffer-utf8text rb))
  (define cp (sk-textblob-runbuffer-clusters rb))
  (unless (and gp (or (eq? kind 'default) pp) (or (not text) (and tp cp)))
    (error who "native builder returned incomplete run buffers"))
  (for ([g (in-list gs)] [i (in-naturals)]) (ptr-set! gp _uint16 i g))
  (unless (eq? kind 'default)
    (define flat (if (eq? kind 'horizontal) coords (append* coords)))
    (for ([x (in-list flat)] [i (in-naturals)]) (ptr-set! pp _float i x)))
  (when text
    (memcpy tp text (bytes-length text))
    (for ([c (in-list clusters)] [i (in-naturals)]) (ptr-set! cp _uint32 i c)))
  (void/reference-sink rb text))

(define (append-run! who b f gs kind coords origin text clusters)
  (define bh (builder-h who b)) (define fh (font-h who f))
  (define n (length gs))
  (define cost (if (zero? n) 0 (text-run-cost n kind text)))
  (call-with-owned who (list bh fh)
    (lambda (bp fp)
      (define rb (text-blob-builder-resource-runs b))
      (define cb (text-blob-builder-resource-cost b))
      (text-run-budget who (+ (unbox cb) cost))
      (check-face-glyphs who fp gs)
      ;; Empty runs validate all input and resources but create no native run.
      (unless (zero? n)
        (define snapshot #f) (define touched? #f) (define installed? #f)
        (with-handlers ([(lambda (_) #t)
                         (lambda (e)
                           (when (and snapshot (not installed?)) (skia-close! snapshot))
                           ;; Native builders cannot roll back an allocated run.
                           ;; An append failure after allocation is terminal.
                           (when touched? (skia-close! b))
                           (raise e))])
          (set! snapshot (copy-font who fp))
          (define positions
            (case kind
              [(default) (default-positions who fp gs origin)]
              [(horizontal) (for/list ([x (in-list coords)]) (list x (cadr origin)))]
              [(positioned) coords]
              [(transformed) '()]))
          (define info
            (text-run-info kind (vector->immutable-vector (list->vector gs))
                           (vector->immutable-vector (list->vector positions))
                           (and (eq? kind 'transformed)
                                (vector->immutable-vector (list->vector coords)))
                           text (and clusters (vector->immutable-vector (list->vector clusters)))))
          (define run (retained-text-run snapshot info))
          (define native-run (make-sk-textblob-runbuffer #f #f #f #f))
          (set! touched? #t)
          (allocate-run! bp fp kind n coords origin text native-run)
          ;; Run buffers are filled before ANY subsequent builder allocation.
          (fill-run! who native-run kind gs coords text clusters)
          (set-box! rb (cons run (unbox rb)))
          (set! installed? #t)
          (set-box! cb (+ (unbox cb) cost))))))
  (void))

(define (text-blob-builder-add-run! b f glyphs #:origin [origin '(0 0)]
                                    #:text [text #f] #:clusters [clusters #f])
  (define who 'text-blob-builder-add-run!)
  (define gs (text-run-glyphs who glyphs))
  (define at (text-run-point who origin))
  (define-values (bs cs) (text-run-metadata who text clusters (length gs)))
  (append-run! who b f gs 'default '() at bs cs))
(define (text-blob-builder-add-horizontal-run! b f glyphs xs #:y [y 0]
                                               #:text [text #f] #:clusters [clusters #f])
  (define who 'text-blob-builder-add-horizontal-run!)
  (define gs (text-run-glyphs who glyphs))
  (define coords (text-run-scalars who xs (length gs)))
  (define yy (scalar who y))
  (define-values (bs cs) (text-run-metadata who text clusters (length gs)))
  (append-run! who b f gs 'horizontal coords (list 0.0 yy) bs cs))
(define (text-blob-builder-add-positioned-run! b f glyphs positions
                                               #:text [text #f] #:clusters [clusters #f])
  (define who 'text-blob-builder-add-positioned-run!)
  (define gs (text-run-glyphs who glyphs))
  (define coords (text-run-points who positions (length gs)))
  (define-values (bs cs) (text-run-metadata who text clusters (length gs)))
  (append-run! who b f gs 'positioned coords '(0.0 0.0) bs cs))
(define (text-blob-builder-add-transformed-run! b f glyphs transforms
                                                #:text [text #f] #:clusters [clusters #f])
  (define who 'text-blob-builder-add-transformed-run!)
  (define gs (text-run-glyphs who glyphs))
  (define xs (text-run-sequence who transforms 32))
  (define coords
    (text-run-transforms who (for/list ([x (in-list xs)])
                              (if (atlas-transform? x) (atlas-transform-coefficients x) x))
                         (length gs)))
  (define-values (bs cs) (text-run-metadata who text clusters (length gs)))
  (append-run! who b f gs 'transformed coords '(0.0 0.0) bs cs))
(define (text-blob-builder-add-shaped-run! b sh run #:origin [origin '(0 0)] #:text [text #f])
  (define who 'text-blob-builder-add-shaped-run!)
  (define at (text-run-point who origin))
  (unless (shaped-run? run) (raise-argument-error who "shaped-run?" run))
  (define glyphs (text-run-glyphs who (shaped-run-glyphs run)))
  (define points (text-run-points who (shaped-run-positions run) (length glyphs)))
  (text-run-budget who (if (null? glyphs) 0 (text-run-cost (length glyphs) 'positioned #f)))
  (call-with-owned who (list (builder-h who b) (shaper-h who sh))
    (lambda ignored
      (define positions
        (for/list ([p (in-list points)])
          (list (scalar who (+ (car at) (car p))) (scalar who (+ (cadr at) (cadr p))))))
      (text-blob-builder-add-positioned-run!
       b (shaper-font sh) glyphs positions
       #:text text #:clusters (and text (shaped-run-clusters run))))))

(define (text-blob-builder-finish! b)
  (define who 'text-blob-builder-finish!)
  (call-with-owned who (list (builder-h who b))
    (lambda (bp)
      (define rb (text-blob-builder-resource-runs b))
      (define runs (reverse (unbox rb)))
      (cond
        [(null? runs) (skia-close! b) #f]
        [else
         (define handle #f) (define blob #f)
         (with-handlers ([(lambda (_) #t)
                          (lambda (e)
                            (cond [blob (skia-close! blob)] [handle (owned-close! who handle)])
                            (skia-close! b)
                            (raise e))])
           (set! handle (new-owned who 'text-blob (lambda () (sk_textblob_builder_make bp)) sk_textblob_unref))
           (set! blob (make-multi-text-blob-record handle #f '() '() runs))
           ;; Transfer private font ownership before closing the single-use builder.
           (set-box! rb '())
           (set-box! (text-blob-builder-resource-cost b) 0)
           (skia-close! b)
           blob)]))))
(define (retained-runs blob)
  (if (multi-text-blob? blob) (multi-text-blob-runs blob)
      (list (retained-text-run
             (text-blob-font blob)
             (text-run-info 'positioned
                            (vector->immutable-vector (list->vector (text-blob-glyphs blob)))
                            (vector->immutable-vector (list->vector (text-blob-positions blob)))
                            #f #f #f)))))
(define (text-blob-run-count blob)
  (call-with-owned 'text-blob-run-count (list (text-blob-h 'text-blob-run-count blob))
    (lambda (_) (if (multi-text-blob? blob) (length (multi-text-blob-runs blob)) 1))))
(define (text-blob-runs blob)
  (define who 'text-blob-runs)
  (call-with-owned who (list (text-blob-h who blob))
    (lambda (_)
      (vector->immutable-vector (list->vector (map retained-text-run-info (retained-runs blob)))))))
(define (text-blob-run-font blob index)
  (define who 'text-blob-run-font)
  (call-with-owned who (list (text-blob-h who blob))
    (lambda (_)
      (define runs (retained-runs blob))
      (text-run-index who index (length runs))
      (call-with-owned who (list (font-h who (retained-text-run-font (list-ref runs index))))
        (lambda (fp) (copy-font who fp))))))

(define (text-blob-intercepts blob top bottom #:paint [paint #f])
  (define who 'text-blob-intercepts)
  (define band (text-run-band who top bottom))
  (define handles (append (list (text-blob-h who blob)) (if paint (list (paint-h who paint)) '())))
  (call-with-owned who handles
    (lambda (bp . paint-pointers)
      (define runs (retained-runs blob))
      (when (for/or ([r (in-list runs)])
              (eq? (text-run-info-positioning (retained-text-run-info r)) 'transformed))
        (error who "Skia m119 ignores RSXform runs; intercepts on transformed blobs are unsupported"))
      (define glyph-count
        (for/sum ([r (in-list runs)]) (vector-length (text-run-info-glyphs (retained-text-run-info r)))))
      (define pp (if (null? paint-pointers) #f (car paint-pointers)))
      (define bounds (malloc 2 _float 'atomic))
      (ptr-set! bounds _float 0 (car band)) (ptr-set! bounds _float 1 (cadr band))
      (define count (sk_textblob_get_intercepts bp bounds #f pp))
      (unless (and (exact-nonnegative-integer? count) (even? count) (<= count (* 2 glyph-count)))
        (error who "invalid native interval count: ~a" count))
      (text-run-budget who (* count 12))
      (cond
        [(zero? count) #()]
        [else
         (define output (malloc count _float 'atomic))
         (define written (sk_textblob_get_intercepts bp bounds output pp))
         (unless (= written count) (error who "native interval count changed"))
         (begin0
           (vector->immutable-vector
            (for/vector ([i (in-range 0 count 2)])
              (define a (scalar who (ptr-ref output _float i)))
              (define b (scalar who (ptr-ref output _float (add1 i))))
              (unless (<= a b) (error who "reversed native interval"))
              (list a b)))
           (void/reference-sink bounds output))]))))

(define (positioned-glyphs->path f glyphs positions)
  (define who 'positioned-glyphs->path)
  (define gs (text-run-glyphs who glyphs))
  (define coords (text-run-points who positions (length gs)))
  (text-run-budget who (* 26 (length gs)))
  (call-with-owned who (list (font-h who f))
    (lambda (fp)
      (check-face-glyphs who fp gs)
      (define out (make-path))
      (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! out) (raise e))])
        (unless (null? gs)
          (define input (glyph-buffer gs))
          (define points (malloc (* 2 (length gs)) _float 'atomic))
          (for ([v (in-list (append* coords))] [i (in-naturals)]) (ptr-set! points _float i v))
          (call-with-owned who (list (path-h who out))
            (lambda (dest)
              ;; SkTextEncoding::kGlyphID = 3; length is bytes, not glyph count.
              (sk_text_utils_get_pos_path input (* 2 (length gs)) 3 points fp dest)))
          (void/reference-sink input points))
        (text-run-budget who (+ (* 8 (path-point-count out)) (path-native-verb-count out)))
        out))))

(define (shaped-run->text-blob/on-path sh run path
                                      #:start-offset [start 0] #:normal-offset [normal 0]
                                      #:contour [contour 0] #:force-closed? [closed? #f]
                                      #:text [text #f])
  (define who 'shaped-run->text-blob/on-path)
  (define first (scalar who start)) (define delta (scalar who normal))
  (boolean who closed?)
  (unless (exact-nonnegative-integer? contour) (raise-argument-error who "exact-nonnegative-integer?" contour))
  (unless (shaped-run? run) (raise-argument-error who "shaped-run?" run))
  (define gs (text-run-glyphs who (shaped-run-glyphs run)))
  (define points (text-run-points who (shaped-run-positions run) (length gs)))
  (text-run-budget who (text-run-cost (length gs) 'transformed #f))
  ;; Validate the live path/shaper even for an empty run.
  (call-with-owned who (list (shaper-h who sh) (path-h who path))
    (lambda ignored
      (with-skia ([measure (make-path-measure path #:force-closed? closed?)])
        (for ([i (in-range contour)])
          (unless (path-measure-next-contour! measure) (error who "contour index out of range")))
        (define contour-length (path-measure-length measure))
        (when (and (pair? gs) (not (> contour-length 0))) (error who "selected contour has no measurable length"))
        (define transforms
          (for/list ([p (in-list points)])
            (define d (scalar who (+ first (car p))))
            (unless (<= 0 d contour-length)
              (raise-arguments-error who "shaped glyph origin is outside the selected contour"
                                     "distance" d "contour length" contour-length))
            (define frame (path-measure-matrix measure d))
            (unless frame (error who "no tangent frame at shaped glyph origin"))
            (text-run-path-placement who (matrix-x0 frame) (matrix-y0 frame)
                                     (matrix-xx frame) (matrix-yx frame) (+ delta (cadr p)))))
        (with-skia ([builder (make-text-blob-builder)])
          (text-blob-builder-add-transformed-run!
           builder (shaper-font sh) gs transforms #:text text #:clusters (and text (shaped-run-clusters run)))
          (text-blob-builder-finish! builder))))))
(define (draw-shaped-run/on-path canvas sh run path paint
                                  #:start-offset [start 0] #:normal-offset [normal 0]
                                  #:contour [contour 0] #:force-closed? [closed? #f])
  (call-on-canvas 'draw-shaped-run/on-path canvas (list (paint-h 'draw-shaped-run/on-path paint))
                  (lambda ignored (void)))
  (define blob (shaped-run->text-blob/on-path sh run path #:start-offset start #:normal-offset normal
                                            #:contour contour #:force-closed? closed?))
  (when blob
    (call-with-skia-resource blob (lambda (b) (draw-text-blob canvas b 0 0 paint))))
  (void))
