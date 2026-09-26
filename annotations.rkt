#lang racket/base
(require "private/core.rkt" "private/native.rkt" "private/types.rkt"
         "private/check.rkt" "private/annotation-util.rkt"
         "matrix.rkt" "private/path-matrix.rkt"
         (submod "private/core.rkt" annotation-internals))
(provide canvas-annotation-backend canvas-annotate-url!
         canvas-define-destination! canvas-link-destination!
         destination-id svg-destination-id)

(define (destination-id name)
  (annotation-name->id 'destination-id name))
(define (svg-destination-id name #:id-prefix [prefix "skia"])
  (annotation-svg-id 'svg-destination-id name prefix))

;; Only called while call-on-canvas holds a live owning resource. PDF scopes
;; span all pages; SVG has one viewport. Canvas aliases use the same scope.
(define (annotation-target who c)
  (define owner (canvas-owner who c))
  (cond [(pdf-page? owner) (values 'pdf (pdf-page-document owner))]
        [(svg-document? owner) (values 'svg owner)]
        [(surface? owner) (values 'raster owner)]
        [(picture-recorder? owner) (values 'recording owner)]
        [else (error who "unsupported annotation canvas")]))

(define (canvas-annotation-backend c)
  (call-on-canvas
   'canvas-annotation-backend c '()
   (lambda (_cp)
     (define-values (kind scope) (annotation-target 'canvas-annotation-backend c))
     kind)))

(define (call-with-annotation-data who bs proc)
  ;; Include the NUL byte in SkData's size: both native document writers expect
  ;; that terminator. Copy into native storage before calling or recording.
  (call-with-native-temporary
   who 'annotation-data
   (lambda () (sk_data_new_with_copy bs (bytes-length bs))) sk_data_unref proc))

(define (canvas-annotate-url! c x y width height uri)
  (define who 'canvas-annotate-url!)
  (define rr (rect who x y width height))
  (define bs (annotation-c-string who (annotation-uri who uri)))
  (call-on-canvas
   who c '()
   (lambda (cp)
     (define-values (kind scope) (annotation-target who c))
     ;; Raster annotations are deliberately invisible no-ops. Recorded URL
     ;; annotations are native display-list commands, replayed by PDF and SVG.
     (unless (or (eq? kind 'raster) (zero? width) (zero? height))
       (call-with-annotation-data who bs
         (lambda (dp) (sk_canvas_draw_url_annotation cp rr dp))))))
  (void))

(define (canvas-define-destination! c name x y)
  (define who 'canvas-define-destination!)
  (define checked (annotation-name who name))
  (define id (annotation-name->id who checked))
  (define fx (scalar who x))
  (define fy (scalar who y))
  (define bs (annotation-c-string who id))
  (call-on-canvas
   who c '()
   (lambda (cp)
     (define-values (kind scope) (annotation-target who c))
     (case kind
       [(recording)
        (raise-arguments-error who
                               "named destinations require a live PDF/SVG canvas; define after picture replay"
                               "name" checked)]
       [(pdf)
        (call-with-annotation-data
         who bs
         (lambda (dp)
           ;; Reserve the name before emission so duplicates cannot reach Skia.
           (annotation-define! who scope checked fx fy)
           (sk_canvas_draw_named_destination_annotation cp (make-sk-point fx fy) dp)))]
       [(svg)
        ;; Native SkSVGDevice does not implement Define_Named_Dest. Capture the
        ;; affine point now, then insert a predefined view during finalization.
        (define-values (px py) (matrix-map-point (canvas-transform c) fx fy))
        (annotation-define! who scope checked px py)]
       [else (void)])))
  (void))

(define (canvas-link-destination! c x y width height name)
  (define who 'canvas-link-destination!)
  (define rr (rect who x y width height))
  (define checked (annotation-name who name))
  (define id (annotation-name->id who checked))
  (call-on-canvas
   who c '()
   (lambda (cp)
     (define-values (kind scope) (annotation-target who c))
     (case kind
       [(recording)
        (raise-arguments-error who
                               "named links require a live PDF/SVG canvas; add after picture replay"
                               "name" checked)]
       [(pdf svg)
        (define target
          (if (eq? kind 'svg) (string-append "urn:racket-skia:destination:" id) id))
        (define bs (annotation-c-string who target))
        ;; Even a zero-sized or fully clipped reference is checked at finish;
        ;; misspelled names are not silently accepted based on graphics state.
        (call-with-annotation-data
         who bs
         (lambda (dp)
           (annotation-reference! who scope checked)
           (unless (or (zero? width) (zero? height))
             (sk_canvas_draw_link_destination_annotation cp rr dp))))]
       [else (void)])))
  (void))
