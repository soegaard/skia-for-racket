#lang racket/base
;; Evidence helpers. Raw RGBA is encoded/reviewed by the Python inspector only
;; after semantic checks. None of these output files is normal presentation.
(require racket/class racket/file racket/list json
         "../private/gpu-io-trace.rkt"
         "../tests/gpu-dc-consumer-fixtures.rkt")
(provide observe-consumer-io! write-consumer-capture! finish-consumer-report!
         workload-id extent->json ensure-consumer! consumer-identity)
(define (workload-id workload extent target)
  (string-append target "-" (consumer-workload-scene workload) "-"
                 (consumer-workload-mode workload) "-" (car extent)))
(define (extent->json extent)
  (hasheq 'name (car extent) 'pixel_width (list-ref extent 1) 'pixel_height (list-ref extent 2)
          'logical_width (list-ref extent 3) 'logical_height (list-ref extent 4)))
(define (observe-consumer-io! proc #:capture? [capture? #f] #:present? [present? #f])
  (define ledger (box '()))
  (define result (parameterize ([current-gpu-io-ledger ledger]) (proc)))
  (define events (reverse (unbox ledger)))
  (define (of-kind kind)
    (count (lambda (e) (equal? (hash-ref e 'kind) kind)) events))
  (if capture?
      (ensure-consumer! (= (of-kind "readback") 1) "explicit capture must perform exactly one readback")
      (ensure-consumer! (zero? (of-kind "readback")) "consumer drawing/presentation performed a readback"))
  (when present?
    (ensure-consumer! (= (of-kind "present-request") 1) "normal GUI frame did not request one presentation"))
  (values result events))
(define (write-consumer-capture! directory workload extent target data layout events)
  (define id (workload-id workload extent target))
  (ensure-consumer! (= (bytes-length data) (* 4 (list-ref extent 1) (list-ref extent 2)))
                    "wrong RGBA readback size")
  (define file (string-append id ".rgba"))
  (call-with-output-file (build-path directory file)
    (lambda (out) (write-bytes data out)) #:exists 'error #:mode 'binary)
  (hasheq 'id id 'scene (consumer-workload-scene workload) 'mode (consumer-workload-mode workload)
          'target target 'extent (extent->json extent) 'file file 'layout layout 'draw_io events))
(define (finish-consumer-report! directory name token backend captures checks)
  (define report
    (hasheq 'schema 1 'stage "0.60" 'suite name 'status "passed" 'run_token token
            'backend backend 'identity (consumer-identity)
            'captures captures 'checks checks 'physical_display_verified #f))
  (call-with-output-file (build-path directory (string-append name ".json"))
    (lambda (out) (write-json report out) (newline out)) #:exists 'error)
  (printf "gpu-dc-consumers-~a: ~a captures; passed.\n" name (length captures)))
