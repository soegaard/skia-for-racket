#lang racket/base

;; Opt-in native CPU tests for distinctions specified by the R2 Reference.
(require rackunit racket/file racket/list skia)
(define (results thunk) (call-with-values thunk list))

(module+ test
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
  (test-case "gradient positions and radii are checked"
    (check-exn exn:fail? (lambda () (make-linear-gradient-shader 0 0 0 0 '(red blue))))
    (check-exn exn:fail?
               (lambda () (make-linear-gradient-shader 0 0 10 0 '(red blue)
                                                        #:positions '(1 0))))
    (check-exn exn:fail? (lambda () (make-radial-gradient-shader 0 0 0 '(red blue))))))
