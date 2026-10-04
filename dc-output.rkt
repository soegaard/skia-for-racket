#lang racket/base
;; Opt-in bridge. Do not add this module to main.rkt: native DC metrics already
;; depend on main.rkt, and neither the CPU nor GPU entry point should change.
(require racket/class racket/list
         (prefix-in rd: racket/draw) (prefix-in sk: "main.rkt")
         "dc.rkt" "output.rkt" "private/dc-output-capture.rkt" "private/dc-output-native.rkt"
         "private/dc-support.rkt" "private/annotation-util.rkt"
         (submod "private/dc-class.rkt" canvas)
         (only-in "private/dc-region-adapter.rkt" dc-region-query-info)
         (only-in "private/check.rkt" check-dimensions)
         (only-in "private/output-util.rkt" raster-output-scale))
(provide make-dc-output-page call-with-output-dc skia-output-dc? output-dc-capabilities
         current-output-dc-command-limit draw-dc-raster-group
         dc-annotate-url! dc-define-destination! dc-link-destination!)
(define vector-only? (make-parameter #f))
(define in-explicit-raster? (make-parameter #f))
(define (check-policy policy)
  (unless (memq policy '(prefer-vector require-vector))
    (raise-argument-error 'dc-output "'prefer-vector or 'require-vector" policy)))
(define (call-with-output-dc c width height draw
                             #:policy [policy 'prefer-vector]
                             #:background [background "white"]
                             #:smoothing [smoothing 'smoothed]
                             #:text-mode [mode (sk:current-text-output-mode)]
                             #:raster-scale [scale (sk:current-raster-output-scale)])
  (define-values (w h) (output-dc-size 'call-with-output-dc width height))
  (check-policy policy)
  (output-dc-procedure! 'call-with-output-dc draw 1)
  (unless (memq mode '(native outline))
    (raise-argument-error 'call-with-output-dc "'native or 'outline" mode))
  (raster-output-scale 'call-with-output-dc scale)
  ;; Validate the receiver before invoking application code. GPU output remains
  ;; the job of gpu-dc/render-canvas; this bridge never reads a GPU target.
  (define backend (sk:canvas-execution-backend c))
  (unless (memq backend '(pdf svg raster))
    (raise-arguments-error 'call-with-output-dc "requires a live PDF, SVG or CPU raster canvas"
                           "backend" backend))
  (unless (sk:matrix4-affine-2d? (sk:canvas-matrix4 c))
    (error 'call-with-output-dc "receiver must have an affine 2D transform"))
  (when (and (eq? backend 'raster) (eq? policy 'require-vector))
    (error 'call-with-output-dc "require-vector requires a document receiver"))
  (parameterize ([sk:current-text-output-mode mode]
                 [sk:current-raster-output-scale scale]
                 [vector-only? (eq? policy 'require-vector)])
    (define-values (commands count)
      (capture-output-dc w h draw #:background background #:smoothing smoothing))
    ;; The DC is closed now, including selection locks. Callback errors and
    ;; escapes never reach replay. A replay/native failure aborts normal byte
    ;; exporters; this is not rollback for a manually managed live document.
    (define groups (replay-output-dc c w h commands policy scale))
    (hasheq 'schema 1 'stage "0.63" 'backend (symbol->string backend)
            'command_count count 'logical_width w 'logical_height h
            'text_mode (symbol->string mode) 'policy (symbol->string policy)
            'dc_expired #t 'groups groups
            'native_groups (count-groups groups "native")
            'raster_groups (count-groups groups "raster"))))
(define (count-groups groups strategy)
  (count (lambda (g) (equal? (hash-ref g 'strategy) strategy)) groups))

(define (make-dc-output-page width height draw
                             #:unit [unit 'pt] #:margins [margins 0]
                             #:background [background #f]
                             #:smoothing [smoothing 'smoothed]
                             #:policy [policy 'prefer-vector]
                             #:on-report [on-report void])
  (output-dc-procedure! 'make-dc-output-page draw 1)
  (output-dc-procedure! 'make-dc-output-page on-report 1)
  (check-policy policy)
  (unless (memq smoothing '(unsmoothed smoothed aligned))
    (raise-argument-error 'make-dc-output-page "valid DC smoothing mode" smoothing))
  ;; Use the existing page constructor for all physical units, margins, page
  ;; backgrounds and document-size validation. The DC is content-box local.
  (define descriptor (make-output-page width height void #:unit unit #:margins margins
                                       #:background background #:clip? #t))
  (define-values (cw ch) (output-page-content-size descriptor))
  (output-dc-size 'make-dc-output-page cw ch)
  (make-output-page width height
    (lambda (c)
      (on-report (call-with-output-dc c cw ch draw #:smoothing smoothing #:policy policy)))
    #:unit unit #:margins margins #:background background #:clip? #t))

(define (live-dc! who dc)
  (unless (is-a? dc rd:dc<%>) (raise-argument-error who "dc<%> object" dc))
  (send dc get-size)
  (void))
(define (annotation! who dc kind args)
  (live-dc! who dc)
  (when (in-explicit-raster?)
    (dc-unsupported who 'annotation-inside-explicit-raster "0.63: annotate the receiving document instead"))
  ;; Raster/GPU authoring uses the same helpers as documents; annotations are
  ;; invisible no-ops there, not a reason for a CPU/GPU transfer.
  (when (skia-output-dc? dc) (output-dc-special! dc kind args))
  (void))
(define (annotation-rectangle who x y w h)
  (list (dc-real who x) (dc-real who y) (dc-extent who w) (dc-extent who h)))
(define (dc-annotate-url! dc x y width height uri)
  (annotation! 'dc-annotate-url! dc 'url
    (append (annotation-rectangle 'dc-annotate-url! x y width height)
            (list (annotation-uri 'dc-annotate-url! uri)))))
(define (dc-define-destination! dc name x y)
  (annotation! 'dc-define-destination! dc 'destination
    (list (annotation-name 'dc-define-destination! name)
          (dc-real 'dc-define-destination! x) (dc-real 'dc-define-destination! y))))
(define (dc-link-destination! dc x y width height name)
  (annotation! 'dc-link-destination! dc 'link
    (append (annotation-rectangle 'dc-link-destination! x y width height)
            (list (annotation-name 'dc-link-destination! name)))))

(define (draw-dc-raster-group dc x y width height draw
                              #:scale [scale (sk:current-raster-output-scale)]
                              #:label [label "dc-explicit-raster"])
  (define who 'draw-dc-raster-group)
  (live-dc! who dc)
  (define fx (dc-real who x)) (define fy (dc-real who y))
  (define-values (w h) (output-dc-size who width height))
  (output-dc-procedure! who draw 1)
  (raster-output-scale who scale)
  (unless (string? label) (raise-argument-error who "string?" label))
  (when (and (skia-output-dc? dc) (vector-only?))
    (dc-unsupported who 'explicit-raster-under-require-vector "0.63"))
  (define pw (inexact->exact (ceiling (* w scale))))
  (define ph (inexact->exact (ceiling (* h scale))))
  (check-dimensions who pw ph)
  ;; Account for the child surface, copied RGBA and optional bitmap bridge.
  (when (> (* 12 pw ph) (sk:current-skia-byte-limit))
    (error who "raster group working buffers exceed current-skia-byte-limit"))
  (define local-raster-dc%
    (class skia-dc%
      (super-new)
      (define/override (get-size) (super get-size) (values w h))
      ;; The group's logical map is an ordinary initial matrix, not a second
      ;; backing scale. Keep region query extents in that same local space.
      (define/override (dc-region-query-info)
        (define-values (_w _h matrix clip) (super dc-region-query-info))
        (values w h matrix clip))))
  (define child #f)
  (define entered? #f)
  (define pixels
    (call-with-continuation-barrier
     (lambda ()
       (dynamic-wind
        (lambda ()
          (when entered? (error who "raster group cannot be reentered"))
          (set! entered? #t))
        (lambda ()
          (set! child (new local-raster-dc% [width pw] [height ph] [smoothing 'smoothed]
                              [background (make-object rd:color% 0 0 0 0.0)]))
          (send child set-initial-matrix (vector (/ pw w) 0 0 (/ ph h) 0 0))
          (parameterize ([in-explicit-raster? #t])
            (call-with-dc-canvas-paint child
              (lambda () (call-with-values (lambda () (draw child)) (lambda ignored (void))))))
          (bytes->immutable-bytes (send child get-rgba-bytes #:premultiplied? #t)))
        (lambda () (parameterize-break #f (when child (send child close))))))))
  (cond
    [(skia-output-dc? dc)
     (output-dc-special! dc 'raster
       (list fx fy w h pw ph pixels (string->immutable-string label) scale))]
    [else
     (define bitmap (rd:make-bitmap pw ph #t))
     (define argb (make-bytes (bytes-length pixels)))
     (for ([i (in-range 0 (bytes-length pixels) 4)])
       (bytes-set! argb i (bytes-ref pixels (+ i 3)))
       (bytes-copy! argb (+ i 1) pixels i (+ i 3)))
     (send bitmap set-argb-pixels 0 0 pw ph argb #f #t #:unscaled? #t)
     (define previous (send dc get-transformation))
     (dynamic-wind void
       (lambda ()
         (send dc transform (vector (/ w pw) 0 0 (/ h ph) fx fy))
         (unless (send dc draw-bitmap bitmap 0 0) (error who "bitmap insertion failed")))
       (lambda () (send dc set-transformation previous)))])
  (void))
