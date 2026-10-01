#lang racket/base
(require rackunit racket/class racket/list racket/vector
         (prefix-in rd: racket/draw)
         "../private/dc-support.rkt" "../private/dc-class.rkt"
         "../private/dc-text-spec.rkt" "../private/dc-bitmap.rkt"
         (only-in "../private/check.rkt" current-skia-byte-limit))
(provide dc-compat-pure-tests dc-compat-pure-test-count)
(define test-font (rd:make-font #:face "Arial" #:size 16 #:size-in-pixels? #t))
(define (request text [mode #f] [offset 0]) (dc-text-description 'test text test-font mode offset))
(define (bitmap w h pixels [alpha? #t] [backing 1.0])
  (define bm (rd:make-bitmap w h alpha? #:backing-scale backing))
  (send bm set-argb-pixels 0 0 (inexact->exact (ceiling (* w backing)))
        (inexact->exact (ceiling (* h backing))) pixels #f #f #:unscaled? #t)
  bm)
(define red (make-object rd:color% 255 0 0))
(define blue (make-object rd:color% 0 0 255))
(define (fresh)
  (define events (box '()))
  (define (record . e) (set-box! events (cons e (unbox events))) (void))
  (define renderer
    (dc-renderer+
     (lambda (w h) (box #t)) void
     (lambda (_s op) (record 'path op)) (lambda (_s . xs) (apply record 'clear xs))
     (lambda (_s) #f) (lambda (_s _p) #"") (lambda (_s) #"")
     (lambda (_s request) (record 'measure request) (values 10.0 20.0 3.0 1.0))
     (lambda (_s . xs) (apply record 'text xs))
     (lambda (_s _spec c) (record 'glyph c) (char=? c #\A))
     (lambda (_s . xs) (apply record 'bitmap xs))
     (lambda (_s . xs) (apply record 'copy xs))))
  (values (new (make-skia-dc-class renderer) [width 64] [height 48]) events))
(define (first-clip-point clip)
  (car (dc-clip-path-commands (car (dc-clip-paths clip)))))
(define dc-compat-pure-tests
  (test-suite
   "DC compatibility contracts; recording renderer, no Skia pixels"
   (test-case "font pixel size preserves fractions"
     (define f (rd:make-font #:face "Arial" #:size 12.5 #:size-in-pixels? #t))
     (check-= (dc-font-spec-size (dc-font-description 'test f)) 12.5 0.0001))
   (test-case "font weight and style translate without native loading"
     (define f (rd:make-font #:face "Arial" #:weight 'semibold #:style 'slant))
     (define d (dc-font-description 'test f))
     (check-equal? (dc-font-spec-weight d) 600) (check-eq? (dc-font-spec-slant d) 'oblique))
   (test-case "font features are deterministically sorted"
     (define f (rd:make-font #:face "Arial" #:feature-settings (hash "liga" 0 "kern" 1)))
     (check-equal? (dc-font-spec-features (dc-font-description 'test f)) '("kern=1" "liga=0")))
   (test-case "character mode ignores control characters"
     (check-equal? (dc-text-spec-units (request "a\nb\u200Ec")) '("a" "b" "c")))
   (test-case "offset precedes NUL truncation"
     (check-equal? (dc-text-spec-units (request "x\u0000ab\u0000cd" #t 2)) '("ab")))
   (test-case "end offset is empty"
     (check-equal? (dc-text-spec-units (request "abc" #t 3)) '()))
   (test-case "invalid offsets do not become substrings"
     (for ([n '(-1 0.5 4 #f)]) (check-exn exn:fail:contract? (lambda () (request "abc" #t n)))))
   (test-case "grapheme mode keeps combining sequence together"
     (check-equal? (dc-text-spec-units (request "a\u0301b" 'grapheme)) '("á" "b")))
   (test-case "true non-grapheme modes combine"
     (check-equal? (dc-text-spec-units (request "office" 'anything)) '("office")))
   (test-case "combined paragraphs rejected rather than silently laid out"
     (check-exn exn:fail:skia-dc:unsupported? (lambda () (request "a\nb" #t))))
   (test-case "class forwards real metrics and explicit font override"
     (define-values (dc e) (fresh))
     (check-equal? (call-with-values (lambda () (send dc get-text-extent "abc" test-font #t)) list)
                   '(10.0 20.0 3.0 1.0))
     (check-equal? (dc-font-spec-family (dc-text-spec-font (second (car (unbox e))))) "Arial")
     (send dc close))
   (test-case "character metrics query a font not a made-up text string"
     (define-values (dc e) (fresh))
     (check-equal? (send dc get-char-width) 10.0) (check-equal? (send dc get-char-height) 20.0)
     (check-true (dc-font-spec? (second (car (unbox e))))) (send dc close))
   (test-case "glyph query returns backend observation"
     (define-values (dc e) (fresh))
     (check-true (send dc glyph-exists? #\A)) (check-false (send dc glyph-exists? #\B))
     (send dc close))
   (test-case "text drawing snapshots foreground alpha and transform"
     (define-values (dc e) (fresh)) (send dc set-font test-font)
     (send dc set-origin 3 4) (send dc set-alpha 0.5) (send dc set-text-foreground "red")
     (send dc draw-text "abc" 7 8 #t)
     (define op (car (unbox e)))
     (check-eq? (car op) 'text) (check-equal? (list-ref op 2) '#(1.0 0.0 0.0 1.0 3.0 4.0))
     (check-equal? (list-ref op 7) '#(255 0 0 0.5)) (send dc close))
   (test-case "invalid text leaves recording untouched"
     (define-values (dc e) (fresh))
     (check-exn exn:fail? (lambda () (send dc draw-text "abc" 0 0 #t 4)))
     (parameterize ([current-skia-byte-limit 1])
       (check-exn exn:fail? (lambda () (send dc draw-text "α" 0 0 #t))))
     (check-equal? (unbox e) '()) (send dc close))
   (test-case "new methods obey owner thread"
     (define-values (dc e) (fresh)) (define result (box #f))
     (thread-wait (thread (lambda () (with-handlers ([exn:fail? (lambda (_) (set-box! result #t))])
                                     (send dc get-text-extent "x")))))
     (check-true (unbox result)) (send dc close))
   (test-case "new methods reject closed DC"
     (define-values (dc e) (fresh)) (send dc close)
     (for ([op (list (lambda () (send dc get-text-extent "x")) (lambda () (send dc glyph-exists? #\A))
                     (lambda () (send dc copy 0 0 1 1 2 2)))]) (check-exn exn:fail? op)))
   (test-case "color source ignores monochrome style and tint"
     (define bm (bitmap 1 1 (bytes 255 10 20 30)))
     (define data (dc-bitmap-snapshot 'test bm 'xor red #f blue))
     (check-equal? (dc-bitmap-data-pixels data) (bytes 10 20 30 255)))
   (test-case "color alpha is premultiplied exactly once"
     (define bm (bitmap 1 1 (bytes 128 255 0 0)))
     (check-equal? (dc-bitmap-data-pixels (dc-bitmap-snapshot 'test bm 'solid red #f blue))
                   (bytes 128 0 0 128)))
   (test-case "alpha mask ignores mask colors"
     (define bm (bitmap 1 1 (bytes 255 255 0 0)))
     (define mask (bitmap 1 1 (bytes 128 0 255 0)))
     (check-equal? (dc-bitmap-data-pixels (dc-bitmap-snapshot 'test bm 'solid red mask blue))
                   (bytes 128 0 0 128)))
   (test-case "opaque grayscale mask uses inverse RGB average"
     (define bm (bitmap 1 1 (bytes 255 255 0 0)))
     (define mask (bitmap 1 1 (bytes 255 0 0 0) #f))
     (check-equal? (dc-bitmap-data-pixels (dc-bitmap-snapshot 'test bm 'solid red mask blue))
                   (bytes 255 0 0 255))
     (send mask set-argb-pixels 0 0 1 1 (bytes 255 30 60 90))
     (check-equal? (dc-bitmap-data-pixels (dc-bitmap-snapshot 'test bm 'solid red mask blue))
                   (bytes 195 0 0 195)))
   (test-case "bad mask size fails before drawing"
     (define bm (bitmap 1 1 (bytes 255 255 0 0)))
     (check-exn exn:fail:contract? (lambda () (dc-bitmap-snapshot 'test bm 'solid red (rd:make-bitmap 2 1) blue))))
   (test-case "bitmap snapshot detaches source mutation"
     (define bm (bitmap 1 1 (bytes 255 255 0 0)))
     (define before (dc-bitmap-snapshot 'test bm 'solid red #f blue))
     (send bm set-argb-pixels 0 0 1 1 (bytes 255 0 0 255))
     (check-equal? (dc-bitmap-data-pixels before) (bytes 255 0 0 255))
     (check-true (immutable? (dc-bitmap-data-pixels before))))
   (test-case "HiDPI source preserves physical pixels"
     (define bm (bitmap 1 1 (apply bytes (append* (make-list 4 '(255 255 0 0)))) #t 2))
     (define data (dc-bitmap-snapshot 'test bm 'solid red #f blue))
     (check-equal? (list (dc-bitmap-data-width data) (dc-bitmap-data-height data)) '(2 2)))
   (test-case "partial source rectangle shifts destination without stretching"
     (define data (dc-bitmap-data 4 4 1 4 4 #""))
     (check-equal? (dc-bitmap-source-rect 'test data -2 0 4 4 10 10 8 8) '#(0.0 0.0 2.0 4.0 14.0 10.0 4.0 8.0)))
   (test-case "outside source is empty"
     (check-false (dc-bitmap-source-rect 'test (dc-bitmap-data 4 4 1 4 4 #"") 10 0 2 2 0 0 2 2)))
   (test-case "bitmap method applies DC alpha, not text foreground"
     (define-values (dc e) (fresh)) (send dc set-alpha 0.25) (send dc set-text-foreground "green")
     (send dc draw-bitmap (bitmap 1 1 (bytes 255 255 0 0)) 0 0)
     (define op (car (unbox e))) (check-eq? (car op) 'bitmap)
     (check-equal? (list-ref op 5) 0.25) (send dc close))
   (test-case "associated region freezes construction transform"
     (define-values (dc e) (fresh)) (send dc set-origin 3 4)
     (define r (new rd:region% [dc dc])) (send r set-rectangle 1 2 5 6)
     (send dc set-origin 30 40) (send dc set-clipping-region r) (send dc clear)
     (check-equal? (first-clip-point (second (car (unbox e)))) '#(move 4.0 6.0)) (send dc close))
   (test-case "unassociated region captures install transform"
     (define-values (dc e) (fresh)) (define r (new rd:region%)) (send r set-rectangle 1 2 5 6)
     (send dc set-origin 3 4) (send dc set-clipping-region r) (send dc set-origin 0 0) (send dc clear)
     (check-equal? (first-clip-point (second (car (unbox e)))) '#(move 4.0 6.0)) (send dc close))
   (test-case "intersections retain separate clip paths"
     (define-values (dc e) (fresh)) (define a (new rd:region%)) (define b (new rd:region%))
     (send a set-rectangle 0 0 10 10) (send b set-rectangle 5 5 10 10) (send a intersect b)
     (send dc set-clipping-region a) (send dc clear)
     (check-equal? (length (dc-clip-paths (second (car (unbox e))))) 2) (send dc close))
   (test-case "odd-even clip rule retained"
     (define-values (dc e) (fresh)) (define p (new rd:dc-path%))
     (send p rectangle 0 0 10 10) (send p rectangle 2 2 4 4)
     (define r (new rd:region%)) (send r set-path p 0 0 'odd-even)
     (send dc set-clipping-region r) (send dc clear)
     (check-eq? (dc-clip-path-rule (car (dc-clip-paths (second (car (unbox e)))))) 'odd-even) (send dc close))
   (test-case "selected region locks and replacement unlocks"
     (define-values (dc e) (fresh)) (define r (new rd:region%)) (send r set-rectangle 0 0 1 1)
     (send dc set-clipping-region r)
     (check-exn exn:fail? (lambda () (send r set-rectangle 0 0 2 2)))
     (check-exn exn:fail? (lambda () (send dc set-clipping-region (new object%))))
     (check-eq? (send dc get-clipping-region) r)
     (check-exn exn:fail? (lambda () (send r set-rectangle 0 0 2 2)))
     (send dc set-clipping-region #f) (send r set-rectangle 0 0 2 2) (send dc close))
   (test-case "close unlocks external region"
     (define-values (dc e) (fresh)) (define r (new rd:region%)) (send r set-rectangle 0 0 1 1)
     (send dc set-clipping-region r) (send dc close) (send r set-rectangle 0 0 2 2))
   (test-case "empty region is an empty clip, not no clipping"
     (define-values (dc e) (fresh)) (send dc set-clipping-region (new rd:region%)) (send dc clear)
     (check-equal? (dc-clip-paths (second (car (unbox e)))) '()) (send dc close))
   (test-case "copy dispatch is independent of current opacity"
     (define-values (dc e) (fresh)) (send dc set-alpha 0.0) (send dc copy 0 0 4 4 2 2)
     (check-eq? (caar (unbox e)) 'copy) (send dc close))
   (test-case "singular text bitmap and copy do not draw"
     (define-values (dc e) (fresh)) (send dc set-scale 0 1)
     (send dc draw-text "x" 0 0) (send dc draw-bitmap (bitmap 1 1 (bytes 255 255 0 0)) 0 0)
     (send dc copy 0 0 1 1 2 2) (check-equal? (unbox e) '()) (send dc close))))
(define dc-compat-pure-test-count 36)
