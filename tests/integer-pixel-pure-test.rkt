#lang racket/base
(require rackunit racket/list racket/vector "../main.rkt"
         "../private/integer-pixel-util.rkt")
(provide integer-pixel-pure-tests)
(define (bad thunk) (check-exn exn:fail? thunk))
(define (info color [alpha #f])
  (make-image-info 3 2 #:color-type color
                   #:alpha-type (or alpha (if (memq color '(rgb-888x rgb-565 gray-8)) 'opaque 'premul))))
(define (layout i [rb #f]) (call-with-values (lambda () (image-info-storage-layout i #:row-bytes rb)) list))
(define integer-pixel-pure-tests
  (test-suite
   "Image information and integer samples (pure)"
   (test-case "metadata defaults and seven integer formats"
     (check-equal? (vector-length integer-pixel-formats) 7)
     (define i (make-image-info 4 2))
     (check-equal? (image-info-color-type i) 'rgba-8888)
     (check-equal? (image-info-alpha-type i) 'premul)
     (check-false (image-info-color-space i))
     (check-equal? (image-info-bytes-per-pixel i) 4))
   (test-case "zero descriptions do not become allocatable buffers"
     (define i (make-image-info 0 12))
     (check-equal? (layout i) '(0 0 0))
     (bad (lambda () (make-raster-buffer-from-info i)))
     (bad (lambda () (make-surface-from-info i))))
   (test-case "empty height has no final-row underflow"
     (check-equal? (layout (make-image-info 3 0)) '(12 0 0)))
   (test-case "negative fractional boolean and oversized dimensions reject"
     (for ([v (in-list '(-1 1/2 32769 #f #t 1.0))])
       (bad (lambda () (make-image-info v 1))) (bad (lambda () (make-image-info 1 v)))))
   (test-case "unknown and unsupported formats reject explicitly"
     (for ([f (in-list '(unknown rgba-f16-norm rg-f16 argb-4444 invented))])
       (bad (lambda () (make-image-info 2 2 #:color-type f)))))
   (test-case "alpha-free formats require opaque metadata"
     (for ([f (in-list '(rgb-565 gray-8 rgb-888x))])
       (bad (lambda () (make-image-info 2 2 #:color-type f)))
       (check-true (image-info? (info f)))))
   (test-case "alpha-only cannot have unpremultiplied or colored interpretation"
     (bad (lambda () (info 'alpha-8 'unpremul)))
     (bad (lambda () (make-image-info 2 2 #:color-type 'alpha-8 #:color-space 'srgb))))
   (test-case "unknown alpha modes reject"
     (for ([a (in-list '(unknown false #t 1))]) (bad (lambda () (info 'rgba-8888 a)))))
   (test-case "byte strides need only their own format alignment"
     (check-equal? (layout (info 'alpha-8) 5) '(5 8 10))
     (check-equal? (layout (info 'rgb-565) 8) '(8 14 16))
     (check-equal? (layout (info 'bgra-8888) 16) '(16 28 32)))
   (test-case "stride size and alignment reject before native loading"
     (for ([rb (in-list '(0 -1 5 6 11 13 12.0 #t))]) (bad (lambda () (layout (info 'rgba-8888) rb)))))
   (test-case "budget charges final-row padding"
     (parameterize ([current-skia-byte-limit 31]) (bad (lambda () (layout (info 'rgba-8888) 16)))))
   (test-case "31-bit row arithmetic is bounded independently of user budget"
     (parameterize ([current-skia-byte-limit (expt 2 50)])
       (bad (lambda () (layout (make-image-info 1 1) (expt 2 32))))
       (bad (lambda () (layout (make-image-info 32768 32768))))))
   (test-case "description construction does not allocate pixel storage"
     (parameterize ([current-skia-byte-limit 1]) (check-true (image-info? (make-image-info 32768 32768)))))
   (test-case "descriptors accept only explicit detached forms"
     (for ([d (in-list '(#f srgb linear-srgb))]) (check-true (color-space-descriptor? d)))
     (bad (lambda () (make-image-info 1 1 #:color-space 'display-p3)))
     (bad (lambda () (make-image-info 1 1 #:color-space (box 'srgb)))))
   (test-case "ICC descriptor copies bytes and is immutable"
     (define b (make-bytes 128)) (bytes-copy! b 0 (integer->integer-bytes 128 4 #f #t))
     (bytes-copy! b 36 #"acsp")
     (define i (make-image-info 1 1 #:color-space b))
     (bytes-fill! b 0)
     (check-true (color-space-descriptor? (image-info-color-space i)))
     (check-true (immutable? (image-info-color-space i))))
   (test-case "ICC descriptor header and size are checked"
     (bad (lambda () (make-image-info 1 1 #:color-space #"not ICC")))
     (define b (make-bytes 128)) (bytes-copy! b 36 #"acsp")
     (bad (lambda () (make-image-info 1 1 #:color-space b))))
   (test-case "dimension changes preserve interpretation"
     (define i (make-image-info 1 2 #:color-type 'bgra-8888 #:alpha-type 'unpremul #:color-space 'srgb))
     (check-equal? (image-info-with-dimensions i 4 5)
                   (make-image-info 4 5 #:color-type 'bgra-8888 #:alpha-type 'unpremul #:color-space 'srgb)))
   (test-case "operation matrix does not promise unpremultiplied rendering"
     (check-true (image-info-supports? (info 'rgba-8888 'unpremul) 'storage))
     (check-false (image-info-supports? (info 'rgba-8888 'unpremul) 'raster-canvas))
     (bad (lambda () (make-surface-from-info (info 'rgba-8888 'unpremul)))))
   (test-case "GPU readback cannot treat arbitrary storage as RGBA"
     (for ([f (in-vector integer-pixel-formats)])
       (check-equal? (image-info-supports? (info f) 'gpu-readback) (eq? f 'rgba-8888)))
     (check-false (image-info-supports? (info 'rgba-8888 'opaque) 'gpu-readback)))
   (test-case "unrecognized operations reject instead of advertising support"
     (bad (lambda () (image-info-supports? (info 'rgba-8888) 'gpu-hdr))))
   (test-case "bytes per pixel and channel precision are independent"
     (check-equal? (image-info-bytes-per-pixel (info 'rgba-1010102)) 4)
     (check-equal? (image-info-channel-bits (info 'rgba-1010102)) '#(10 10 10 2))
     (check-equal? (image-info-channel-bits (info 'rgb-565)) '#(5 6 5)))
   (test-case "BGRA storage exposes logical RGBA samples"
     (check-equal? (integer-sample->bytes 'test (info 'bgra-8888) '#(20 40 60 255)) (bytes 60 40 20 255))
     (check-equal? (integer-bytes->sample 'test (info 'bgra-8888) (bytes 60 40 20 255)) '#(20 40 60 255)))
   (test-case "RGB565 packing is the native word f800 for red"
     (check-equal? (integer-sample->bytes 'test (info 'rgb-565) '#(31 0 0))
                   (integer->integer-bytes #xf800 2 #f (system-big-endian?))))
   (test-case "1010102 packing uses low red and high alpha bits"
     (check-equal? (integer-sample->bytes 'test (info 'rgba-1010102) '#(1023 0 0 3))
                   (integer->integer-bytes #xc00003ff 4 #f (system-big-endian?))))
   (test-case "ten-bit distinctions survive raw samples"
     (define i (info 'rgba-1010102))
     (for ([n (in-list '(1 2 341 342 1022 1023))])
       (define sample (vector n n n 3))
       (check-equal? (integer-bytes->sample 'test i (integer-sample->bytes 'test i sample)) sample)))
   (test-case "opaque samples require initialized maximum alpha"
     (define i (info 'rgba-8888 'opaque))
     (check-equal? (integer-black-sample i) '#(0 0 0 255))
     (bad (lambda () (integer-sample->bytes 'test i '#(0 0 0 0)))))
   (test-case "premultiplication compares differing channel precisions correctly"
     (define i (info 'rgba-1010102))
     (check-equal? (integer-sample-check 'test i '#(341 341 341 1)) '#(341 341 341 1))
     (bad (lambda () (integer-sample-check 'test i '#(342 0 0 1)))))
   (test-case "sample type count and ranges reject"
     (for ([s (in-list (list '#(1 2 3) '#(-1 0 0 255) '#(256 0 0 255) '#(1.0 2 3 255) '#(1 0 0 0)))])
       (bad (lambda () (integer-sample-check 'test (info 'rgba-8888) s)))))
   (test-case "unpremultiplied samples retain hidden RGB at zero alpha"
     (check-equal? (integer-sample->bytes 'test (info 'rgba-8888 'unpremul) '#(99 88 77 0)) (bytes 99 88 77 0)))
   (test-case "strided input can omit only the final padding"
     (define i (make-image-info 1 2 #:color-type 'alpha-8))
     (check-equal? (integer-tight-input 'test i (bytes 10 99 99 99 20) 4) (bytes 10 20))
     (bad (lambda () (integer-tight-input 'test i (bytes 10 99 99 99) 4))))
   (test-case "whole-storage writes require the exact padded allocation"
     (define i (make-image-info 1 2 #:color-type 'alpha-8))
     (bad (lambda () (integer-storage-input 'test i (bytes 1 2 3 4 5) 4 #:full? #t)))
     (check-equal? (integer-storage-input 'test i (bytes 1 2 3 4 5 6 7 8) 4 #:full? #t)
                   (bytes 1 2 3 4 5 6 7 8)))
   (test-case "malformed last pixel is rejected before any write"
     (define i (make-image-info 2 1))
     (bad (lambda () (integer-tight-input 'test i (bytes 0 0 0 0 255 0 0 0) 8))))
   (test-case "integer alpha extraction needs no color conversion"
     (check-equal? (integer-sample-alpha (info 'rgba-1010102) '#(0 0 0 2)) 170)
     (check-equal? (integer-sample-alpha (info 'rgb-565) '#(0 0 0)) 255))
   (test-case "metadata is an ordinary thread-shareable value"
     (define i (info 'rgba-1010102)) (define result (make-channel))
     (define t (thread (lambda () (channel-put result (image-info-channel-bits i)))))
     (check-equal? (channel-get result) '#(10 10 10 2)) (thread-wait t))
))
