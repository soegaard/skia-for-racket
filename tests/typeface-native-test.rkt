#lang racket/base
(require rackunit rackunit/text-ui racket/list racket/vector
         "../main.rkt" "../typefaces.rkt" "typeface-fixtures.rkt")
(provide typeface-native-tests)
(define (with-face proc)
  (with-skia ([face (typeface-from-bytes (fixture-font-bytes))]) (proc face)))
(define (raster face)
  (with-skia ([font (make-font face #:size 40 #:hinting 'none #:edging 'alias)]
              [paint (make-paint #:color 'black #:antialias? #f)]
              [surface (make-surface 96 64 #:background 'white)])
    (draw-simple-text (surface-canvas surface) fixture-text 8 48 font paint)
    (surface->rgba-bytes surface #:premultiplied? #t)))
(define (ink? data)
  (for/or ([i (in-range 0 (bytes-length data) 4)]) (< (bytes-ref data i) 50)))
(define (wrong-thread thunk)
  (define result (box #f))
  (thread-wait
   (thread (lambda ()
             (with-handlers ([exn:fail? (lambda (e) (set-box! result e))])
               (thunk)))))
  (check-pred exn:fail? (unbox result)))
(define typeface-native-tests
  (test-suite
   "0.68a native typeface resources, metadata and detached data"
   (test-case "copied bytes survive mutation of caller storage"
     (define data (fixture-font-bytes))
     (with-skia ([face (typeface-from-bytes data)])
       (bytes-fill! data 0)
       (check-equal? (typeface-postscript-name face) (fixture-postscript))
       (check-true (ink? (raster face)))))
   (test-case "manager-created face survives manager closure"
     (with-skia ([fm (make-font-manager)]
                 [face (font-manager-typeface-from-bytes fm (fixture-font-bytes))])
       (skia-close! fm)
       (check-equal? (typeface-glyph-count face) 4)
       (check-true (ink? (raster face)))))
   (test-case "two TTC members have distinct identities and geometry"
     (define collection (fixture-collection-bytes))
     (with-skia ([a (typeface-from-bytes collection #:index 0)]
                 [b (typeface-from-bytes collection #:index 1)])
       (bytes-fill! collection 0)
       (check-equal? (typeface-postscript-name a) (fixture-postscript))
       (check-equal? (typeface-postscript-name b) (fixture-postscript #t))
       (check-equal? (typeface-weight b) 700)
       (check-not-equal? (raster a) (raster b))))
   (test-case "manager TTC construction uses the requested collection member"
     (with-skia ([fm (make-font-manager)]
                 [face (font-manager-typeface-from-bytes fm (fixture-collection-bytes) #:index 1)])
       (check-equal? (typeface-postscript-name face) (fixture-postscript #t))))
   (test-case "malformed data and unavailable collection member fail explicitly"
     (check-exn exn:fail? (lambda () (typeface-from-bytes #"not a font")))
     (check-exn exn:fail? (lambda () (typeface-from-bytes (fixture-collection-bytes) #:index 20))))
   (test-case "metadata agrees with the controlled fixture"
     (with-face (lambda (f)
       (check-equal? (typeface-glyph-count f) 4)
       (check-equal? (typeface-units-per-em f) 1000)
       (check-true (typeface-fixed-pitch? f))
       (check-equal? (typeface-style f) (make-font-style))
       (check-equal? (typeface-family-name f) fixture-family))))
   (test-case "PostScript and style metadata are detached immutable values"
     (with-face (lambda (f)
       (define name (typeface-postscript-name f))
       (define style (typeface-style f))
       (skia-close! f)
       (check-true (immutable? name))
       (check-equal? name (fixture-postscript))
       (check-equal? (font-style-weight style) 400))))
   (test-case "tags and full table data match independent fixture construction"
     (with-face (lambda (f)
       (define tags (typeface-table-tags f))
       (check-true (immutable? tags))
       (for ([name '("name" "maxp" "kern" "cmap")])
         (define bytes (typeface-table-bytes f name))
         (check-not-false (member (font-table-tag name) (vector->list tags)))
         (check-equal? bytes (fixture-table-bytes name))
         (check-equal? (typeface-table-size f name) (bytes-length bytes))
         (check-true (immutable? bytes))))))
   (test-case "bounded table slices use exclusive byte offsets"
     (with-face (lambda (f)
       (define all (typeface-table-bytes f "name"))
       (check-equal? (typeface-table-bytes f "name" #:start 2 #:end 10) (subbytes all 2 10))
       (check-equal? (typeface-table-bytes f "name" #:start 10) (subbytes all 10))
       (check-equal? (typeface-table-bytes f "name" #:start (bytes-length all)) #""))))
   (test-case "absent tables return false, not empty bytes"
     (with-face (lambda (f)
       (check-false (typeface-table-size f "ZZZZ"))
       (check-false (typeface-table-bytes f "ZZZZ"))
       (check-exn exn:fail:contract? (lambda () (typeface-table-bytes f "ZZZZ" #:start -1))))))
   (test-case "table ranges reject out-of-bounds, reversed and noninteger indices"
     (with-face (lambda (f)
       (define n (typeface-table-size f "maxp"))
       (check-exn exn:fail:contract? (lambda () (typeface-table-bytes f "maxp" #:end (add1 n))))
       (check-exn exn:fail:contract? (lambda () (typeface-table-bytes f "maxp" #:start 5 #:end 3)))
       (check-exn exn:fail:contract? (lambda () (typeface-table-bytes f "maxp" #:start 1.0))))))
   (test-case "small requested slice works even when the full table exceeds budget"
     (with-face (lambda (f)
       (define name (fixture-table-bytes "name"))
       (parameterize ([current-skia-byte-limit 8])
         (check-equal? (typeface-table-bytes f "name" #:start 0 #:end 8) (subbytes name 0 8))
         (check-exn exn:fail:contract? (lambda () (typeface-table-bytes f "name")))))))
   (test-case "table tag buffer respects its budget"
     (with-face (lambda (f)
       (parameterize ([current-skia-byte-limit 4])
         (check-exn exn:fail:contract? (lambda () (typeface-table-tags f)))))))
   (test-case "copied tables survive typeface closure"
     (with-face (lambda (f)
       (define bytes (typeface-table-bytes f "maxp"))
       (skia-close! f)
       (check-equal? bytes (fixture-table-bytes "maxp")))))
   (test-case "raw font bytes plus returned index re-import the selected face"
     (with-skia ([f (typeface-from-bytes (fixture-collection-bytes) #:index 1)])
       (define-values (data index) (typeface->font-bytes f))
       (check-true (immutable? data))
       (check-true (exact-nonnegative-integer? index))
       (skia-close! f)
       ;; Some font hosts may reconstruct a standalone SFNT rather than return
       ;; the source TTC. The returned data/index pair is authoritative.
       (with-skia ([again (typeface-from-bytes data #:index index)])
         (check-equal? (typeface-postscript-name again) (fixture-postscript #t))
         (check-equal? (typeface-glyph-count again) 4))))
   (test-case "raw font extraction checks the byte limit"
     (with-face (lambda (f)
       (parameterize ([current-skia-byte-limit 16])
         (check-exn exn:fail? (lambda () (typeface->font-bytes f)))))))
   (test-case "kerning is a design-unit vector or explicit backend unavailability"
     (with-face (lambda (f)
       (define k (typeface-kerning-pair-adjustments f '(2 3)))
       ;; CoreText and other hosts may not implement legacy pair kerning.
       ;; Unsupported is #f, never invented zeros read from an undefined buffer.
       (when k (check-equal? k '#(-80)) (check-true (immutable? k)))
       (check-equal? (typeface-kerning-pair-adjustments f '()) '#())
       (check-equal? (typeface-kerning-pair-adjustments f '(2)) '#()))))
   (test-case "invalid glyph IDs and excessive kerning buffers reject"
     (with-face (lambda (f)
       (check-exn exn:fail:contract? (lambda () (typeface-kerning-pair-adjustments f '(2 4))))
       (parameterize ([current-skia-byte-limit 7])
         (check-exn exn:fail:contract? (lambda () (typeface-kerning-pair-adjustments f '(2 3))))))))
   (test-case "empty style set participates in generic resource lifetime"
     (with-skia ([s (make-empty-font-style-set)])
       (check-true (skia-resource? s))
       (check-equal? (font-style-set-count s) 0)
       (check-equal? (font-style-set-styles s) '#())
       (check-false (font-style-set-match s))
       (check-exn exn:fail:contract? (lambda () (font-style-set-ref s 0)))
       (check-exn exn:fail:contract? (lambda () (font-style-set-typeface s 0)))
       (skia-close! s) (check-true (skia-closed? s)) (skia-close! s)
       (check-exn exn:fail? (lambda () (font-style-set-count s)))))
   (test-case "style set and typeface survive original manager/set closure"
     (with-skia ([fm (make-font-manager)])
       (check-true (positive? (font-manager-family-count fm)))
       (with-skia ([styles (font-manager-style-set-ref fm 0)])
         (skia-close! fm)
         (check-true (positive? (font-style-set-count styles)))
         (define entry (font-style-set-ref styles 0))
         (check-equal? (font-style-entry-index entry) 0)
         (check-true (immutable? (font-style-entry-name entry)))
         (with-skia ([face (font-style-set-typeface styles 0)]
                     [matched (font-style-set-match styles (font-style-entry-style entry))])
           (skia-close! styles)
           (check-true (positive? (typeface-glyph-count face)))
           (check-true (positive? (typeface-glyph-count matched)))
           (check-pred font-style? (font-style-entry-style entry))))))
   (test-case "family style snapshots have stable indices and detached metadata"
     (with-skia ([fm (make-font-manager)])
       (define family (font-manager-family-name fm 0))
       (with-skia ([styles (font-manager-style-set fm family)])
         (define entries (font-style-set-styles styles))
         (check-true (immutable? entries))
         (check-equal? (vector-length entries) (font-style-set-count styles))
         (for ([e (in-vector entries)] [i (in-naturals)])
           (check-equal? (font-style-entry-index e) i)
           (check-equal? e (font-style-set-ref styles i)))
         (skia-close! styles) (skia-close! fm)
         (for ([e (in-vector entries)]) (check-pred font-style? (font-style-entry-style e))))))
   (test-case "unrecognized family returns an empty set without choosing a fallback"
     (with-skia ([fm (make-font-manager)]
                 [s (font-manager-style-set fm "__Skia_No_Such_Family_068a_62c347e8__")])
       (check-equal? (font-style-set-count s) 0)
       (check-false (font-style-set-match s))))
   (test-case "invalid family/style indices fail before native indexing"
     (with-skia ([fm (make-font-manager)] [s (make-empty-font-style-set)])
       (check-exn exn:fail:contract? (lambda () (font-manager-style-set-ref fm (font-manager-family-count fm))))
       (check-exn exn:fail:contract? (lambda () (font-style-set-ref s -1)))
       (check-exn exn:fail:contract? (lambda () (font-style-set-match s 'normal)))))
   (test-case "empty queries still validate lifetime and thread affinity"
     (with-face (lambda (f)
       (wrong-thread (lambda () (typeface-kerning-pair-adjustments f '())))
       (skia-close! f)
       (check-exn exn:fail? (lambda () (typeface-table-bytes f "maxp" #:end 0)))
       (check-exn exn:fail? (lambda () (typeface-kerning-pair-adjustments f '()))))))
   (test-case "style-set queries and close enforce their owner thread"
     (with-skia ([s (make-empty-font-style-set)])
       (wrong-thread (lambda () (font-style-set-styles s)))
       (wrong-thread (lambda () (skia-close! s)))
       (check-false (skia-closed? s))))
   (test-case "byte-loaded typefaces work through the existing HarfBuzz path"
     (with-face (lambda (face)
       (with-skia ([font (make-font face #:size 30)] [shaper (make-shaper font)])
         (skia-close! face) (skia-close! font)
         (define run (shape-text shaper fixture-text))
         (check-equal? (shaped-run-glyphs run) '(2 3))
         (check-true (positive? (shaped-run-advance-x run)))))))
   (test-case "style-set scoped cleanup runs on exceptions and continuation escape"
     (define escaped #f)
     (let/ec done
       (with-skia ([s (make-empty-font-style-set)]) (set! escaped s) (done (void))))
     (check-true (skia-closed? escaped))
     (define failed #f)
     (check-exn exn:fail? (lambda ()
       (with-skia ([s (make-empty-font-style-set)]) (set! failed s) (error 'test "scope"))))
     (check-true (skia-closed? failed)))
))
(module+ main (skia-check!) (exit (if (zero? (run-tests typeface-native-tests)) 0 1)))
