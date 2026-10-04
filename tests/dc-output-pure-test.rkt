#lang racket/base
(require rackunit racket/class racket/list
         (prefix-in rd: racket/draw)
         "../private/dc-output-capture.rkt" "../private/dc-support.rkt"
         (only-in "../private/check.rkt" current-skia-byte-limit))
(provide dc-output-pure-tests dc-output-pure-test-count)
(define (fill dc [color "red"])
  (send dc set-pen "black" 1 'transparent)
  (send dc set-brush color 'solid)
  (send dc draw-rectangle 2 3 8 6))
(define (captured draw [w 32] [h 24])
  (define-values (ops _count) (capture-output-dc w h draw)) ops)
(define (kinds ops) (map output-dc-command-kind ops))
(define dc-output-pure-tests
  (test-suite
   "Document DC capture, lifetime and explicit pixel boundary"
   (test-case "empty callback does not imply a clear or raster allocation"
     (check-equal? (captured void) '()))
   (test-case "ordered requests preserve independent paint selections"
     (define ops (captured (lambda (dc) (fill dc "red") (fill dc "blue"))))
     (check-equal? (kinds ops) '(path path))
     (define command (car (output-dc-command-arguments (car ops))))
     (check-equal? (vector-ref (dc-ink-rgba (dc-draw-ink command)) 0) 255))
   (test-case "logical fractional dimensions are not rounded in public queries"
     (captured (lambda (dc)
       (check-equal? (call-with-values (lambda () (send dc get-size)) list) '(32.5 24.25))) 32.5 24.25))
   (test-case "clearing is an explicit captured operation"
     (check-equal? (kinds (captured (lambda (dc) (send dc clear)))) '(clear)))
   (test-case "copy is rejected, not an implicit whole-page screenshot"
     (check-exn exn:fail:skia-dc:unsupported?
       (lambda () (captured (lambda (dc) (send dc copy 0 0 8 6 1 1))))))
   (test-case "erase is rejected instead of losing prior document content"
     (check-exn exn:fail:skia-dc:unsupported? (lambda () (captured (lambda (dc) (send dc erase))))))
   (test-case "pixel size is not invented for vector storage"
     (check-exn exn:fail:skia-dc:unsupported? (lambda () (captured (lambda (dc) (send dc get-pixel-size))))))
   (test-case "snapshot requires the explicit output-page raster path"
     (check-exn exn:fail:skia-dc:unsupported? (lambda () (captured (lambda (dc) (send dc snapshot))))))
   (test-case "RGBA and PNG do not secretly allocate a page bitmap"
     (for ([method '(get-rgba-bytes get-png-bytes)])
       (check-exn exn:fail:skia-dc:unsupported?
         (lambda () (captured (lambda (dc) (dynamic-send dc method)))))))
   (test-case "alpha combines the ordered children as one operation"
     (define ops (captured (lambda (dc)
       (send dc start-alpha 0.5) (fill dc "red") (fill dc "blue") (send dc end-alpha))))
     (check-equal? (kinds ops) '(alpha))
     (define args (output-dc-command-arguments (car ops)))
     (check-equal? (kinds (car args)) '(path path))
     (check-= (caddr args) 0.5 1e-10))
   (test-case "nested alpha stays nested, not flattened per draw"
     (define ops (captured (lambda (dc)
       (send dc start-alpha 0.5) (send dc start-alpha 0.25)
       (fill dc) (send dc end-alpha) (send dc end-alpha))))
     (check-equal? (kinds (car (output-dc-command-arguments (car ops)))) '(alpha)))
   (test-case "unfinished alpha children are discarded"
     (check-equal? (kinds (captured (lambda (dc)
       (fill dc) (send dc start-alpha 0.5) (fill dc "blue")))) '(path)))
   (test-case "ordinary return expires the exact DC object"
     (define saved #f)
     (captured (lambda (dc) (set! saved dc) (check-true (skia-output-dc? dc))))
     (check-false (send saved ok?))
     (check-exn exn:fail? (lambda () (send saved draw-line 0 0 1 1))))
   (test-case "callback exception expires state and releases selected objects"
     (define saved #f) (define pen (rd:make-pen #:immutable? #f))
     (check-exn #rx"deliberate" (lambda () (captured (lambda (dc)
       (set! saved dc) (send dc set-pen pen) (error 'probe "deliberate")))))
     (check-false (send saved ok?))
     (check-not-exn (lambda () (send pen set-width 3))))
   (test-case "escape also expires the DC"
     (define saved #f)
     (let/ec escape (captured (lambda (dc) (set! saved dc) (escape 'escaped))))
     (check-false (send saved ok?)))
   (test-case "captured continuation cannot reactivate an expired DC"
     (define resume #f)
     (captured (lambda (_dc) (call/cc (lambda (k) (set! resume k) (void)))))
     (check-exn exn:fail? (lambda () (resume (void)))))
   (test-case "selected pen is unlocked when scope closes"
     (define pen (rd:make-pen #:immutable? #f))
     (captured (lambda (dc) (send dc set-pen pen)))
     (check-not-exn (lambda () (send pen set-width 4))))
   (test-case "expired metadata/query access cannot revive a DC"
     (define saved #f) (captured (lambda (dc) (set! saved dc)))
     (check-exn exn:fail? (lambda () (send saved get-size)))
     (check-exn exn:fail? (lambda () (send saved get-capabilities))))
   (test-case "cross-thread drawing is rejected"
     (captured (lambda (dc)
       (define ch (make-channel))
       (thread (lambda () (channel-put ch (with-handlers ([exn:fail? (lambda (_) #t)]) (fill dc) #f))))
       (check-true (channel-get ch)))))
   (test-case "nested captures reject rather than mix destinations"
     (check-exn exn:fail? (lambda () (captured (lambda (_dc) (captured void))))))
   (test-case "large vector extent does not reserve an RGBA root"
     (parameterize ([current-skia-byte-limit 4096])
       (check-equal? (kinds (captured fill 20000 20000)) '(path))))
   (test-case "existing alpha allocation guard remains conservative"
     (parameterize ([current-skia-byte-limit 16])
       (check-exn exn:fail? (lambda () (captured (lambda (dc) (send dc start-alpha 0.5)))))))
   (test-case "command limit is enforced and cleanup still expires DC"
     (define saved #f)
     (parameterize ([current-output-dc-command-limit 1])
       (check-exn #rx"command-limit" (lambda () (captured (lambda (dc)
         (set! saved dc) (fill dc) (fill dc))))))
     (check-false (send saved ok?)))
   (test-case "queued payload budget rejects accumulated data and expires the DC"
     (define saved #f)
     (parameterize ([current-skia-byte-limit 256])
       (check-exn #rx"queued command payload" (lambda () (captured (lambda (dc)
         (set! saved dc) (output-dc-special! dc 'raster (list (make-bytes 300))))))))
     (check-false (send saved ok?)))
   (test-case "capability list does not advertise unsupported pixel operations"
     (check-false (memq 'copy (hash-ref (output-dc-capabilities) 'drawing)))
     (check-false (memq 'erase (hash-ref (output-dc-capabilities) 'drawing))))
   (test-case "invalid command budgets are rejected"
     (for ([bad '(0 -1 1.5 #f)])
       (check-exn exn:fail? (lambda () (current-output-dc-command-limit bad)))))
   (test-case "invalid sizes reject before the callback"
     (for ([bad (list 0 -1 +nan.0 +inf.0 32769 #f)])
       (check-exn exn:fail? (lambda () (captured (lambda (_) (error 'wrong "callback invoked")) bad 10)))))
   (test-case "required keyword callback is rejected before construction"
     (check-exn exn:fail? (lambda () (captured (lambda (_dc #:required _x) (void))))))
   (test-case "multiple callback results do not become commands"
     (check-equal? (captured (lambda (_) (values 1 2 3))) '()))
   (test-case "annotation command captures current transform"
     (define ops (captured (lambda (dc)
       (send dc set-origin 7 9)
       (output-dc-special! dc 'destination '("target" 1 2)))))
     (check-equal? (kinds ops) '(destination))
     (check-equal? (cadr (output-dc-command-arguments (car ops))) '#(1.0 0.0 0.0 1.0 7.0 9.0)))
   (test-case "annotations inside isolated alpha groups reject"
     (check-exn exn:fail:skia-dc:unsupported? (lambda () (captured (lambda (dc)
       (send dc start-alpha 0.5) (output-dc-special! dc 'url '(0 0 4 4 "https://example.org")))))))
   (test-case "unknown private output operations reject"
     (check-exn exn:fail? (lambda () (captured (lambda (dc) (output-dc-special! dc 'invalid '()))))))
   (test-case "class capabilities are detached declarations, not probes"
     (define info (output-dc-capabilities))
     (check-true (immutable? info))
     (check-equal? (hash-ref info 'stage) "0.63")
     (check-false (hash-ref info 'native_probe_performed)))
   (test-case "plain objects are not document DCs"
     (check-false (skia-output-dc? (new object%)))
     (check-exn exn:fail? (lambda () (output-dc-special! (new object%) 'url '()))))))
(define dc-output-pure-test-count 34)
(module+ main
  (require rackunit/text-ui)
  (define failures (run-tests dc-output-pure-tests))
  (printf "dc-output-pure: ~a cases, ~a failures\n" dc-output-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
