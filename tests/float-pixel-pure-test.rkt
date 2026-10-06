#lang racket/base
(require rackunit racket/list racket/vector ffi/unsafe "../main.rkt"
         "../private/types.rkt" "../private/float-pixel-util.rkt" "../private/pixel-sample-util.rkt")
(provide float-pixel-pure-tests)
(define (bad thunk) (check-exn exn:fail? thunk))
(define (finfo [format 'rgba-f16] [alpha 'premul])
  (make-image-info 1 1 #:color-type format #:alpha-type alpha))
(define float-pixel-pure-tests
  (test-suite
   "Floating colors and storage (pure)"
   (test-case "Color4f is detached unpremultiplied data"
     (define c (make-color4f -0.5 1.25 2 0.5))
     (check-equal? (color4f->vector c) '#(-0.5 1.25 2.0 0.5))
     (check-false (skia-resource? c)) (check-true (immutable? (color4f->vector c))))
   (test-case "color channels reject nonfinite and nonreal values"
     (for ([v (in-list (list +nan.0 +inf.0 -inf.0 1+2i #t 'red))])
       (bad (lambda () (make-color4f v 0 0)))
       (bad (lambda () (make-color4f 0 v 0)))
       (bad (lambda () (make-color4f 0 0 v)))))
   (test-case "alpha is always finite in range"
     (for ([v (in-list (list -0.01 1.01 +nan.0 +inf.0 #f))])
       (bad (lambda () (make-color4f 0 0 0 v)))))
   (test-case "byte color conversion is explicit and exact at endpoints"
     (check-equal? (color4f->vector (color->color4f (rgba 255 0 255 255))) '#(1.0 0.0 1.0 1.0))
     (check-equal? (color4f->rgba (make-color4f 1 0 1)) (rgba 255 0 255 255)))
   (test-case "extended color quantization requires an explicit clipping choice"
     (define c (make-color4f -0.5 1.5 0.5 0.5))
     (bad (lambda () (color4f->rgba c)))
     (check-equal? (color4f->rgba c #:out-of-range 'clip) (rgba 0 255 128 128))
     (bad (lambda () (color4f->rgba c #:out-of-range 'guess))))
   (test-case "integer format inventory and defaults stay unchanged"
     (check-equal? integer-pixel-formats '#(rgba-8888 bgra-8888 rgb-888x alpha-8 gray-8 rgb-565 rgba-1010102))
     (check-equal? float-pixel-formats '#(rgba-f16 rgba-f32))
     (check-equal? (vector-length pixel-formats) 9)
     (check-equal? (image-info-color-type (make-image-info 1 1)) 'rgba-8888))
   (test-case "metadata reports stored bits and sample kind independently"
     (check-equal? (image-info-channel-bits (finfo)) '#(16 16 16 16))
     (check-equal? (image-info-channel-bits (finfo 'rgba-f32)) '#(32 32 32 32))
     (check-equal? (image-info-sample-type (finfo)) 'float)
     (check-equal? (image-info-sample-type (make-image-info 1 1)) 'unsigned-integer))
   (test-case "F16 and F32 native byte orders and pixel sizes"
     (for ([f (in-vector float-pixel-formats)] [bpp (in-list '(8 16))])
       (define i (finfo f))
       (check-equal? (image-info-bytes-per-pixel i) bpp)
       (check-equal? (image-info-byte-order i) (if (system-big-endian?) 'big-endian 'little-endian))))
   (test-case "float layouts include last-row padding"
     (define i (make-image-info 3 2 #:color-type 'rgba-f16))
     (check-equal? (call-with-values (lambda () (image-info-storage-layout i #:row-bytes 32)) list) '(32 56 64))
     (parameterize ([current-skia-byte-limit 63])
       (bad (lambda () (image-info-storage-layout i #:row-bytes 32)))))
   (test-case "float stride and extent checks precede allocation"
     (bad (lambda () (image-info-storage-layout (finfo 'rgba-f32) #:row-bytes 20)))
     (bad (lambda () (make-raster-buffer-from-info (make-image-info 0 3 #:color-type 'rgba-f32)))))
   (test-case "float storage is not a generalized GPU target claim"
     (for ([f (in-vector float-pixel-formats)])
       (check-true (image-info-supports? (finfo f) 'raster-canvas))
       (check-false (image-info-supports? (finfo f 'unpremul) 'raster-canvas))
       (check-false (image-info-supports? (finfo f) 'gpu-readback))))
   (test-case "normalized F16 and other float enums remain outside scope"
     (for ([f (in-list '(rgba-f16-norm a16-float r16g16-float))])
       (bad (lambda () (make-image-info 1 1 #:color-type f)))))
   (test-case "half-float known bit patterns"
     (for ([v (in-list '(0.0 -0.0 1.0 -2.0 0.5 65504.0))]
           [word (in-list '(0 32768 15360 49152 14336 31743))])
       (check-equal? (real->binary16 v) word)))
   (test-case "half-float ties round to even without an intermediate float32"
     (check-equal? (real->binary16 (+ 1 (expt 2 -11))) #x3c00)
     (check-equal? (real->binary16 (+ 1 (* 3 (expt 2 -11)))) #x3c02)
     (check-equal? (real->binary16 (+ 1 (expt 2 -11) (expt 2 -35))) #x3c01))
   (test-case "half subnormal and signed-zero storage is preserved"
     (check-equal? (real->binary16 (expt 2 -24)) 1)
     (check-equal? (real->binary16 (expt 2 -25)) 0)
     (check-equal? (real->binary16 (* 3 (expt 2 -25))) 2)
     (check-eqv? (binary16->real #x8000) -0.0))
   (test-case "every finite binary16 bit pattern roundtrips"
     (for ([word (in-range 65536)] #:unless (= (bitwise-bit-field word 10 15) 31))
       (check-equal? (real->binary16 (binary16->real word)) word)))
   (test-case "half nonfinite patterns and overflow reject"
     (for ([word (in-list '(31744 64512 32256 65535))]) (bad (lambda () (binary16->real word))))
     (bad (lambda () (real->binary16 65505))) (bad (lambda () (real->binary16 +nan.0))))
   (test-case "float samples retain precision below one byte step"
     (for ([format (in-vector float-pixel-formats)])
       (define i (finfo format))
       (define a (float-sample->bytes 'test i '#(0.5 0 0 1)))
       (define b (float-sample->bytes 'test i '#(0.5009765625 0 0 1)))
       (check-not-equal? a b)))
   (test-case "float premultiplication allows negative and above-alpha RGB"
     (check-equal? (float-sample-check 'test (finfo) '#(-0.25 0.75 1.5 0.5)) '#(-0.25 0.75 1.5 0.5)))
   (test-case "zero-alpha premul is canonical but unpremul retains hidden RGB"
     (bad (lambda () (float-sample->bytes 'test (finfo) '#(1 0 0 0))))
     (check-equal? (float-bytes->sample 'test (finfo 'rgba-f16 'unpremul)
                     (float-sample->bytes 'test (finfo 'rgba-f16 'unpremul) '#(1 2 3 0))) '#(1.0 2.0 3.0 0.0)))
   (test-case "quantized zero alpha cannot leave nonzero premultiplied RGB"
     (bad (lambda () (float-sample->bytes 'test (finfo) (vector 1 0 0 (expt 2 -30))))))
   (test-case "opaque sample initialization uses float one, not integer bits"
     (for ([f (in-vector float-pixel-formats)])
       (define i (finfo f 'opaque))
       (check-equal? (float-bytes->sample 'test i (float-sample->bytes 'test i (float-black-sample i)))
                     '#(0.0 0.0 0.0 1.0))
       (bad (lambda () (float-sample->bytes 'test i '#(0 0 0 0.5))))))
   (test-case "sample lengths and invalid raw float channels reject"
     (bad (lambda () (float-bytes->sample 'test (finfo) (make-bytes 7))))
     (bad (lambda () (float-sample-check 'test (finfo) '#(1 2 3))))
     (bad (lambda () (float-sample-check 'test (finfo) '#(0 0 0 +inf.0))))
     (bad (lambda () (float-sample-check 'test (finfo) '#(65505 0 0 1)))) )
   (test-case "raw storage scans all pixels before destination publication"
     (define i (make-image-info 2 1 #:color-type 'rgba-f32))
     (define good (float-sample->bytes 'test (finfo 'rgba-f32) '#(0 0 0 1)))
     (define bad-pixel (bytes-copy good))
     (bytes-copy! bad-pixel 0 (real->floating-point-bytes +inf.0 4 (system-big-endian?)))
     (bad (lambda () (pixel-storage-input 'test i (bytes-append good bad-pixel) 32))))
   (test-case "full storage and tight views have separate padding contracts"
     (define i (make-image-info 1 2 #:color-type 'rgba-f16))
     (define pixel (float-sample->bytes 'test (finfo) '#(0.5 0.25 0.75 1)))
     (define input (bytes-append pixel (make-bytes 8 165) pixel))
     (check-equal? (pixel-tight-input 'test i input 16) (bytes-append pixel pixel))
     (bad (lambda () (pixel-storage-input 'test i input 16 #:full? #t))))
   (test-case "alpha8 extraction explicitly quantizes float alpha"
     (check-equal? (pixel-sample-alpha/8 (finfo) '#(0 0 0 0.5)) 128))
   (test-case "Color4f ABI is sixteen bytes in RGBA order"
     (check-equal? (ctype-sizeof _sk-color4f) 16)
     (define c (make-sk-color4f 0.125 0.375 0.625 0.875))
     (for ([i (in-range 4)] [v (in-list '(0.125 0.375 0.625 0.875))])
       (check-= (ptr-ref c _float i) v 0.000001)))
   (test-case "gradient inputs reject before native loading"
     (bad (lambda () (make-linear-gradient-color4f-shader '(0 0) '(1 0) '(red blue) #:color-space 'srgb)))
     (bad (lambda () (make-radial-gradient-color4f-shader '(0 0) 0 '() #:color-space 'srgb)))
     (bad (lambda () (make-sweep-gradient-color4f-shader '(0 0) '() #:color-space 'srgb #:start-angle 360 #:end-angle 0))))
   (test-case "stops that collapse at float32 precision are rejected"
     (define cs (list (make-color4f 0 0 0) (make-color4f 1 1 1)))
     (bad (lambda () (make-linear-gradient-color4f-shader '(0 0) '(1 0) cs #:color-space 'srgb
                        #:stops '(0.5 0.500000000001)))))
   (test-case "missing color interpretation is never guessed"
     (bad (lambda () (make-color4f-shader (make-color4f 0 0 0) #:color-space #f))))
   (test-case "new float native accessors reject invalid owners"
     (bad (lambda () (paint-color4f #f)))
     (bad (lambda () (pixmap-color4f #f 0 0)))
     (bad (lambda () (pixmap-alphaf #f 0 0)))
     (bad (lambda () (canvas-clear-color4f! #f (make-color4f 1 0 0)))))
   (test-case "float precision is not reported as portable vector output"
     (for ([backend (in-list '(pdf svg))] [ignored (in-naturals)])
       (check-equal? (output-capability-status (output-capability-for backend 'float-color)) 'needs-raster)
       (check-equal? (output-capability-status (output-capability-for backend 'float-pixels)) 'needs-raster)))
))
