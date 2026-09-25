#lang racket/base
(require racket/list
         rackunit rackunit/text-ui ffi/unsafe
         "../main.rkt" "../private/types.rkt" "../private/harfbuzz-types.rkt"
         "../private/bidi.rkt" "../private/line-break.rkt"
         "../private/unicode-conformance.rkt" "../private/joining.rkt")
(provide pure-tests)

(define pure-tests
  (test-suite
   "Colors, validation, and ABI layouts (no native library)"
   (test-case "byte colors and named colors"
     (check-equal? (rgb 1 2 3) (rgba 1 2 3 255))
     (check-equal? (color->argb 'red) #xffff0000)
     (check-equal? (color->argb 'transparent) 0)
     (check-equal? (color->rgba 'green) (rgba 0 128 0 255)))
   (test-case "string and integer color ordering are explicit"
     (check-equal? (color->rgba "#12345680") (rgba 18 52 86 128))
     (check-equal? (color->rgba #x80123456) (rgba 18 52 86 128))
     (check-equal? (color->rgba "#ABCDEF") (rgba 171 205 239 255)))
   (test-case "color packing round trips"
     (for* ([a '(0 1 127 255)] [r '(0 19 255)] [g '(0 71 255)] [b '(0 181 255)])
       (define c (rgba r g b a))
       (check-equal? (color->rgba (color->argb c)) c)))
   (test-case "invalid colors are rejected"
     (for ([v (in-list (list -1 #x100000000 "#abc" "#GG0000" 'unknown #f 1.0))])
       (check-false (color? v))
       (check-exn exn:fail:contract? (lambda () (color->rgba v))))
     (check-exn exn:fail:contract? (lambda () (rgba 1 2 3 0.5)))
     (check-exn exn:fail:contract? (lambda () (rgb 256 0 0))))
   (test-case "surface dimensions are checked before native loading"
     (for ([n (in-list '(0 -1 1.5 32769))])
       (check-exn exn:fail:contract? (lambda () (make-surface n 10))))
     (parameterize ([current-skia-byte-limit 15])
       (check-exn exn:fail:contract? (lambda () (make-surface 2 2)))))
   (test-case "paint options are checked before native loading"
     (check-exn exn:fail:contract? (lambda () (make-paint #:style 'wrong)))
     (check-exn exn:fail:contract? (lambda () (make-paint #:stroke-width -1)))
     (check-exn exn:fail:contract? (lambda () (make-paint #:stroke-width +inf.0)))
     (check-exn exn:fail:contract? (lambda () (make-paint #:stroke-width +nan.0)))
     (check-exn exn:fail:contract? (lambda () (make-paint #:antialias? 1))))
   (test-case "image buffer validation before native loading"
     (check-exn exn:fail:contract? (lambda () (rgba-bytes->image 2 2 (make-bytes 15))))
     (check-exn exn:fail? (lambda () (rgba-bytes->image 1 1 (bytes 255 0 0 128)
                                                                   #:premultiplied? #t))))
   (test-case "byte-limit parameter rejects invalid settings"
     (for ([n '(0 -1 1.5 #f)])
       (check-exn exn:fail:contract? (lambda () (current-skia-byte-limit n)))))
   (test-case "C bool is one byte"
     (check-equal? (ctype-sizeof _stdbool) 1))
   (test-case "native struct sizes"
     (define p (ctype-sizeof _pointer))
     (check-equal? (ctype-sizeof _sk-image-info) (+ p 16))
     (check-equal? (ctype-sizeof _sk-rect) 16)
     (check-equal? (ctype-sizeof _sk-point) 8)
     (check-equal? (ctype-sizeof _sk-textblob-runbuffer) (* 4 p))
     (check-equal? (ctype-sizeof _sk-irect) 16)
     (check-equal? (ctype-sizeof _sk-sampling) 24)
     (check-equal? (ctype-sizeof _sk-png-options) (+ 8 (* 3 p)))
     (check-equal? (ctype-sizeof _sk-jpeg-options)
                   (+ 12 (if (= p 8) 4 0) (* 3 p)))
     (check-equal? (ctype-sizeof _sk-webp-options) (+ 8 (* 2 p)))
     (check-equal? (ctype-sizeof _sk-font-metrics) 64))
   (test-case "native struct field order"
     (define info (make-sk-image-info #f 123 456 4 2))
     (define p (ctype-sizeof _pointer))
     (check-false (ptr-ref info _pointer))
     (check-equal? (ptr-ref (ptr-add info p) _int32) 123)
     (check-equal? (ptr-ref (ptr-add info (+ p 4)) _int32) 456)
     (check-equal? (ptr-ref (ptr-add info (+ p 8)) _int) 4)
     (check-equal? (ptr-ref (ptr-add info (+ p 12)) _int) 2)
     (define options (make-sk-png-options 248 6 #f #f #f))
     (check-equal? (ptr-ref options _int) 248)
     (check-equal? (ptr-ref (ptr-add options 4) _int) 6)
     (for ([offset (in-list (list 8 (+ 8 p) (+ 8 (* 2 p))))])
       (check-false (ptr-ref (ptr-add options offset) _pointer))))
   (test-case "point ABI field order"
     (define p (make-sk-point 12.5 -7.25))
     (check-= (ptr-ref p _float) 12.5 0.001)
     (check-= (ptr-ref (ptr-add p 4) _float) -7.25 0.001))
   (test-case "text-blob runbuffer ABI field order"
     (define p (ctype-sizeof _pointer))
     (define r (make-sk-textblob-runbuffer #f #f #f #f))
     (for ([offset (in-list (list 0 p (* 2 p) (* 3 p)))])
       (check-false (ptr-ref (ptr-add r offset) _pointer))))
   (test-case "codec and encoder ABI field order"
     (define p (ctype-sizeof _pointer))
     (define ir (make-sk-irect 1 2 30 40))
     (check-equal? (ptr-ref ir _int32) 1)
     (check-equal? (ptr-ref (ptr-add ir 4) _int32) 2)
     (check-equal? (ptr-ref (ptr-add ir 8) _int32) 30)
     (check-equal? (ptr-ref (ptr-add ir 12) _int32) 40)
     (define jpeg (make-sk-jpeg-options 91 2 1 #f #f #f))
     (check-equal? (ptr-ref jpeg _int) 91)
     (check-equal? (ptr-ref (ptr-add jpeg 4) _int) 2)
     (check-equal? (ptr-ref (ptr-add jpeg 8) _int) 1)
     (define jpeg-ptr-start (+ 12 (if (= p 8) 4 0)))
     (for ([offset (in-list (list jpeg-ptr-start
                                  (+ jpeg-ptr-start p)
                                  (+ jpeg-ptr-start (* 2 p))))])
       (check-false (ptr-ref (ptr-add jpeg offset) _pointer)))
     (define webp (make-sk-webp-options 1 73.5 #f #f))
     (check-equal? (ptr-ref webp _int) 1)
     (check-= (ptr-ref (ptr-add webp 4) _float) 73.5 0.001)
     (check-false (ptr-ref (ptr-add webp 8) _pointer))
     (check-false (ptr-ref (ptr-add webp (+ 8 p)) _pointer)))
   (test-case "sampling padding is honored"
     (define s (make-sk-sampling 0 #f 0.0 0.0 1 0))
     (check-equal? (ptr-ref (ptr-add s 4) _uint8) 0)
     (check-equal? (ptr-ref (ptr-add s 16) _int) 1)
     (check-equal? (ptr-ref (ptr-add s 20) _int) 0))
   (test-case "font and typeface options validate before native loading"
     (check-exn exn:fail:contract? (lambda () (make-font 'not-a-typeface)))
     (check-exn exn:fail:contract? (lambda () (make-font #:size 0)))
     (check-exn exn:fail:contract? (lambda () (make-font #:scale-x -1)))
     (check-exn exn:fail:contract? (lambda () (make-font #:edging 'wrong)))
     (check-exn exn:fail:contract? (lambda () (make-font #:hinting 'wrong)))
     (check-exn exn:fail:contract? (lambda () (make-font #:subpixel? 1)))
     (check-exn exn:fail:contract?
                (lambda () (typeface-from-family "x" #:weight 1001)))
     (check-exn exn:fail:contract?
                (lambda () (typeface-from-family "x" #:width 0)))
     (check-exn exn:fail:contract?
                (lambda () (typeface-from-family "x" #:slant 'wrong)))
     (check-exn exn:fail?
                (lambda () (typeface-from-file "definitely-not-a-font-file.ttf"))))
   (test-case "shader and gradient options validate before native loading"
     (check-exn exn:fail:contract? (lambda () (make-paint #:shader 'not-a-shader)))
     (check-exn exn:fail? (lambda ()
                            (make-linear-gradient-shader 0 0 10 0 '(red))))
     (check-exn exn:fail? (lambda ()
                            (make-linear-gradient-shader
                             0 0 10 0 '(red blue) #:positions '(0))))
     (check-exn exn:fail? (lambda ()
                            (make-linear-gradient-shader
                             0 0 10 0 '(red blue) #:positions '(0.8 0.2))))
     (check-exn exn:fail? (lambda ()
                            (make-linear-gradient-shader
                             0 0 10 0 '(red blue) #:positions '(-0.1 1))))
     (check-exn exn:fail? (lambda ()
                            (make-linear-gradient-shader
                             0 0 10 0 '(red blue) #:tile-mode 'wrong)))
     (check-exn exn:fail? (lambda ()
                            (make-linear-gradient-shader 2 3 2 3 '(red blue))))
     (check-exn exn:fail:contract? (lambda ()
                                     (make-radial-gradient-shader
                                      0 0 0 '(red blue))))
     (check-exn exn:fail? (lambda ()
                            (make-sweep-gradient-shader
                             0 0 '(red blue) #:start-angle 10 #:end-angle 10)))
     (check-exn exn:fail:contract? (lambda ()
                                     (make-two-point-conical-gradient-shader
                                      0 0 -1 10 0 2 '(red blue))))
     (check-exn exn:fail? (lambda ()
                            (make-two-point-conical-gradient-shader
                             0 0 2 0 0 2 '(red blue))))
     (check-exn exn:fail:contract? (lambda () (make-image-shader 'not-an-image)))
     (check-exn exn:fail? (lambda () (make-blend-shader 'wrong 'a 'b))))
   (test-case "path-effect options validate before native loading"
     (check-exn exn:fail:contract? (lambda () (make-paint #:path-effect 'wrong)))
     (check-exn exn:fail? (lambda () (make-dash-path-effect '(5))))
     (check-exn exn:fail? (lambda () (make-dash-path-effect '(5 3 2))))
     (check-exn exn:fail:contract? (lambda () (make-dash-path-effect '(5 -1))))
     (check-exn exn:fail? (lambda () (make-dash-path-effect '(0 0))))
     (check-exn exn:fail:contract? (lambda () (make-dash-path-effect '(5 5) +inf.0)))
     (check-exn exn:fail:contract? (lambda () (make-corner-path-effect 0)))
     (check-exn exn:fail:contract? (lambda () (make-discrete-path-effect 0 2)))
     (check-exn exn:fail:contract? (lambda () (make-discrete-path-effect 1e-6 2)))
     (check-exn exn:fail:contract? (lambda () (make-discrete-path-effect 4 -1)))
     (check-exn exn:fail:contract? (lambda () (make-discrete-path-effect 4 1 -1)))
     (check-exn exn:fail:contract?
                (lambda () (make-discrete-path-effect 4 1 #x100000000)))
     (check-exn exn:fail? (lambda () (make-trim-path-effect -0.1 1)))
     (check-exn exn:fail? (lambda () (make-trim-path-effect 0.8 0.2)))
     (check-exn exn:fail? (lambda () (make-trim-path-effect 0.5 0.5)))
     (check-exn exn:fail? (lambda () (make-trim-path-effect 0 1)))
     (check-exn exn:fail? (lambda () (make-trim-path-effect 0 1.1)))
     (check-exn exn:fail? (lambda () (make-trim-path-effect 0 1 #:mode 'wrong)))
     (check-exn exn:fail:contract?
                (lambda () (make-compose-path-effect 'wrong 'also-wrong)))
     (check-exn exn:fail:contract?
                (lambda () (make-sum-path-effect 'wrong 'also-wrong))))
   (test-case "path-measure options validate before native loading"
     (check-exn exn:fail:contract? (lambda () (make-path-measure 'not-a-path)))
     (check-exn exn:fail:contract?
                (lambda () (make-path-measure 'not-a-path #:force-closed? 1)))
     (check-exn exn:fail:contract?
                (lambda () (make-path-measure 'not-a-path #:res-scale 0))))
   (test-case "encoded image inputs validate before native loading"
     (check-exn exn:fail? (lambda () (image-from-bytes #"")))
     (check-exn exn:fail? (lambda () (encoded-image-info-from-bytes #"")))
     (check-exn exn:fail?
                (lambda () (image-from-file "definitely-not-an-image-file.png")))
     (check-exn exn:fail?
                (lambda ()
                  (encoded-image-info-from-file "definitely-not-an-image-file.png")))
     (parameterize ([current-skia-byte-limit 3])
       (check-exn exn:fail? (lambda () (image-from-bytes #"abcd")))
       (check-exn exn:fail?
                  (lambda () (encoded-image-info-from-bytes #"abcd"))))
     (check-exn exn:fail:contract?
                (lambda () (image->png-bytes #f #:compression 10)))
     (check-exn exn:fail:contract?
                (lambda () (image->jpeg-bytes #f #:quality 101)))
     (check-exn exn:fail?
                (lambda () (image->jpeg-bytes #f #:downsample 'wrong)))
     (check-exn exn:fail:contract?
                (lambda () (image->webp-bytes #f #:quality -1)))
     (check-exn exn:fail:contract?
                (lambda () (image->webp-bytes #f #:lossless? 1)))
     (check-exn exn:fail:contract?
                (lambda () (image->encoded-bytes #f 'bmp))))
   (test-case "font metrics ABI field order"
     (define m
       (make-sk-font-metrics #x0f
                             1.0 2.0 3.0 4.0 5.0
                             6.0 7.0 8.0 9.0 10.0 11.0
                             12.0 13.0 14.0 15.0))
     (check-equal? (ptr-ref m _uint32) #x0f)
     (for ([expected (in-range 1 16)] [offset (in-range 4 64 4)])
       (check-= (ptr-ref (ptr-add m offset) _float) expected 0.001)))
   (test-case "filter constructors validate before native loading"
     (check-exn exn:fail:contract?
                (lambda () (make-color-matrix-filter '(1 2 3))))
     (check-exn exn:fail:contract?
                (lambda () (make-color-matrix-filter
                            (append (make-list 19 0) (list +nan.0)))))
     (check-exn exn:fail? (lambda () (make-blend-color-filter 'red 'dst)))
     (check-exn exn:fail:contract? (lambda () (make-blend-color-filter 'red 'wrong)))
     (check-exn exn:fail:contract? (lambda () (make-blur-mask-filter 0)))
     (check-exn exn:fail:contract? (lambda () (make-blur-mask-filter 2 #:style 'wrong)))
     (check-exn exn:fail:contract? (lambda () (make-blur-mask-filter 2 #:respect-ctm? 1)))
     (check-exn exn:fail? (lambda () (make-blur-image-filter 0 0)))
     (check-exn exn:fail:contract? (lambda () (make-blur-image-filter -1 2)))
     (check-exn exn:fail:contract? (lambda () (make-blur-image-filter 1 2 #:tile-mode 'wrong)))
     (check-exn exn:fail? (lambda () (make-blur-image-filter 1 2 #:tile-mode 'mirror)))
     (check-exn exn:fail:contract? (lambda () (make-blur-image-filter 1 2 #:input 'bad)))
     (check-exn exn:fail:contract?
                (lambda () (make-drop-shadow-image-filter 1 2 -1 3 'black)))
     (check-exn exn:fail:contract?
                (lambda () (make-drop-shadow-image-filter 1 2 3 4 'black #:input 'bad)))
     (check-exn exn:fail:contract? (lambda () (make-color-filter-image-filter 'bad)))
     (check-exn exn:fail:contract? (lambda () (make-compose-image-filter 'bad 'also-bad))))
   (test-case "paint filter options validate before native loading"
     (check-exn exn:fail:contract? (lambda () (make-paint #:color-filter 'bad)))
     (check-exn exn:fail:contract? (lambda () (make-paint #:mask-filter 'bad)))
     (check-exn exn:fail:contract? (lambda () (make-paint #:image-filter 'bad)))
     (check-exn exn:fail:contract? (lambda () (paint-set-color-filter! 'not-a-paint #f)))
     (check-exn exn:fail:contract? (lambda () (paint-set-mask-filter! 'not-a-paint #f)))
     (check-exn exn:fail:contract? (lambda () (paint-set-image-filter! 'not-a-paint #f))))
   (test-case "svg-path->path validates data before native loading"
     (check-exn exn:fail:contract? (lambda () (svg-path->path 42)))
     (check-exn exn:fail? (lambda () (svg-path->path (string-append "a" (string (integer->char 0)) "b")))))
   (test-case "path point and add-path validators run before native loading"
     (check-exn exn:fail:contract? (lambda () (path-point-ref 'not-a-path 0)))
     (check-exn exn:fail:contract? (lambda () (path-add-path! 'a 'b #:mode 'nope))))
   (test-case "picture recording arguments validate before native loading"
     (check-exn exn:fail:contract? (lambda () (call-with-picture 0 10 void)))
     (check-exn exn:fail:contract? (lambda () (call-with-picture 10 10 #f))))
   (test-case "draw-picture keywords validate before native loading"
     (check-exn exn:fail:contract? (lambda () (draw-picture 'not-a-canvas 'not-a-picture #:width 10)))
     (check-exn exn:fail:contract? (lambda () (draw-picture 'not-a-canvas 'not-a-picture #:width 10 #:height 'bad))))
   (test-case "font-manager options validate before native loading"
     (check-exn exn:fail:contract? (lambda () (font-manager-family-count 'not-a-manager)))
     (check-exn exn:fail:contract?
                (lambda () (font-manager-match-family 'not-a-manager "Helvetica")))
     (check-exn exn:fail:contract?
                (lambda () (font-manager-match-character 'not-a-manager #\A)))
     (check-exn exn:fail:contract?
                (lambda () (font-manager-match-character 'not-a-manager #\A #:languages #f))))
   (test-case "positioned text-blob arguments validate before native loading"
     (check-exn exn:fail:contract?
                (lambda () (make-positioned-text-blob 'not-a-font '#(1) '((0 0)))))
     (check-exn exn:fail:contract? (lambda () (text-blob-bounds 'not-a-blob)))
     (check-exn exn:fail:contract?
                (lambda () (draw-text-blob 'not-a-canvas 'not-a-blob 0 0 'not-a-paint))))
   (test-case "HarfBuzz shaping ABI struct sizes"
     (check-equal? (ctype-sizeof _hb-glyph-info) 20)
     (check-equal? (ctype-sizeof _hb-glyph-position) 20)
     (check-equal? (ctype-sizeof _hb-feature) 16))
   (test-case "shaper argument validation does not require native loading"
     (check-exn exn:fail:contract? (lambda () (make-shaper 'not-a-font)))
     (check-exn exn:fail:contract? (lambda () (shape-text 'not-a-shaper "abc"))))
   (test-case "text-layout options validate before native loading"
     (check-exn exn:fail:contract? (lambda () (layout-text 'not-a-shaper 42)))
     (check-exn exn:fail:contract? (lambda () (layout-text 'not-a-shaper "x" #:width 0)))
     (check-exn exn:fail:contract? (lambda () (layout-text 'not-a-shaper "x" #:align 'diagonal)))
     (check-exn exn:fail:contract? (lambda () (layout-text 'not-a-shaper "x" #:direction 'ttb)))
     (check-exn exn:fail:contract? (lambda () (layout-text 'not-a-shaper "x" #:line-height 0)))
     (check-exn exn:fail:contract? (lambda () (draw-text-layout 'not-a-canvas 'not-a-layout 0 0 'not-a-paint))))
   (test-case "justification validates width before native loading"
     (check-exn #rx"requires a positive #:width"
                (lambda () (layout-text 'not-a-shaper "alpha beta" #:align 'justify)))
     (check-exn #rx"requires a positive #:width"
                (lambda ()
                  (layout-mixed-text 'bad 'also-bad "alpha beta"
                                     #:align 'justify-all))))
   (test-case "layout break opportunities validate without native loading"
     (define op (make-layout-break-opportunity 4 "-"))
     (check-true (layout-break-opportunity? op))
     (check-equal? (layout-break-opportunity-index op) 4)
     (check-equal? (layout-break-opportunity-insert op) "-")
     (check-exn exn:fail:contract?
                (lambda () (make-layout-break-opportunity -1)))
     (check-exn exn:fail:contract?
                (lambda () (make-layout-break-opportunity 1 42)))
     (check-exn #rx"hard line breaks"
                (lambda () (make-layout-break-opportunity 1 "-\n"))))
   (test-case "break provider arity validates before native loading"
     (check-exn exn:fail:contract?
                (lambda ()
                  (layout-text 'not-a-shaper "alpha" #:width 40
                               #:break-provider (lambda (text) '(2)))))
     (check-exn exn:fail:contract?
                (lambda ()
                  (layout-mixed-text 'bad 'also-bad "alpha" #:width 40
                                     #:break-provider (lambda () '(2))))))
   (test-case "bidi resolver separates ordinary LTR and RTL text"
     (define-values (levels direction) (bidi-resolve-levels "abc אבג" 'auto))
     (check-eq? direction 'ltr)
     (check-true (for/and ([i (in-range 3)]) (even? (vector-ref levels i))))
     (check-true (for/and ([i (in-range 4 7)]) (odd? (vector-ref levels i)))))
   (test-case "bidi resolver keeps numbers LTR inside an RTL paragraph"
     (define-values (levels direction) (bidi-resolve-levels "אבג 123" 'auto))
     (check-eq? direction 'rtl)
     (check-true (for/and ([i (in-range 3)]) (odd? (vector-ref levels i))))
     (check-true (for/and ([i (in-range 4 7)]) (even? (vector-ref levels i)))))
   (test-case "Unicode conformance parsers accept official test syntax"
     (define lb
       (parse-line-break-test-line
        "÷ 0041 × 0020 ÷ 0042 ÷ # Latin + space"))
     (check-equal? (line-break-case-text lb) "A B")
     (check-equal? (line-break-case-breaks lb) '(0 2 3))
     (define bc
       (parse-bidi-character-test-line
        "05D0 0041; 2; 1; 1 2; 1 0 # Hebrew + Latin"))
     (check-eq? (bidi-character-case-requested bc) 'auto)
     (check-equal? (bidi-character-case-paragraph-level bc) 1)
     (check-equal? (bidi-character-case-levels bc) '(1 2))
     (check-equal? (bidi-character-case-reorder bc) '(1 0)))
   (test-case "Unicode conformance smoke vectors pass"
     (define lb-result
       (run-line-break-conformance-port
        (open-input-string "÷ 0041 × 0020 ÷ 0042 ÷\n")))
     (check-equal? (unicode-conformance-result-total lb-result) 1)
     (check-equal? (unicode-conformance-result-passed lb-result) 1)
     (check-equal? (unicode-conformance-result-failures lb-result) '())
     (define bidi-result
       (run-bidi-character-conformance-port
        (open-input-string "05D0 0041; 2; 1; 1 2; 1 0\n")))
     (check-equal? (unicode-conformance-result-total bidi-result) 1)
     (check-equal? (unicode-conformance-result-passed bidi-result) 1)
     (check-equal? (unicode-conformance-result-failures bidi-result) '()))
   (test-case "bidi explicit embeddings and overrides set nested levels"
     (define rlo-text
       (string #\A #\u202E #\B #\C #\u202C #\space #\D))
     (define-values (rlo-levels rlo-dir)
       (bidi-resolve-levels rlo-text 'ltr))
     (check-eq? rlo-dir 'ltr)
     (check-equal? (vector-ref rlo-levels 0) 0)
     (check-equal? (vector-ref rlo-levels 2) 1)
     (check-equal? (vector-ref rlo-levels 3) 1)
     (check-equal? (vector-ref rlo-levels 6) 0)
     (define lre-text
       (string #\u05D0 #\u202A #\a #\b #\u202C))
     (define-values (lre-levels lre-dir)
       (bidi-resolve-levels lre-text 'rtl))
     (check-eq? lre-dir 'rtl)
     (check-equal? (vector-ref lre-levels 2) 2)
     (check-equal? (vector-ref lre-levels 3) 2))
   (test-case "bidi isolates protect surrounding paragraph direction"
     (define text (string #\u2067 #\u05D0 #\u2069 #\A))
     (define-values (levels direction) (bidi-resolve-levels text 'auto))
     (check-eq? direction 'ltr)
     (check-true (odd? (vector-ref levels 1)))
     (check-equal? (vector-ref levels 3) 0))
   (test-case "bidi FSI chooses direction from isolate contents"
     (define rtl-isolate (string #\A #\u2068 #\u05D0 #\u2069 #\B))
     (define-values (rtl-levels rtl-dir)
       (bidi-resolve-levels rtl-isolate 'auto))
     (check-eq? rtl-dir 'ltr)
     (check-true (odd? (vector-ref rtl-levels 2)))
     (define ltr-isolate
       (string #\u05D0 #\u2068 #\a #\u2069 #\u05D1))
     (define-values (ltr-levels outer-dir)
       (bidi-resolve-levels ltr-isolate 'auto))
     (check-eq? outer-dir 'rtl)
     (check-equal? (vector-ref ltr-levels 2) 2))
   (test-case "bidi X9 controls and overflow remain well-defined"
     (check-true (bidi-x9-removed? #\u202A))
     (check-true (bidi-x9-removed? #\u202C))
     (check-false (bidi-x9-removed? #\u2067))
     (check-false (bidi-x9-removed? #\u2069))
     (define deep
       (string-append (make-string 140 #\u202B)
                      "A"
                      (make-string 140 #\u202C)))
     (define-values (levels _direction) (bidi-resolve-levels deep 'ltr))
     (check-true
      (for/and ([level (in-vector levels)]) (<= level 126))))
   (test-case "bidi line-specific L1 resets trailing isolate formatting"
     (define text
       (string-append "A " (string #\u2067) "אב" (string #\u2069) "   B"))
     (define first-line-end (sub1 (string-length text)))
     (define-values (levels direction)
       (bidi-resolve-levels text 'ltr
                            #:line-breaks
                            (list first-line-end (string-length text))))
     (check-eq? direction 'ltr)
     ;; The spaces immediately before the logical line end are reset to the
     ;; paragraph level by L1 even though the preceding isolate is RTL.
     (check-equal? (vector-ref levels (- first-line-end 1)) 0)
     (check-equal? (vector-ref levels (- first-line-end 2)) 0))
   (test-case "mixed-layout arguments validate before native loading"
     (check-exn exn:fail:contract? (lambda () (layout-mixed-text 'bad 'also-bad 42)))
     (check-exn exn:fail:contract?
                (lambda () (layout-mixed-text 'bad 'also-bad "x" #:align 'diagonal)))
     (check-exn exn:fail:contract?
                (lambda () (draw-mixed-text-layout 'bad 'not-a-layout 0 0 'paint))))
   (test-case "UAX #14 line-break classes use Unicode 15.1 defaults"
     (check-eq? (line-break-class #\A) 'AL)
     (check-eq? (line-break-class #\界) 'ID)
     (check-eq? (line-break-class #\u00A0) 'GL)
     (check-eq? (line-break-class #\u3041) 'NS))
   (test-case "UAX #14 finds Latin-space and ideographic opportunities"
     (check-equal?
      (map line-break-opportunity-index (line-break-opportunities "alpha beta"))
      '(6 10))
     (check-equal?
      (map line-break-opportunity-index (line-break-opportunities "世界中文"))
      '(1 2 3 4)))
   (test-case "UAX #14 keeps punctuation and glue attached"
     (check-equal?
      (map line-break-opportunity-index (line-break-opportunities "(世界)"))
      '(2 4))
     (check-equal?
      (map line-break-opportunity-index
           (line-break-opportunities (string-append "a" (string #\u00A0) "b")))
      '(3))
     (check-equal?
      (map line-break-opportunity-index
           (line-break-opportunities (string-append "a" (string #\u2060) "b")))
      '(3)))
   (test-case "UAX #14 keeps ordinary numeric expressions intact"
     (check-equal?
      (map line-break-opportunity-index (line-break-opportunities "12,345.67"))
      '(9)))
   (test-case "line breaking preserves default grapheme clusters"
     (define text (string-append "a" (string #\u0301) "界"))
     (check-equal?
      (map line-break-opportunity-index (line-break-opportunities text))
      '(2 3))
     ;; LB8a remains non-tailorable even when the ZWJ is the last code point
     ;; of a grapheme cluster whose first code point has another class.
     (define joined (string #\uAA14 #\u200D #\uA9A3))
     (check-equal?
      (map line-break-opportunity-index (line-break-opportunities joined))
      '(3)))
   (test-case "Unicode hard line breaks split layout paragraphs"
     (define text
       (string-append "a\r\nb" (string #\u2028) "c"
                      (string #\u0085) "d" (string #\u000B) "e"))
     (check-equal? (split-hard-lines text) '("a" "b" "c" "d" "e"))
     (define ops (line-break-opportunities "a\r\nb"))
     (check-equal? (map line-break-opportunity-index ops) '(3 4))
     (check-equal? (map line-break-opportunity-kind ops) '(mandatory mandatory)))
   (test-case "Unicode joining data exposes Arabic kashida boundaries"
     (check-eq? (joining-type #\u0628) 'D)
     (check-eq? (joining-type #\u0627) 'R)
     (check-eq? (joining-type #\u0640) 'C)
     (check-equal? (arabic-kashida-boundaries "بب") '(1))
     (check-equal?
      (arabic-kashida-boundaries (string #\u0628 #\u200C #\u0628))
      '()))
   (test-case "filesystem path predicate is not shadowed"
     (check-true (path? (string->path "sample.png")))
     (check-false (skia-path? (string->path "sample.png"))))))

(module+ test
  (define failures (run-tests pure-tests))
  (unless (zero? failures) (error 'pure-tests "~a failures" failures)))
