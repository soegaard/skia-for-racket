#lang racket/base
(require rackunit racket/list racket/vector "../main.rkt" "integer-pixel-fixtures.rkt"
         (submod "../raster-buffers.rkt" gpu-transfer-internals))
(provide integer-pixel-native-tests)
(define (with-buffer format proc)
  (define info (integer-fixture-info format))
  (with-skia ([b (make-raster-buffer-from-info info #:row-bytes (+ (image-info-min-row-bytes info) 8))])
    (fill-integer-fixture! b format) (proc b info)))
(define (pixel bytes x y [width 80])
  (bytes->list (subbytes bytes (* 4 (+ x (* y width))) (* 4 (+ 1 x (* y width))))))
(define (set-padding! b value)
  (define raw (raster-buffer->storage-bytes b))
  (define i (raster-buffer-image-info b))
  (define tight (image-info-min-row-bytes i)) (define rb (raster-buffer-row-bytes b))
  (for* ([y (in-range (image-info-height i))] [x (in-range tight rb)]) (bytes-set! raw (+ (* y rb) x) value))
  (raster-buffer-write-storage! b raw))
(define (check-padding b value)
  (define raw (raster-buffer->storage-bytes b)) (define i (raster-buffer-image-info b))
  (define rb (raster-buffer-row-bytes b))
  (for* ([y (in-range (image-info-height i))] [x (in-range (image-info-min-row-bytes i) rb)])
    (check-equal? (bytes-ref raw (+ (* y rb) x)) value)))
(define integer-pixel-native-tests
  (test-suite
   "General integer pixel storage (native)"
   (test-case "all seven formats retain exact integer samples"
     (for ([format (in-vector integer-pixel-formats)])
       (with-buffer format
         (lambda (b info)
           (check-equal? (raster-buffer-image-info b) info)
           (call-with-raster-buffer-pixmap b
             (lambda (v)
               (for* ([y (in-range 2)] [x (in-range 4)])
                 (check-equal? (pixmap-sample v x y) (vector-ref (integer-fixture-samples format) x)))))))))
   (test-case "raw channel bytes distinguish RGBA and BGRA"
     (with-buffer 'rgba-8888 (lambda (b _) (check-equal? (subbytes (raster-buffer->storage-bytes b) 0 4) (bytes 255 0 0 255))))
     (with-buffer 'bgra-8888 (lambda (b _) (check-equal? (subbytes (raster-buffer->storage-bytes b) 0 4) (bytes 0 0 255 255)))))
   (test-case "all formats convert into explicit RGBA samples"
     (for ([format (in-vector integer-pixel-formats)])
       (with-buffer format
         (lambda (b _)
           (define data (raster-buffer->rgba-bytes b #:premultiplied? #t))
           (check-equal? (pixel data 0 0 4)
                         (case format [(alpha-8) '(0 0 0 0)] [(gray-8) '(0 0 0 255)] [else '(255 0 0 255)]))
           (check-equal? (pixel data 3 1 4)
                         (if (eq? format 'alpha-8) '(0 0 0 255) '(255 255 255 255)))))))
   (test-case "raw ten-bit distinctions do not pass through eight-bit helpers"
     (with-skia ([b (make-raster-buffer-from-info (integer-fixture-info 'rgba-1010102 2 1))])
       (call-with-raster-buffer-pixmap b
         (lambda (v)
           (pixmap-set-sample! v 0 0 '#(1 2 3 3)) (pixmap-set-sample! v 1 0 '#(2 3 4 3))
           (check-equal? (pixmap-sample v 0 0) '#(1 2 3 3))
           (check-equal? (pixmap-sample v 1 0) '#(2 3 4 3))) #:writable? #t)))
   (test-case "opaque allocations are initialized opaque black"
     (for ([format (in-list '(rgba-8888 bgra-8888 rgba-1010102 alpha-8 rgb-888x gray-8 rgb-565))])
       (with-skia ([b (make-raster-buffer-from-info (make-image-info 3 2 #:color-type format #:alpha-type 'opaque))])
         (check-true (raster-buffer-opaque? b))
         (define bytes (raster-buffer->rgba-bytes b))
         (check-equal? (pixel bytes 0 0 3) '(0 0 0 255)))))
   (test-case "premultiplied allocations start transparent"
     (for ([format (in-list '(rgba-8888 bgra-8888 rgba-1010102 alpha-8))])
       (with-skia ([b (make-raster-buffer-from-info (make-image-info 2 1 #:color-type format))])
         (check-false (raster-buffer-opaque? b)))))
   (test-case "color writes preserve opaque alpha"
     (with-skia ([b (make-raster-buffer-from-info (make-image-info 1 1 #:alpha-type 'opaque))])
       (call-with-raster-buffer-pixmap b (lambda (v) (pixmap-fill! v (rgba 40 50 60 0))) #:writable? #t)
       (check-true (raster-buffer-opaque? b))))
   (test-case "malformed raw input is transactional including a late invalid alpha"
     (with-buffer 'rgba-8888
       (lambda (b _)
         (set-padding! b 173)
         (define before (raster-buffer->storage-bytes b)) (define bad (bytes-copy before))
         (bytes-set! bad (+ (raster-buffer-row-bytes b) 15) 0)
         (check-exn exn:fail? (lambda () (raster-buffer-write-storage! b bad)))
         (check-equal? (raster-buffer->storage-bytes b) before))))
   (test-case "raw writes are copied rather than aliased"
     (with-buffer 'bgra-8888
       (lambda (b _)
         (define raw (raster-buffer->storage-bytes b)) (raster-buffer-write-storage! b raw)
         (bytes-fill! raw 0)
         (check-equal? (pixel (raster-buffer->rgba-bytes b) 0 0 4) '(255 0 0 255)))))
   (test-case "subset addressing uses bytes per pixel and preserves every padding byte"
     (for ([format (in-vector integer-pixel-formats)])
       (with-buffer format
         (lambda (b _)
           (set-padding! b 205)
           (call-with-raster-buffer-pixmap b
             (lambda (v)
               (define sub (pixmap-subset v 1 1 2 1))
               (pixmap-set-sample! sub 0 0 (vector-ref (integer-fixture-samples format) 3))
               (check-equal? (pixmap-sample v 1 1) (vector-ref (integer-fixture-samples format) 3))
               (check-equal? (pixmap-sample v 0 1) (vector-ref (integer-fixture-samples format) 0))) #:writable? #t)
           (check-padding b 205)))))
   (test-case "view storage is tight and does not expose neighboring padding"
     (with-buffer 'rgb-565
       (lambda (b _)
         (call-with-raster-buffer-pixmap b
           (lambda (v)
             (define sub (pixmap-subset v 1 0 2 2))
             (check-equal? (bytes-length (pixmap->storage-bytes sub)) 8)
             (check-equal? (image-info-width (pixmap-image-info sub)) 2)
             (check-equal? (pixmap-row-bytes sub) (raster-buffer-row-bytes b)))))))
   (test-case "copy preserves the format and resets destination padding"
     (for ([format (in-vector integer-pixel-formats)])
       (with-buffer format
         (lambda (b info)
           (set-padding! b 173)
           (with-skia ([copy (raster-buffer-copy b #:row-bytes (+ 16 (image-info-min-row-bytes info)))])
             (check-equal? (raster-buffer-image-info copy) info)
             (check-equal? (raster-buffer->rgba-bytes copy) (raster-buffer->rgba-bytes b))
             (check-padding copy 0))))))
   (test-case "format conversion preserves color and does not overwrite padding"
     (with-buffer 'rgba-8888
       (lambda (b _)
         (with-skia ([converted (raster-buffer-convert b (integer-fixture-info 'bgra-8888) #:row-bytes 24)])
           (check-equal? (raster-buffer->rgba-bytes converted) (raster-buffer->rgba-bytes b))
           (check-padding converted 0)))))
   (test-case "RGBA writes keep hidden unpremultiplied channels"
     (with-skia ([b (make-raster-buffer-from-info (make-image-info 1 1 #:alpha-type 'unpremul))])
       (raster-buffer-write-rgba! b (bytes 99 88 77 0))
       (check-equal? (raster-buffer->storage-bytes b) (bytes 99 88 77 0))))
   (test-case "legacy premultiplication remains byte-exact"
     (with-skia ([b (make-raster-buffer 1 1)])
       (raster-buffer-write-rgba! b (bytes 255 127 0 128))
       (check-equal? (raster-buffer->storage-bytes b) (bytes 128 64 0 128))))
   (test-case "RGBA writes convert to selected integer channels"
     (for ([format (in-list '(rgba-8888 bgra-8888 rgb-888x rgb-565 rgba-1010102))])
       (with-buffer format
         (lambda (b _)
           (define data (apply bytes-append (make-list 8 (bytes 255 0 0 255))))
           (raster-buffer-write-rgba! b data)
           (call-with-raster-buffer-pixmap b
             (lambda (v) (check-equal? (pixmap-sample v 3 1) (vector-ref (integer-fixture-samples format) 0))))))))
   (test-case "alpha extraction returns independent untagged alpha storage"
     (for ([format (in-vector integer-pixel-formats)])
       (with-buffer format
         (lambda (b _)
           (with-skia ([a (raster-buffer-extract-alpha b)])
             (check-equal? (image-info-color-type (raster-buffer-image-info a)) 'alpha-8)
             (check-false (image-info-color-space (raster-buffer-image-info a)))
             (skia-close! b)
             (check-equal? (raster-buffer->storage-bytes a)
                           (if (eq? format 'alpha-8) (bytes 0 85 170 255 0 85 170 255) (make-bytes 8 255))))))))
   (test-case "two-bit alpha extraction expands exactly"
     (with-skia ([b (make-raster-buffer-from-info (integer-fixture-info 'rgba-1010102 4 1))])
       (call-with-raster-buffer-pixmap b
         (lambda (v) (for ([a (in-range 4)]) (pixmap-set-sample! v a 0 (vector 0 0 0 a)))) #:writable? #t)
       (with-skia ([a (raster-buffer-extract-alpha b)])
         (check-equal? (raster-buffer->storage-bytes a) (bytes 0 85 170 255)))))
   (test-case "native raster images preserve format and outlive the source"
     (for ([format (in-vector integer-pixel-formats)])
       (with-buffer format
         (lambda (b info)
           (with-skia ([image (raster-buffer->image b)])
             (check-equal? (image-color-type image) format)
             (check-equal? (image->image-info image) info)
             (skia-close! b)
             (with-skia ([surface (make-surface 80 64 #:background 'white)])
               (draw-integer-fixture (surface-canvas surface) image)
               (check-equal? (pixel (surface->rgba-bytes surface) 4 4) '(0 255 0 255))))))))
   (test-case "image snapshots do not observe later writes"
     (with-buffer 'bgra-8888
       (lambda (b _)
         (with-skia ([image (raster-buffer->image b)])
           (call-with-raster-buffer-pixmap b (lambda (v) (pixmap-fill! v 'black)) #:writable? #t)
           (check-equal? (pixel (image->rgba-bytes image) 0 0 4) '(255 0 0 255))))))
   (test-case "all advertised raster formats perform real direct-buffer drawing"
     (for ([format (in-vector integer-pixel-formats)])
       (with-buffer format
         (lambda (b _)
           (set-padding! b 121)
           (call-with-raster-buffer-canvas b (lambda (c) (canvas-clear! c 'white)))
           (check-padding b 121)
           (check-equal? (pixel (raster-buffer->rgba-bytes b) 0 0 4)
                         (if (eq? format 'alpha-8) '(0 0 0 255) '(255 255 255 255)))))))
   (test-case "unpremultiplied buffers reject canvas exposure before callback"
     (with-skia ([b (make-raster-buffer-from-info (make-image-info 2 2 #:alpha-type 'unpremul))])
       (define called? #f)
       (check-exn exn:fail? (lambda () (call-with-raster-buffer-canvas b (lambda (_) (set! called? #t)))))
       (check-false called?) (check-equal? (bytes-length (raster-buffer->storage-bytes b)) 16)))
   (test-case "owned surface constructor initializes selected format"
     (for ([format (in-vector integer-pixel-formats)])
       (with-skia ([surface (make-surface-from-info (integer-fixture-info format 4 2) #:background 'white)]
                   [image (surface-snapshot surface)])
         (check-equal? (image-color-type image) format)
         (check-equal? (pixel (surface->rgba-bytes surface) 1 1 4)
                       (if (eq? format 'alpha-8) '(0 0 0 255) '(255 255 255 255))))))
   (test-case "detached color-space descriptions survive source and buffer close"
     (define saved #f)
     (with-skia ([space (make-srgb-color-space)] [b (make-raster-buffer 2 1 #:color-space space)])
       (set! saved (raster-buffer-image-info b)) (skia-close! space)
       (check-equal? (image-info-color-space saved) 'srgb)
       (call-with-raster-buffer-pixmap b (lambda (v) (pixmap-fill! v 'red)) #:writable? #t))
     (check-equal? (image-info-color-space saved) 'srgb))
   (test-case "new buffer retains color space after temporary construction owner closes"
     (define info (make-image-info 1 1 #:color-space 'linear-srgb))
     (with-skia ([b (make-raster-buffer-from-info info)] [image (raster-buffer->image b)])
       (skia-close! b) (check-equal? (image-info-color-space (image->image-info image)) 'linear-srgb)))
   (test-case "native ICC parsing remains fallible after structural descriptor validation"
     (define bytes (make-bytes 128)) (bytes-copy! bytes 0 (integer->integer-bytes 128 4 #f #t))
     (bytes-copy! bytes 36 #"acsp")
     (define info (make-image-info 1 1 #:color-space bytes))
     (check-exn exn:fail? (lambda () (make-raster-buffer-from-info info))))
   (test-case "tagged versus untagged conversion rejects rather than relabeling"
     (with-skia ([src (make-raster-buffer 1 1)]
                 [dst (make-raster-buffer-from-info (make-image-info 1 1 #:color-space 'srgb))])
       (call-with-raster-buffer-pixmap src
         (lambda (s) (call-with-raster-buffer-pixmap dst
                       (lambda (d) (check-exn exn:fail? (lambda () (pixmap-convert! d s)))) #:writable? #t)))))
   (test-case "sRGB to linear conversion changes samples, not just metadata"
     (with-skia ([src (make-raster-buffer-from-info (make-image-info 1 1 #:color-space 'srgb))])
       (raster-buffer-write-rgba! src (bytes 128 128 128 255))
       (with-skia ([dst (raster-buffer-convert src (make-image-info 1 1 #:color-space 'linear-srgb))])
         (call-with-raster-buffer-pixmap dst
           (lambda (d) (check-true (<= 54 (vector-ref (pixmap-sample d 0 0) 0) 56)))))))
   (test-case "expired views reject new operations as well as old ones"
     (with-buffer 'rgb-565
       (lambda (b _)
         (define stale (call-with-raster-buffer-pixmap b values #:writable? #t))
         (for ([operation (in-list (list (lambda () (pixmap-image-info stale))
                                         (lambda () (pixmap-sample stale 0 0))
                                         (lambda () (pixmap-set-sample! stale 0 0 '#(0 0 0)))
                                         (lambda () (pixmap-opaque? stale))
                                         (lambda () (pixmap->storage-bytes stale))))])
           (check-exn exn:fail? operation)))))
   (test-case "active scope excludes buffer mutation snapshot conversion and closure"
     (with-buffer 'alpha-8
       (lambda (b info)
         (call-with-raster-buffer-pixmap b
           (lambda (_)
             (for ([op (in-list (list (lambda () (skia-close! b))
                                      (lambda () (raster-buffer->storage-bytes b))
                                      (lambda () (raster-buffer-copy b))
                                      (lambda () (raster-buffer-convert b info))))]) (check-exn exn:fail? op)))))))
   (test-case "read-only leases reject raw sample writes"
     (with-buffer 'gray-8
       (lambda (b _)
         (call-with-raster-buffer-pixmap b
           (lambda (v) (check-exn exn:fail? (lambda () (pixmap-set-sample! v 0 0 '#(10)))))))))
   (test-case "exception unwinding expires views and releases the lease"
     (with-buffer 'rgb-565
       (lambda (b _)
         (define stale #f)
         (check-exn exn:fail?
           (lambda () (call-with-raster-buffer-pixmap b (lambda (v) (set! stale v) (error 'test "escape")))))
         (check-exn exn:fail? (lambda () (pixmap-sample stale 0 0)))
         (check-equal? (raster-buffer-width b) 4))))
   (test-case "new metadata and storage operations enforce owner thread"
     (with-buffer 'rgba-8888
       (lambda (b _)
         (define answer (make-channel))
         (define t (thread (lambda () (channel-put answer
           (with-handlers ([exn:fail? (lambda (_) 'rejected)]) (raster-buffer-image-info b) 'unexpected)))))
         (check-equal? (channel-get answer) 'rejected) (thread-wait t))))
   (test-case "same-allocation conversion is rejected even for disjoint subsets"
     (with-buffer 'rgba-8888
       (lambda (b _)
         (call-with-raster-buffer-pixmap b
           (lambda (v)
             (check-exn exn:fail? (lambda () (pixmap-convert! (pixmap-subset v 0 0 2 1) (pixmap-subset v 2 1 2 1)))))
           #:writable? #t))))
   (test-case "legacy GPU transfer rejects incompatible formats before exposing an address"
     (for ([format (in-vector integer-pixel-formats)] #:unless (eq? format 'rgba-8888))
       (with-buffer format
         (lambda (b _)
           (define called? #f)
           (check-exn exn:fail? (lambda () (call-with-raster-buffer-gpu-transfer b
             (lambda args (set! called? #t)))))
           (check-false called?) (check-equal? (raster-buffer-width b) 4)))))
   (test-case "lowered byte budgets reject copies without invalidating the buffer"
     (with-buffer 'rgba-8888
       (lambda (b _)
         (parameterize ([current-skia-byte-limit 4])
           (check-exn exn:fail? (lambda () (raster-buffer->storage-bytes b))))
         (check-equal? (raster-buffer-width b) 4))))
))
