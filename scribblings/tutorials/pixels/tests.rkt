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
  (test-case "the writable subregion replaces exactly the requested interior pixel"
    (with-skia ([buffer (make-source-buffer)])
      (stamp-region! buffer)
      (define pixels (raster-buffer->rgba-bytes buffer))
      (define offset (* 4 (+ 150 (* 105 pixel-width))))
      (check-equal? (subbytes pixels offset (+ offset 4)) (bytes 56 201 189 255)))))
