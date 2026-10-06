#lang racket/base
(require racket/list "../main.rkt")
(provide operation-scenes operation-blue operation-width operation-height
         make-operation-source make-operation-float-source make-operation-filter
         operation-filter-subset operation-filter-clip
         make-operation-scene-image operation-pixel operation-check-pixels)
(define operation-scenes '(offset clip blur shadow scale raw))
(define operation-blue (rgb 32 96 192))
(define operation-width 96) (define operation-height 64)
(define (make-operation-source)
  (with-skia ([b (make-raster-buffer 16 12)])
    (call-with-raster-buffer-pixmap b (lambda (v) (pixmap-fill! v operation-blue)) #:writable? #t)
    (raster-buffer->image b)))
(define (make-operation-float-source [space #f])
  (with-skia ([b (make-raster-buffer-from-info
                  (make-image-info 4 3 #:color-type 'rgba-f32 #:color-space space))])
    (call-with-raster-buffer-pixmap b
      (lambda (v)
        (for* ([y (in-range 3)] [x (in-range 4)])
          (pixmap-set-sample! v x y '#(0.5009765625 0.25 0.75 1.0)))) #:writable? #t)
    (raster-buffer->image b)))
(define (make-operation-filter scene)
  (case scene
    [(offset clip) (make-offset-image-filter 7 5)]
    [(blur) (make-blur-image-filter 2 2)]
    [(shadow) (make-drop-shadow-image-filter 8 6 2 2 (rgb 0 0 0))]
    [else (raise-argument-error 'make-operation-filter "offset, clip, blur or shadow" scene)]))
(define (operation-filter-subset scene) (and (eq? scene 'clip) '#(4 3 8 6)))
(define (operation-filter-clip scene)
  (case scene [(clip) '#(12 9 5 3)] [(blur) '#(-8 -8 32 28)] [else '#(-8 -8 48 40)]))

;; Return an independently owned, tightly cropped image, its world placement,
;; detached filter metadata, and optional raw F32 evidence before conversion.
(define (make-operation-scene-image scene)
  (case scene
    [(offset clip blur shadow)
     (with-skia ([source (make-operation-source)] [filter (make-operation-filter scene)])
       (define-values (out subset offset)
         (image-apply-filter source filter #:subset (operation-filter-subset scene)
                             #:clip (operation-filter-clip scene)))
       (with-skia ([result out])
         (values (apply image-subset result (vector->list subset)) offset
                 (hasheq 'backing_dimensions (list (image-width result) (image-height result))
                         'valid_subset (vector->list subset) 'offset (vector->list offset)
                         'clip (vector->list (operation-filter-clip scene))) #f)))]
    [(scale)
     (with-skia ([source (make-operation-float-source)]
                 [scaled (image->raster-buffer source
                           #:info (make-image-info 16 12 #:color-type 'rgba-f32) #:sampling 'nearest)]
                 [bytes (raster-buffer-convert scaled (make-image-info 16 12))])
       (values (raster-buffer->image bytes) '#(0 0)
               (hasheq 'conversion "explicit-f32-to-rgba8888" 'source_dimensions '(4 3))
               (raster-buffer->storage-bytes scaled)))]
    [(raw)
     (with-skia ([source (make-operation-source)] [shader (make-raw-image-shader source)]
                 [paint (make-paint #:shader shader #:antialias? #f)] [surface (make-surface 16 12)])
       (draw-rect (surface-canvas surface) 0 0 16 12 paint)
       (values (surface-snapshot surface) '#(0 0)
               (hasheq 'conversion "explicit-raw-shader-rasterization") #f))]
    [else (raise-argument-error 'make-operation-scene-image "symbol in operation-scenes" scene)]))
(define (operation-pixel data x y [width operation-width])
  (define at (* 4 (+ x (* width y))))
  (bytes->list (subbytes data at (+ at 4))))
(define (operation-check-pixels scene data)
  (unless (= (bytes-length data) (* 4 operation-width operation-height))
    (error 'image-operation-fixture "wrong capture dimensions"))
  (define (near x y expected [tolerance 3])
    (unless (for/and ([a (in-list (operation-pixel data x y))] [b (in-list expected)])
              (<= (abs (- a b)) tolerance))
      (error 'image-operation-fixture "~a: incorrect semantic pixel at ~a,~a" scene x y)))
  (near 4 4 '(0 255 0 255)) (near 90 58 '(255 255 255 255))
  (case scene
    [(offset) (near 36 30 '(32 96 192 255)) (near 25 21 '(255 255 255 255))]
    [(clip) (near 38 30 '(32 96 192 255)) (near 34 30 '(255 255 255 255))]
    [(scale) (near 32 26 '(128 64 191 255))]
    [(raw) (near 32 26 '(32 96 192 255))]
    [(blur)
     (near 32 26 '(32 96 192 255) 15)
     (unless (< (car (operation-pixel data 22 26)) 250)
       (error 'image-operation-fixture "blur halo was lost"))]
    [(shadow)
     (near 32 26 '(32 96 192 255))
     (define c (operation-pixel data 44 34))
     (unless (and (< (car c) 110) (< (cadr c) 110) (< (caddr c) 110))
       (error 'image-operation-fixture "offset shadow was lost"))])
  (void))
