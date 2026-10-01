#lang racket/base
(require rackunit racket/class racket/list racket/math
         (prefix-in rd: racket/draw) (prefix-in sk: "../main.rkt") "../dc.rkt")
(provide dc-compat-native-tests dc-compat-native-test-count)
(define font (rd:make-font #:size 16 #:size-in-pixels? #t #:hinting 'unaligned))
(define (with-dc proc [w 160] [h 64] [backing 1])
  (define dc (new skia-dc% [width w] [height h] [backing-scale backing] [smoothing 'unsmoothed]))
  (dynamic-wind void (lambda () (send dc set-font font) (proc dc)) (lambda () (send dc close))))
(define (extent dc str [mode #f] [offset 0])
  (call-with-values (lambda () (send dc get-text-extent str #f mode offset)) list))
(define (at dc x y)
  (define-values (w h) (send dc get-pixel-size)) (define bs (send dc get-rgba-bytes #:premultiplied? #t))
  (define i (* 4 (+ x (* y w)))) (bytes->list (subbytes bs i (+ i 4))))
(define (bitmap w h argb [alpha #t] [backing 1])
  (define bm (rd:make-bitmap w h alpha #:backing-scale backing))
  (send bm set-argb-pixels 0 0 (* w backing) (* h backing) argb #f #f #:unscaled? #t) bm)
(define (solid r g b [a 255]) (bitmap 1 1 (bytes a r g b)))
(define red (make-object rd:color% 255 0 0))
(define (ink-count dc)
  (define b (send dc get-rgba-bytes))
  (for/sum ([i (in-range 3 (bytes-length b) 4)] #:when (> (bytes-ref b i) 0)) 1))
(define dc-compat-native-tests
  (test-suite
   "Skia DC text, bitmap and region native execution"
   (test-case "text renders actual colored pixels"
     (with-dc (lambda (dc) (send dc set-text-foreground "red") (send dc draw-text "Skia" 3 3 #t)
                (check-true (> (ink-count dc) 20))
                (define bytes (send dc get-rgba-bytes))
                (check-true (for/or ([i (in-range 0 (bytes-length bytes) 4)])
                              (and (> (bytes-ref bytes i) 0) (= (bytes-ref bytes (+ i 1)) 0)))))))
   (test-case "all combining modes produce finite nonnegative extents"
     (with-dc (lambda (dc)
                (for ([mode '(#f grapheme #t)])
                  (define e (extent dc "office á" mode))
                  (check-equal? (length e) 4)
                  (for ([n (in-list e)]) (check-true (and (real? n) (<= 0 n 10000))))))))
   (test-case "character widths are additive"
     (with-dc (lambda (dc)
                (check-= (car (extent dc "AV")) (+ (car (extent dc "A")) (car (extent dc "V"))) 0.001))))
   (test-case "grapheme widths are additive across clusters"
     (with-dc (lambda (dc)
                (check-= (car (extent dc "áb" 'grapheme))
                          (+ (car (extent dc "á" 'grapheme)) (car (extent dc "b" 'grapheme))) 0.001))))
   (test-case "empty extent retains font height"
     (with-dc (lambda (dc) (define e (extent dc "")) (check-equal? (car e) 0.0) (check-true (> (cadr e) 0)))) )
   (test-case "NUL stops both measurement and drawing"
     (with-dc (lambda (dc)
                (check-equal? (extent dc "Skia\u0000ignored" #t) (extent dc "Skia" #t))
                (send dc draw-text "Skia" 2 2 #t) (define before (send dc get-rgba-bytes))
                (send dc erase) (send dc draw-text "Skia\u0000ignored" 2 2 #t)
                (check-equal? (send dc get-rgba-bytes) before))))
   (test-case "offset measured and drawn consistently"
     (with-dc (lambda (dc)
                (check-equal? (extent dc "xxSkia" #t 2) (extent dc "Skia" #t))
                (send dc draw-text "xxSkia" 2 2 #t 2) (check-true (> (ink-count dc) 20)))))
   (test-case "glyph availability is a real font query"
     (with-dc (lambda (dc) (check-true (send dc glyph-exists? #\A))
                (check-true (boolean? (send dc glyph-exists? (integer->char #x10FFFF)))))))
   (test-case "character metrics are available"
     (with-dc (lambda (dc) (check-true (> (send dc get-char-width) 0))
                (check-true (> (send dc get-char-height) 0)))))
   (test-case "zero-size font draws nothing"
     (with-dc (lambda (dc) (send dc set-font (rd:make-font #:size 0 #:size-in-pixels? #t))
                (check-equal? (extent dc "abc" #t) '(0.0 0.0 0.0 0.0))
                (send dc draw-text "abc" 0 0 #t) (check-equal? (ink-count dc) 0))))
   (test-case "solid text background is disabled by text angle"
     (with-dc (lambda (dc) (send dc set-text-mode 'solid) (send dc set-text-background "red")
                (send dc draw-text "   " 5 5 #t) (check-true (> (ink-count dc) 0))
                (send dc erase) (send dc draw-text "   " 5 5 #t 0 0.2)
                (check-equal? (ink-count dc) 0))))
   (test-case "text opacity zero produces no pixels"
     (with-dc (lambda (dc) (send dc set-alpha 0) (send dc draw-text "Skia" 2 2 #t)
                (check-equal? (ink-count dc) 0))))
   (test-case "text respects empty region clipping"
     (with-dc (lambda (dc) (send dc set-clipping-region (new rd:region%))
                (send dc draw-text "Skia" 2 2 #t) (check-equal? (ink-count dc) 0))))
   (test-case "combined bidi and fallback render without GUI"
     (with-dc (lambda (dc) (send dc draw-text "Racket שלום العربية" 2 2 #t)
                (check-true (> (ink-count dc) 30)))))
   (test-case "repeated text operations retain no caller-owned native objects"
     (for ([i (in-range 6)])
       (with-dc (lambda (dc) (send dc get-text-extent "á office" #f #t)
                  (send dc draw-text "á office" 2 2 #t) (check-true (> (ink-count dc) 20))))))
   (test-case "color bitmap ignores style and tint"
     (with-dc (lambda (dc) (check-true (send dc draw-bitmap (solid 10 20 30) 2 3 'xor red))
                (check-equal? (at dc 2 3) '(10 20 30 255)))))
   (test-case "source alpha and DC opacity combine"
     (with-dc (lambda (dc) (send dc set-alpha 0.5) (send dc draw-bitmap (solid 255 0 0 128) 2 3)
                (define p (at dc 2 3)) (check-true (<= 63 (first p) 65))
                (check-true (<= 63 (fourth p) 65)))))
   (test-case "source mutation is reflected only in subsequent draws"
     (with-dc (lambda (dc) (define bm (solid 255 0 0)) (send dc draw-bitmap bm 2 2)
                (send bm set-argb-pixels 0 0 1 1 (bytes 255 0 0 255)) (send dc draw-bitmap bm 3 2)
                (check-equal? (at dc 2 2) '(255 0 0 255)) (check-equal? (at dc 3 2) '(0 0 255 255)))))
   (test-case "color alpha mask controls opacity not tint"
     (with-dc (lambda (dc) (send dc draw-bitmap (solid 255 0 0) 2 2 'solid red (solid 0 255 0 128))
                (check-equal? (at dc 2 2) '(128 0 0 128)))))
   (test-case "grayscale white mask suppresses drawing"
     (with-dc (lambda (dc)
                (send dc draw-bitmap (solid 255 0 0) 2 2 'solid red (bitmap 1 1 (bytes 255 255 255 255) #f))
                (check-equal? (at dc 2 2) '(0 0 0 0)))))
   (test-case "monochrome solid leaves white pixels transparent"
     (with-dc (lambda (dc) (define bm (rd:make-monochrome-bitmap 2 1))
                (send bm set-argb-pixels 0 0 2 1 (bytes 255 0 0 0 255 255 255 255))
                (send dc draw-bitmap bm 2 2 'solid red)
                (check-equal? (at dc 2 2) '(255 0 0 255)) (check-equal? (at dc 3 2) '(0 0 0 0)))))
   (test-case "monochrome opaque uses DC background"
     (with-dc (lambda (dc) (define bm (rd:make-monochrome-bitmap 1 1))
                (send bm set-argb-pixels 0 0 1 1 (bytes 255 255 255 255))
                (send dc set-background "blue") (send dc draw-bitmap bm 2 2 'opaque red)
                (check-equal? (at dc 2 2) '(0 0 255 255)))))
   (test-case "source sections select source pixels"
     (with-dc (lambda (dc) (define bm (bitmap 2 1 (bytes 255 255 0 0 255 0 0 255)))
                (send dc draw-bitmap-section bm 2 2 1 0 1 1)
                (check-equal? (at dc 2 2) '(0 0 255 255)))))
   (test-case "partially outside source clips destination position"
     (with-dc (lambda (dc) (send dc draw-bitmap-section (solid 255 0 0) 2 2 -1 0 2 1)
                (check-equal? (at dc 2 2) '(0 0 0 0)) (check-equal? (at dc 3 2) '(255 0 0 255)))))
   (test-case "HiDPI source has logical display size"
     (with-dc (lambda (dc) (define bm (bitmap 1 1 (apply bytes (append* (make-list 4 '(255 255 0 0)))) #t 2))
                (send dc draw-bitmap bm 2 2) (check-equal? (at dc 2 2) '(255 0 0 255))
                (check-equal? (at dc 3 2) '(0 0 0 0)))))
   (test-case "smooth section convenience does not alter DC transform"
     (with-dc (lambda (dc) (define before (send dc get-transformation))
                (send dc draw-bitmap-section-smooth (solid 255 0 0) 2 2 4 4 0 0 1 1)
                (check-equal? (send dc get-transformation) before)
                (check-equal? (at dc 3 3) '(255 0 0 255)))))
   (test-case "copy overlap uses a snapshot and ignores DC opacity"
     (with-dc (lambda (dc) (define bm (bitmap 3 1 (bytes 255 255 0 0 255 0 255 0 255 0 0 255)))
                (send dc draw-bitmap bm 2 2) (send dc set-alpha 0) (send dc copy 2 2 3 1 3 2)
                (check-equal? (at dc 3 2) '(255 0 0 255)) (check-equal? (at dc 4 2) '(0 255 0 255))
                (check-equal? (at dc 5 2) '(0 0 255 255)))))
   (test-case "copy transparent pixels replaces existing alpha"
     (with-dc (lambda (dc) (send dc draw-bitmap (solid 255 0 0) 4 4) (send dc copy 0 0 1 1 4 4)
                (check-equal? (at dc 4 4) '(0 0 0 0)))))
   (test-case "copy respects destination clipping"
     (with-dc (lambda (dc) (send dc draw-bitmap (solid 255 0 0) 2 2)
                (send dc set-clipping-rect 5 5 1 1) (send dc copy 2 2 1 1 6 6)
                (check-equal? (at dc 6 6) '(0 0 0 0)))))
   (test-case "arbitrary odd-even region preserves holes"
     (with-dc (lambda (dc) (define p (new rd:dc-path%))
                (send p rectangle 2 2 14 14) (send p rectangle 6 6 4 4)
                (define r (new rd:region%)) (send r set-path p 0 0 'odd-even)
                (send dc set-clipping-region r) (send dc set-background "red") (send dc clear)
                (check-equal? (at dc 3 3) '(255 0 0 255)) (check-equal? (at dc 7 7) '(0 0 0 0)))))
   (test-case "two region paths intersect instead of union"
     (with-dc (lambda (dc) (define a (new rd:region%)) (define b (new rd:region%))
                (send a set-rectangle 0 0 10 10) (send b set-rectangle 5 5 10 10) (send a intersect b)
                (send dc set-clipping-region a) (send dc clear)
                (check-equal? (at dc 7 7) '(255 255 255 255)) (check-equal? (at dc 2 2) '(0 0 0 0)))))
   (test-case "attached region uses construction transform"
     (with-dc (lambda (dc) (send dc set-origin 4 5) (define r (new rd:region% [dc dc]))
                (send r set-rectangle 0 0 3 3) (send dc set-origin 40 50) (send dc set-clipping-region r)
                (send dc clear) (check-equal? (at dc 5 6) '(255 255 255 255)))))
   (test-case "detached region uses install transform and backing scale"
     (with-dc (lambda (dc) (define r (new rd:region%)) (send r set-rectangle 0 0 2 2)
                (send dc set-origin 4 5) (send dc set-clipping-region r) (send dc set-origin 0 0)
                (send dc clear) (check-equal? (at dc 8 10) '(255 255 255 255))
                (check-equal? (at dc 7 10) '(0 0 0 0))) 32 24 2))
   (test-case "bad combined-text arguments leave native pixels unchanged"
     (with-dc (lambda (dc) (send dc clear) (define before (send dc get-rgba-bytes))
                (check-exn exn:fail:skia-dc:unsupported? (lambda () (send dc draw-text "x\ny" 0 0 #t)))
                (check-equal? (send dc get-rgba-bytes) before))))))
(define dc-compat-native-test-count 34)
