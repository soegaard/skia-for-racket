#lang racket/base
(require rackunit racket/list racket/vector ffi/unsafe
         "../main.rkt" "image-operation-fixtures.rkt"
         (submod "../raster-buffers.rkt" image-operation-internals))
(provide image-operation-native-tests)
(define (near-vector actual expected [tolerance 0.00001])
  (check-equal? (vector-length actual) (vector-length expected))
  (for ([a (in-vector actual)] [b (in-vector expected)]) (check-= a b tolerance)))
(define (first-sample b)
  (call-with-raster-buffer-pixmap b (lambda (v) (pixmap-sample v 0 0))))
(define (with-applied filter proc #:subset [subset #f] #:clip [clip '#(-8 -8 48 40)])
  (with-skia ([source (make-operation-source)])
    (define-values (out valid offset) (image-apply-filter source filter #:subset subset #:clip clip))
    (with-skia ([result out]) (proc result valid offset))))
(define (render-source source filter)
  (with-skia ([surface (make-surface 96 64 #:background 'white)]
              [paint (make-paint #:image-filter filter #:antialias? #f)])
    (draw-image (surface-canvas surface) source 24 20 #:paint paint #:sampling 'nearest)
    (surface->rgba-bytes surface)))
(define (render-result result valid offset)
  (with-skia ([visible (apply image-subset result (vector->list valid))]
              [surface (make-surface 96 64 #:background 'white)])
    (draw-image (surface-canvas surface) visible (+ 24 (vector-ref offset 0)) (+ 20 (vector-ref offset 1))
                #:sampling 'nearest)
    (surface->rgba-bytes surface)))
(define image-operation-native-tests
  (test-suite
   "Direct image operations (native)"
   (test-case "raster image metadata has independent meanings"
     (with-skia ([image (make-operation-source)])
       (check-true (exact-positive-integer? (image-unique-id image)))
       (check-false (image-lazy-generated? image)) (check-false (image-texture-backed? image))
       (check-false (image-alpha-only? image)) (check-true (image-valid? image))
       (check-true (image-pixels-available? image))))
   (test-case "alpha-only image query is native and does not inspect composite coverage"
     (with-skia ([b (make-raster-buffer-from-info (make-image-info 2 2 #:color-type 'alpha-8))]
                 [image (raster-buffer->image b)])
       (check-true (image-alpha-only? image))))
   (test-case "encoded image remains lazy until explicit materialization"
     (with-skia ([source (make-operation-source)] [lazy (image-from-bytes (image->png-bytes source))]
                 [plain (image->non-texture-image lazy)] [raster (image->raster-image lazy)])
       (check-true (image-lazy-generated? lazy)) (check-true (image-lazy-generated? plain))
       (check-false (image-lazy-generated? raster)) (check-true (image-pixels-available? raster))
       (check-equal? (image->rgba-bytes raster) (image->rgba-bytes source))))
   (test-case "nontexture aliases have their own native reference"
     (with-skia ([source (make-operation-source)] [copy (image->non-texture-image source)])
       (check-false (eq? source copy)) (check-equal? (image-unique-id source) (image-unique-id copy))
       (skia-close! source) (check-true (image-valid? copy))))
   (test-case "raster aliases outlive source wrappers"
     (with-skia ([source (make-operation-source)] [copy (image->raster-image source)])
       (skia-close! source) (check-equal? (image-width copy) 16)
       (check-equal? (subbytes (image->rgba-bytes copy) 0 4) (bytes 32 96 192 255))))
   (test-case "materialization retains F32 precision without quantization"
     (with-skia ([source (make-operation-float-source)] [copy (image->raster-image source)]
                 [b (image->raster-buffer copy)])
       (check-eq? (image-color-type copy) 'rgba-f32)
       (near-vector (first-sample b) '#(0.5009765625 0.25 0.75 1.0) 0.000001)))
   (test-case "full image read yields independent buffer storage"
     (with-skia ([source (make-operation-source)] [b (image->raster-buffer source)])
       (skia-close! source) (check-equal? (bytes->list (subbytes (raster-buffer->rgba-bytes b) 0 4)) '(32 96 192 255))))
   (test-case "readback cannot alias the immutable source image"
     (with-skia ([source (make-operation-source)] [b (image->raster-buffer source)])
       (call-with-raster-buffer-pixmap b (lambda (v) (pixmap-fill! v 'red)) #:writable? #t)
       (check-equal? (bytes->list (subbytes (image->rgba-bytes source) 0 4)) '(32 96 192 255))))
   (test-case "direct cropped reads use source coordinates"
     (with-skia ([source (make-operation-source)] [b (make-raster-buffer 5 3)])
       (call-with-raster-buffer-pixmap b
         (lambda (v) (image-read-pixmap! source v #:source-x 11 #:source-y 9)) #:writable? #t)
       (check-equal? (bytes->list (subbytes (raster-buffer->rgba-bytes b) 0 4)) '(32 96 192 255))))
   (test-case "cropped reads select nonuniform source pixels"
     (with-skia ([source (rgba-bytes->image 2 2 (bytes 255 0 0 255 0 255 0 255
                                                      0 0 255 255 255 255 255 255))]
                 [b (make-raster-buffer 1 1)])
       (call-with-raster-buffer-pixmap b
         (lambda (v) (image-read-pixmap! source v #:source-x 1 #:source-y 0)) #:writable? #t)
       (check-equal? (raster-buffer->rgba-bytes b) (bytes 0 255 0 255))))
   (test-case "nearest scaling preserves a nonuniform pixel grid"
     (with-skia ([source (rgba-bytes->image 2 1 (bytes 255 0 0 255 0 0 255 255))]
                 [b (image->raster-buffer source #:info (make-image-info 4 1) #:sampling 'nearest)])
       (check-equal? (raster-buffer->rgba-bytes b)
                     (bytes 255 0 0 255 255 0 0 255 0 0 255 255 0 0 255 255))))
   (test-case "F16 destination retains a sub-byte input distinction"
     (with-skia ([source (make-operation-float-source)]
                 [b (image->raster-buffer source #:info (make-image-info 8 6 #:color-type 'rgba-f16)
                                           #:sampling 'nearest)])
       (near-vector (first-sample b) '#(0.5009765625 0.25 0.75 1.0) 0.00001)))
   (test-case "raw shader local translation and tiling preserve numeric pixels"
     (with-skia ([source (rgba-bytes->image 2 1 (bytes 255 0 0 255 0 0 255 255))]
                 [shader (make-raw-image-shader source #:tile-x 'repeat #:matrix (make-matrix 1 0 0 1 1 0))]
                 [paint (make-paint #:shader shader #:antialias? #f)] [s (make-surface 4 1)])
       (draw-rect (surface-canvas s) 0 0 4 1 paint)
       (check-equal? (surface->rgba-bytes s)
                     (bytes 0 0 255 255 255 0 0 255 0 0 255 255 255 0 0 255))))
   (test-case "out-of-bounds reads reject without mutating destination"
     (with-skia ([source (make-operation-source)] [b (make-raster-buffer 5 3)])
       (define before (raster-buffer->storage-bytes b))
       (call-with-raster-buffer-pixmap b
         (lambda (v) (check-exn exn:fail? (lambda () (image-read-pixmap! source v #:source-x 15)))) #:writable? #t)
       (check-equal? (raster-buffer->storage-bytes b) before)))
   (test-case "padding and pixels outside a destination subset remain unchanged"
     (with-skia ([source (make-operation-source)] [b (make-raster-buffer 8 5 #:row-bytes 40)])
       (raster-buffer-write-storage! b (make-bytes 200 255))
       (call-with-raster-buffer-pixmap b
         (lambda (v) (image-read-pixmap! source (pixmap-subset v 2 1 3 2))) #:writable? #t)
       (define data (raster-buffer->storage-bytes b))
       (for ([y (in-range 5)]) (check-equal? (subbytes data (+ (* y 40) 32) (* (add1 y) 40)) (make-bytes 8 255)))
       (check-equal? (subbytes data 0 4) (make-bytes 4 255))
       (check-equal? (subbytes data 48 52) (bytes 32 96 192 255))))
   (test-case "read-only pixmaps cannot be destinations"
     (with-skia ([source (make-operation-source)] [b (make-raster-buffer 16 12)])
       (call-with-raster-buffer-pixmap b
         (lambda (v) (check-exn exn:fail? (lambda () (image-read-pixmap! source v)))))))
   (test-case "expired pixmaps cannot be reused"
     (with-skia ([source (make-operation-source)] [b (make-raster-buffer 16 12)])
       (define old (call-with-raster-buffer-pixmap b values #:writable? #t))
       (check-exn exn:fail? (lambda () (image-scale-pixmap! source old)))))
   (test-case "native staging exceptions leave the destination untouched"
     (with-skia ([b (make-raster-buffer 2 2)])
       (define before (raster-buffer->storage-bytes b))
       (call-with-raster-buffer-pixmap b
         (lambda (v)
           (check-exn exn:fail? (lambda ()
             (call-with-pixmap-write-staging 'test v (lambda (_pm _info) (error 'test "injected failure")))))) #:writable? #t)
       (check-equal? (raster-buffer->storage-bytes b) before)))
   (test-case "nearest scaling changes dimensions explicitly"
     (with-skia ([source (make-operation-source)]
                 [b (image->raster-buffer source #:info (make-image-info 32 24) #:sampling 'nearest)])
       (check-equal? (list (raster-buffer-width b) (raster-buffer-height b)) '(32 24))
       (check-equal? (bytes->list (subbytes (raster-buffer->rgba-bytes b) 0 4)) '(32 96 192 255))))
   (test-case "BGRA conversion preserves channel order in raw storage"
     (with-skia ([source (make-operation-source)]
                 [b (image->raster-buffer source #:info (make-image-info 16 12 #:color-type 'bgra-8888))])
       (check-equal? (bytes->list (subbytes (raster-buffer->storage-bytes b) 0 4)) '(192 96 32 255))))
   (test-case "F32 scaling preserves sub-byte distinctions"
     (with-skia ([source (make-operation-float-source)]
                 [b (image->raster-buffer source #:info (make-image-info 16 12 #:color-type 'rgba-f32) #:sampling 'nearest)])
       (near-vector (first-sample b) '#(0.5009765625 0.25 0.75 1.0) 0.000001)))
   (test-case "explicit F32 to integer conversion ends precision provenance"
     (with-skia ([source (make-operation-float-source)]
                 [b (image->raster-buffer source #:info (make-image-info 16 12))]
                 [out (raster-buffer->image b)])
       (check-eq? (image-color-type out) 'rgba-8888)
       (check-equal? (bytes->list (subbytes (image->rgba-bytes out) 0 4)) '(128 64 191 255))))
   (test-case "tagged to untagged read is not silently relabeled"
     (with-skia ([source (make-operation-float-source 'srgb)] [b (make-raster-buffer 4 3)])
       (define before (raster-buffer->storage-bytes b))
       (call-with-raster-buffer-pixmap b
         (lambda (v) (check-exn exn:fail? (lambda () (image-read-pixmap! source v)))) #:writable? #t)
       (check-equal? before (raster-buffer->storage-bytes b))))
   (test-case "color conversion uses the destination descriptor"
     (with-skia ([source (make-operation-float-source 'srgb)]
                 [b (image->raster-buffer source
                      #:info (make-image-info 4 3 #:color-type 'rgba-f32 #:color-space 'linear-srgb))])
       (define value (first-sample b))
       (check-= (vector-ref value 1) 0.0508761 0.001)
       (check-= (vector-ref value 2) 0.5225216 0.001)))
   (test-case "filter output returns a geometric offset rather than dropping it"
     (with-skia ([filter (make-offset-image-filter 7 5)])
       (with-applied filter
         (lambda (out subset offset)
           (check-equal? offset '#(7 5))
           (check-equal? (vector->list (vector-copy subset 2)) '(16 12))
           (check-true (immutable? subset)) (check-true (immutable? offset))))))
   (test-case "nonzero input subset and clip have distinct coordinate systems"
     (with-skia ([filter (make-offset-image-filter 7 5)])
       (with-applied filter
         (lambda (out subset offset)
           (check-equal? offset '#(12 9))
           (check-equal? (vector->list (vector-copy subset 2)) '(5 3)))
         #:subset '#(4 3 8 6) #:clip '#(12 9 5 3))))
   (test-case "negative offsets remain drawable"
     (with-skia ([filter (make-offset-image-filter -3 -2)])
       (with-applied filter (lambda (out subset offset) (check-equal? offset '#(-3 -2))))))
   (test-case "filtered image outlives source and filter wrappers"
     (with-skia ([source (make-operation-source)] [filter (make-offset-image-filter 7 5)])
       (define-values (out subset offset) (image-apply-filter source filter #:clip '(-8 -8 48 40)))
       (with-skia ([result out])
         (skia-close! source) (skia-close! filter)
         (check-true (image-valid? result)) (check-true (bytes? (render-result result subset offset))))))
   (test-case "direct offset filtering matches independent canvas placement"
     (with-skia ([source (make-operation-source)] [filter (make-offset-image-filter 7 5)])
       (define-values (out subset offset) (image-apply-filter source filter #:clip '(-8 -8 48 40)))
       (with-skia ([result out])
         (check-equal? (render-result result subset offset) (render-source source filter)))))
   (test-case "blur produces an expanded halo and correct final placement"
     (define-values (im offset meta raw) (make-operation-scene-image 'blur))
     (with-skia ([image im])
       (check-true (< (vector-ref offset 0) 0))
       (check-true (> (image-width image) 16))
       (check-true (> (image-height image) 12))))
   (test-case "drop shadow keeps its enlarged valid extent"
     (define-values (im offset meta raw) (make-operation-scene-image 'shadow))
     (with-skia ([image im]) (check-true (> (image-width image) 16)) (check-true (> (image-height image) 12))))
   (test-case "null native filter result raises instead of publishing out parameters"
     (with-skia ([source (make-operation-source)] [filter (make-offset-image-filter 100 100)])
       (check-exn exn:fail? (lambda () (image-apply-filter source filter #:clip '(0 0 2 2))))
       (check-true (image-valid? source))))
   (test-case "filter clip budget is checked before native evaluation"
     (with-skia ([source (make-operation-source)] [filter (make-offset-image-filter 0 0)])
       (parameterize ([current-skia-byte-limit 4096])
         (check-exn exn:fail? (lambda () (image-apply-filter source filter #:clip '(-100 -100 256 256)))))))
   (test-case "raw shader retains its image independently"
     (with-skia ([source (make-operation-source)] [shader (make-raw-image-shader source)]
                 [paint (make-paint #:shader shader)] [surface (make-surface 16 12)])
       (skia-close! source) (skia-close! shader)
       (draw-rect (surface-canvas surface) 0 0 16 12 paint)
       (check-equal? (bytes->list (subbytes (surface->rgba-bytes surface) 0 4)) '(32 96 192 255))))
   (test-case "raw shader bypasses source to destination color conversion"
     (with-skia ([source (make-operation-float-source 'srgb)] [shader (make-raw-image-shader source)]
                 [paint (make-paint #:shader shader #:antialias? #f)]
                 [b (make-raster-buffer-from-info (make-image-info 4 3 #:color-type 'rgba-f32 #:color-space 'linear-srgb))])
       (call-with-raster-buffer-canvas b (lambda (c) (draw-rect c 0 0 4 3 paint)))
       (near-vector (first-sample b) '#(0.5009765625 0.25 0.75 1.0) 0.00001)))
   (test-case "raw shader rejects unsupported cubic sampling"
     (with-skia ([source (make-operation-source)])
       (check-exn exn:fail? (lambda () (make-raw-image-shader source #:sampling 'cubic)))))
   (test-case "raw shader rejects singular local matrices"
     (with-skia ([source (make-operation-source)])
       (check-exn exn:fail? (lambda () (make-raw-image-shader source #:matrix (make-matrix 0 0 0 0 0 0))))))
   (test-case "raw shader strict document export requires explicit rasterization"
     (with-skia ([source (make-operation-source)] [shader (make-raw-image-shader source)] [paint (make-paint #:shader shader)])
       (define page (make-output-page 32 24 (lambda (c) (draw-rect c 0 0 16 12 paint))))
       (for ([kind '(pdf svg)])
         (check-exn exn:fail:output-audit? (lambda () (output->bytes/audit page kind #:policy 'error))))))
   (test-case "float filtering cannot erase the source precision requirement"
     (with-skia ([source (make-operation-float-source)] [filter (make-offset-image-filter 0 0)])
       ;; m119 may either preserve F32 for this filter path or return a
       ;; narrower native result. The wrapper must never silently publish the
       ;; latter. Accept both portable outcomes: an explicit precision
       ;; rejection, or an F32 result that retains strict document provenance.
       (define outcome
         (with-handlers ([exn:fail?
                          (lambda (e)
                            (check-true
                             (regexp-match? #rx"reduced float storage precision"
                                            (exn-message e)))
                            'rejected)])
           (define-values (im subset offset)
             (image-apply-filter source filter #:clip '(0 0 4 3)))
           (with-skia ([out im])
             (check-eq? (image-color-type out) 'rgba-f32)
             (define page (make-output-page 8 8 (lambda (c) (draw-image c out 0 0))))
             (check-exn exn:fail:output-audit?
                        (lambda () (output->bytes/audit page 'pdf #:policy 'error)))
             'preserved)))
       (check-not-false (memq outcome '(rejected preserved)))
       (check-true (image-valid? source))))
   (test-case "closed resources reject before new native work"
     (with-skia ([source (make-operation-source)] [filter (make-offset-image-filter 0 0)])
       (skia-close! filter)
       (check-exn exn:fail? (lambda () (image-apply-filter source filter #:clip '(0 0 16 12))))
       (skia-close! source)
       (check-exn exn:fail? (lambda () (image-unique-id source)))
       (check-exn exn:fail? (lambda () (image->raster-image source)))))
   (test-case "metadata preserves owner-thread affinity"
     (with-skia ([source (make-operation-source)])
       (define result (make-channel))
       (define worker (thread (lambda ()
         (channel-put result (with-handlers ([exn:fail? (lambda (_) 'rejected)])
                               (image-unique-id source) 'unexpected)))))
       (check-eq? (channel-get result) 'rejected) (thread-wait worker)))))
(module+ test
  (require rackunit/text-ui)
  (unless (zero? (run-tests image-operation-native-tests)) (error 'image-operations "native tests failed")))
