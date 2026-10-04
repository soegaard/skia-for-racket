#lang racket/base
;; Declarative compatibility boundary; no GUI, font parsing, or native probing.
(require racket/list)
(provide skia-dc-compatibility dc-interface-arities)
;; Racket draw-lib 1.22+ dc<%>. Arity excludes the receiver. The acceptance
;; suite compares both the member set and each arity against the actual class.
(define dc-interface-arities
  '((cache-font-metrics-key 0) (clear 0) (copy 6) (draw-arc 6)
    (draw-bitmap 3 4 5 6) (draw-bitmap-section 7 8 9 10)
    (draw-ellipse 4) (draw-line 4) (draw-lines 1 2 3) (draw-path 1 2 3 4)
    (draw-point 2) (draw-polygon 1 2 3 4) (draw-rectangle 4)
    (draw-rounded-rectangle 4 5) (draw-spline 6) (draw-text 3 4 5 6)
    (end-doc 0) (end-page 0) (start-alpha 1) (end-alpha 0) (erase 0)
    (flush 0) (get-alpha 0) (get-background 0) (get-backing-scale 0)
    (get-brush 0) (get-char-height 0) (get-char-width 0) (get-clipping-region 0)
    (get-device-scale 0) (get-font 0) (get-gl-context 0) (get-initial-matrix 0)
    (get-origin 0) (get-pen 0) (get-rotation 0) (get-scale 0) (get-size 0)
    (get-smoothing 0) (get-text-background 0) (get-text-extent 1 2 3 4)
    (get-text-foreground 0) (get-text-mode 0) (get-transformation 0)
    (glyph-exists? 1) (ok? 0) (resume-flush 0) (rotate 1) (scale 2)
    (set-alignment-scale 1) (set-alpha 1) (set-background 1) (set-brush 1 2)
    (set-clipping-rect 4) (set-clipping-region 1) (set-font 1)
    (set-initial-matrix 1) (set-origin 2) (set-pen 1 3) (set-rotation 1)
    (set-scale 2) (set-smoothing 1) (set-text-background 1)
    (set-text-foreground 1) (set-text-mode 1) (set-transformation 1)
    (start-doc 1) (start-page 0) (suspend-flush 0) (transform 1)
    (translate 2) (try-color 2)))
(define noop-methods '(start-doc end-doc start-page end-page flush suspend-flush resume-flush))
(define (skia-dc-compatibility [target 'raster])
  (unless (memq target '(raster gpu pdf svg))
    (raise-argument-error 'skia-dc-compatibility "'raster, 'gpu, 'pdf, or 'svg" target))
  (define document? (and (memq target '(pdf svg)) #t))
  (define (status method)
    (cond [(memq method noop-methods) 'checked-no-op]
          [(and document? (memq method '(copy erase))) 'explicit-raster-group]
          [else 'supported-with-limits]))
  (hasheq 'schema 1 'stage "0.64" 'target target
          'scope "wrapper declarations, not execution evidence"
          'native_probe_performed #f 'full_drop_in_compatibility #f
          'dc_lifetime (if (eq? target 'raster) 'persistent 'callback-scoped)
          'methods
          (for/list ([row (in-list dc-interface-arities)])
            (hasheq 'name (car row) 'arities (cdr row) 'status (status (car row))))
          'text "single-line Skia/HarfBuzz; no universal Cairo/Pango metric or pixel identity"
          'font_descriptions "plain family or single-family Pango description; size from font%; non-normal weight/style override description"
          'font_parser "Racket-supplied Pango, parsing only; no Pango layout or drawing"
          'unsupported
          '(native-cairo-handle-brushes combined-tabs-or-hard-breaks
            pango-family-cascades pango-font-variants pango-gravity pango-variation-axes
            persistent-gpu-dc automatic-cpu-fallback)
          'document_limits
          (and document?
               '(bounded-explicit-raster-for-pixel-operations conservative-alpha-and-pattern-fallback
                 native-text-or-annotation-loss-rejected))
          'documentation "docs/DC-COMPATIBILITY.md"))
