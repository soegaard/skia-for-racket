#lang racket/base
(require rackunit racket/file
         "../main.rkt" "codec-fixtures.rkt")
(provide codec-native-tests)

(define (frame-pixels c index #:normalize? [normalize? #t])
  (with-skia ([im (codec->image c #:frame-index index #:normalize-origin? normalize?)])
    (image->rgba-bytes im)))
(define (reorder pixels order)
  (apply bytes-append
         (for/list ([i (in-vector order)]) (subbytes pixels (* 4 i) (+ (* 4 i) 4)))))
(define (make-test-jpeg)
  (with-skia ([im (rgba-bytes->image 3 2
                    (bytes 255 0 0 255 0 255 0 255 0 0 255 255
                           255 255 0 255 0 255 255 255 255 0 255 255))])
    (image->jpeg-bytes im #:quality 100 #:downsample 'yuv-444)))

(define codec-native-tests
  (test-suite
   "Advanced codecs: native checks"
   (test-case "GIF metadata includes timing, dependencies, disposal and bounds"
     (with-skia ([c (codec-from-bytes animated-gif)])
       (check-true (skia-resource? c))
       (check-false (skia-closed? c))
       (define info (codec-info c))
       (check-equal? (list (encoded-image-info-width info) (encoded-image-info-height info)) '(3 2))
       (check-equal? (encoded-image-info-format info) 'gif)
       (check-equal? (encoded-image-info-frame-count info) 5)
       (check-equal? (codec-frame-count c) 5)
       (check-equal? (codec-repetition-count c) 2)
       (for ([i (in-range 5)] [duration (in-list '(40 70 90 110 130))]
             [disposal (in-list '(keep restore-previous restore-background keep keep))])
         (define f (codec-frame-info c i))
         (check-true (codec-frame-info? f))
         (check-equal? (codec-frame-info-index f) i)
         (check-equal? (codec-frame-info-duration f) duration)
         (check-true (codec-frame-info-fully-received? f))
         (check-equal? (codec-frame-info-disposal-method f) disposal)
         (check-not-false (memq (codec-frame-info-blend f) '(src src-over)))
         (check-true (immutable? (codec-frame-info-rect f))))
       (check-false (codec-frame-info-required-frame (codec-frame-info c 0)))
       (check-equal? (codec-frame-info-rect (codec-frame-info c 1)) '#(1 0 1 1))))
   (test-case "GIF frames are fully composited, including restore previous/background"
     (with-skia ([c (codec-from-bytes animated-gif)])
       (for ([expected (in-vector gif-expected-frames)] [i (in-naturals)])
         (check-equal? (frame-pixels c i) expected))))
   (test-case "GIF decoding is independent of call order and repeat count"
     (with-skia ([c (codec-from-bytes animated-gif)])
       (for ([i (in-list '(4 1 3 0 2 4 4 0 3 1))])
         (collect-garbage)
         (check-equal? (frame-pixels c i) (vector-ref gif-expected-frames i)))))
   (test-case "animated WebP exposes frame timing and infinite repetition"
     (with-skia ([c (codec-from-bytes animated-webp)])
       (check-equal? (encoded-image-info-format (codec-info c)) 'webp)
       (check-equal? (codec-frame-count c) 3)
       (check-equal? (codec-repetition-count c) -1)
       (for ([i (in-range 3)] [duration (in-list '(40 70 90))])
         (check-equal? (codec-frame-info-duration (codec-frame-info c i)) duration))))
   (test-case "animated WebP exact pixels survive out-of-order decoding"
     (with-skia ([c (codec-from-bytes animated-webp)])
       (for ([i (in-list '(2 0 1 2 1 0))])
         (check-equal? (frame-pixels c i) (vector-ref webp-expected-frames i)))))
   (test-case "codec owns a copy of the caller's encoded bytes"
     (define input (bytes-copy animated-gif))
     (with-skia ([c (codec-from-bytes input)])
       (bytes-fill! input 0)
       (collect-garbage)
       (check-equal? (frame-pixels c 4) (vector-ref gif-expected-frames 4))))
   (test-case "metadata is independent but operations reject a closed codec"
     (define c (codec-from-bytes animated-gif))
     (define f (codec-frame-info c 1))
     (skia-close! c)
     (skia-close! c)
     (check-true (skia-closed? c))
     (check-equal? (codec-frame-info-duration f) 70)
     (for ([thunk (in-list (list (lambda () (codec-info c))
                                (lambda () (codec-frame-count c))
                                (lambda () (codec-repetition-count c))
                                (lambda () (codec-frame-info c 0))
                                (lambda () (codec-color-space c))
                                (lambda () (codec->image c))))])
       (check-exn exn:fail? thunk)))
   (test-case "decoded images outlive the codec and have no stale encoded source"
     (with-skia ([im (with-skia ([c (codec-from-bytes animated-gif)])
                       (codec->image c #:frame-index 3))])
       (collect-garbage)
       (check-equal? (image->rgba-bytes im) (vector-ref gif-expected-frames 3))
       (check-false (image-original-encoded-bytes im))
       (with-skia ([roundtrip (image-from-bytes (image->png-bytes im))])
         (check-equal? (image->rgba-bytes roundtrip) (image->rgba-bytes im)))))
   (test-case "codec resources enforce creator-thread ownership"
     (with-skia ([c (codec-from-bytes animated-gif)])
       (define result (make-channel))
       (define worker
         (thread
          (lambda ()
            (channel-put result
              (for/list ([thunk (in-list (list (lambda () (codec-info c))
                                              (lambda () (codec->image c))
                                              (lambda () (skia-close! c))))])
                (with-handlers ([exn:fail? (lambda (_) #t)]) (thunk) #f))))))
       (define answer (sync/timeout 10 result))
       (unless answer (kill-thread worker))
       (check-equal? answer '(#t #t #t))
       (check-equal? (frame-pixels c 0) (vector-ref gif-expected-frames 0))))
   (test-case "still PNG/JPEG/WebP have one decodable frame without changing legacy metadata"
     (with-skia ([source (rgba-bytes->image 3 2 (vector-ref gif-expected-frames 1))])
       (for ([format (in-list '(png jpeg webp))])
         (define bs (image->encoded-bytes source format #:webp-lossless? #t))
         (with-skia ([c (codec-from-bytes bs)] [legacy (image-from-bytes bs)])
           (check-equal? (codec-frame-count c) 1)
           (check-equal? (codec-info c) (encoded-image-info-from-bytes bs))
           (when (zero? (encoded-image-info-frame-count (codec-info c)))
             (check-false (codec-frame-info c 0)))
           (check-equal? (frame-pixels c 0) (image->rgba-bytes legacy))
           (check-exn exn:fail:contract? (lambda () (codec->image c #:frame-index 1)))))))
   (test-case "all EXIF origins normalize exactly once and expose display dimensions"
     (define jpeg (make-test-jpeg))
     (for ([origin (in-range 1 9)] [order (in-vector orientation-orders)])
       (with-skia ([c (codec-from-bytes (jpeg-with-origin jpeg origin))]
                   [raw (codec->image c #:normalize-origin? #f)]
                   [normalized (codec->image c)])
         (define info (codec-info c))
         (define dims (if (< origin 5) '(3 2) '(2 3)))
         (check-equal? (list (image-width raw) (image-height raw)) '(3 2))
         (check-equal? (list (image-width normalized) (image-height normalized)) dims)
         (check-equal? (list (encoded-image-info-display-width info)
                             (encoded-image-info-display-height info)) dims)
         (check-equal? (image->rgba-bytes normalized) (reorder (image->rgba-bytes raw) order))
         (with-skia ([again (image-frame-from-bytes (image->png-bytes normalized))])
           (check-equal? (list (image-width again) (image-height again)) dims)
           (check-equal? (image->rgba-bytes again) (image->rgba-bytes normalized))))))
   (test-case "byte convenience decoder returns a detached selected frame"
     (with-skia ([im (image-frame-from-bytes animated-gif 4)])
       (check-equal? (image->rgba-bytes im) (vector-ref gif-expected-frames 4)))
     (with-skia ([im (image-frame-from-bytes (jpeg-with-origin (make-test-jpeg) 6)
                                            #:normalize-origin? #f)])
       (check-equal? (list (image-width im) (image-height im)) '(3 2))))
   (test-case "explicit color-space conversion and owned color references"
     (with-skia ([srgb (make-srgb-color-space)]
                 [linear (make-linear-srgb-color-space)]
                 [source (rgba-bytes->image 1 1 (bytes 128 128 128 255) #:color-space srgb)]
                 [c (codec-from-bytes (image->png-bytes source))]
                 [plain (codec->image c #:color-space srgb)]
                 [converted (codec->image c #:color-space linear)])
       (with-skia ([tag (image-color-space converted)])
         (check-true (color-space=? tag linear)))
       (define expected (image->rgba-bytes plain #:color-space linear))
       (define actual (image->rgba-bytes converted))
       (for ([a (in-bytes actual)] [b (in-bytes expected)]) (check-true (<= (abs (- a b)) 2)))
       (define source-cs (codec-color-space c))
       (when source-cs
         (with-skia ([owned-cs source-cs])
           (skia-close! c)
           (check-true (color-space? owned-cs))
           (check-true (boolean? (color-space-srgb? owned-cs)))))
       (skia-close! linear)
       (check-equal? (image->rgba-bytes converted) actual)))
   (test-case "invalid frame indexes fail without damaging the codec"
     (with-skia ([c (codec-from-bytes animated-gif)])
       (for ([bad (in-list '(-1 5 100 2147483648 1/2))])
         (check-exn exn:fail:contract? (lambda () (codec->image c #:frame-index bad)))
         (check-exn exn:fail:contract? (lambda () (codec-frame-info c bad))))
       (check-equal? (frame-pixels c 2) (vector-ref gif-expected-frames 2))))
   (test-case "corrupt/truncated data and decoded-byte limits are strict"
     (for ([bad (in-list (list #"not an image" truncated-gif))])
       (check-exn exn:fail?
                  (lambda ()
                    (with-skia ([c (codec-from-bytes bad)] [im (codec->image c)]) (void)))))
     (with-skia ([c (codec-from-bytes animated-gif)])
       (parameterize ([current-skia-byte-limit 23])
         (check-equal? (codec-frame-count c) 5)
         (check-exn exn:fail:contract? (lambda () (codec->image c))))
       (check-equal? (frame-pixels c 4) (vector-ref gif-expected-frames 4))))
   (test-case "file constructors own a snapshot and detach convenience images"
     (define filename (make-temporary-file "skia-codec-~a.gif"))
     (dynamic-wind
       void
       (lambda ()
         (call-with-output-file filename
           (lambda (out) (write-bytes animated-gif out)) #:exists 'truncate #:mode 'binary)
         (with-skia ([c (codec-from-file filename)]
                     [im (image-frame-from-file filename 1)])
           (delete-file filename)
           (check-equal? (frame-pixels c 4) (vector-ref gif-expected-frames 4))
           (check-equal? (image->rgba-bytes im) (vector-ref gif-expected-frames 1))))
       (lambda () (when (file-exists? filename) (delete-file filename)))))
   (test-case "decoded buffers at two MiB remain detached across collections"
     (with-skia ([surface (make-surface 1024 512 #:background 'red)]
                 [c (codec-from-bytes (surface->png-bytes surface))])
       (for ([i (in-range 3)])
         (with-skia ([im (codec->image c)])
           (collect-garbage)
           (define pixels (image->rgba-bytes im))
           (check-equal? (bytes-length pixels) (* 1024 512 4))
           (check-equal? (subbytes pixels 0 4) (bytes 255 0 0 255))
           (check-equal? (subbytes pixels (- (bytes-length pixels) 4)) (bytes 255 0 0 255))))))))

(module+ test
  (require rackunit/text-ui)
  (skia-check!)
  (define failures (run-tests codec-native-tests))
  (unless (zero? failures) (error 'codec-native-test "~a tests failed" failures)))
