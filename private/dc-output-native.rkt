#lang racket/base
;; Replay private immutable DC requests through the *same* native drawing
;; operations used by CPU/GPU. Each output group captures in local coordinates;
;; placement on its receiver preserves the receiver's units, margins and CTM.
(require racket/list
         (prefix-in sk: "../main.rkt") "../output-groups.rkt" "../annotations.rkt"
         "dc-output-capture.rkt" "dc-support.rkt" "dc-native-util.rkt"
         (submod "dc-render.rkt" canvas-internals)
         (submod "dc-text.rkt" canvas-internals))
(provide replay-output-dc)
(define (concat-dc-matrix! c m)
  (sk:canvas-concat-matrix3! c
    (sk:make-matrix3 (vector-ref m 0) (vector-ref m 2) (vector-ref m 4)
                     (vector-ref m 1) (vector-ref m 3) (vector-ref m 5) 0 0 1)))
(define (relative-state c matrix clip thunk)
  (sk:call-with-canvas-state c
    (lambda ()
      ;; Clip paths are in the DC's logical device coordinates. Unlike the
      ;; native renderer's recorder-local install-clip!, do not reset the CTM.
      (when clip
        (if (null? (dc-clip-paths clip))
            (sk:canvas-clip-rect! c 0 0 0 0)
            (for ([p (in-list (dc-clip-paths clip))])
              (call-with-path (dc-clip-path-commands p) (dc-clip-path-rule p)
                (lambda (path) (sk:canvas-clip-path! c path #:antialias? #f))))))
      (concat-dc-matrix! c matrix)
      (thunk))))
(define (replay-output-dc c width height commands policy scale)
  (define reports '())
  (define (retain! report)
    (set! reports (cons (output-group-report->jsexpr report) reports)))
  (define (group destination label thunk [choice policy])
    (retain! (draw-output-group destination 0 0 width height thunk
                #:policy choice #:scale scale #:label label)))
  (define (replay destination ops)
    (for ([op (in-list ops)])
      (define args (output-dc-command-arguments op))
      (case (output-dc-command-kind op)
        [(url destination link)
         (define payload (car args))
         (relative-state destination (cadr args) (caddr args)
           (lambda ()
             (apply (case (output-dc-command-kind op)
                      [(url) canvas-annotate-url!]
                      [(destination) canvas-define-destination!]
                      [else canvas-link-destination!]) destination payload)))]
        [(raster)
         (define payload (car args))
         ;; Payload: x y logical-width logical-height pixel-width pixel-height
         ;; premultiplied RGBA, label. User authoring already ran once in an
         ;; isolated CPU DC; it is never retried during output inspection.
         (when (eq? policy 'require-vector)
           (dc-unsupported 'draw-dc-raster-group 'explicit-raster-under-require-vector "0.63"))
         (relative-state destination (cadr args) (caddr args)
           (lambda ()
             (define x (list-ref payload 0)) (define y (list-ref payload 1))
             (define w (list-ref payload 2)) (define h (list-ref payload 3))
             (define pw (list-ref payload 4)) (define ph (list-ref payload 5))
             (sk:with-skia ([image (sk:rgba-bytes->image pw ph (list-ref payload 6) #:premultiplied? #t)]
                           [paint (sk:make-paint #:color (native-color (vector 255 255 255 (cadddr args))))])
               (retain! (draw-output-group destination x y w h
                          (lambda (rc) (sk:draw-image-rect rc image 0 0 w h #:paint paint))
                          #:policy 'raster #:scale (list-ref payload 8) #:label (list-ref payload 7))))))]
        [(alpha)
         (group destination "dc-alpha"
           (lambda (rc)
             (install-clip! rc (cadr args))
             (sk:with-skia ([paint (sk:make-paint #:color (native-color (vector 255 255 255 (caddr args))))])
               (sk:call-with-canvas-layer rc
                 (lambda () (replay rc (car args)))
                 #:bounds (vector 0 0 width height) #:paint paint))))]
        [else
         ;; A primitive's fallback can never capture preceding/following text
         ;; or geometry. Alpha fallback similarly covers only its child group.
         (group destination (format "dc-~a" (output-dc-command-kind op))
           (lambda (rc)
             (case (output-dc-command-kind op)
               [(path) (apply draw-on-canvas! rc args)]
               [(clear)
                (install-clip! rc (car args))
                (sk:with-skia ([paint (sk:make-paint #:color (native-color (cadr args)) #:antialias? #f)])
                  ;; A finite DC clear is geometry, not a recorded unbounded
                  ;; color fill that would force SVG rasterization.
                  (sk:draw-rect rc 0 0 width height paint))]
               [(bitmap) (apply bitmap-on-canvas! rc args)]
               [(text) (apply dc-render-text-on-canvas! rc args)]
               [else (error 'replay-output-dc "unknown private command")])))])))
  (replay c commands)
  (reverse reports))
