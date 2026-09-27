#lang racket/base
(require racket/file racket/path racket/list racket/string json "../main.rkt")
(define blue (rgb 50 100 220))
(define teal (rgb 14 149 142))
(define orange (rgb 240 160 32))
(define ink (rgb 32 52 78))
(define names '("stride" "canvas" "snapshots"))
(define titles '("Rows have a stride; views have a lifetime"
                 "One allocation, two ways to change pixels"
                 "Snapshots are independent of mutable storage"))
(define subtitles '("Explicit row bytes, strict integer subsets, and checked temporary access."
                     "The canvas borrows native pixels directly; pixmap edits use the same allocation."
                     "Every image shown here remains valid after its source buffer has been closed."))
(define notes
  '(("160 x 96 RGBA pixels use 704 bytes per row: 640 active bytes plus 64 bytes of padding."
     "The writable 80 x 48 subset keeps the parent stride. It is not a packed copy."
     "Returning ends the view's lifetime; a later borrow does not revive the old view.")
    ("Each canvas scope starts with a fresh matrix and clip, without clearing existing pixels."
     "Canvas access and pixmap access are exclusive. Closing an actively borrowed buffer is rejected."
     "Cleanup retires the canvas even on an escape or exception. Pixel changes are not rolled back.")
    ("Left: a copied image from the original card. Right: the modified buffer, scaled into new storage."
     "The original snapshot is not a live view. Picture replay can retain it without retaining mutable pixels."
     "These are source images, not vector art. No additional panel-sized fallback is introduced.")))
(define current-decisions (make-parameter #f))
(define (rgba-list c) (define v (color->rgba c)) (list (rgba-red v) (rgba-green v) (rgba-blue v) (rgba-alpha v)))
(define (write-json-file path data)
  (call-with-output-file path (lambda (out) (write-json data out) (newline out)) #:exists 'replace))
(define (rejects? thunk) (with-handlers ([exn:fail? (lambda (_) #t)]) (thunk) #f))
(define (raw-pixel bs w x y) (bytes->list (subbytes bs (* 4 (+ x (* w y))) (* 4 (+ 1 x (* w y))))))
(define (buffer-pixel b x y)
  (call-with-raster-buffer-pixmap b (lambda (v) (rgba-list (pixmap-pixel v x y)))))
(define (padding-zero? b)
  (define bs (raster-buffer->storage-bytes b))
  (define rb (raster-buffer-row-bytes b)) (define active (* 4 (raster-buffer-width b)))
  (for/and ([y (in-range (raster-buffer-height b))])
    (equal? (subbytes bs (+ (* y rb) active) (* (add1 y) rb)) (make-bytes (- rb active)))))
(define (stripe-bytes)
  (define bs (make-bytes (* 160 96 4)))
  (for* ([y (in-range 96)] [x (in-range 160)])
    (define c (list-ref (list blue teal orange (rgb 100 70 170)) (quotient x 40)))
    (define off (* 4 (+ x (* y 160))))
    (for ([value (in-list (append (take (rgba-list c) 3) (list (if (< y 64) 255 128))))]
          [i (in-naturals)]) (bytes-set! bs (+ off i) value)))
  bs)
(define (card c color)
  (with-skia ([p (make-paint #:color color)] [q (make-paint #:color orange)]
              [lines (make-paint #:color 'white #:stroke-width 3)])
    (draw-rounded-rect c 4 4 152 88 12 12 p)
    (draw-circle c 40 48 23 q)
    (for ([y '(32 48 64)]) (draw-line c 82 y 142 y lines))))
(define (make-assets)
  (define trace (make-hasheq))
  (define first
    (with-skia ([b (make-raster-buffer 160 96 #:row-bytes 704)])
      (define input (stripe-bytes))
      (raster-buffer-write-rgba! b input)
      (bytes-fill! input 0)
      (define before (raster-buffer->image b))
      (define expired #f) (define subset-stride #f) (define read-only? #f)
      (call-with-raster-buffer-pixmap b
        (lambda (v) (set! read-only? (rejects? (lambda () (pixmap-fill! v 'red))))))
      (call-with-raster-buffer-pixmap b
        (lambda (v)
          (set! expired (pixmap-subset v 40 24 80 48))
          (set! subset-stride (pixmap-row-bytes expired))
          (pixmap-fill! expired orange)) #:writable? #t)
      (hash-set! trace 'layout
        (hasheq 'width 160 'height 96 'row_bytes (raster-buffer-row-bytes b)
                'allocation_bytes (raster-buffer-byte-size b) 'subset_row_bytes subset-stride
                'padding_zero (padding-zero? b) 'read_only_rejected read-only?
                'expired_view_rejected (rejects? (lambda () (pixmap-pixel expired 0 0)))
                'outside (buffer-pixel b 0 0) 'inside (buffer-pixel b 40 24)))
      (list before (raster-buffer->image b))))
  (define second
    (with-skia ([b (make-raster-buffer 160 96 #:row-bytes 704)])
      (define old-canvas #f)
      (call-with-raster-buffer-canvas b (lambda (c) (set! old-canvas c) (card c blue)))
      (define before (raster-buffer->image b))
      (call-with-raster-buffer-pixmap b
        (lambda (v) (pixmap-fill! (pixmap-subset v 12 12 16 16) teal)) #:writable? #t)
      (hash-set! trace 'canvas
        (hasheq 'direct_pixel (buffer-pixel b 80 80) 'edited_pixel (buffer-pixel b 16 16)
                'padding_zero (padding-zero? b)
                'expired_canvas_rejected (rejects? (lambda () (canvas-clear! old-canvas 'white)))))
      (list before (raster-buffer->image b))))
  (define third
    (with-skia ([b (make-raster-buffer 160 96 #:row-bytes 704)]
                [scaled (make-raster-buffer 320 192 #:row-bytes 1344)])
      (call-with-raster-buffer-canvas b (lambda (c) (card c blue)))
      (define snapshot (raster-buffer->image b))
      (call-with-raster-buffer-canvas b (lambda (c) (canvas-clear! c 'transparent) (card c teal)))
      (call-with-raster-buffer-pixmap b
        (lambda (src)
          (call-with-raster-buffer-pixmap scaled
            (lambda (dst) (pixmap-scale! dst src #:sampling 'nearest)) #:writable? #t)))
      (define after (raster-buffer->image scaled))
      (skia-close! b) (skia-close! scaled)
      (hash-set! trace 'snapshots
        (hasheq 'sources_closed (and (skia-closed? b) (skia-closed? scaled))
                'before (raw-pixel (image->rgba-bytes snapshot) 160 80 80)
                'after (raw-pixel (image->rgba-bytes after) 320 160 160)))
      (list snapshot after)))
  (with-skia ([b (make-raster-buffer 1 1 #:row-bytes 8)])
    (raster-buffer-write-rgba! b (bytes 255 128 64 128))
    (hash-set! trace 'premultiplied (bytes->list (subbytes (raster-buffer->storage-bytes b) 0 4))))
  (values (list first second third) trace))
(define (label c text x y [size 10])
  (with-skia ([font (make-font #:size size #:linear-metrics? #t #:subpixel? #t #:hinting 'none)]
              [p (make-paint #:color ink)]) (draw-simple-text c text x y font p)))
(define (checker c x y)
  (with-skia ([a (make-paint #:color (rgb 242 245 248) #:antialias? #f)]
              [b (make-paint #:color (rgb 225 232 240) #:antialias? #f)])
    (draw-rect c x y 300 180 a)
    (for* ([row (in-range 12)] [col (in-range 19)] #:when (odd? (+ row col)))
      (draw-rect c (+ x (* col 16)) (+ y (* row 16))
                 (min 16 (- 300 (* col 16))) (min 16 (- 180 (* row 16))) b))))
(define (draw-page c index images document?)
  (with-skia ([p (make-paint #:color teal)]) (draw-rect c 0 0 34 2 p))
  (label c (list-ref titles index) 0 32 21)
  (label c (list-ref subtitles index) 0 55 9.5)
  (for ([im (in-list images)] [x '(0 352)] [j (in-naturals)]
        [caption (in-list (list-ref
          '(("01  Original storage; input bytes already changed" "02  A writable subset changes only its rectangle")
            ("01  Native canvas writes into the buffer" "02  A pixmap edits the same pixels afterward")
            ("01  Original snapshot after source mutation" "02  Modified storage scaled into a new buffer")) index))])
    (label c caption x 105 9.5) (checker c x 126)
    (define (content local) (draw-image-rect local im 0 0 300 180 #:sampling 'linear))
    (if document?
        (let ([decision (draw-output-group c x 126 300 180 content
                            #:label (format "~a-~a" (list-ref names index) j))])
          (when (current-decisions)
            (set-box! (current-decisions) (cons (output-group-report->jsexpr decision) (unbox (current-decisions))))))
        (with-canvas-state c (canvas-translate! c x 126) (content c))))
  (for ([text (in-list (list-ref notes index))] [y '(340 368 396)]) (label c text 0 y 9))
  (label c "RACKET / SKIA   |   OWNED RASTER BUFFERS AND SCOPED PIXMAPS" 0 444 9)
  (label c (number->string (add1 index)) 652 444 9))
(define (escape-html s)
  (for/fold ([s s]) ([p '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;") ("\"" . "&quot;"))])
    (string-replace s (car p) (cdr p))))
(module+ main
  (define args (current-command-line-arguments))
  (when (> (vector-length args) 1) (error 'raster-buffers "expected optional output prefix"))
  (define prefix (if (zero? (vector-length args)) "output/raster-buffers-0.37" (vector-ref args 0)))
  (define (file suffix) (string-append prefix suffix))
  (make-directory* (or (path-only (string->path prefix)) (current-directory)))
  (define-values (assets trace) (make-assets))
  (dynamic-wind void
    (lambda ()
      (define pages (for/list ([images (in-list assets)] [i (in-naturals)])
                      (make-output-page 720 500 (lambda (c) (draw-page c i images #t)) #:margins 24 #:background 'white)))
      (define pd (box '())) (define sd (box '()))
      (define report (parameterize ([current-decisions pd])
                       (save-output/audit pages (file ".pdf") 'pdf #:policy 'error #:exists 'replace #:title "Owned raster buffers")))
      (write-json-file (file ".pdf.audit.json") (output-audit-report->jsexpr report))
      (for ([name (in-list names)] [page (in-list pages)] [images (in-list assets)] [i (in-naturals)])
        (define report (parameterize ([current-decisions sd])
                         (save-output/audit page (file (string-append "." name ".svg")) 'svg #:policy 'error #:id-prefix name #:exists 'replace)))
        (write-json-file (file (string-append "." name ".audit.json")) (output-audit-report->jsexpr report))
        (for ([im (in-list images)] [j (in-naturals)])
          (save-image im (file (format ".~a.source-~a.png" name j)) 'png #:exists 'replace))
        (define reference (make-output-page 720 500 (lambda (c) (draw-page c i images #f)) #:margins 24 #:background 'white))
        (with-skia ([im (output-page->image reference #:dpi 144)])
          (save-image im (file (string-append "." name ".reference.png")) 'png #:exists 'replace)))
      (write-json-file (file ".samples.json") trace)
      (write-json-file (file ".decisions.json") (hasheq 'pdf (reverse (unbox pd)) 'svg (reverse (unbox sd))))
      (define base (escape-html (path->string (file-name-from-path prefix))))
      (call-with-output-file (file ".review.html")
        (lambda (out)
          (display "<!doctype html><meta charset=\"utf-8\"><title>Raster buffers review</title><style>body{font:16px system-ui;margin:24px;background:#edf0f4;color:#20344e}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:32px}img{width:100%;background:white}figure{margin:0}@media(max-width:850px){.pair{grid-template-columns:1fr}}</style><h1>Raster buffers and scoped pixmaps</h1>" out)
          (fprintf out "<p><a href=\"~a.pdf\">Actual PDF</a> | <a href=\"~a.samples.json\">Native memory checks</a> | <a href=\"~a.inspection.json\">Inspection</a></p>" base base base)
          (display "<p>Left: actual SVG. Right: independent raster placement of the same source snapshots; not a PDF/SVG rasterization and not an independent proof of buffer contents. Native tests and samples check memory behavior.</p>" out)
          (for ([name (in-list names)])
            (fprintf out "<h2>~a</h2><div class=\"pair\"><figure><figcaption>Actual SVG</figcaption><img src=\"~a.~a.svg\"></figure><figure><figcaption>Raster reference</figcaption><img src=\"~a.~a.reference.png\"></figure></div>" name base name base name)))
        #:exists 'replace)
      (printf "Wrote ~a.pdf; 3 SVG/reference pairs, 6 source snapshots, 4 audits, native memory samples and review HTML\n" prefix))
    (lambda () (for* ([row (in-list assets)] [im (in-list row)]) (skia-close! im)))))
