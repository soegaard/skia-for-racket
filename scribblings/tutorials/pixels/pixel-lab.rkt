#lang racket

(require skia)
(provide pixel-width pixel-height padded-row-bytes
         make-source-buffer make-tiny-buffer duotone-rgba process-buffer! stamp-region!
         make-study-images draw-checker draw-pixel-study)

(define pixel-width 192)
(define pixel-height 128)
(define padded-row-bytes 800) ; 768 active RGBA bytes, followed by 32 padding bytes.

(define (make-source-buffer)
  (define buffer
    (make-raster-buffer pixel-width pixel-height #:row-bytes padded-row-bytes))
  (call-with-raster-buffer-canvas
   buffer
   (lambda (canvas)
     (define gradient
       (make-linear-gradient-shader 0 0 pixel-width 0 '("#126BAA" "#EC5B81" "#FFD07B")))
     (define paint (make-paint #:shader gradient))
     (define white (make-paint #:color 'white))
     (define dark (make-paint #:color "#243653"))
     (define translucent (make-paint #:color (rgba 255 150 50 128)))
     (draw-rect canvas 0 0 pixel-width 92 paint)
     (draw-circle canvas 46 45 27 white)
     (draw-rounded-rect canvas 100 20 65 50 8 8 dark)
     ;; The strip has real transparency, not a checkerboard baked into its pixels.
     (draw-rect canvas 0 102 pixel-width 26 translucent)))
  buffer)

(define (make-tiny-buffer)
  (define buffer (make-raster-buffer 3 2 #:row-bytes 16))
  ;; The input has tight 12-byte rows; the destination has padded 16-byte rows.
  (raster-buffer-write-rgba!
   buffer (bytes 255 0 0 255  0 255 0 255  0 0 255 255
                 255 255 0 255  0 255 255 255  255 0 255 255)
   #:row-bytes 12)
  buffer)

(define (duotone-rgba source)
  (unless (and (bytes? source) (zero? (remainder (bytes-length source) 4)))
    (raise-argument-error 'duotone-rgba "RGBA byte string with length divisible by four" source))
  (define result (bytes-copy source))
  (define dark '(20 43 76))
  (define light '(245 182 74))
  (for ([i (in-range 0 (bytes-length source) 4)])
    ;; An artistic score in encoded channel space, not linear-light luminance.
    (define amount (/ (+ (bytes-ref source i)
                         (bytes-ref source (+ i 1))
                         (bytes-ref source (+ i 2))) 765))
    (for ([low (in-list dark)] [high (in-list light)] [channel (in-range 3)])
      (bytes-set! result (+ i channel) (exact-round (+ low (* amount (- high low)))))))
  ;; The fourth byte of every pixel is unchanged.
  result)

(define (process-buffer! buffer)
  (define copied-pixels (raster-buffer->rgba-bytes buffer))
  (define transformed-pixels (duotone-rgba copied-pixels))
  (raster-buffer-write-rgba! buffer transformed-pixels))

(define (stamp-region! buffer)
  (call-with-raster-buffer-pixmap
   buffer
   (lambda (view)
     (define patch (pixmap-subset view 145 100 32 20))
     (pixmap-fill! patch (rgba 56 201 189 255)))
   #:writable? #t))

(define (make-study-images)
  (define buffer (make-source-buffer))
  (define original (raster-buffer->image buffer))
  (process-buffer! buffer)
  (define processed (raster-buffer->image buffer))
  (stamp-region! buffer)
  (define stamped (raster-buffer->image buffer))
  (list original processed stamped))

(define (draw-checker canvas x y width height)
  (define light (make-paint #:color "#EDF0F5"))
  (define dark (make-paint #:color "#CED5DF"))
  (with-canvas-state canvas
    (canvas-clip-rect! canvas x y width height)
    (for* ([row (in-range (ceiling (/ height 12)))]
           [column (in-range (ceiling (/ width 12)))])
      (draw-rect canvas (+ x (* column 12)) (+ y (* row 12)) 12 12
                 (if (even? (+ row column)) light dark)))))

(define (draw-pixel-study canvas images)
  (define title-font (make-font #:size 28))
  (define font (make-font #:size 14))
  (define ink (make-paint #:color "#203653"))
  (canvas-clear! canvas "#F7F8FA")
  (draw-simple-text canvas "TWO INKS, ONE PIXEL BUFFER" 28 46 title-font ink)
  (draw-simple-text canvas "Copy samples. Transform them. Publish independent images."
                    30 76 font ink)
  (for ([image (in-list images)] [x '(28 276 524)]
        [caption '("Original snapshot" "Duotone snapshot" "After region write")])
    (draw-checker canvas x 106 225 150)
    (draw-image-rect canvas image x 106 225 150 #:sampling 'nearest)
    (draw-simple-text canvas caption x 284 font ink))
  (draw-simple-text canvas "The checkerboard is behind the images; alpha remains in their pixels."
                    30 329 font ink))

(module+ main
  (define images (make-study-images))
  (define surface (make-surface 780 360))
  (draw-pixel-study (surface-canvas surface) images)
  (save-png surface "pixel-study.png" #:exists 'replace)
  (save-image (second images) "duotone.png" 'png #:exists 'replace))
