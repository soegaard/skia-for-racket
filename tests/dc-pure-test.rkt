#lang racket/base
(require rackunit racket/class racket/list racket/math racket/vector
         (prefix-in rd: racket/draw)
         "../private/dc-support.rkt" "../private/dc-class.rkt")
(provide dc-pure-tests dc-pure-test-count)
;; These are production-class tests with an injected recording renderer. They
;; verify protocol/state/geometry, not native Skia pixel execution.
(define (fresh [width 32] [height 24] [scale 1])
  (define events (box '()))
  (define (event v) (set-box! events (cons v (unbox events))))
  (define backend
    (dc-renderer (lambda (w h) (event (list 'create w h)) (box #t))
                 (lambda (s) (event '(close)) (set-box! s #f))
                 (lambda (s op) (event (cons 'draw op)))
                 (lambda (s clip color erase?) (event (list 'clear clip color erase?)))
                 (lambda (s) 'fake-snapshot)
                 (lambda (s p?) (event (list 'rgba p?)) #"fake-rgba")
                 (lambda (s) #"fake-png")))
  (define dc (new (make-skia-dc-class backend) [width width] [height height] [backing-scale scale]))
  (values dc events))
(define (draws e) (for/list ([x (in-list (reverse (unbox e)))] #:when (eq? (car x) 'draw)) (cdr x)))
(define (paint-only dc)
  (send dc set-pen "black" 1 'transparent)
  (send dc set-brush "red" 'solid))
(define (fails? thunk) (check-exn exn:fail:skia-dc:unsupported? thunk))
(define dc-pure-tests
  (test-suite
   "skia-dc foundation (recording renderer; no Skia pixels)"
   (test-case "genuine interface on the running Racket version"
     (define-values (dc e) (fresh))
     ;; `class*` enforces the complete method contract when the class is built;
     ;; `is-a?` is the public runtime membership test for an interface.
     (check-true (is-a? dc rd:dc<%>)))
   (test-case "positive integer logical extent"
     (for ([v '(0 -1 1/2 #f +inf.0)]) (check-exn exn:fail? (lambda () (fresh v 24)))))
   (test-case "backing scale validation"
     (for ([v '(0 -1 #f +inf.0 +nan.0)]) (check-exn exn:fail? (lambda () (fresh 32 24 v)))))
   (test-case "logical and physical size stay separate"
     (define-values (dc e) (fresh 31 23 1.5))
     (check-equal? (call-with-values (lambda () (send dc get-size)) list) '(31.0 23.0))
     (check-equal? (call-with-values (lambda () (send dc get-pixel-size)) list) '(47 35))
     (check-equal? (call-with-values (lambda () (send dc get-device-scale)) list) '(1.0 1.0))
     (check-equal? (send dc get-backing-scale) 1.5))
   (test-case "initial state"
     (define-values (dc e) (fresh))
     (check-true (send dc ok?)) (check-false (send dc get-gl-context))
     (check-equal? (send dc cache-font-metrics-key) 0)
     (check-equal? (send dc get-smoothing) 'unsmoothed)
     (check-equal? (send dc get-alpha) 1.0)
     (check-equal? (send (send dc get-pen) get-width) 1)
     (check-false (send dc get-clipping-region)))
   (test-case "close is one native release and idempotent"
     (define-values (dc e) (fresh))
     (send dc close) (send dc close)
     (check-false (send dc ok?))
     (check-equal? (count (lambda (x) (equal? x '(close))) (unbox e)) 1))
   (test-case "closed drawing and snapshots fail"
     (define-values (dc e) (fresh)) (send dc close)
     (for ([f (in-list (list (lambda () (send dc clear)) (lambda () (send dc snapshot))
                             (lambda () (send dc get-size)) (lambda () (send dc draw-line 0 0 1 1))))])
       (check-exn #rx"closed" f)))
   (test-case "thread ownership checked before drawing"
     (define-values (dc e) (fresh))
     (define answer (box #f))
     (define worker (thread (lambda () (with-handlers ([exn:fail? (lambda (x) (set-box! answer x))])
                                        (send dc clear)))))
     (thread-wait worker)
     (check-true (exn:fail? (unbox answer)))
     (check-equal? (length (unbox e)) 1))
   (test-case "matrix layout is Racket column-affine layout"
     (check-equal? (call-with-values (lambda () (dc-point '#(2 3 5 7 11 13) 17 19)) list)
                   '(140.0 197.0)))
   (test-case "matrix composition order"
     (define m (dc-multiply '#(2 0 0 3 0 0) '#(1 0 0 1 5 7)))
     (check-equal? m '#(2.0 0.0 0.0 3.0 10.0 21.0)))
   (test-case "positive rotation is counter-clockwise"
     (define m (dc-effective (vector dc-identity 0 0 1 1 (/ pi 2))))
     (define-values (x y) (dc-point m 1 0)) (check-= x 0 1e-12) (check-= y -1 1e-12))
   (test-case "setters preserve transformation components"
     (define-values (dc e) (fresh))
     (send dc set-origin 2 3) (send dc set-scale 4 5) (send dc set-rotation 0.25)
     (check-equal? (send dc get-transformation) (vector dc-identity 2.0 3.0 4.0 5.0 0.25)))
   (test-case "transform collapses the separate components"
     (define-values (dc e) (fresh))
     (send dc set-origin 2 3) (send dc set-scale 4 5) (send dc translate 6 7)
     (check-equal? (send dc get-initial-matrix) '#(4.0 0.0 0.0 5.0 26.0 38.0))
     (check-equal? (vector-copy (send dc get-transformation) 1) '#(0.0 0.0 1.0 1.0 0.0)))
   (test-case "input matrices detached"
     (define-values (dc e) (fresh)) (define m (vector 2 0 0 3 4 5))
     (send dc set-initial-matrix m) (vector-set! m 0 99)
     (check-equal? (vector-ref (send dc get-initial-matrix) 0) 2.0)
     (check-true (immutable? (send dc get-initial-matrix))))
   (test-case "transformation failure is transactional"
     (define-values (dc e) (fresh))
     (define before (send dc get-transformation))
     (check-exn exn:fail? (lambda () (send dc set-transformation (vector dc-identity 1 2 3 4 +nan.0))))
     (check-equal? (send dc get-transformation) before))
   (test-case "native matrix overflow does not mutate state"
     (define-values (dc e) (fresh 32 24 2))
     (define before (send dc get-transformation))
     (check-exn exn:fail? (lambda () (send dc set-scale 3e38 3e38)))
     (check-exn exn:fail? (lambda () (send dc set-clipping-rect 3e38 0 1 1)))
     (check-false (send dc get-clipping-region))
     (check-equal? (send dc get-transformation) before))
   (test-case "singular transform is accepted and drawing is empty"
     (define-values (dc e) (fresh)) (send dc set-scale 0 1)
     (send dc draw-rectangle 1 2 3 4) (check-equal? (draws e) '()))
   (test-case "transformed smoothed path passes physical matrix"
     (define-values (dc e) (fresh 32 24 2)) (paint-only dc)
     (send dc set-smoothing 'smoothed) (send dc set-origin 3 4) (send dc set-scale 2 3)
     (send dc draw-rectangle 1 2 3 4)
     (check-equal? (dc-draw-matrix (car (draws e))) '#(4.0 0.0 0.0 6.0 6.0 8.0)))
   (test-case "aligned complex transform explicitly deferred"
     (define-values (dc e) (fresh)) (send dc set-rotation 0.25)
     (fails? (lambda () (send dc draw-rectangle 1 2 3 4))) (check-equal? (draws e) '()))
   (test-case "complex transform supported in smoothed mode"
     (define-values (dc e) (fresh)) (send dc set-smoothing 'smoothed)
     (send dc set-initial-matrix '#(-1 0.2 0.3 1 20 0))
     (send dc draw-line 1 2 3 4) (check-equal? (length (draws e)) 1))
   (test-case "unknown smoothing rejected without change"
     (define-values (dc e) (fresh))
     (check-exn exn:fail? (lambda () (send dc set-smoothing 'fast)))
     (check-equal? (send dc get-smoothing) 'unsmoothed))
   (test-case "invalid alpha rejected"
     (define-values (dc e) (fresh))
     (for ([a '(-1 2 +nan.0 +inf.0 #f)]) (check-exn exn:fail? (lambda () (send dc set-alpha a))))
     (check-equal? (send dc get-alpha) 1.0))
   (test-case "DC and brush alpha multiply"
     (define-values (dc e) (fresh)) (paint-only dc)
     (send dc set-alpha 0.5)
     (send dc set-brush (make-object rd:color% 100 150 200 0.5) 'solid)
     (send dc draw-rectangle 0 0 10 10)
     (check-equal? (vector-ref (dc-ink-rgba (dc-draw-ink (car (draws e)))) 3) 0.25))
   (test-case "returned background is detached"
     (define-values (dc e) (fresh)) (define c (send dc get-background))
     (send c set 0 0 0) (check-equal? (send (send dc get-background) red) 255))
   (test-case "supplied pen is copied not locked"
     (define-values (dc e) (fresh))
     (define p (rd:make-pen #:color "red" #:width 3 #:immutable? #f))
     (send dc set-pen p) (send p set-width 8)
     (check-equal? (send (send dc get-pen) get-width) 3.0)
     (check-exn exn:fail? (lambda () (send (send dc get-pen) set-width 9))))
   (test-case "brush snapshot remains immutable"
     (define-values (dc e) (fresh))
     (define b (rd:make-brush #:color "red" #:immutable? #f))
     (send dc set-brush b) (send b set-color "blue")
     (check-equal? (send (send (send dc get-brush) get-color) red) 255)
     (check-exn exn:fail? (lambda () (send (send dc get-brush) set-color "green"))))
   (test-case "deferred pen style does not replace current pen"
     (define-values (dc e) (fresh)) (define before (send dc get-pen))
     (fails? (lambda () (send dc set-pen "blue" 2 'xor))) (check-eq? (send dc get-pen) before))
   (test-case "deferred brush style does not replace current brush"
     (define-values (dc e) (fresh)) (define before (send dc get-brush))
     (fails? (lambda () (send dc set-brush "blue" 'cross-hatch))) (check-eq? (send dc get-brush) before))
   (test-case "font storage and color controls do not measure text"
     (define-values (dc e) (fresh)) (define f (rd:make-font #:size 18 #:family 'modern))
     (send dc set-font f) (check-eq? (send dc get-font) f)
     (send dc set-text-foreground "red") (send dc set-text-background "blue")
     (send dc set-text-mode 'solid) (check-eq? (send dc get-text-mode) 'solid)
     (check-equal? (length (unbox e)) 1))
   (test-case "try-color returns through destination including alpha"
     (define-values (dc e) (fresh)) (define dest (make-object rd:color%))
     (send dc try-color (make-object rd:color% 3 7 11 0.5) dest)
     (check-equal? (list (send dest red) (send dest green) (send dest blue) (send dest alpha)) '(3 7 11 0.5)))
   (test-case "fill precedes stroke"
     (define-values (dc e) (fresh)) (send dc draw-rectangle 1 2 10 12)
     (check-equal? (map (lambda (op) (dc-ink-stroke? (dc-draw-ink op))) (draws e)) '(#f #t)))
   (test-case "transparent pen and brush perform no draws"
     (define-values (dc e) (fresh)) (send dc set-pen "black" 1 'transparent)
     (send dc set-brush "white" 'transparent) (send dc draw-rectangle 0 0 20 20)
     (check-equal? (draws e) '()))
   (test-case "line and spline never fill with current brush"
     (define-values (dc e) (fresh))
     (send dc draw-line 0 0 10 10) (send dc draw-spline 1 2 3 4 5 6)
     (check-equal? (map (lambda (op) (dc-ink-stroke? (dc-draw-ink op))) (draws e)) '(#t #t)))
   (test-case "polyline is stroked not filled"
     (define-values (dc e) (fresh)) (send dc draw-lines '((1 . 1) (9 . 1) (9 . 9)))
     (check-equal? (length (draws e)) 1) (check-true (dc-ink-stroke? (dc-draw-ink (car (draws e))))))
   (test-case "empty and singleton point lists do not draw"
     (define-values (dc e) (fresh))
     (send dc draw-lines '()) (send dc draw-polygon '((1 . 1))) (check-equal? (draws e) '()))
   (test-case "invalid point list fails before drawing"
     (define-values (dc e) (fresh))
     (check-exn exn:fail? (lambda () (send dc draw-lines '((1 . 1) (2 . bad))))) (check-equal? (draws e) '()))
   (test-case "polygon closure and fill rule"
     (define-values (dc e) (fresh))
     (send dc draw-polygon '((1 . 1) (9 . 1) (9 . 9)) 2 3 'odd-even)
     (for ([op (in-list (draws e))]) (check-equal? (last (dc-draw-commands op)) '#(close))
                                   (check-eq? (dc-draw-rule op) 'odd-even)))
   (test-case "cubic paths use public datum and preserve open subpath"
     (define-values (dc e) (fresh)) (send dc set-smoothing 'smoothed)
     (define p (new rd:dc-path%)) (send p move-to 1 2) (send p curve-to 3 4 5 6 7 8)
     (send dc draw-path p 10 20 'winding)
     (check-equal? (dc-draw-commands (car (draws e))) '(#(move 11.0 22.0) #(cubic 13.0 24.0 15.0 26.0 17.0 28.0))))
   (test-case "rectangle outline is inset in aligned mode"
     (define-values (dc e) (fresh)) (send dc draw-rectangle 1 2 10 12)
     (check-equal? (car (dc-draw-commands (second (draws e)))) '#(move 1.5 2.5))
     (check-equal? (second (dc-draw-commands (second (draws e)))) '#(line 10.5 2.5)))
   (test-case "alignment scale changes snapping grid not geometry transform"
     (define-values (dc e) (fresh)) (send dc set-alignment-scale 2)
     (send dc draw-line 1.25 2.25 10.25 2.25)
     (check-equal? (dc-draw-matrix (car (draws e))) dc-identity)
     (check-equal? (car (dc-draw-commands (car (draws e)))) '#(move 1.0 2.0)))
   (test-case "dash widths and cap conversion"
     (define-values (dc e) (fresh)) (send dc set-smoothing 'smoothed)
     (send dc set-pen (rd:make-pen #:width 3 #:style 'dot-dash #:cap 'projecting #:join 'bevel))
     (send dc draw-line 1 2 3 4)
     (define ink (dc-draw-ink (car (draws e))))
     (check-equal? (dc-ink-dashes ink) '(3.0 6.0 12.0 6.0))
     (check-eq? (dc-ink-cap ink) 'square) (check-eq? (dc-ink-join ink) 'bevel))
   (test-case "zero pen width maps to a drawable hairline"
     (define-values (dc e) (fresh)) (send dc set-pen "black" 0 'solid) (send dc draw-line 0 0 2 2)
     (check-equal? (dc-ink-width (dc-draw-ink (car (draws e)))) 1.0))
   (test-case "point and zero length line are nonempty strokes"
     (define-values (dc e) (fresh)) (send dc draw-point 2 3) (send dc draw-line 2 3 2 3)
     (check-equal? (length (draws e)) 2)
     (check-equal? (dc-draw-commands (first (draws e))) (dc-draw-commands (second (draws e)))))
   (test-case "arc radial edges are fill-only"
     (define-values (dc e) (fresh)) (send dc set-smoothing 'smoothed)
     (send dc draw-arc 0 0 20 10 0 pi)
     (define fill (dc-draw-commands (first (draws e))))
     (define stroke (dc-draw-commands (second (draws e))))
     (check-equal? (car fill) '#(move 10.0 5.0))
     (check-not-equal? (car stroke) (car fill))
     (check-equal? (last fill) '#(close)) (check-not-equal? (last stroke) '#(close)))
   (test-case "equal arc angles produce a full ellipse"
     (define-values (dc e) (fresh)) (send dc set-smoothing 'smoothed)
     (send dc draw-arc 0 0 20 10 0 0)
     (check-true (>= (length (dc-draw-commands (second (draws e)))) 5)))
   (test-case "rounded rectangle uses cubic path segments"
     (define-values (dc e) (fresh)) (send dc draw-rounded-rectangle 0 0 20 20)
     (check-not-false (memq 'cubic (map (lambda (v) (vector-ref v 0)) (dc-draw-commands (car (draws e)))))))
   (test-case "invalid dimensions fail before any ink"
     (define-values (dc e) (fresh))
     (check-exn exn:fail? (lambda () (send dc draw-rectangle 0 0 -1 2)))
     (check-equal? (draws e) '()))
   (test-case "clipping getter returns a real region"
     (define-values (dc e) (fresh)) (send dc set-clipping-rect 1 2 10 12)
     (check-true (is-a? (send dc get-clipping-region) rd:region%)))
   (test-case "rectangle clipping freezes transformed geometry"
     (define-values (dc e) (fresh 32 24 2))
     (send dc set-origin 3 4) (send dc set-clipping-rect 1 2 5 6)
     (send dc set-origin 10 20) (send dc clear)
     (define clear-event (car (unbox e)))
     (check-equal? (car (dc-clip-path-commands (car (dc-clip-paths (second clear-event))))) '#(move 8.0 12.0)))
   (test-case "rectangle tickets can be restored"
     (define-values (dc e) (fresh)) (send dc set-clipping-rect 1 2 3 4)
     (define old (send dc get-clipping-region))
     (send dc set-clipping-region #f) (send dc set-clipping-region old)
     (check-eq? (send dc get-clipping-region) old))
   (test-case "selected regions reject mutation"
     (define-values (dc e) (fresh)) (send dc set-clipping-rect 1 2 3 4)
     (check-exn exn:fail? (lambda () (send (send dc get-clipping-region) set-rectangle 0 0 1 1))))
   (test-case "unassociated regions accepted and foreign associated regions rejected"
     (define-values (dc e) (fresh)) (define-values (other oe) (fresh))
     (send other set-clipping-rect 0 0 1 1)
     (check-exn exn:fail:contract? (lambda () (send dc set-clipping-region (send other get-clipping-region))))
     (define r (new rd:region%)) (send dc set-clipping-region r)
     (check-eq? (send dc get-clipping-region) r))
   (test-case "clipping replacement is not intersection"
     (define-values (dc e) (fresh))
     (send dc set-clipping-rect 0 0 1 1) (send dc set-clipping-rect 10 10 5 5) (send dc clear)
     (check-equal? (car (dc-clip-path-commands (car (dc-clip-paths (second (car (unbox e))))))) '#(move 10.0 10.0)))
   (test-case "erase ignores DC alpha but retains clipping"
     (define-values (dc e) (fresh)) (send dc set-alpha 0.1)
     (send dc set-clipping-rect 1 2 3 4) (send dc erase)
     (define op (car (unbox e)))
     (check-equal? (third op) '#(0 0 0 0.0)) (check-true (fourth op)) (check-not-false (second op)))
   (test-case "clear uses background multiplied by DC alpha"
     (define-values (dc e) (fresh)) (send dc set-alpha 0.25) (send dc set-background "red") (send dc clear)
     (check-equal? (third (car (unbox e))) '#(255 0 0 0.25)))
   (test-case "a minimal recording renderer never fabricates native text metrics"
     (define-values (dc e) (fresh))
     (for ([f (list (lambda () (send dc draw-text "abc" 0 0)) (lambda () (send dc get-text-extent "abc"))
                    (lambda () (send dc get-char-width)) (lambda () (send dc get-char-height))
                    (lambda () (send dc glyph-exists? #\a)))]) (fails? f)))
   (test-case "minimal renderer copy and deferred alpha groups remain explicit"
     (define-values (dc e) (fresh))
     (fails? (lambda () (send dc copy 0 0 1 1 2 2)))
     (fails? (lambda () (send dc start-alpha 0.5)))
     (check-true (void? (send dc end-alpha))) (check-equal? (length (unbox e)) 1))
   (test-case "document and flush hooks are no-ops on a raster DC"
     (define-values (dc e) (fresh))
     (send dc start-doc "demo") (send dc start-page) (send dc end-page) (send dc end-doc)
     (send dc suspend-flush) (send dc flush) (send dc resume-flush)
     (check-equal? (length (unbox e)) 1))
   (test-case "snapshot and byte access dispatch to renderer"
     (define-values (dc e) (fresh))
     (check-eq? (send dc snapshot) 'fake-snapshot)
     (check-equal? (send dc get-png-bytes) #"fake-png")
     (check-equal? (send dc get-rgba-bytes #:premultiplied? #t) #"fake-rgba")
     (check-equal? (car (unbox e)) '(rgba #t)))
   (test-case "capabilities do not claim full compatibility or runtime evidence"
     (check-false (hash-ref (dc-capabilities) 'full_drop_in_compatibility))
     (check-false (hash-ref (dc-capabilities) 'native_probe_performed))
     (check-true (immutable? (dc-capabilities))))))

(define dc-pure-test-count 60)
