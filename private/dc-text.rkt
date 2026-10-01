#lang racket/base
;; The native text path uses existing Skia fonts + HarfBuzz, never a hidden
;; bitmap-dc% or Pango text renderer. Every native resource is scoped to a call.
(require racket/list racket/math
         (prefix-in sk: "../main.rkt")
         (only-in (submod "core.rkt" dc-text-internals)
                  shaper-font call-with-choice-shaper fallback-choice-from-run)
         "dc-support.rkt" "dc-text-spec.rkt" "dc-native-util.rkt")
(provide dc-measure-text dc-render-text! dc-glyph-exists?)
(struct text-unit (layout x width) #:transparent)
(define (font-options f tf)
  (sk:make-font tf #:size (max 1e-6 (dc-font-spec-size f))
                #:edging (dc-font-spec-edging f)
                #:hinting (if (eq? (dc-font-spec-hinting f) 'aligned) 'normal 'none)
                #:subpixel? #t
                #:linear-metrics? (eq? (dc-font-spec-hinting f) 'unaligned)))
(define (call-with-fonts f proc)
  (sk:with-skia ([fm (sk:make-font-manager)]
                [tf (sk:typeface-from-family (dc-font-spec-family f)
                      #:weight (dc-font-spec-weight f) #:slant (dc-font-spec-slant f))]
                [font (font-options f tf)])
    (proc fm font)))
(define (call-with-text request proc)
  (define spec (dc-text-spec-font request))
  (define size (dc-font-spec-size spec))
  (define text-bytes (for/sum ([s (in-list (dc-text-spec-units request))])
                       (bytes-length (string->bytes/utf-8 s))))
  (when (> text-bytes (sk:current-skia-byte-limit))
    (error 'skia-dc-text "text exceeds current-skia-byte-limit"))
  (cond
    [(zero? size) (proc '() '#(0.0 0.0 0.0 0.0) #f #f 0.0 #f)]
    [else
     (call-with-fonts spec
       (lambda (fm font)
         (sk:with-skia ([sh (sk:make-shaper font)])
           (define metrics (sk:font-get-metrics font))
           (define ascent (max 0.0 (- (sk:font-metrics-ascent metrics))))
           (define descent (max 0.0 (sk:font-metrics-descent metrics)))
           (define leading (max 0.0 (sk:font-metrics-leading metrics)))
           (define cursor 0.0)
           (define units
             (for/list ([str (in-list (dc-text-spec-units request))])
               (define layout
                 (sk:layout-mixed-text sh fm str #:features (dc-font-spec-features spec)))
               ;; This bridge exposes no pointer. It reuses the exact existing
               ;; fallback face/weight/width/slant choice used by drawing.
               (for* ([line (in-list (sk:mixed-text-layout-lines layout))]
                      [run (in-list (sk:mixed-text-line-runs line))])
                 (call-with-choice-shaper
                  'skia-dc-text sh fm (fallback-choice-from-run run)
                  (lambda (selected)
                    (define m (sk:font-get-metrics (shaper-font selected)))
                    (set! ascent (max ascent (- (sk:font-metrics-ascent m))))
                    (set! descent (max descent (sk:font-metrics-descent m)))
                    (set! leading (max leading (sk:font-metrics-leading m))))))
               (define natural (sk:mixed-text-layout-width layout))
               (define width (if (eq? (dc-font-spec-hinting spec) 'aligned) (round natural) natural))
               (define unit (text-unit layout cursor width))
               (set! cursor (dc-real 'skia-dc-text (+ cursor width)))
               unit))
           (define height (dc-real 'skia-dc-text (+ ascent descent leading)))
           (define extent (vector cursor height descent leading))
           (proc units extent sh fm (+ leading ascent) metrics))))]))
(define (dc-measure-text _surface request)
  (if (dc-font-spec? request)
      (if (zero? (dc-font-spec-size request)) (values 0.0 0.0 0.0 0.0)
          (call-with-fonts request
            (lambda (_fm font)
              (define m (sk:font-get-metrics font))
              (define ascent (max 0.0 (- (sk:font-metrics-ascent m))))
              (define descent (max 0.0 (sk:font-metrics-descent m)))
              (define leading (max 0.0 (sk:font-metrics-leading m)))
              (values (let ([w (sk:font-metrics-average-character-width m)])
                        (if (> w 0) w (sk:measure-simple-text font "x")))
                      (+ ascent descent leading) descent leading))))
      (call-with-text request (lambda (_units extent _sh _fm _baseline _metrics)
                               (apply values (vector->list extent))))))
(define (dc-render-text! surface request matrix clip x y angle foreground background solid?)
  (call-with-text
   request
   (lambda (units extent _sh _fm baseline metrics)
     (unless (null? units)
       (define c (sk:surface-canvas surface))
       (sk:call-with-canvas-state c
         (lambda ()
           (install-clip! c clip)
           (set-matrix! c matrix)
           (sk:canvas-translate! c x y)
           (when (not (zero? angle)) (sk:canvas-rotate-radians! c (- angle)))
           (when (and solid? (zero? angle))
             (sk:with-skia ([paint (sk:make-paint #:color (native-color background))])
               (sk:draw-rect c 0 0 (vector-ref extent 0) (vector-ref extent 1) paint)))
           (sk:with-skia ([paint (sk:make-paint #:color (native-color foreground))])
             (for ([unit (in-list units)])
               (define layout (text-unit-layout unit))
               (define lines (sk:mixed-text-layout-lines layout))
               (unless (null? lines)
                 (sk:draw-mixed-text-layout
                  c layout (text-unit-x unit)
                  (- baseline (sk:mixed-text-line-baseline (car lines))) paint)))
             (when (and metrics (dc-font-spec-underlined? (dc-text-spec-font request)))
               (define thickness (max 0.5 (or (sk:font-metrics-underline-thickness metrics)
                                               (/ (dc-font-spec-size (dc-text-spec-font request)) 16))))
               (define position (or (sk:font-metrics-underline-position metrics) thickness))
               (sk:draw-rect c 0 (+ baseline position) (vector-ref extent 0) thickness paint))))))))
  (void))
(define (dc-glyph-exists? _surface spec character)
  (unless (char? character) (raise-argument-error 'glyph-exists? "char?" character))
  (call-with-fonts
   spec
   (lambda (fm font)
     (or (positive? (sk:font-char->glyph font character))
         (let ([tf (sk:font-manager-match-character fm character
                     #:family (dc-font-spec-family spec)
                     #:weight (dc-font-spec-weight spec) #:slant (dc-font-spec-slant spec))])
           (and tf
                (sk:with-skia ([face tf] [fallback (font-options spec face)])
                  (positive? (sk:font-char->glyph fallback character)))))))))
