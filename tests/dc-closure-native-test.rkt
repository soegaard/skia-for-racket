#lang racket/base
;; Actual parser, Skia text/bitmap pixels, public recordings, and PDF/SVG scopes.
;; This suite is CPU/headless and runs in every ordinary native CI lane.
(require rackunit racket/class racket/list racket/port
         (prefix-in rd: racket/draw) (prefix-in sk: "../main.rkt")
         "../dc.rkt" "../dc-output.rkt"
         "../private/dc-font-name.rkt" "../private/dc-text-spec.rkt")
(provide dc-closure-native-tests dc-closure-native-test-count)
(define (family)
  (sk:with-skia ([tf (sk:make-typeface)]) (sk:typeface-family-name tf)))
(define (font name [weight 'normal] [style 'normal] [size 18])
  (rd:make-font #:face name #:weight weight #:style style
                #:size size #:size-in-pixels? #t #:hinting 'unaligned))
(define (with-dc proc [backing 1])
  (define dc (new skia-dc% [width 240] [height 100]
                 [backing-scale backing] [smoothing 'smoothed]))
  (dynamic-wind void (lambda () (send dc clear) (proc dc)) (lambda () (send dc close))))
(define (extent dc text f [mode #t])
  (call-with-values (lambda () (send dc get-text-extent text f mode)) list))
(define (draw-label dc f)
  (send dc set-font f)
  (send dc set-text-foreground "navy")
  (send dc draw-text "office / á" 8 8 #t))
(define (render f [backing 1])
  (with-dc (lambda (dc) (draw-label dc f) (send dc get-rgba-bytes)) backing))
(define (same-pixels a b)
  (check-equal? (bytes-length a) (bytes-length b))
  (check-true (for/and ([x (in-bytes a)] [y (in-bytes b)]) (<= (abs (- x y)) 1))))
(define dc-closure-native-tests
  (test-suite
   "0.64 native font-description and DC compatibility acceptance"
   (test-case "actual Pango parser distinguishes weight style and size"
     (define face (dc-font-face 'test "Arial, Bold Italic 72" 'normal 'normal))
     (check-equal? face (dc-face "Arial" 700 'italic 5)))
   (test-case "actual parser handles a trailing comma without adding modifiers"
     (check-equal? (dc-font-face 'test "Arial," 'normal 'normal)
                   (dc-face "Arial" 400 'upright 5)))
   (test-case "built-in script-family descriptions work through the public directory"
     (define f (rd:make-font #:family 'script #:size 18 #:size-in-pixels? #t #:hinting 'unaligned))
     (define resolved (send rd:the-font-name-directory get-screen-name (send f get-font-id) 'normal 'normal))
     (define d (dc-font-description 'test f))
     (define expected (dc-font-face 'test resolved 'normal 'normal))
     (check-equal? (dc-font-spec-family d) (dc-face-family expected))
     (check-eq? (dc-font-spec-slant d) (dc-face-slant expected))
     (with-dc (lambda (dc) (check-true (> (car (extent dc "Script" f)) 0)))))
   (test-case "font% size overrides any size in a comma description"
     (define d (dc-font-description 'test (font "Arial, Bold 72" 'normal 'normal 12.5)))
     (check-= (dc-font-spec-size d) 12.5 0.00001)
     (check-equal? (dc-font-spec-weight d) 700))
   (test-case "explicit weight and style override parsed modifiers"
     (define d (dc-font-description 'test (font "Arial, Bold Italic" 'light 'slant)))
     (check-equal? (dc-font-spec-weight d) 300)
     (check-eq? (dc-font-spec-slant d) 'oblique))
   (test-case "condensed and expanded requests preserve width classes"
     (check-equal? (dc-font-request-width (dc-font-description 'test (font "Arial, Condensed"))) 3)
     (check-equal? (dc-font-request-width (dc-font-description 'test (font "Arial, Expanded"))) 7))
   (test-case "multiple family fallback and variants reject with actual parser"
     (for ([name '("Arial, Helvetica, Bold" "Arial, Small-Caps")])
       (check-exn exn:fail:skia-dc:unsupported? (lambda () (dc-font-description 'test (font name))))))
   (test-case "gravity and variable axes reject instead of being dropped"
     (for ([name '("Arial, Rotated-Left" "Arial, @wght=700")])
       (check-exn exn:fail:skia-dc:unsupported? (lambda () (dc-font-description 'test (font name))))))
   (test-case "described and explicit fonts have the same logical Skia metrics"
     (define name (family))
     (define a (font (string-append name ", Bold Italic 72")))
     (define b (font name 'bold 'italic))
     (with-dc (lambda (dc)
       (for ([mode '(#f #t grapheme)])
         (for ([x (in-list (extent dc "office / á" a mode))]
               [y (in-list (extent dc "office / á" b mode))]) (check-= x y 0.0001))))))
   (test-case "described and explicit fonts draw the same native raster pixels"
     (define name (family))
     (same-pixels (render (font (string-append name ", Bold Italic")))
                  (render (font name 'bold 'italic))))
   (test-case "font size is not multiplied by backing scale"
     (define f (font (string-append (family) ", Bold")))
     (define a (with-dc (lambda (dc) (extent dc "Skia" f)) 1))
     (define b (with-dc (lambda (dc) (extent dc "Skia" f)) 2))
     (for ([x (in-list a)] [y (in-list b)]) (check-= x y 0.0001)))
   (test-case "Retina pixels agree with the equivalent explicit request"
     (define name (family))
     (same-pixels (render (font (string-append name ", Italic")) 2)
                  (render (font name 'normal 'italic) 2)))
   (test-case "glyph availability uses the same described face selection"
     (define name (family))
     (with-dc (lambda (dc)
       (send dc set-font (font (string-append name ", Bold")))
       (define a (for/list ([c '(#\A #\λ #\u4e2d)]) (send dc glyph-exists? c)))
       (send dc set-font (font name 'bold))
       (check-equal? a (for/list ([c '(#\A #\λ #\u4e2d)]) (send dc glyph-exists? c))))))
   (test-case "condensed font drawing and measurement use one request"
     (define f (font (string-append (family) ", Condensed")))
     (with-dc (lambda (dc)
       (define before (extent dc "Skia" f))
       (check-true (> (car before) 0))
       (draw-label dc f)
       (check-equal? (extent dc "Skia" f) before)
       (check-true (for/or ([b (in-bytes (send dc get-rgba-bytes))]) (< b 200))))))
   (test-case "directory mapping updates apply to an already-created explicit font"
     (define f (font "__skia_064_directory_native__"))
     (define id (send f get-font-id))
     (define directory rd:the-font-name-directory)
     (define original (send directory get-screen-name id 'normal 'normal))
     (define name (family))
     (dynamic-wind
      (lambda () (send directory set-screen-name id 'normal 'normal (string-append name ", Bold")))
      (lambda ()
        ;; The installed Racket resolver is authoritative, even when its
        ;; result differs from the string passed to set-screen-name.
        (define resolved (send directory get-screen-name id 'normal 'normal))
        (same-pixels (render f) (render (font resolved))))
      (lambda () (send directory set-screen-name id 'normal 'normal original))))
   (test-case "public recorded procedure and datum preserve described fonts"
     (define f (font (string-append (family) ", Bold Italic")))
     (define recorder (new rd:record-dc% [width 240] [height 100]))
     (send recorder set-smoothing 'smoothed)
     (draw-label recorder f)
     (define proc (send recorder get-recorded-procedure))
     (define datum
       (read (open-input-bytes
              (call-with-output-bytes (lambda (out) (write (send recorder get-recorded-datum) out))))))
     (define from-datum (rd:recorded-datum->procedure datum))
     (define expected (render f))
     (for ([replay (in-list (list proc from-datum))])
       (same-pixels expected (with-dc (lambda (dc) (replay dc) (send dc get-rgba-bytes))))))
   (test-case "described text remains usable inside isolated alpha and clip scopes"
     (define name (family))
     (define (paint f)
       (with-dc (lambda (dc)
         (send dc set-clipping-rect 0 0 180 80)
         (send dc start-alpha 0.5) (draw-label dc f) (send dc end-alpha)
         (send dc get-rgba-bytes))))
     (same-pixels (paint (font (string-append name ", Italic"))) (paint (font name 'normal 'italic))))
   (test-case "unsupported separators fail without changing native pixels"
     (with-dc (lambda (dc)
       (define before (send dc get-rgba-bytes))
       (for* ([sep '(#\tab #\newline #\u000B #\u000C #\u2028)] [mode '(#t grapheme)])
         (check-exn exn:fail:skia-dc:unsupported?
                    (lambda () (send dc draw-text (string #\a sep #\b) 0 0 mode))))
       (check-equal? (send dc get-rgba-bytes) before))))
   (test-case "character-mode controls and NUL boundaries preserve existing output"
     (define f (font (family)))
     (define (paint text mode)
       (with-dc (lambda (dc) (send dc set-font f) (send dc draw-text text 4 4 mode)
                  (send dc get-rgba-bytes))))
     (same-pixels (paint "ab" #f) (paint "a\u000B\u000Cb" #f))
     (same-pixels (paint "ab" #t) (paint "ab\u0000\n" #t)))
   (test-case "PDF and SVG native and outline exports accept described fonts"
     (define f (font (string-append (family) ", Bold")))
     (for* ([format '(pdf svg)] [mode '(native outline)])
       (define saved #f)
       (define-values (bytes report)
         (sk:output->bytes/audit
          (make-dc-output-page 240 100 (lambda (dc) (set! saved dc) (draw-label dc f)))
          format #:policy 'error #:text-mode mode))
       (check-true (> (bytes-length bytes) 100))
       (check-false (sk:output-audit-report-blocking? report))
       (check-false (send saved ok?))
       (check-exn exn:fail? (lambda () (send saved get-text-extent "x")))))
   (test-case "bitmap optional arguments retain documented color and alpha semantics"
     (define bm (rd:make-bitmap 2 2 #t))
     (send bm set-argb-pixels 0 0 2 2 (apply bytes (append* (make-list 4 '(255 20 180 60)))))
     (define tint (make-object rd:color% 255 0 0))
     (define (paint style)
       (with-dc (lambda (dc) (send dc set-alpha 0.5)
         (check-true (send dc draw-bitmap bm 4 4 style tint #f))
         (check-true (send dc draw-bitmap-section bm 8 8 0 0 2 2 style tint #f))
         (send dc get-rgba-bytes))))
     (same-pixels (paint 'solid) (paint 'opaque))
     (same-pixels (paint 'solid) (paint 'xor)))
   (test-case "detached described-text snapshots survive their DC"
     (define image (with-dc (lambda (dc)
                             (draw-label dc (font (string-append (family) ", Bold")))
                             (send dc snapshot))))
     (sk:with-skia ([im image])
       (check-true (> (bytes-length (sk:image->png-bytes im)) 100))))))
(define dc-closure-native-test-count 22)
(module+ main
  (require rackunit/text-ui)
  (define failures (run-tests dc-closure-native-tests))
  (printf "dc-closure-native: ~a cases, ~a failures\n" dc-closure-native-test-count failures)
  (exit (if (zero? failures) 0 1)))
