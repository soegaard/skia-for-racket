#lang racket/base
(require rackunit racket/list "../main.rkt")
(provide raster-buffer-native-tests)
(define (pixel b [x 0] [y 0]) (call-with-raster-buffer-pixmap b (lambda (v) (pixmap-pixel v x y))))
(define (fill! b color) (call-with-raster-buffer-pixmap b (lambda (v) (pixmap-fill! v color)) #:writable? #t))
(define (thread-rejects? thunk)
  (define result (make-channel))
  (thread (lambda () (with-handlers ([exn:fail? (lambda (_) (channel-put result #t))])
                       (thunk) (channel-put result #f))))
  (sync/timeout 10 result))
(define raster-buffer-native-tests
  (test-suite
   "Raster buffers: native storage, scoped borrowing, and snapshots"
   (test-case "generic resource ownership"
     (define b (make-raster-buffer 2 2)) (check-true (raster-buffer? b))
     (check-true (skia-resource? b)) (skia-close! b) (check-true (skia-closed? b)) (skia-close! b))
   (test-case "padded metadata"
     (with-skia ([b (make-raster-buffer 3 2 #:row-bytes 20)])
       (check-equal? (list (raster-buffer-width b) (raster-buffer-height b)
                         (raster-buffer-row-bytes b) (raster-buffer-byte-size b)) '(3 2 20 40))))
   (test-case "full storage starts zero including padding"
     (with-skia ([b (make-raster-buffer 3 2 #:row-bytes 20)])
       (check-equal? (raster-buffer->storage-bytes b) (make-bytes 40))))
   (test-case "fill affects pixels not padding"
     (with-skia ([b (make-raster-buffer 3 2 #:row-bytes 20)])
       (fill! b 'red) (define bs (raster-buffer->storage-bytes b))
       (for ([y (in-range 2)]) (check-equal? (subbytes bs (+ (* y 20) 12) (* (add1 y) 20)) (make-bytes 8)))
       (check-equal? (pixel b 2 1) (rgb 255 0 0))))
   (test-case "tight detached readback"
     (with-skia ([b (make-raster-buffer 2 1 #:row-bytes 16)])
       (fill! b 'blue) (define bs (raster-buffer->rgba-bytes b)) (fill! b 'red)
       (check-equal? bs (bytes 0 0 255 255 0 0 255 255))))
   (test-case "straight input premultiplied once"
     (with-skia ([b (make-raster-buffer 1 1)])
       (raster-buffer-write-rgba! b (bytes 255 128 64 128))
       (check-equal? (raster-buffer->storage-bytes b) (bytes 128 64 32 128))))
   (test-case "premultiplied input not multiplied twice"
     (with-skia ([b (make-raster-buffer 1 1)])
       (raster-buffer-write-rgba! b (bytes 64 32 16 128) #:premultiplied? #t)
       (check-equal? (raster-buffer->rgba-bytes b #:premultiplied? #t) (bytes 64 32 16 128))))
   (test-case "padded input omits final padding"
     (with-skia ([b (make-raster-buffer 1 2 #:row-bytes 12)])
       (raster-buffer-write-rgba! b (bytes 255 0 0 255 9 9 9 9 0 0 255 255) #:row-bytes 8)
       (check-equal? (pixel b 0 1) (rgb 0 0 255))))
   (test-case "invalid late premultiplied pixel leaves destination unchanged"
     (with-skia ([b (make-raster-buffer 2 1)])
       (fill! b 'blue) (define before (raster-buffer->storage-bytes b))
       (check-exn exn:fail? (lambda () (raster-buffer-write-rgba! b (bytes 1 1 1 255 200 0 0 1) #:premultiplied? #t)))
       (check-equal? (raster-buffer->storage-bytes b) before)))
   (test-case "read-only view rejects every write"
     (with-skia ([b (make-raster-buffer 1 1)])
       (call-with-raster-buffer-pixmap b
         (lambda (v)
           (check-false (pixmap-writable? v))
           (check-exn exn:fail? (lambda () (pixmap-fill! v 'red)))
           (check-exn exn:fail? (lambda () (pixmap-set-pixel! v 0 0 'red)))
           (check-exn exn:fail? (lambda () (pixmap-write-rgba! v (bytes 0 0 0 0))))))))
   (test-case "subset preserves parent stride"
     (with-skia ([b (make-raster-buffer 5 4 #:row-bytes 32)])
       (call-with-raster-buffer-pixmap b
         (lambda (v)
           (define sub (pixmap-subset v 2 1 2 2))
           (check-equal? (list (pixmap-width sub) (pixmap-height sub) (pixmap-row-bytes sub)) '(2 2 32))
           (pixmap-fill! sub 'red)) #:writable? #t)
       (check-equal? (pixel b 2 1) (rgb 255 0 0))
       (check-equal? (pixel b 1 1) (rgba 0 0 0 0))
       (check-equal? (pixel b 4 2) (rgba 0 0 0 0))))
   (test-case "nested subset offsets accumulate"
     (with-skia ([b (make-raster-buffer 4 4)])
       (call-with-raster-buffer-pixmap b
         (lambda (v) (pixmap-fill! (pixmap-subset (pixmap-subset v 1 1 3 3) 1 1 1 1) 'blue)) #:writable? #t)
       (check-equal? (pixel b 2 2) (rgb 0 0 255))))
   (test-case "subset bounds never silently clipped"
     (with-skia ([b (make-raster-buffer 2 2)])
       (call-with-raster-buffer-pixmap b (lambda (v) (check-exn exn:fail? (lambda () (pixmap-subset v 1 1 2 2)))))))
   (test-case "out of range pixel rejected before native access"
     (with-skia ([b (make-raster-buffer 2 2)])
       (call-with-raster-buffer-pixmap b (lambda (v) (check-exn exn:fail? (lambda () (pixmap-pixel v 2 0)))))))
   (test-case "escaped views and subsets expire"
     (with-skia ([b (make-raster-buffer 2 2)])
       (define subset #f)
       (define v (call-with-raster-buffer-pixmap b
                   (lambda (root)
                     (set! subset (pixmap-subset root 1 1 1 1))
                     (collect-garbage)
                     (pixmap-fill! subset 'blue)
                     root) #:writable? #t))
       (check-true (pixmap? v)) (check-exn exn:fail? (lambda () (pixmap-width v)))
       (check-exn exn:fail? (lambda () (pixmap-fill! v 'red)))
       (check-exn exn:fail? (lambda () (pixmap-pixel subset 0 0)))
       (check-equal? (pixel b 1 1) (rgb 0 0 255))))
   (test-case "old view does not reactivate in a later scope"
     (with-skia ([b (make-raster-buffer 2 2)])
       (define old (call-with-raster-buffer-pixmap b values))
       (call-with-raster-buffer-pixmap b (lambda (_) (check-exn exn:fail? (lambda () (pixmap-pixel old 0 0)))))))
   (test-case "close during pixmap borrow rejected"
     (with-skia ([b (make-raster-buffer 2 2)])
       (call-with-raster-buffer-pixmap b (lambda (_) (check-exn exn:fail? (lambda () (skia-close! b)))))
       (check-false (skia-closed? b))))
   (test-case "same buffer cannot have nested views"
     (with-skia ([b (make-raster-buffer 2 2)])
       (call-with-raster-buffer-pixmap b (lambda (_) (check-exn exn:fail? (lambda () (call-with-raster-buffer-pixmap b void)))))))
   (test-case "view blocks direct drawing"
     (with-skia ([b (make-raster-buffer 2 2)])
       (call-with-raster-buffer-pixmap b (lambda (_) (check-exn exn:fail? (lambda () (call-with-raster-buffer-canvas b void)))))))
   (test-case "view blocks bulk access through owner"
     (with-skia ([b (make-raster-buffer 2 2)])
       (call-with-raster-buffer-pixmap b (lambda (_) (check-exn exn:fail? (lambda () (raster-buffer->storage-bytes b)))))))
   (test-case "view callback returns multiple values"
     (with-skia ([b (make-raster-buffer 2 2)])
       (check-equal? (call-with-values (lambda () (call-with-raster-buffer-pixmap b (lambda (_) (values 1 2)))) list) '(1 2))))
   (test-case "view exception releases lease"
     (with-skia ([b (make-raster-buffer 2 2)])
       (check-exn exn:fail? (lambda () (call-with-raster-buffer-pixmap b (lambda (_) (error 'test "abort")))))
       (check-equal? (pixel b) (rgba 0 0 0 0))))
   (test-case "view continuation escape retires lease"
     (with-skia ([b (make-raster-buffer 2 2)])
       (define old #f)
       (check-eq? (let/ec exit (call-with-raster-buffer-pixmap b (lambda (v) (set! old v) (exit 'escaped)))) 'escaped)
       (check-exn exn:fail? (lambda () (pixmap-pixel old 0 0)))
       (check-equal? (pixel b) (rgba 0 0 0 0))))
   (test-case "buffer and view reject cross-thread access"
     (with-skia ([b (make-raster-buffer 2 2)])
       (check-true (thread-rejects? (lambda () (raster-buffer-width b))))
       (call-with-raster-buffer-pixmap b (lambda (v) (check-true (thread-rejects? (lambda () (pixmap-pixel v 0 0))))))))
   (test-case "native direct canvas changes same padded allocation"
     (with-skia ([b (make-raster-buffer 3 2 #:row-bytes 20)])
       (call-with-raster-buffer-canvas b (lambda (c) (canvas-clear! c 'red)))
       (check-equal? (pixel b 2 1) (rgb 255 0 0))
       (define raw (raster-buffer->storage-bytes b))
       (check-equal? (subbytes raw 12 20) (make-bytes 8)) (check-equal? (subbytes raw 32 40) (make-bytes 8))))
   (test-case "canvas sees preexisting pixel contents"
     (with-skia ([b (make-raster-buffer 8 8)] [p (make-paint #:color 'blue)])
       (fill! b 'red)
       (call-with-raster-buffer-canvas b (lambda (c) (draw-rect c 0 0 4 8 p)))
       (check-equal? (pixel b 1 1) (rgb 0 0 255)) (check-equal? (pixel b 6 1) (rgb 255 0 0))))
   (test-case "escaped canvas is expired"
     (with-skia ([b (make-raster-buffer 2 2)])
       (define c (call-with-raster-buffer-canvas b values))
       (check-exn exn:fail? (lambda () (canvas-clear! c 'white)))))
   (test-case "canvas borrow blocks close and pixel views"
     (with-skia ([b (make-raster-buffer 2 2)])
       (call-with-raster-buffer-canvas b
         (lambda (_)
           (check-exn exn:fail? (lambda () (skia-close! b)))
           (check-exn exn:fail? (lambda () (call-with-raster-buffer-pixmap b void)))
           (check-exn exn:fail? (lambda () (call-with-raster-buffer-canvas b void)))))))
   (test-case "canvas callback returns multiple values"
     (with-skia ([b (make-raster-buffer 2 2)])
       (check-equal? (call-with-values (lambda () (call-with-raster-buffer-canvas b (lambda (_) (values 'a 'b)))) list) '(a b))))
   (test-case "canvas exceptions retain writes and release storage"
     (with-skia ([b (make-raster-buffer 2 2)])
       (check-exn exn:fail? (lambda () (call-with-raster-buffer-canvas b (lambda (c) (canvas-clear! c 'red) (error 'test "abort")))))
       (check-equal? (pixel b) (rgb 255 0 0))))
   (test-case "canvas escape retires canvas without rollback"
     (with-skia ([b (make-raster-buffer 2 2)])
       (define c #f)
       (check-eq? (let/ec exit (call-with-raster-buffer-canvas b (lambda (v) (set! c v) (canvas-clear! v 'blue) (exit 'escaped)))) 'escaped)
       (check-exn exn:fail? (lambda () (canvas-clear! c 'white))) (check-equal? (pixel b) (rgb 0 0 255))))
   (test-case "fresh canvas starts at identity with full clip"
     (with-skia ([b (make-raster-buffer 4 4)])
       (call-with-raster-buffer-canvas b (lambda (c) (canvas-translate! c 10 10) (canvas-clip-rect! c 0 0 1 1)))
       (call-with-raster-buffer-canvas b (lambda (c) (canvas-clear! c 'blue)))
       (check-equal? (pixel b 3 3) (rgb 0 0 255))))
   (test-case "snapshot survives source mutation and closure"
     (define b (make-raster-buffer 2 2)) (fill! b 'red)
     (with-skia ([im (raster-buffer->image b)])
       (fill! b 'blue) (skia-close! b)
       (check-equal? (subbytes (image->rgba-bytes im) 0 4) (bytes 255 0 0 255))))
   (test-case "copy changes stride without sharing pixels"
     (with-skia ([b (make-raster-buffer 2 2 #:row-bytes 16)])
       (fill! b 'red)
       (with-skia ([copy (raster-buffer-copy b #:row-bytes 20)])
         (fill! b 'blue) (check-equal? (pixel copy) (rgb 255 0 0))
         (check-equal? (raster-buffer-row-bytes copy) 20)
         (check-equal? (subbytes (raster-buffer->storage-bytes copy) 8 20) (make-bytes 12)))))
   (test-case "color-space reference survives source wrapper"
     (define cs (make-linear-srgb-color-space))
     (with-skia ([b (make-raster-buffer 2 2 #:color-space cs)])
       (skia-close! cs)
       (with-skia ([im (raster-buffer->image b)] [tag (image-color-space im)])
         (check-true (color-space-linear-gamma? tag)))))
   (test-case "nearest pixmap scaling between separate buffers"
     (with-skia ([src (make-raster-buffer 1 1)] [dst (make-raster-buffer 3 2 #:row-bytes 20)])
       (fill! src 'red)
       (call-with-raster-buffer-pixmap src
         (lambda (s) (call-with-raster-buffer-pixmap dst (lambda (d) (pixmap-scale! d s #:sampling 'nearest)) #:writable? #t)))
       (check-equal? (pixel dst 2 1) (rgb 255 0 0))))
   (test-case "scaling rejects shared allocation aliases"
     (with-skia ([b (make-raster-buffer 4 2)])
       (call-with-raster-buffer-pixmap b
         (lambda (v) (check-exn exn:fail? (lambda () (pixmap-scale! (pixmap-subset v 2 0 2 2) (pixmap-subset v 0 0 2 2))))) #:writable? #t)))
   (test-case "closed buffers reject read copy snapshot and borrow"
     (define b (make-raster-buffer 2 2)) (skia-close! b)
     (for ([op (list raster-buffer-width raster-buffer->storage-bytes raster-buffer-copy raster-buffer->image
                     (lambda (v) (call-with-raster-buffer-canvas v void)))])
       (check-exn exn:fail? (lambda () (op b)))))
   (test-case "image snapshots integrate with strict SVG output groups"
     (with-skia ([b (make-raster-buffer 2 2)])
       (fill! b 'red)
       (with-skia ([im (raster-buffer->image b)])
         (define report #f)
         (define page (make-output-page 30 20
                        (lambda (c) (set! report (draw-output-group c 0 0 30 20
                          (lambda (local) (draw-image-rect local im 0 0 30 20))))) #:background 'white))
         (define-values (svg audit) (output->bytes/audit page 'svg #:policy 'error))
         (check-eq? (output-group-report-strategy report) 'native)
         (check-false (output-audit-report-blocking? audit))
         (check-true (regexp-match? #rx#"data:image/png" svg)))))
   (test-case "snapshot retained through picture replay"
     (define b (make-raster-buffer 2 2)) (fill! b 'red)
     (define im (raster-buffer->image b))
     (with-skia ([pic (call-with-picture 2 2 (lambda (c) (draw-image c im 0 0)))])
       (skia-close! im) (skia-close! b)
       (with-skia ([s (make-surface 2 2)])
         (draw-picture (surface-canvas s) pic)
         (check-equal? (surface-pixel s 1 1) (rgb 255 0 0)))))))
