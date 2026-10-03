#lang racket/base
;; Exercises the real dc<%> implementation with an instrumented non-native
;; renderer. This is not evidence of GPU execution or GUI initialization.
(require rackunit racket/class racket/list
         (prefix-in rd: racket/draw)
         "../gpu-dc.rkt" "../private/dc-support.rkt" "../private/gpu-dc-scope.rkt"
         (only-in "../private/check.rkt" current-skia-byte-limit))
(provide gpu-dc-pure-tests gpu-dc-pure-test-count)
(struct target (width height [closed? #:mutable]) #:transparent)
(define (make-probe #:bad-close? [bad-close? #f] #:bad-create? [bad-create? #f])
  (define events (box '()))
  (define (record tag . args) (set-box! events (cons (cons tag args) (unbox events))))
  (define renderer
    (dc-renderer/styles
     (lambda (w h)
       (when bad-create? (error 'probe "allocation failed"))
       (define t (target w h #f)) (record 'create t) t)
     (lambda (t)
       (when (target-closed? t) (error 'probe "double close"))
       (set-target-closed?! t #t) (record 'close t)
       (when bad-close? (error 'probe "release failed")))
     (lambda (t command) (record 'draw t command))
     (lambda (t clip color erase?) (record 'clear t clip color erase?))
     (lambda (t) (record 'snapshot t) 'detached-snapshot)
     (lambda (t premul?) (record 'rgba t premul?) #"rgba")
     (lambda (t) (record 'png t) #"png")
     (lambda (t request) (record 'measure t request) (values 11.0 12.0 3.0 1.0))
     (lambda args (apply record 'text args))
     (lambda (_t _request _char) #t)
     (lambda args (apply record 'bitmap args))
     (lambda args (apply record 'copy args))
     (lambda args (apply record 'composite args))
     (lambda (_commands _kind _ink) (values 0.0 0.0 10.0 20.0))))
  (values renderer events))
(define extent (checked-frame-size 80 60 40 20))
(define (entries events tag)
  (filter (lambda (event) (eq? (car event) tag)) (reverse (unbox events))))
(define (scope proc #:extent [size extent] #:clear? [clear? #f])
  (define-values (renderer events) (make-probe))
  (call-with-frame-dc/renderer renderer size proc
    (lambda (root) (set-box! events (cons (list 'commit root) (unbox events))))
    #:clear? clear?)
  events)
(define (fill dc)
  (send dc set-pen "black" 1 'transparent)
  (send dc set-brush "blue" 'solid)
  (send dc draw-rectangle 1 2 8 6))
(define (draw-command events) (caddr (car (entries events 'draw))))
(define gpu-dc-pure-tests
  (test-suite
   "Frame-scoped GPU DC state, scaling and lifetime (no native renderer)"
   (test-case "capabilities are detached declarations and predicate rejects unrelated objects"
     (check-true (immutable? (skia-gpu-dc-capabilities)))
     (check-equal? (hash-ref (skia-gpu-dc-capabilities) 'stage) "0.59")
     (check-false (hash-ref (skia-gpu-dc-capabilities) 'native_probe_performed))
     (check-false (skia-gpu-dc? #f))
     (check-false (skia-gpu-dc? (new object%))))
   (test-case "actual dimensions yield independent device scales"
     (check-equal? (checked-frame-size 80 60 40 20) (dc-frame-size 80 60 40.0 20.0 2.0 3.0))
     (define e (checked-frame-size 101 77 40.5 30.5))
     (check-= (dc-frame-size-scale-x e) (/ 101 40.5) 1e-12)
     (check-= (dc-frame-size-scale-y e) (/ 77 30.5) 1e-12))
   (test-case "invalid geometry fails before construction"
     (for ([args (in-list '((0 60 40 20) (80 -1 40 20) (80.5 60 40 20)
                           (80 60 0 20) (80 60 40 -1) (80 60 +inf.0 20)
                           (80 60 40 +nan.0)))])
       (check-exn exn:fail? (lambda () (apply checked-frame-size args)))))
   (test-case "physical allocation respects the existing byte limit"
     (parameterize ([current-skia-byte-limit 100])
       (check-exn exn:fail? (lambda () (checked-frame-size 80 60 40 20)))))
   (test-case "forged scale metadata is rejected before allocation"
     (define-values (r events) (make-probe))
     (check-exn exn:fail?
       (lambda () (call-with-frame-dc/renderer r (dc-frame-size 80 60 40.0 20.0 1.0 1.0) void void)))
     (check-equal? (unbox events) '()))
   (test-case "logical size and device scale differ from actual allocation size"
     (scope (lambda (dc)
       (check-true (skia-gpu-dc? dc)) (check-true (is-a? dc rd:dc<%>))
       (check-equal? (call-with-values (lambda () (send dc get-size)) list) '(40.0 20.0))
       (check-equal? (call-with-values (lambda () (send dc get-pixel-size)) list) '(80 60))
       (check-equal? (call-with-values (lambda () (send dc get-device-scale)) list) '(2.0 3.0))
       (check-equal? (send dc get-backing-scale) 1.0)
       (check-equal? (send dc get-initial-matrix) dc-identity))))
   (test-case "fractional logical dimensions do not round-trip through scalar backing scale"
     (scope (lambda (dc)
       (check-equal? (call-with-values (lambda () (send dc get-size)) list) '(40.5 30.5))
       (check-equal? (call-with-values (lambda () (send dc get-pixel-size)) list) '(101 77)))
       #:extent (checked-frame-size 101 77 40.5 30.5)))
   (test-case "geometry is mapped once at the renderer boundary"
     (define events (scope fill))
     (check-equal? (dc-draw-matrix (draw-command events)) '#(2.0 0.0 0.0 3.0 0.0 0.0))
     (check-equal? (vector->list (car (dc-draw-commands (draw-command events)))) '(move 1.0 2.0)))
   (test-case "user transforms remain logical while drawing is physically scaled"
     (define events (scope (lambda (dc)
       (send dc set-origin 4 5) (send dc set-scale 2 4)
       (check-equal? (call-with-values (lambda () (send dc get-origin)) list) '(4.0 5.0))
       (fill dc))))
     (check-equal? (dc-draw-matrix (draw-command events)) '#(4.0 0.0 0.0 12.0 8.0 15.0)))
   (test-case "clip paths use both device scales"
     (define events (scope (lambda (dc) (send dc set-clipping-rect 1 2 8 6) (fill dc))))
     (define clip (dc-draw-clip (draw-command events)))
     (define p (car (dc-clip-paths clip)))
     (check-equal? (car (dc-clip-path-commands p)) '#(move 2.0 6.0)))
   (test-case "region query extents remain logical"
     (scope (lambda (dc)
       (define-values (w h matrix clipping) (send dc dc-region-query-info))
       (check-equal? (list w h) '(40.0 20.0))
       (check-equal? matrix dc-identity) (check-false clipping))))
   (test-case "text metrics remain logical and text drawing scales once"
     (define events (scope (lambda (dc)
       (check-equal? (call-with-values (lambda () (send dc get-text-extent "abc")) list)
                     '(11.0 12.0 3.0 1.0))
       (send dc draw-text "abc" 2 3))))
     (check-equal? (list-ref (car (entries events 'text)) 3) '#(2.0 0.0 0.0 3.0 0.0 0.0)))
   (test-case "bitmap target geometry scales without changing source rectangles"
     (define bitmap (make-object rd:bitmap% 4 3 #f #t))
     (define events (scope (lambda (dc) (check-true (send dc draw-bitmap bitmap 1 2)))))
     (define e (car (entries events 'bitmap)))
     (check-equal? (list-ref e 4) '#(2.0 0.0 0.0 3.0 0.0 0.0)))
   (test-case "copy receives a physical matrix and logical source/destination coordinates"
     (define events (scope (lambda (dc) (send dc copy 1 2 5 6 7 8))))
     (define e (car (entries events 'copy)))
     (check-equal? (list-ref e 2) '#(2.0 0.0 0.0 3.0 0.0 0.0))
     (check-equal? (drop e 4) '(1 2 5 6 7 8)))
   (test-case "alpha children have physical size and completed groups composite once"
     (define events (scope (lambda (dc) (send dc start-alpha 0.5) (fill dc) (send dc end-alpha))))
     (check-equal? (length (entries events 'create)) 2)
     (for ([e (in-list (entries events 'create))])
       (check-equal? (list (target-width (cadr e)) (target-height (cadr e))) '(80 60)))
     (check-equal? (length (entries events 'composite)) 1)
     (check-equal? (length (entries events 'close)) 2))
   (test-case "unfinished groups are discarded before commit, not merged"
     (define events (scope (lambda (dc) (send dc start-alpha 0.5) (fill dc))))
     (check-equal? (entries events 'composite) '())
     (check-equal? (map car (reverse (unbox events))) '(create create draw close commit close)))
   (test-case "nested groups are all released on normal completion"
     (define events (scope (lambda (dc) (send dc start-alpha 0.5) (send dc start-alpha 0.5) (fill dc))))
     (check-equal? (length (entries events 'create)) 3)
     (check-equal? (length (entries events 'close)) 3)
     (check-equal? (entries events 'composite) '()))
   (test-case "frame auto-clear is explicit and can be disabled for borrowed surfaces"
     (check-equal? (length (entries (scope void #:clear? #t) 'clear)) 1)
     (check-equal? (entries (scope void #:clear? #f) 'clear) '()))
   (test-case "ordinary drawing never calls public CPU-transfer callbacks"
     (define events (scope (lambda (dc) (fill dc) (send dc start-alpha 0.4) (fill dc) (send dc end-alpha))))
     (for ([kind '(snapshot rgba png)]) (check-equal? (entries events kind) '())))
   (test-case "explicit transfer methods dispatch only when requested"
     (define events (scope (lambda (dc)
       (check-eq? (send dc snapshot) 'detached-snapshot)
       (check-equal? (send dc get-rgba-bytes #:premultiplied? #t) #"rgba")
       (check-equal? (send dc get-png-bytes) #"png"))))
     (for ([kind '(snapshot rgba png)]) (check-equal? (length (entries events kind)) 1)))
   (test-case "callback values survive cleanup and commit"
     (define-values (r events) (make-probe))
     (check-equal?
       (call-with-values (lambda () (call-with-frame-dc/renderer r extent (lambda (_) (values 1 2 3)) void)) list)
       '(1 2 3))
     (check-equal? (length (entries events 'close)) 1))
   (test-case "saved DC is closed, including pure state methods and metadata"
     (define saved #f)
     (scope (lambda (dc) (set! saved dc)))
     (check-true (skia-gpu-dc? saved)) (check-false (send saved ok?))
     (for ([proc (in-list (list (lambda () (fill saved)) (lambda () (send saved get-size))
                               (lambda () (send saved get-device-scale))
                               (lambda () (send saved get-capabilities))
                               (lambda () (send saved get-pen)) (lambda () (send saved snapshot))))])
       (check-exn exn:fail? proc))
     (check-not-exn (lambda () (send saved close))))
   (test-case "a later frame never reactivates a saved DC"
     (define a #f) (define b #f)
     (scope (lambda (dc) (set! a dc)))
     (scope (lambda (dc) (set! b dc) (check-false (send a ok?)) (check-false (eq? a b))))
     (check-false (send a ok?)) (check-false (send b ok?)))
   (test-case "callback exception discards groups, releases root and cancels commit"
     (define-values (r events) (make-probe)) (define committed? #f) (define saved #f)
     (check-exn #rx"callback failed"
       (lambda () (call-with-frame-dc/renderer r extent
         (lambda (dc) (set! saved dc) (send dc start-alpha 0.4) (error 'probe "callback failed"))
         (lambda (_) (set! committed? #t)))))
     (check-false committed?) (check-false (send saved ok?))
     (check-equal? (length (entries events 'close)) 2))
   (test-case "non-exception raised values are preserved even when cleanup fails"
     (define-values (r events) (make-probe #:bad-close? #t))
     (define result (with-handlers ([(lambda (_) #t) values])
       (call-with-frame-dc/renderer r extent (lambda (_) (raise 'original)) void)))
     (check-eq? result 'original)
     (check-equal? (length (entries events 'close)) 1))
   (test-case "cleanup errors after successful painting are not reported as success"
     (define-values (r events) (make-probe #:bad-close? #t))
     (check-exn #rx"release failed" (lambda () (call-with-frame-dc/renderer r extent void void)))
     (check-equal? (length (entries events 'close)) 1))
   (test-case "allocation failure cannot invoke the callback or commit"
     (define-values (r events) (make-probe #:bad-create? #t))
     (check-exn #rx"allocation failed"
       (lambda () (call-with-frame-dc/renderer r extent
         (lambda (_) (error 'probe "unexpected callback"))
         (lambda (_) (error 'probe "unexpected commit")))))
     (check-equal? (unbox events) '()))
   (test-case "commit failure still closes the DC and root"
     (define-values (r events) (make-probe)) (define saved #f)
     (check-exn #rx"commit failed"
       (lambda () (call-with-frame-dc/renderer r extent (lambda (dc) (set! saved dc))
         (lambda (_) (error 'probe "commit failed")))))
     (check-false (send saved ok?)) (check-equal? (length (entries events 'close)) 1))
   (test-case "selected mutable styles unlock when the scope exits"
     (define pen (new rd:pen% [color "red"] [width 2]))
     (scope (lambda (dc)
       (send dc set-pen pen)
       (check-eq? (send dc get-pen) pen)
       (check-exn exn:fail? (lambda () (send pen set-width 3)))))
     (check-not-exn (lambda () (send pen set-width 3))))
   (test-case "nested DC scopes reject without disturbing the outer scope"
     (define-values (r events) (make-probe))
     (scope (lambda (dc)
       (check-exn #rx"nested" (lambda () (call-with-frame-dc/renderer r extent void void)))
       (fill dc)))
     (check-equal? (unbox events) '()))
   (test-case "wrong-thread drawing rejects while the scope is live"
     (scope (lambda (dc)
       (define answer (make-channel))
       (thread (lambda () (channel-put answer
         (with-handlers ([exn:fail? (lambda (_) 'rejected)]) (send dc get-size) 'accepted))))
       (check-eq? (sync/timeout 5 answer) 'rejected)
       (check-true (send dc ok?)))))
   (test-case "escaping the callback cancels commit and still expires the DC"
     (define-values (r events) (make-probe)) (define saved #f) (define committed? #f)
     (check-eq? (let/ec escape
       (call-with-frame-dc/renderer r extent
         (lambda (dc) (set! saved dc) (escape 'escaped))
         (lambda (_) (set! committed? #t)))) 'escaped)
     (check-false committed?) (check-false (send saved ok?))
     (check-equal? (length (entries events 'close)) 1))
   (test-case "a captured callback continuation cannot reenter a closed scope"
     (define k #f)
     (scope (lambda (_dc) (call/cc (lambda (saved) (set! k saved)))))
     (check-exn exn:fail? (lambda () (k 'resume))))))
(define gpu-dc-pure-test-count 33)
(module+ main
  (require rackunit/text-ui)
  (define failures (run-tests gpu-dc-pure-tests))
  (printf "gpu-dc-pure: ~a cases, ~a failures; real DC class, instrumented renderer, no GPU.\n"
          gpu-dc-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
