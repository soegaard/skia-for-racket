#lang racket

(require rackunit "pixel-lab.rkt" skia)

(module+ test
  (test-case "duotone leaves alpha and its input byte string unchanged"
    (define source (bytes 255 0 0 128 0 0 0 0 255 255 255 255))
    (define before (bytes-copy source))
    (define result (duotone-rgba source))
    (check-equal? source before)
    (check-equal? (map (lambda (i) (bytes-ref result i)) '(3 7 11)) '(128 0 255))
    (check-equal? (subbytes result 8 11) (bytes 245 182 74)))
  (test-case "malformed sample data is rejected"
    (check-exn exn:fail:contract? (lambda () (duotone-rgba (bytes 1 2 3)))))
  (test-case "padded storage and tight copies have different lengths"
    (with-skia ([buffer (make-source-buffer)])
      (check-equal? (bytes-length (raster-buffer->storage-bytes buffer)) (* 800 128))
      (check-equal? (bytes-length (raster-buffer->rgba-bytes buffer)) (* 192 128 4))))
  (test-case "editing a byte copy does not modify the buffer"
    (with-skia ([buffer (make-source-buffer)])
      (define before (raster-buffer->rgba-bytes buffer))
      (define copy (raster-buffer->rgba-bytes buffer))
      (bytes-fill! copy 0)
      (check-equal? (raster-buffer->rgba-bytes buffer) before)))
  (test-case "processing preserves zero padding"
    (with-skia ([buffer (make-source-buffer)])
      (process-buffer! buffer)
      (define storage (raster-buffer->storage-bytes buffer))
      (for ([y (in-range pixel-height)])
        (check-equal? (subbytes storage (+ (* y 800) 768) (* (+ y 1) 800)) (make-bytes 32)))))
  (test-case "snapshots remain unchanged after mutation and close"
    (define buffer (make-source-buffer))
    (define image (raster-buffer->image buffer))
    (define before (image->rgba-bytes image))
    (process-buffer! buffer)
    (stamp-region! buffer)
    (skia-close! buffer)
    (check-equal? (image->rgba-bytes image) before)
    (skia-close! image))
  (test-case "a saved pixmap is expired after its callback"
    (with-skia ([buffer (make-source-buffer)])
      (define escaped #f)
      (call-with-raster-buffer-pixmap buffer (lambda (view) (set! escaped view)))
      (check-exn exn:fail? (lambda () (pixmap-width escaped)))))
  (test-case "taking a snapshot during an exclusive borrow is rejected"
    (with-skia ([buffer (make-source-buffer)])
      (call-with-raster-buffer-pixmap
       buffer (lambda (_view)
                (check-exn exn:fail? (lambda () (raster-buffer->image buffer)))))))
  (test-case "the tiny layout diagram reads padded storage rather than invented cells"
    (with-skia ([buffer (make-tiny-buffer)])
      (define storage (raster-buffer->storage-bytes buffer))
      (check-equal? (subbytes storage 0 12)
                    (bytes 255 0 0 255 0 255 0 255 0 0 255 255))
      (check-equal? (subbytes storage 12 16) (make-bytes 4))
      (check-equal? (subbytes storage 16 28)
                    (bytes 255 255 0 255 0 255 255 255 255 0 255 255))
      (check-equal? (subbytes storage 28 32) (make-bytes 4))))
  (test-case "processing preserves transparent gaps and the translucent strip"
    (with-skia ([buffer (make-source-buffer)])
      (define before (raster-buffer->rgba-bytes buffer))
      (process-buffer! buffer)
      (define after (raster-buffer->rgba-bytes buffer))
      (for ([i (in-range 3 (bytes-length before) 4)])
        (check-equal? (bytes-ref after i) (bytes-ref before i)))
      (check-equal? (bytes-ref after (+ (* 4 (+ 20 (* 96 pixel-width))) 3)) 0)
      (check-equal? (bytes-ref after (+ (* 4 (+ 20 (* 110 pixel-width))) 3)) 128)))
  (test-case "straight and stored readbacks describe the same half-transparent red"
    (with-skia ([buffer (make-raster-buffer 1 1)])
      (raster-buffer-write-rgba! buffer (bytes 255 0 0 128))
      (check-equal? (raster-buffer->rgba-bytes buffer) (bytes 255 0 0 128))
      (check-equal? (raster-buffer->storage-bytes buffer) (bytes 128 0 0 128))))
  (test-case "pixmap fill replaces pixels instead of compositing over the old color"
    (with-skia ([buffer (make-raster-buffer 2 1)])
      (raster-buffer-write-rgba! buffer (bytes 0 0 255 255 0 0 255 255))
      (call-with-raster-buffer-pixmap
       buffer
       (lambda (view)
         (pixmap-fill! (pixmap-subset view 0 0 1 1) (rgba 255 0 0 128)))
       #:writable? #t)
      (check-equal? (raster-buffer->rgba-bytes buffer)
                    (bytes 255 0 0 128 0 0 255 255))))
  (test-case "the writable subregion replaces exactly the requested interior pixel"
    (with-skia ([buffer (make-source-buffer)])
      (stamp-region! buffer)
      (define pixels (raster-buffer->rgba-bytes buffer))
      (define offset (* 4 (+ 150 (* 105 pixel-width))))
      (check-equal? (subbytes pixels offset (+ offset 4)) (bytes 56 201 189 255)))))
