#lang racket/base

;;;
;;; Reference Raster Test
;;;

;; Checks raster stride and borrowing, pixel conversion, image independence, output groups, and
;; caches.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Opt-in CPU/native acceptance. These tests do not create GUI windows or GPU contexts.
(require rackunit racket/class racket/file racket/list racket/vector
         skia skia/bitmap skia/native-capabilities)


;;;
;;; Diagnostic Operations
;;;

; sample-at : raster-buffer? exact-nonnegative-integer? exact-nonnegative-integer? -> any
;   Samples a pixel through a callback-scoped read-only pixmap.
(define (sample-at buffer x y)
  (call-with-raster-buffer-pixmap buffer (lambda (view) (pixmap-sample view x y))))


; with-writable : raster-buffer? procedure? -> any
;   Gives the callback a writable pixmap whose borrow expires when the scope exits.
(define (with-writable buffer proc)
  (call-with-raster-buffer-pixmap buffer proc #:writable? #t))

(module+ test
  (test-case "legacy buffer allocation includes zeroed padding"
    (with-skia ([buffer (make-raster-buffer 2 2 #:row-bytes 12)])
      (check-equal? (raster-buffer-width buffer) 2)
      (check-equal? (raster-buffer-height buffer) 2)
      (check-equal? (raster-buffer-row-bytes buffer) 12)
      (check-equal? (raster-buffer-byte-size buffer) 24)
      (check-equal? (raster-buffer->storage-bytes buffer) (make-bytes 24))))

  (test-case "raw buffer copies retain padding while view copies are tight"
    (with-skia ([buffer (make-raster-buffer 2 2 #:row-bytes 12)])
      (define data (make-bytes 24))
      (bytes-copy! data 8 (bytes 1 2 3 4))
      (bytes-copy! data 20 (bytes 5 6 7 8))
      (raster-buffer-write-storage! buffer data)
      (bytes-set! data 8 99)
      (check-equal? (bytes-ref (raster-buffer->storage-bytes buffer) 8) 1)
      (define tight (call-with-raster-buffer-pixmap buffer pixmap->storage-bytes))
      (check-equal? tight (make-bytes 16))
      (check-false (immutable? tight))))

  (test-case "independent buffer copies omit old padding"
    (with-skia ([buffer (make-raster-buffer 2 1 #:row-bytes 12)])
      (raster-buffer-write-storage! buffer (bytes 255 0 0 255 0 0 0 0 1 2 3 4))
      (with-skia ([copy (raster-buffer-copy buffer #:row-bytes 16)])
        (check-equal? (subbytes (raster-buffer->storage-bytes copy) 8) (make-bytes 8))
        (with-writable buffer (lambda (view) (pixmap-fill! view 'blue)))
        (check-equal? (sample-at copy 0 0) #(255 0 0 255)))))

  (test-case "pixmap subsets share a lease and expire together"
    (with-skia ([buffer (make-raster-buffer 3 2)])
      (define saved
        (with-writable buffer
          (lambda (view)
            (check-equal? (raster-buffer-width buffer) 3)
            (define subset (pixmap-subset view 2 1 1 1))
            (check-equal? (pixmap-row-bytes subset) 12)
            (pixmap-set-sample! subset 0 0 #(255 0 0 255))
            subset)))
      (check-true (pixmap? saved))
      (check-exn exn:fail? (lambda () (pixmap-width saved)))
      (check-equal? (sample-at buffer 2 1) #(255 0 0 255))))

  (test-case "read-only views and concurrent buffer scopes reject writes"
    (with-skia ([buffer (make-raster-buffer 1 1)])
      (call-with-raster-buffer-pixmap buffer
        (lambda (view)
          (check-false (pixmap-writable? view))
          (check-exn exn:fail? (lambda () (pixmap-fill! view 'red)))
          (check-exn exn:fail? (lambda () (raster-buffer->storage-bytes buffer)))
          (check-exn exn:fail?
                     (lambda () (call-with-raster-buffer-pixmap buffer void)))))))

  (test-case "completed view writes survive a callback failure"
    (with-skia ([buffer (make-raster-buffer 1 1)])
      (check-exn exn:fail?
        (lambda ()
          (with-writable buffer
            (lambda (view)
              (pixmap-fill! view 'red)
              (error 'test "after write")))))
      (check-equal? (sample-at buffer 0 0) #(255 0 0 255))))

  (test-case "invalid full storage is rejected before mutation"
    (with-skia ([buffer (make-raster-buffer 1 1)])
      (define before (raster-buffer->storage-bytes buffer))
      (check-exn exn:fail?
                 (lambda () (raster-buffer-write-storage! buffer (bytes 255 0 0 0))))
      (check-exn exn:fail?
                 (lambda () (raster-buffer-write-storage! buffer (make-bytes 3))))
      (check-equal? (raster-buffer->storage-bytes buffer) before)))

  (test-case "view storage accepts minimum input length without changing padding"
    (with-skia ([buffer (make-raster-buffer 2 2 #:row-bytes 12)])
      (define initial (make-bytes 24))
      (bytes-copy! initial 8 (bytes 9 8 7 6))
      (bytes-copy! initial 20 (bytes 5 4 3 2))
      (raster-buffer-write-storage! buffer initial)
      (define input (make-bytes 20))
      (bytes-copy! input 12 (bytes 255 0 0 255))
      (with-writable buffer
        (lambda (view) (pixmap-write-storage! view input #:row-bytes 12)))
      (check-equal? (sample-at buffer 0 1) #(255 0 0 255))
      (define after (raster-buffer->storage-bytes buffer))
      (check-equal? (subbytes after 8 12) (bytes 9 8 7 6))
      (check-equal? (subbytes after 20 24) (bytes 5 4 3 2))))

  (test-case "BGRA stored order is distinct from logical sample order"
    (with-skia ([buffer (make-raster-buffer-from-info
                         (make-image-info 1 1 #:color-type 'bgra-8888))])
      (with-writable buffer
        (lambda (view) (pixmap-set-sample! view 0 0 #(20 40 60 255))))
      (check-equal? (sample-at buffer 0 0) #(20 40 60 255))
      (check-equal? (raster-buffer->storage-bytes buffer) (bytes 60 40 20 255))))

  (test-case "opaque initialization and float color filling preserve alpha rules"
    (with-skia ([buffer (make-raster-buffer-from-info
                         (make-image-info 1 1 #:alpha-type 'opaque))])
      (check-equal? (sample-at buffer 0 0) #(0 0 0 255))
      (check-true (raster-buffer-opaque? buffer))
      (with-writable buffer
        (lambda (view)
          (check-exn exn:fail?
                     (lambda () (pixmap-fill-color4f! view (make-color4f 1 0 0 0.5))))))
      (check-equal? (sample-at buffer 0 0) #(0 0 0 255))))

  (test-case "F16 samples preserve extended channels and validate rounded zero alpha"
    (with-skia ([buffer (make-raster-buffer-from-info
                         (make-image-info 1 1 #:color-type 'rgba-f16))])
      (with-writable buffer
        (lambda (view)
          (pixmap-set-sample! view 0 0 #(-0.5 2.0 0.0 0.5))
          (check-equal? (pixmap-sample view 0 0) #(-0.5 2.0 0.0 0.5))
          (define before (pixmap->storage-bytes view))
          (check-exn exn:fail?
                     (lambda () (pixmap-set-sample! view 0 0 #(0.5 0 0 1e-20))))
          (check-equal? (pixmap->storage-bytes view) before)))))

  (test-case "pixel conversion uses distinct buffers and leaves source unchanged"
    (with-skia ([source (make-raster-buffer-from-info
                         (make-image-info 1 1 #:color-type 'bgra-8888))]
                [destination (make-raster-buffer 1 1)])
      (with-writable source
        (lambda (view) (pixmap-set-sample! view 0 0 #(20 40 60 255))))
      (call-with-raster-buffer-pixmap source
        (lambda (src)
          (with-writable destination (lambda (dst) (pixmap-convert! dst src)))))
      (check-equal? (sample-at destination 0 0) #(20 40 60 255))
      (check-equal? (raster-buffer->storage-bytes source) (bytes 60 40 20 255))))

  (test-case "tagged to untagged pixel conversion is not implicit sRGB"
    (with-skia ([source (make-raster-buffer 1 1)]
                [destination (make-raster-buffer-from-info
                              (make-image-info 1 1 #:color-space 'srgb))])
      (define before (raster-buffer->storage-bytes destination))
      (call-with-raster-buffer-pixmap source
        (lambda (src)
          (with-writable destination
            (lambda (dst) (check-exn exn:fail? (lambda () (pixmap-convert! dst src)))))))
      (check-equal? (raster-buffer->storage-bytes destination) before)))

  (test-case "buffer drawing shares pixels but the resulting image owns a copy"
    (with-skia ([buffer (make-raster-buffer 2 2)])
      (define saved #f)
      (call-with-raster-buffer-canvas buffer
        (lambda (canvas) (set! saved canvas) (canvas-clear! canvas 'red)))
      (check-exn exn:fail? (lambda () (canvas-save-count saved)))
      (with-skia ([image (raster-buffer->image buffer)])
        (with-writable buffer (lambda (view) (pixmap-fill! view 'blue)))
        (skia-close! buffer)
        (check-equal? (subbytes (image->rgba-bytes image) 0 4) (bytes 255 0 0 255)))))

  (test-case "alpha extraction produces independent alpha-only storage"
    (with-skia ([buffer (make-raster-buffer 1 1)])
      (with-writable buffer (lambda (view) (pixmap-set-sample! view 0 0 #(10 20 30 128))))
      (with-skia ([alpha (raster-buffer-extract-alpha buffer)])
        (skia-close! buffer)
        (check-equal? (image-info-color-type (raster-buffer-image-info alpha)) 'alpha-8)
        (check-equal? (raster-buffer->storage-bytes alpha) (bytes 128)))))

  (test-case "materialized images remain usable after source closure"
    (with-skia ([surface (make-surface 2 2 #:background 'red)]
                [snapshot (surface-snapshot surface)])
      (define bytes (image->png-bytes snapshot))
      (with-skia ([source (image-from-bytes bytes)] [raster (image->raster-image source)])
        (skia-close! source)
        (check-false (image-lazy-generated? raster))
        (check-true (image-pixels-available? raster))
        (check-true (image-valid? raster))
        (check-false (image-texture-backed? raster)))))

  (test-case "failed full-rectangle image reads preserve destination bytes"
    (with-skia ([surface (make-surface 1 1 #:background 'red)]
                [image (surface-snapshot surface)]
                [buffer (make-raster-buffer 2 2)])
      (define before (raster-buffer->storage-bytes buffer))
      (with-writable buffer
        (lambda (view) (check-exn exn:fail? (lambda () (image-read-pixmap! image view)))))
      (check-equal? (raster-buffer->storage-bytes buffer) before)))

  (test-case "image scaling returns an independently owned buffer"
    (with-skia ([surface (make-surface 1 1 #:background 'red)]
                [image (surface-snapshot surface)]
                [buffer (image->raster-buffer image #:info (make-image-info 3 2)
                                               #:sampling 'nearest)])
      (skia-close! image)
      (check-equal? (sample-at buffer 2 1) #(255 0 0 255))))

  (test-case "image-filter results carry bounded immutable placement"
    (with-skia ([surface (make-surface 6 4 #:background 'red)]
                [image (surface-snapshot surface)]
                [filter (make-offset-image-filter 2 1)])
      (define-values (result subset offset)
        (image-apply-filter image filter #:clip '(0 0 12 10)))
      (call-with-skia-resource result
        (lambda (result)
          (check-true (immutable? subset))
          (check-true (immutable? offset))
          (with-skia ([part (apply image-subset result (vector->list subset))]
                      [target (make-surface 12 10)])
            (draw-image (surface-canvas target) part
                        (vector-ref offset 0) (vector-ref offset 1))
            (check-equal? (color->argb (surface-pixel target 3 2)) #xffff0000))))))

  (test-case "Racket bitmap copies are not Skia resources"
    (with-skia ([surface (make-surface 2 3 #:background 'blue)])
      (define bitmap (surface->bitmap surface))
      (skia-close! surface)
      (check-equal? (send bitmap get-width) 2)
      (check-equal? (send bitmap get-height) 3)
      (check-false (skia-resource? bitmap))))

  (test-case "surface property snapshots outlive the surface"
    (with-skia ([surface (make-surface 2 2)])
      (define properties (surface-properties-of surface))
      (skia-close! surface)
      (check-true (surface-properties? properties))
      (check-true (immutable? (surface-properties->jsexpr properties)))))

  (test-case "preflight and export are two separate authoring executions"
    (define count 0)
    (define page
      (make-output-page 10 10
        (lambda (canvas)
          (set! count (add1 count))
          (with-skia ([paint (make-paint #:color 'red)])
            (draw-rect canvas 1 1 8 8 paint)))))
    (define preflight (analyze-output-page page 'svg))
    (check-equal? count 1)
    (check-equal? (output-audit-report-mode preflight) 'preflight)
    (define-values (bytes report) (output->bytes/audit page 'svg #:policy 'vector-only))
    (check-equal? count 2)
    (check-true (positive? (bytes-length bytes)))
    (check-false (output-audit-report-blocking? report))
    (check-equal? (output-audit-report-mode report) 'export))

  (test-case "strict audited publication preserves an existing destination"
    (define directory (make-temporary-file "reference-raster-audit-~a" 'directory))
    (dynamic-wind void
      (lambda ()
        (define destination (build-path directory "test.svg"))
        (call-with-output-file destination (lambda (out) (write-bytes #"before" out)))
        (with-skia ([surface (make-surface 1 1 #:background 'red)]
                    [image (surface-snapshot surface)])
          (define page (make-output-page 5 5 (lambda (canvas) (draw-image canvas image 0 0))))
          (check-exn exn:fail:output-audit?
            (lambda ()
              (save-output/audit page destination 'svg #:policy 'vector-only #:exists 'replace)))
          (check-equal? (file->bytes destination) #"before")))
      (lambda () (delete-directory/files directory))))

  (test-case "raster groups capture once and include padding before scaling"
    (define calls 0)
    (with-skia ([surface (make-surface 20 20)] [paint (make-paint #:color 'red)])
      (define report
        (draw-output-group (surface-canvas surface) 4 5 8 6
          (lambda (canvas) (set! calls (add1 calls)) (draw-rect canvas 0 0 8 6 paint))
          #:policy 'raster #:scale 2 #:padding 1))
      (check-equal? calls 1)
      (check-equal? (output-group-report-strategy report) 'raster)
      (check-equal? (output-group-report-pixel-size report) #(20 16))
      (check-equal? (output-group-report-padded-bounds report) #(3.0 4.0 10.0 8.0))
      (check-equal? (hash-ref (output-group-report-execution report) 'readback_count) 0)
      (check-true (immutable? (output-group-report->jsexpr report)))))

  (test-case "vector-required groups reject embedded images without authoring retries"
    (define calls 0)
    (with-skia ([surface (make-surface 1 1 #:background 'red)]
                [image (surface-snapshot surface)] [document (make-svg-document 10 10)])
      (define rejected
        (with-handlers ([exn:fail:output-group? exn:fail:output-group-report])
          (draw-output-group (svg-document-canvas document) 0 0 5 5
            (lambda (canvas) (set! calls (add1 calls)) (draw-image canvas image 0 0))
            #:policy 'require-vector)))
      (check-equal? calls 1)
      (check-true (output-group-report? rejected))
      (check-equal? (output-group-report-strategy rejected) 'reject)
      (check-equal? (output-group-report-reason rejected) 'vector-required)))

  (test-case "cache setters return previous settings and all changes are restored"
    (for ([get (in-list (list skia-font-cache-limit skia-font-cache-count-limit
                             skia-resource-cache-limit skia-resource-cache-single-allocation-limit))]
          [set-limit! (in-list (list skia-set-font-cache-limit! skia-set-font-cache-count-limit!
                              skia-set-resource-cache-limit!
                              skia-set-resource-cache-single-allocation-limit!))])
      (define old (get))
      (dynamic-wind void
        (lambda ()
          (check-equal? (set-limit! (add1 old)) old)
          (check-equal? (get) (add1 old)))
        (lambda () (set-limit! old)))))

  (test-case "memory reports distinguish bounded observations from process totals"
    (define empty (skia-memory-statistics #:max-entries 0 #:string-limit 0 #:byte-limit 0))
    (check-true (memory-statistics? empty))
    (check-equal? (vector-length (memory-statistics-entries empty)) 0)
    (check-equal? (memory-statistics-scope empty) 'process-global-skia-caches)
    (check-equal? (memory-statistics-string-bytes empty) 0)
    (define report (skia-memory-statistics #:max-entries 32 #:byte-limit 4096))
    (check-true (immutable? (memory-statistics-entries report)))
    (check-false (hash-ref (memory-statistics->jsexpr report) 'atomic))
    (for ([entry (in-vector (memory-statistics-entries report))])
      (check-true (immutable? (memory-statistic-name entry)))
      (case (memory-statistic-kind entry)
        [(numeric) (check-true (exact-nonnegative-integer? (memory-statistic-value entry)))]
        [(string) (check-false (memory-statistic-units entry))
                  (check-true (immutable? (memory-statistic-value entry)))])))

  (test-case "native symbol observations are not GPU backend certification"
    (define report (skia-native-capabilities))
    (check-true (hash-ref report 'required_cpu_symbols_resolved))
    (check-true (hash-ref report 'racket_layouts_checked))
    (check-false (hash-ref report 'backend_creation_verified))
    (check-false (hash-ref report 'hardware_acceleration_verified))
    (define rows
      (skia-native-symbol-inventory '(sk_version_get_milestone
                                    skia_reference_intentionally_missing_symbol
                                    sk_version_get_milestone)))
    (check-equal? (map (lambda (row) (hash-ref row 'available)) rows) '(#t #f #t))
    (check-equal? (hash-ref (car rows) 'name) "sk_version_get_milestone")))
