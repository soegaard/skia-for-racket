#lang racket/base

;;;
;;; Output Audit Pure Test
;;;

;; Covers output audit: pure policies and provenance.
;; This source-only regression layer checks contracts and lifecycle rules before native rendering
;; is involved.

;;;
;;; Imports and Exports
;;;
(require rackunit json "../output-policy.rkt"
         (submod "../output-policy.rkt" internals)
         "../private/audit-trace.rkt" (submod "../private/audit-trace.rkt" testing))
(provide output-audit-pure-tests)

;;;
;;; Fixtures and Assertions
;;;

; fake : symbol? [symbol?] -> any/c
;   Registers a synthetic resource with the audit layer without native allocation.
(define (fake kind [who 'test]) (audit-allocate who kind (lambda () (box kind))))

; attach! : any/c any/c [symbol?] -> any
;   Records a synthetic native setter so paint-child provenance can be tested.
(define (attach! p s [setter 'sk_paint_set_shader])
  (define pp (box 'p))
  (define sp (and s (box 's)))
  (audit-use (if s (list p s) (list p)) (if s (list pp sp) (list pp))
    (lambda () (audit-native-call setter (list pp sp) void))))

; draw : any/c [symbol? procedure? symbol?] -> any
;   Routes a synthetic drawing through the canvas audit scope and selected native-operation tag.
(define (draw p [backend 'svg] [thunk void] [op 'sk_canvas_draw_rect])
  (audit-on-canvas 'draw-rect 'owner backend (fake 'surface) (if p (list p) '())
    (lambda () (audit-native-call op '() thunk))))

; capture : procedure? [symbol? symbol? boolean?] -> output-audit-report?
;   Collects a detached audit report under the chosen backend, policy, and dry-run mode.
(define (capture thunk [backend 'svg] [policy 'report] [dry? #f])
  (define-values (_ report) (call-with-audit-collector backend policy dry? 1 thunk))
  report)

; has-feature? : output-audit-report? symbol? [symbol?] -> boolean?
;   Finds a feature event, optionally requiring a specific classification status.
(define (has-feature? report feature [status #f])
  (for/or ([e (in-list (output-audit-report-events report))])
    (and (eq? (output-audit-event-feature e) feature)
         (or (not status) (eq? (output-audit-event-status e) status)))))


;;;
;;; Regression Suite
;;;

; output-audit-pure-tests : test-suite?
;   Collects the regression cases for output audit: pure policies and provenance.
(define output-audit-pure-tests
  (test-suite
   "Output audit: pure policies and provenance"
   (test-case "complete finite policy table"
     (for* ([b (in-list output-backends)] [f (in-list output-feature-names)])
       (define c (output-capability-for b f))
       (check-eq? (output-capability-backend c) b)
       (check-eq? (output-capability-feature c) f)
       (check-true (string? (output-capability-reason c)))))
   (test-case "invalid backend rejected"
     (check-exn exn:fail:contract? (lambda () (output-capability-for 'png 'geometry))))
   (test-case "unknown feature spelling rejected"
     (check-exn exn:fail:contract? (lambda () (output-capability-for 'pdf 'shdaer))))
   (test-case "embedded images are not pure vectors"
     (check-eq? (output-capability-status (output-capability-for 'svg 'image)) 'embedded-raster))
   (test-case "runtime shaders require an explicit boundary"
     (for ([b '(pdf svg)])
       (check-eq? (output-capability-status (output-capability-for b 'runtime-shader))
         'needs-raster)))
   (test-case "filter expansion differs across backends"
     (check-eq? (output-capability-status (output-capability-for 'pdf 'image-filter))
       'native-expansion)
     (check-eq? (output-capability-status (output-capability-for 'svg 'image-filter)) 'needs-raster))
   (test-case "native SVG text is viewer dependent"
     (check-eq? (output-capability-status (output-capability-for 'svg 'native-text))
       'viewer-dependent))
   (test-case "empty complete observation is vector-only"
     (define r (capture void))
     (check-false (output-audit-report-blocking? r))
     (check-true (output-audit-report-vector-only? r)))
   (test-case "runtime provenance reaches a paint"
     (define s (fake 'shader 'runtime-effect->shader))
     (define p (fake 'paint 'make-paint)) (attach! p s)
     (define r (capture (lambda () (draw p))))
     (check-true (has-feature? r 'runtime-shader 'needs-raster))
     (check-true (output-audit-report-blocking? r)))
   (test-case "report converts to JSON-safe ordinary values"
     (define r (capture (lambda () (draw (fake 'paint 'make-paint)))))
     (check-true (jsexpr? (output-audit-report->jsexpr r)))
     (check-equal? (hash-ref (output-audit-report->jsexpr r) 'backend) "svg"))
   (test-case "policy rejects before native drawing"
     (define ran? #f)
     (define p (fake 'paint 'make-paint)) (attach! p (fake 'shader 'runtime-effect->shader))
     (check-exn exn:fail:output-audit?
       (lambda () (capture (lambda () (draw p 'svg (lambda () (set! ran? #t)))) 'svg 'error)))
     (check-false ran?))
   (test-case "vector-only rejects an embedded image"
     (check-exn exn:fail:output-audit?
       (lambda () (capture (lambda () (draw #f 'svg void 'sk_canvas_draw_image)) 'svg 'vector-only))))
   (test-case "preflight suppresses target paint calls"
     (define n 0)
     (define r (capture (lambda () (draw #f 'svg (lambda () (set! n (add1 n))))) 'svg 'report #t))
     (check-equal? n 0)
     (check-eq? (output-audit-report-mode r) 'preflight)
     (check-true (has-feature? r 'geometry)))
   (test-case "export executes target calls exactly once"
     (define n 0)
     (capture (lambda () (draw #f 'svg (lambda () (set! n (add1 n))))))
     (check-equal? n 1))
   (test-case "independent raster work is not part of vector report"
     (check-equal? (output-audit-report-events (capture (lambda () (draw #f 'raster)))) '()))
   (test-case "parent keeps detached child facts"
     (define child (fake 'shader 'runtime-effect->shader))
     (define parent
       (audit-allocate 'shader-with-local-matrix 'shader
         (lambda () (audit-use (list child) (list (box 'pointer))
                       (lambda () (box 'parent))))))
     (hash-set! resources child (provenance 'shader '(linear-gradient) (hasheq)))
     (check-not-false (memq 'runtime-shader (features parent))))
   (test-case "constructor matrices preserve local-transform output limitations"
     (for ([matrix (in-list (list #f (box 'matrix)))])
       (define h
         (audit-allocate 'make-linear-gradient-shader 'shader
           (lambda ()
             (audit-native-call 'sk_shader_new_linear_gradient
                                (list 'points 'colors #f 2 0 matrix) void)
             (box 'shader))))
       (check-not-false (memq 'linear-gradient (features h)))
       (check-equal? (and (memq 'shader-local-matrix (features h)) #t) (and matrix #t))))
   (test-case "paint-copy snapshots slots"
     (define p (fake 'paint 'make-paint)) (attach! p (fake 'shader 'runtime-effect->shader))
     (define q (audit-use (list p) (list (box 'p)) (lambda () (fake 'paint 'paint-copy))))
     (attach! p #f)
     (check-true (has-feature? (capture (lambda () (draw q))) 'runtime-shader)))
   (test-case "paint getter inherits only its own slot"
     (define p (fake 'paint 'make-paint))
     (attach! p (fake 'shader 'make-linear-gradient-shader))
     (attach! p (fake 'image-filter 'make-blur-image-filter) 'sk_paint_set_imagefilter)
     (define s (audit-use (list p) (list (box 'p)) (lambda () (fake 'shader 'paint-shader))))
     (check-equal? (features s) '(linear-gradient)))
   (test-case "clearing a slot removes old risk"
     (define p (fake 'paint 'make-paint)) (attach! p (fake 'shader 'runtime-effect->shader))
     (attach! p #f)
     (check-false (output-audit-report-blocking? (capture (lambda () (draw p))))))
   (test-case "ordinary SrcOver replaces custom blender provenance"
     (define p (fake 'paint 'make-paint))
     (attach! p (fake 'blender 'runtime-effect->blender) 'sk_paint_set_blender)
     (define pp (box 'p))
     (audit-use (list p) (list pp)
       (lambda () (audit-native-call 'sk_paint_set_blendmode (list pp 3) void)))
     (check-equal? (features p) '()))
   (test-case "raster groups resolve shader serialization risks"
     (define p (fake 'paint 'make-paint)) (attach! p (fake 'shader 'runtime-effect->shader))
     (define r
       (capture (lambda () (call-with-audit-raster 'svg 20 30 (hasheq)
                             (lambda () (draw p 'raster)))) 'svg 'error))
     (check-true (has-feature? r 'runtime-shader 'rasterized))
     (check-true
      (for/and ([event (in-list (output-audit-report-events r))])
        (andmap immutable? (output-audit-event-scope event))))
     (check-false (output-audit-report-blocking? r))
     (check-false (output-audit-report-vector-only? r)))
   (test-case "rasterization cannot preserve annotations"
     (define r (capture (lambda () (call-with-audit-raster 'svg 2 2 (hasheq)
                                    (lambda () (audit-raster-annotation! 'link 'raster))))))
     (check-true (has-feature? r 'annotation 'discarded))
     (check-true (output-audit-report-blocking? r)))
   (test-case "bounded events fail rather than return a partial green report"
     (parameterize ([current-output-audit-event-limit 1])
       (check-exn exn:fail? (lambda () (capture (lambda () (draw #f) (draw #f)))))))
   (test-case "failed scope does not contaminate the next scope"
     (check-exn exn:fail? (lambda () (capture (lambda () (draw #f) (error 'probe "stop")))))
     (check-equal? (output-audit-report-events (capture void)) '()))
   (test-case "scope labels and page numbers are recorded"
     (define r (capture
                 (lambda () (parameterize ([audit-page-index 2] [audit-labels '("inner" "outer")])
                                    (draw #f)))))
     (define e (car (output-audit-report-events r)))
     (check-equal? (output-audit-event-page e) 2)
     (check-equal? (output-audit-event-scope e) '("outer" "inner")))
   (test-case "inherited collector rejects another thread"
     (define ch (make-channel))
     (capture
      (lambda ()
        (thread
          (lambda () (channel-put ch (with-handlers ([exn:fail? (lambda (_) #t)]) (draw #f) #f))))
        (check-true (channel-get ch)))))
   (test-case "recorded risks survive until picture replay"
     (define rec (fake 'picture-recorder 'make-picture-recorder))
     (define p (fake 'paint 'make-paint)) (attach! p (fake 'shader 'runtime-effect->shader))
     (audit-on-canvas 'draw-rect 'rec 'recording rec (list p)
       (lambda () (audit-native-call 'sk_canvas_draw_rect '() void)))
     (define pic
       (audit-use (list rec) (list (box 'rec))
         (lambda () (fake 'picture 'picture-recorder-finish-recording!))))
     (define r (capture
                 (lambda () (audit-on-canvas 'draw-picture 'out 'svg (fake 'svg-document) (list pic)
                              (lambda () (audit-native-call 'sk_canvas_draw_picture '() void))))))
     (check-true (has-feature? r 'runtime-shader)))
   (test-case "recorder reuse resets its feature summary"
     (define rec (fake 'picture-recorder 'make-picture-recorder))
     (hash-set! resources rec (provenance 'picture-recorder '(runtime-shader) (hasheq)))
     (define rp (box 'rec))
     (audit-use (list rec) (list rp)
       (lambda () (audit-native-call 'sk_picture_recorder_begin_recording (list rp) void)))
     (check-equal? (features rec) '()))
   (test-case "unknown canvas draws stay explicitly unknown"
     (check-true (has-feature? (capture (lambda () (draw #f 'svg void 'sk_canvas_draw_future)))
                               'unknown-operation 'unknown)))
   (test-case "nested explicit audit has separate collector state"
     (define inner #f)
     (define outer (capture (lambda () (set! inner (capture (lambda () (draw #f)))))))
     (check-equal? (length (output-audit-report-events inner)) 1)
     (check-equal? (output-audit-report-events outer) '()))))
