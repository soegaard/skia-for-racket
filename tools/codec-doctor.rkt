#lang racket/base
(require ffi/unsafe "../main.rkt" "../private/types.rkt" "../tests/codec-fixtures.rkt")
(provide codec-doctor!)

(define (codec-doctor!)
  (unless (and (= (ctype-sizeof _sk-codec-options)
                  (if (= (ctype-sizeof _pointer) 8) 24 16))
               (= (ctype-sizeof _sk-codec-frame-info) 44))
    (error 'doctor "codec ABI layout mismatch"))
  (for ([data (in-list (list animated-gif animated-webp))]
        [expected (in-list (list gif-expected-frames webp-expected-frames))]
        [format (in-list '(gif webp))])
    (with-skia ([c (codec-from-bytes data)])
      (unless (= (codec-frame-count c) (vector-length expected))
        (error 'doctor "~a frame count mismatch" format))
      (for ([i (in-range (sub1 (vector-length expected)) -1 -1)])
        (with-skia ([im (codec->image c #:frame-index i)])
          (unless (equal? (image->rgba-bytes im) (vector-ref expected i))
            (error 'doctor "~a frame ~a pixel mismatch" format i))))))
  (with-skia ([source (rgba-bytes->image 3 2 (vector-ref gif-expected-frames 1))])
    (define jpeg (image->jpeg-bytes source #:quality 100 #:downsample 'yuv-444))
    (for ([origin (in-range 1 9)] [order (in-vector orientation-orders)])
      (with-skia ([c (codec-from-bytes (jpeg-with-origin jpeg origin))]
                  [raw (codec->image c #:normalize-origin? #f)]
                  [normalized (codec->image c)])
        (define pixels (image->rgba-bytes raw))
        (define expected
          (apply bytes-append
                 (for/list ([i (in-vector order)])
                   (subbytes pixels (* 4 i) (+ (* 4 i) 4)))))
        (unless (equal? expected (image->rgba-bytes normalized))
          (error 'doctor "EXIF orientation ~a mismatch" origin)))))
  (printf "Advanced codecs passed: 5 GIF frames, 3 WebP frames, 8 EXIF orientations; ABI options=~a frame-info=~a\n"
          (ctype-sizeof _sk-codec-options) (ctype-sizeof _sk-codec-frame-info)))

(module+ main (skia-check!) (codec-doctor!))
