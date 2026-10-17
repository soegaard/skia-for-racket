#lang racket/base

;;;
;;; Reference Core Test
;;;

;; Checks canvas restoration, clipping, retained paint/path/image values, path measurement, and
;; encoder options.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Opt-in native CPU tests for distinctions specified by the R2 Reference.
(require rackunit racket/file racket/list skia)

;;;
;;; Diagnostic Operations
;;;

; results : procedure? -> list?
;;   Collects multiple return values into a list for exact Reference assertions.
(define (results thunk) (call-with-values thunk list))

(module+ test
  (test-case "unsupported blend modes are rejected without changing the paint"
    (check-exn exn:fail? (lambda () (make-paint #:blend-mode 'not-a-blend-mode)))
    (with-skia ([paint (make-paint)]
                [destination (make-color-shader 'white)]
                [source (make-color-shader 'blue)])
      (check-exn exn:fail?
                 (lambda () (paint-set-blend-mode! paint 'not-a-blend-mode)))
      (check-equal? (paint-blend-mode-or-src-over paint) 'src-over)
      (check-exn exn:fail?
                 (lambda () (make-blend-shader 'not-a-blend-mode destination source)))))
  (test-case "intersection and difference operate within the existing clip"
    (with-skia ([surface (make-surface 8 6 #:background 'white)]
                [paint (make-paint #:color 'blue #:antialias? #f)])
      (define canvas (surface-canvas surface))
      (define samples
        (for/list ([operation '(intersect difference)])
          (canvas-clear! canvas 'white)
          (with-canvas-state canvas
            (canvas-clip-rect! canvas 0 0 6 6)
            (canvas-clip-rect! canvas 2 2 2 2 #:operation operation)
            (draw-paint canvas paint))
          (check-equal? (canvas-save-count canvas) 1)
          (for/list ([x '(3 1 7)])
            (equal? (surface-pixel surface x 3) (color->rgba 'blue)))))
      (check-equal? samples '((#t #f #f) (#f #t #f)))
      ;; Neither clipping scope survives its exit.
      (draw-paint canvas paint)
      (check-equal? (surface-pixel surface 7 3) (color->rgba 'blue))))
  (test-case "state restoration is not pixel rollback"
    (with-skia ([surface (make-surface 8 8)]
                [paint (make-paint #:color 'red #:antialias? #f)])
      (define canvas (surface-canvas surface))
      (check-equal? (canvas-save-count canvas) 1)
      (check-equal? (canvas-save! canvas) 1)
      (canvas-restore-to-count! canvas 1)
      (check-exn exn:fail? (lambda () (canvas-restore! canvas)))
      (check-exn exn:fail?
                 (lambda ()
                   (with-canvas-state canvas
                     (canvas-translate! canvas 2 3)
                     (draw-rect canvas 0 0 2 2 paint)
                     (error 'example "escape after drawing"))))
      (check-equal? (canvas-transform canvas) matrix-identity)
      (check-equal? (color->argb (surface-pixel surface 2 3)) #xffff0000)
      (with-canvas-state canvas
        (check-exn exn:fail? (lambda () (canvas-restore-to-count! canvas 1))))))
  (test-case "clips stay in target space and clear uses source replacement"
    (with-skia ([surface (make-surface 4 1 #:background 'white)])
      (define canvas (surface-canvas surface))
      (with-canvas-state canvas
        (canvas-translate! canvas 1 0)
        (canvas-clip-rect! canvas 0 0 1 1)
        (canvas-reset-transform! canvas)
        (canvas-clear! canvas 'transparent))
      (check-equal? (rgba-alpha (surface-pixel surface 0 0)) 255)
      (check-equal? (rgba-alpha (surface-pixel surface 1 0)) 0)
      (check-equal? (rgba-alpha (surface-pixel surface 2 0)) 255)))
  (test-case "paint copies and retained getters have independent wrappers"
    (with-skia ([shader (make-color-shader 'blue)]
                [paint (make-paint #:shader shader)]
                [copy (paint-copy paint)]
                [retained (paint-shader copy)]
                [surface (make-surface 1 1)])
      (paint-set-shader! paint #f)
      (skia-close! shader)
      (skia-close! paint)
      (check-false (skia-closed? retained))
      (draw-paint (surface-canvas surface) copy)
      (check-equal? (color->argb (surface-pixel surface 0 0)) #xff0000ff)
      (paint-reset! copy)
      (check-false (paint-shader copy))
      (check-equal? (paint-stroke-width copy) 0.0)
      (check-false (paint-antialias? copy))))
  (test-case "path snapshots, copies, fill reset, and curve bounds"
    (with-skia ([path (make-path '((move 0 0) (quad 50 100 100 0)) #:fill-rule 'even-odd)]
                [copy (path-copy path)])
      (define sequence (in-path-segments path #:mode 'raw))
      (check-equal? (results (lambda () (path-bounds path))) '(0.0 0.0 100.0 100.0))
      (check-equal? (results (lambda () (path-tight-bounds path))) '(0.0 0.0 100.0 50.0))
      (path-reset! path)
      (check-equal? (path-fill-rule path) 'winding)
      (check-equal? (path-point-count path) 0)
      (check-equal? (path-point-count copy) 3)
      (skia-close! path)
      (check-equal? (for/list ([segment sequence]) (path-segment-verb segment)) '(move quad))
      (check-exn exn:fail?
                 (lambda () (path-segments copy #:mode 'raw #:force-closed? #t)))))
  (test-case "native conic reductions and relative moves after close"
    (for ([weight '(-1 0 1 2)] [verb '(line line quad conic)])
      (with-skia ([path (make-path '((move 0 0)))])
        (path-conic-to! path 5 10 10 0 weight)
        (check-equal? (map path-segment-verb (path-segments path #:mode 'raw))
                      (list 'move verb))))
    (with-skia ([path (make-path '((move 10 20) (line 40 50) (close)))])
      (path-rmove-to! path 2 3)
      (check-equal? (results (lambda () (path-last-point path))) '(12.0 23.0))))
  (test-case "path measurement snapshots and distinct distance contracts"
    (with-skia ([path (make-path '((move 0 0) (line 10 0)))]
                [measure (make-path-measure path)])
      (path-line-to! path 100 0)
      (skia-close! path)
      (check-equal? (path-measure-length measure) 10.0)
      (check-equal? (results (lambda () (path-measure-position+tangent measure 5)))
                    '(5.0 0.0 1.0 0.0))
      (check-exn exn:fail? (lambda () (path-measure-position+tangent measure 11)))
      (define endpoint (path-measure-matrix measure 11 #:mode 'position))
      (check-equal? (results (lambda () (matrix-map-point endpoint 0 0))) '(10.0 0.0))
      (path-measure-set-path! measure #f)
      (check-equal? (path-measure-length measure) 0.0)
      (check-false (path-measure-matrix measure 0))))
  (test-case "surface snapshots and raw-image copies are independent"
    (define samples (bytes 255 0 0 255 0 0 255 255))
    (with-skia ([image (rgba-bytes->image 2 1 samples)]
                [subset (image-subset image 0 0 1 1)]
                [surface (make-surface 2 1 #:background 'red)]
                [snapshot (surface-snapshot surface)])
      (bytes-set! samples 0 0)
      (check-equal? (bytes-ref (image->rgba-bytes image) 0) 255)
      (canvas-clear! (surface-canvas surface) 'blue)
      (check-equal? (image->rgba-bytes snapshot) (bytes 255 0 0 255 255 0 0 255))
      (check-exn exn:fail? (lambda () (image-subset image 1 0 2 1)))
      (skia-close! image)
      (check-equal? (image-width image) 2)
      (check-equal? (image->rgba-bytes subset) (bytes 255 0 0 255))))
  (test-case "encoders validate selected-format options"
    (with-skia ([image (rgba-bytes->image 1 1 (bytes 255 0 0 255))])
      (define png (image->encoded-bytes image 'png #:quality 'unused))
      (check-equal? (subbytes png 0 8) #"\211PNG\r\n\32\n")
      (check-exn exn:fail? (lambda () (image->encoded-bytes image 'gif)))
      (check-exn exn:fail? (lambda () (image->png-bytes image #:compression 10)))))

  (test-case "normal iteration exposes a closing line; raw iteration exposes stored verbs"
    (with-skia ([path (make-path '((move 10 20) (line 40 20) (line 40 50) (close)))])
      (define before (path->commands path))
      (define (describe mode)
        (for/list ([segment (in-list (path-segments path #:mode mode))])
          (list (path-segment-verb segment) (path-segment-closing-line? segment))))
      (check-equal? (describe 'normal)
                    '((move #f) (line #f) (line #f) (line #t) (close #f)))
      (check-equal? (describe 'raw) '((move #f) (line #f) (line #f) (close #f)))
      (check-equal? (path->commands path) before)))
  (test-case "omitting the initial move on an extracted path changes its geometry"
    (with-skia ([path (make-path '((move 10 20) (line 90 20)))]
                [measure (make-path-measure path)]
                [moved (path-measure-segment measure 20 40)]
                [unmoved (path-measure-segment measure 20 40 #:start-with-move-to? #f)])
      (check-equal? (path->commands moved) '((move 30.0 20.0) (line 50.0 20.0)))
      (check-equal? (path->commands unmoved) '((move 0.0 0.0) (line 50.0 20.0)))))
  (test-case "native reset does not restore make-paint defaults"
    (with-skia ([paint (make-paint)])
      (define constructed (list (paint-stroke-width paint) (paint-antialias? paint)))
      (paint-reset! paint)
      (check-equal? constructed '(1.0 #t))
      (check-equal? (list (paint-stroke-width paint) (paint-antialias? paint)) '(0.0 #f))
      (check-false (skia-closed? paint))))
  (test-case "standard color spaces are independently owned and compared by description"
    (with-skia ([srgb (make-srgb-color-space)]
                [another (make-srgb-color-space)]
                [linear (make-linear-srgb-color-space)])
      (check-false (eq? srgb another))
      (check-equal?
       (list (color-space=? srgb another) (color-space=? srgb linear)
             (color-space-srgb? srgb) (color-space-srgb? linear)
             (color-space-linear-gamma? srgb) (color-space-linear-gamma? linear))
       '(#t #f #t #f #f #t))
      (skia-close! srgb)
      (check-true (color-space? srgb))
      (check-false (skia-closed? another))
      (check-true (color-space-srgb? another))
      (check-exn exn:fail? (lambda () (color-space=? srgb another)))
      (check-exn exn:fail? (lambda () (color-space-srgb? srgb)))
      (check-exn exn:fail? (lambda () (color-space-linear-gamma? srgb)))))
  (test-case "equal RGB bytes in sRGB and linear sRGB represent different colors"
    (define samples (bytes 128 128 128 255))
    (with-skia ([srgb (make-srgb-color-space)]
                [linear (make-linear-srgb-color-space)]
                [encoded (rgba-bytes->image 1 1 samples #:color-space srgb)]
                [light (rgba-bytes->image 1 1 samples #:color-space linear)]
                [surface (make-surface 2 1 #:color-space srgb)])
      (define canvas (surface-canvas surface))
      (draw-image canvas encoded 0 0)
      (draw-image canvas light 1 0)
      (define output (surface->rgba-bytes surface #:color-space srgb))
      (check-equal? (subbytes output 0 4) samples)
      (for ([i '(4 5 6)]) (check-= (bytes-ref output i) 188 1))
      (check-equal? (bytes-ref output 7) 255)
      (check-equal? (image->rgba-bytes encoded) samples)
      (check-equal? (image->rgba-bytes light) samples)))
  (test-case "dispatcher options are conditional for both bytes and file output"
    (define directory (make-temporary-file "skia-reference-encoding-~a" 'directory))
    (define filename (build-path directory "result.bin"))
    (define sentinel #"existing output survives a validation failure")
    (define (reset-file!)
      (call-with-output-file filename #:exists 'truncate/replace #:mode 'binary
        (lambda (out) (write-bytes sentinel out))))
    (define (dispatch image format file? options)
      (define entries
        (sort (if file? (cons (cons '#:exists 'replace) options) options)
              keyword<? #:key car))
      (define result
        (keyword-apply (if file? save-image image->encoded-bytes)
                       (map car entries) (map cdr entries)
                       (if file? (list image filename format) (list image format))))
      (if file?
          (begin (check-true (void? result)) (file->bytes filename))
          result))
    (define (check-format format encoded)
      (check-true (bytes? encoded))
      (case format
        [(png) (check-equal? (subbytes encoded 0 8) #"\211PNG\r\n\32\n")]
        [(jpeg) (check-equal? (subbytes encoded 0 2) #"\377\330")]
        [(webp)
         (check-equal? (subbytes encoded 0 4) #"RIFF")
         (check-equal? (subbytes encoded 8 12) #"WEBP")]))
    (define cases
      '((#:quality jpeg webp)
        (#:png-compression png)
        (#:jpeg-downsample jpeg)
        (#:jpeg-alpha jpeg)
        (#:webp-lossless? webp)))
    (dynamic-wind
      void
      (lambda ()
        (with-skia ([image (rgba-bytes->image 1 1 (bytes 50 109 230 255))])
          ;; Every format-specific keyword is tried in every format, for both dispatchers.
          (for* ([format '(png jpeg webp)] [file? '(#f #t)] [entry (in-list cases)])
            (define option (car entry))
            (define active? (memq format (cdr entry)))
            (define (call) (dispatch image format file? (list (cons option 'unused))))
            (when file? (reset-file!))
            (with-check-info (['format format] ['file-output? file?] ['keyword option])
              (if active?
                  (begin
                    (check-exn exn:fail? call)
                    (when file? (check-equal? (file->bytes filename) sentinel)))
                  (check-format format (call)))))
          ;; JPEG requires an exact integer; WebP accepts fractional quality.
          (for* ([format '(png jpeg webp)] [file? '(#f #t)])
            (define (call) (dispatch image format file? (list (cons '#:quality 87.5))))
            (when file? (reset-file!))
            (with-check-info (['format format] ['file-output? file?])
              (if (eq? format 'jpeg)
                  (begin
                    (check-exn exn:fail? call)
                    (when file? (check-equal? (file->bytes filename) sentinel)))
                  (check-format format (call)))))
          ;; Color-management arguments are common, not ignored in any of these formats.
          (for* ([format '(png jpeg webp)] [file? '(#f #t)]
                 [option '(#:color-space #:icc-profile #:icc-description)])
            (when file? (reset-file!))
            (with-check-info (['format format] ['file-output? file?] ['keyword option])
              (check-exn exn:fail?
                         (lambda ()
                           (dispatch image format file? (list (cons option 'unused)))))
              (when file? (check-equal? (file->bytes filename) sentinel))))
          ;; Valid active settings still reach all three encoders.
          (for* ([format '(png jpeg webp)] [file? '(#f #t)])
            (define options
              (case format
                [(png) (list (cons '#:png-compression 0))]
                [(jpeg) (list (cons '#:quality 87) (cons '#:jpeg-downsample 'yuv-444)
                              (cons '#:jpeg-alpha 'blend-on-black))]
                [(webp) (list (cons '#:quality 87.5) (cons '#:webp-lossless? #t))]))
            (check-format format (dispatch image format file? options)))))
      (lambda () (delete-directory/files directory))))

  (test-case "gradient positions and radii are checked"
    (check-exn exn:fail? (lambda () (make-linear-gradient-shader 0 0 0 0 '(red blue))))
    (check-exn exn:fail?
               (lambda () (make-linear-gradient-shader 0 0 10 0 '(red blue)
                                                        #:positions '(1 0))))
    (check-exn exn:fail? (lambda () (make-radial-gradient-shader 0 0 0 '(red blue))))))
