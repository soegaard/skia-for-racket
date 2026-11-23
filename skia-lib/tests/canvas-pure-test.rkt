#lang racket/base

;;;
;;; Canvas Pure Test
;;;

;; Covers canvas primitives: validation without native loading.
;; This source-only regression layer checks contracts and lifecycle rules before native rendering
;; is involved.

;;;
;;; Imports and Exports
;;;
(require rackunit racket/list racket/string racket/vector "../main.rkt"
         (only-in "../canvas-primitives.rkt" [draw-rounded-rect primitive-draw-rounded-rect]))
(provide canvas-pure-tests)

;;;
;;; Error Message Assertions
;;;

; check-drawing-error : procedure? list? string? ... -> void?
;   Checks the public procedure name, calling form, and complete diagnostic fields.
(define (check-drawing-error thunk form . fields)
  (check-exn
   (lambda (e)
     (and (exn:fail:contract? e)
          (string-prefix? (exn-message e) (format "~a:" (car form)))
          (for/and ([field (in-list (cons (format "calling form: ~s" form) fields))])
            (string-contains? (string-append "\n" (exn-message e) "\n")
                              (format "\n  ~a\n" field)))))
   thunk))

;;;
;;; Regression Suite
;;;

; canvas-pure-tests : test-suite?
;   Collects the regression cases for canvas primitives: validation without native loading.
(define canvas-pure-tests
  (test-suite
   "Canvas primitives: validation without native loading"
   (test-case "circle radius error identifies the argument and calling form"
     (check-drawing-error
      (lambda () (draw-circle #f 1 2 -10 #f))
      '(draw-circle canvas x y radius paint)
      "expected: nonnegative finite real" "given: -10"
      "argument: radius" "argument position: 4th"))
   (test-case "callers without a calling form keep their existing diagnostics"
     (check-exn
      (lambda (e)
        (and (exn:fail:contract? e)
             (string-prefix? (exn-message e) "canvas-translate!:")
             (string-contains? (exn-message e) "finite real representable as a C float")
             (not (string-contains? (exn-message e) "calling form:"))))
      (lambda () (canvas-translate! #f +inf.0 0))))
   (test-case "all line coordinates have distinct argument positions"
     (for ([name (in-list '(x0 y0 x1 y1))]
           [index (in-naturals 1)]
           [position (in-list '(2nd 3rd 4th 5th))])
       (check-drawing-error
        (lambda () (apply draw-line (list-set '(#f 0 0 1 1 #f) index +nan.0)))
        '(draw-line canvas x0 y0 x1 y1 paint)
        (format "argument: ~a" name) (format "argument position: ~a" position))))
   (test-case "scalar restrictions retain location information"
     (for ([value (in-list (list +nan.0 +inf.0 -inf.0 1e39 'not-a-number))])
       (check-drawing-error
        (lambda () (draw-circle #f 0 0 value #f))
        '(draw-circle canvas x y radius paint)
        "expected: finite real representable as a C float"
        "argument: radius" "argument position: 4th"))
     (check-drawing-error
      (lambda () (draw-point #f 0 +inf.0 #f)) '(draw-point canvas x y paint)
      "argument: y" "argument position: 3rd"))
   (test-case "rectangle extents and computed edges identify their inputs"
     (check-drawing-error
      (lambda () (draw-rect #f 0 0 -1 2 #f)) '(draw-rect canvas x y width height paint)
      "argument: width" "argument position: 4th")
     (check-drawing-error
      (lambda () (draw-oval #f 0 0 1 -2 #f)) '(draw-oval canvas x y width height paint)
      "argument: height" "argument position: 5th")
     (check-drawing-error
      (lambda () (draw-rect #f 3e38 0 3e38 1 #f)) '(draw-rect canvas x y width height paint)
      "arguments: x, width" "argument positions: 2nd, 4th"
      "computed edge: \"x + width\"")
     (check-drawing-error
      (lambda () (draw-oval #f 0 3e38 1 3e38 #f)) '(draw-oval canvas x y width height paint)
      "arguments: y, height" "argument positions: 3rd, 5th"
      "computed edge: \"y + height\""))
   (test-case "keywords are identified by name instead of a positional index"
     (check-drawing-error
      (lambda () (draw-points #f '() #f #:mode 'triangle))
      '(draw-points canvas points paint #:mode mode)
      "argument: mode" "argument keyword: #:mode" "allowed: '(lines points polygon)")
     (check-drawing-error
      (lambda () (draw-polygon #f '() #f #:closed? 1))
      '(draw-polygon canvas points paint #:closed? closed?)
      "argument: closed?" "argument keyword: #:closed?")
     (check-drawing-error
      (lambda () (draw-arc #f 0 0 1 1 0 90 #f #:use-center? 1))
      '(draw-arc canvas x y width height start sweep paint #:use-center? use-center?)
      "argument: use-center?" "argument keyword: #:use-center?")
     (check-drawing-error
      (lambda () (draw-color #f 'red #:blend-mode 'bad-mode))
      '(draw-color canvas color #:blend-mode mode)
      "argument: mode" "argument keyword: #:blend-mode"))
   (test-case "arc angles retain their public names and positions"
     (check-drawing-error
      (lambda () (draw-arc #f 0 0 1 1 0 +inf.0 #f))
      '(draw-arc canvas x y width height start sweep paint #:use-center? use-center?)
      "argument: sweep" "argument position: 7th"))
   (test-case "nested point errors identify the containing argument and coordinate"
     (check-drawing-error
      (lambda () (draw-points #f '#(#(0 0) #(1 +inf.0)) #f))
      '(draw-points canvas points paint #:mode mode)
      "argument: points" "argument position: 2nd" "point index (0-based): 1" "coordinate: 'y")
     (check-drawing-error
      (lambda () (draw-polygon #f '((0 0) (bad 1)) #f))
      '(draw-polygon canvas points paint #:closed? closed?)
      "argument: points" "argument position: 2nd" "point index (0-based): 1" "coordinate: 'x")
     (check-drawing-error
      (lambda () (draw-points #f '((0 0) (1 2 3)) #f))
      '(draw-points canvas points paint #:mode mode)
      "argument: points" "point index (0-based): 1")
     (check-drawing-error
      (lambda () (draw-polygon #f '((0 0) bad) #f))
      '(draw-polygon canvas points paint #:closed? closed?)
      "argument: points" "point index (0-based): 1"))
   (test-case "point counts and budgets retain their explanations and argument locations"
     (check-drawing-error
      (lambda () (draw-points #f '((0 0)) #f #:mode 'lines))
      '(draw-points canvas points paint #:mode mode)
      "argument: points" "argument position: 2nd" "count: 1")
     (parameterize ([current-skia-byte-limit 8])
       (check-drawing-error
        (lambda () (draw-points #f '((0 0) (1 1)) #f))
        '(draw-points canvas points paint #:mode mode)
        "argument: points" "required bytes: 16")))
   (test-case "rounded rectangle errors describe the selected calling form"
     (check-drawing-error
      (lambda () (draw-rounded-rect #f #f #f)) '(draw-rounded-rect canvas shape paint)
      "argument: shape" "argument position: 2nd")
     (check-drawing-error
      (lambda () (draw-rounded-rect #f 0 0 10 10 -1 2 #f))
      '(draw-rounded-rect canvas x y width height radius-x radius-y paint)
      "argument: radius-x" "argument position: 6th")
     (check-drawing-error
      (lambda () (draw-rounded-rect #f 0 0 10 10 1 -2 #f))
      '(draw-rounded-rect canvas x y width height radius-x radius-y paint)
      "argument: radius-y" "argument position: 7th")
     (check-drawing-error
      (lambda () (draw-rounded-rect #f (make-rounded-rect 0 0 10 10) #f))
      '(draw-rounded-rect canvas shape paint)
      "argument: paint" "argument position: 3rd")
     (check-drawing-error
      (lambda () (draw-rounded-rect #f 0 0 10 10 1 2 #f))
      '(draw-rounded-rect canvas x y width height radius-x radius-y paint)
      "argument: paint" "argument position: 8th")
     (check-drawing-error
      (lambda () (draw-double-rounded-rect #f (make-rounded-rect 0 0 10 10) #f #f))
      '(draw-double-rounded-rect canvas outer inner paint)
      "argument: inner" "argument position: 3rd"))
   (test-case "resource and color type errors name the public drawing procedure"
     (check-drawing-error
      (lambda () (draw-paint #f #f)) '(draw-paint canvas paint)
      "expected: paint?" "argument: paint" "argument position: 2nd")
     (check-drawing-error
      (lambda () (draw-path #f #f #f)) '(draw-path canvas path paint)
      "expected: skia-path?" "argument: path" "argument position: 2nd")
     (check-drawing-error
      (lambda () (draw-color #f 'not-a-color)) '(draw-color canvas color #:blend-mode mode)
      "expected: color?" "argument: color" "argument position: 2nd")
     (check-drawing-error
      (lambda () (draw-color #f 'red)) '(draw-color canvas color #:blend-mode mode)
      "expected: canvas?" "argument: canvas" "argument position: 1st"))
   (test-case "rounded rect is a pure immutable value"
     (define r (make-rounded-rect 1 2 30 40))
     (check-true (rounded-rect? r))
     (check-equal? (rounded-rect-bounds r) #(1.0 2.0 30.0 40.0))
     (check-true (immutable? (rounded-rect-bounds r))))
   (test-case "uniform scalar radii"
     (check-equal? (rounded-rect-radii (make-rounded-rect 0 0 20 30 #:radii 5))
                   #(#(5.0 5.0) #(5.0 5.0) #(5.0 5.0) #(5.0 5.0))))
   (test-case "corner order is TL TR BR BL"
     (check-equal?
       (rounded-rect-radii (make-rounded-rect 0 0 20 30 #:radii '((1 2) (3 4) (5 6) (7 8))))
                   #(#(1.0 2.0) #(3.0 4.0) #(5.0 6.0) #(7.0 8.0))))
   (test-case "input vectors are deeply copied"
     (define p (vector 1 2)) (define rs (vector p p p p))
     (define r (make-rounded-rect 0 0 20 30 #:radii rs))
     (vector-set! p 0 99) (vector-set! rs 1 #(8 9))
     (check-equal? (vector-ref (rounded-rect-radii r) 1) #(1.0 2.0))
     (check-true (immutable? (vector-ref (rounded-rect-radii r) 0))))
   (test-case "oversized radii preserved for native normalization"
     (check-equal? (vector-ref (rounded-rect-radii (make-rounded-rect 0 0 20 20 #:radii 100)) 0)
                   #(100.0 100.0)))
   (test-case "zero-area rounded rectangle is allowed"
     (check-true (rounded-rect? (make-rounded-rect 0 0 0 20))))
   (test-case "negative rectangle size rejected"
     (check-exn exn:fail:contract? (lambda () (make-rounded-rect 0 0 -1 20))))
   (test-case "non-finite bounds rejected"
     (check-exn exn:fail:contract? (lambda () (make-rounded-rect +nan.0 0 2 3))))
   (test-case "computed edge overflow rejected"
     (check-exn exn:fail:contract? (lambda () (make-rounded-rect 3e38 0 3e38 3))))
   (test-case "negative radius rejected"
     (check-exn exn:fail:contract? (lambda () (make-rounded-rect 0 0 20 20 #:radii -1))))
   (test-case "corner arity checked"
     (check-exn exn:fail:contract? (lambda () (make-rounded-rect 0 0 20 20 #:radii '((1 2) (3 4))))))
   (test-case "radius pair arity checked"
     (check-exn exn:fail:contract?
       (lambda () (make-rounded-rect 0 0 20 20 #:radii '((1) (2 3) (4 5) (6 7))))))
   (test-case "non-finite radius rejected"
     (check-exn exn:fail:contract? (lambda () (make-rounded-rect 0 0 20 20 #:radii +inf.0))))
   (test-case "point coordinates checked first"
     (check-exn exn:fail:contract? (lambda () (draw-point #f +nan.0 0 #f))))
   (test-case "point mode checked"
     (check-exn exn:fail:contract? (lambda () (draw-points #f '() #f #:mode 'triangle))))
   (test-case "independent line pairs cannot have odd count"
     (check-exn exn:fail:contract? (lambda () (draw-points #f '((0 0)) #f #:mode 'lines))))
   (test-case "point shape checked"
     (check-exn exn:fail:contract? (lambda () (draw-points #f '((0 0 1)) #f))))
   (test-case "point buffer limit checked before allocation"
     (parameterize ([current-skia-byte-limit 8])
       (check-exn exn:fail:contract? (lambda () (draw-points #f '((0 0) (1 1)) #f))))
     (parameterize ([current-skia-byte-limit 32])
       (check-exn exn:fail:contract?
         (lambda () (draw-points #f '((0 0) (1 1) (2 2) (3 3)) #f #:mode 'polygon)))))
   (test-case "invalid arc angle rejected"
     (check-exn exn:fail:contract? (lambda () (draw-arc #f 0 0 2 3 +inf.0 90 #f))))
   (test-case "arc center flag is boolean"
     (check-exn exn:fail:contract? (lambda () (draw-arc #f 0 0 2 3 0 90 #f #:use-center? 1))))
   (test-case "draw-rounded-rect accepts exactly the two public calling forms"
     (check-eq? draw-rounded-rect primitive-draw-rounded-rect)
     (check-equal? (procedure-arity draw-rounded-rect) '(3 8))
     (define-values (required allowed) (procedure-keywords draw-rounded-rect))
     (check-equal? required '())
     (check-equal? allowed '())
     (check-exn exn:fail:contract:arity? (lambda () (draw-rounded-rect #f #f)))
     (check-exn exn:fail:contract:arity? (lambda () (draw-rounded-rect #f 0 0 #f)))
     (check-exn
      (lambda (e)
        (and (exn:fail:contract? e)
             (regexp-match? #rx"^draw-rounded-rect:" (exn-message e))
             (regexp-match? #rx"rounded-rect[?]" (exn-message e))))
      (lambda () (draw-rounded-rect #f '(0 0 1 1) #f)))
     (for ([arguments (in-list (list (list #f 0 0 -1 4 1 1 #f)
                                     (list #f 0 0 4 -1 1 1 #f)
                                     (list #f 0 0 4 4 -1 1 #f)
                                     (list #f 0 0 4 4 1 +inf.0 #f)
                                     (list #f +nan.0 0 4 4 1 1 #f)
                                     (list #f 3e38 0 3e38 4 1 1 #f)))])
       (check-exn exn:fail:contract? (lambda () (apply draw-rounded-rect arguments)))))
   (test-case "clip rounded rect requires specification"
     (check-exn exn:fail:contract? (lambda () (canvas-clip-rounded-rect! #f #f))))
   (test-case "draw color checks blend mode"
     (check-exn exn:fail:contract? (lambda () (draw-color #f 'red #:blend-mode 'nonsense))))
   (test-case "layer bounds arity checked"
     (check-exn exn:fail:contract? (lambda () (canvas-save-layer! #f #:bounds '(0 0 1)))))
   (test-case "layer bounds reject negative extent"
     (check-exn exn:fail:contract? (lambda () (canvas-save-layer! #f #:bounds '(0 0 -1 10)))))
   (test-case "query validation rejects bad canvas"
     (for ([query (in-list (list canvas-local-clip-bounds canvas-device-clip-bounds
                                 canvas-clip-empty? canvas-clip-rect?))])
       (check-exn exn:fail:contract? (lambda () (query #f)))))
   (test-case "points and layers have conservative output policies"
     (check-eq? (output-capability-status (output-capability-for 'svg 'point-sprites)) 'needs-raster)
     (check-eq? (output-capability-status (output-capability-for 'pdf 'layer)) 'native-expansion)
     (check-eq? (output-capability-status (output-capability-for 'svg 'layer)) 'needs-raster))
   (test-case "PDF text reason is backend-specific"
     (check-true
       (regexp-match? #rx"PDF"
         (output-capability-reason (output-capability-for 'pdf 'native-text)))))))
