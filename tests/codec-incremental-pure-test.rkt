#lang racket/base
(require rackunit rackunit/text-ui racket/list
         "../private/codec-incremental-input.rkt" "../private/codec-incremental-util.rkt"
         "../image-info.rkt" "../private/check.rkt" "codec-incremental-fixtures.rkt")
(provide codec-incremental-pure-tests codec-incremental-pure-test-count)
(define parts (incremental-fixture-parts))
(define header (car parts))
(define first (cadr parts))
(define codec-incremental-pure-tests
  (test-suite "Incremental input framing and detached progress"
    (test-case "empty input has no visible bytes"
      (define s (make-incremental-input 4096))
      (check-equal? (incremental-input-size s) 0) (check-equal? (incremental-input-visible s) 0))
    (test-case "split signature remains unavailable"
      (define s (make-incremental-input 4096))
      (incremental-input-append! s (subbytes header 0 5) #f)
      (check-equal? (incremental-input-visible s) 0))
    (test-case "complete signature exposes only signature"
      (define s (make-incremental-input 4096))
      (incremental-input-append! s (subbytes header 0 8) #f)
      (check-equal? (incremental-input-visible s) 8))
    (test-case "incomplete IHDR is not exposed"
      (define s (make-incremental-input 4096))
      (incremental-input-append! s (subbytes header 0 32) #f)
      (check-equal? (incremental-input-visible s) 8))
    (test-case "complete IHDR is exposed"
      (define s (make-incremental-input 4096))
      (incremental-input-append! s header #f)
      (check-equal? (incremental-input-visible s) (bytes-length header)))
    (test-case "partial IDAT body stays hidden"
      (define s (make-incremental-input 4096))
      (incremental-input-append! s (bytes-append header (subbytes first 0 20)) #f)
      (check-equal? (incremental-input-visible s) (bytes-length header)))
    (test-case "partial IDAT CRC stays hidden"
      (define s (make-incremental-input 4096))
      (incremental-input-append! s (bytes-append header (subbytes first 0 (sub1 (bytes-length first)))) #f)
      (check-equal? (incremental-input-visible s) (bytes-length header)))
    (test-case "IDAT appears when complete"
      (define s (make-incremental-input 4096))
      (incremental-input-append! s header #f)
      (incremental-input-append! s first #f)
      (check-equal? (incremental-input-visible s) (+ (bytes-length header) (bytes-length first))))
    (test-case "one-byte feeding preserves bytes"
      (define s (make-incremental-input 4096)) (define data (incremental-fixture-bytes))
      (for ([b (in-bytes data)]) (incremental-input-append! s (bytes b) #f))
      (check-equal? (incremental-input-slice s 0 (bytes-length data)) data)
      (check-equal? (incremental-input-visible s) (bytes-length data)))
    (test-case "input copies mutable caller storage"
      (define s (make-incremental-input 4096)) (define data (bytes-copy header))
      (incremental-input-append! s data #f) (bytes-fill! data 0)
      (check-equal? (incremental-input-slice s 0 (bytes-length header)) header))
    (test-case "growth preserves old prefix"
      (define s (make-incremental-input 16384))
      (incremental-input-append! s (make-bytes 4000 37) #f)
      (incremental-input-append! s (make-bytes 5000 99) #t)
      (check-equal? (incremental-input-slice s 3998 4002) (bytes 37 37 99 99)))
    (test-case "quota failure does not append or finalize"
      (define s (make-incremental-input 3))
      (incremental-input-append! s #"ab" #f)
      (check-exn exn:fail? (lambda () (incremental-input-append! s #"cd" #t)))
      (check-equal? (incremental-input-size s) 2) (check-false (incremental-input-final? s)))
    (test-case "lower current operation limit is enforced"
      (define s (make-incremental-input 10))
      (check-exn exn:fail? (lambda () (incremental-input-append! s #"abcd" #f 3)))
      (check-equal? (incremental-input-size s) 0))
    (test-case "empty finalization is explicit"
      (define s (make-incremental-input 3))
      (check-equal? (incremental-input-append! s #"" #t) 0)
      (check-true (incremental-input-final? s)))
    (test-case "sealed inputs reject more bytes"
      (define s (make-incremental-input 10)) (incremental-input-append! s #"a" #t)
      (check-exn exn:fail? (lambda () (incremental-input-append! s #"b" #f))))
    (test-case "final truncated PNG tail is exposed once"
      (define s (make-incremental-input 4096))
      (define data (bytes-append header (subbytes first 0 17)))
      (incremental-input-append! s data #t)
      (check-equal? (incremental-input-visible s) (bytes-length data)))
    (test-case "other formats require sealed input"
      (define s (make-incremental-input 100))
      (incremental-input-append! s #"not a png" #f)
      (check-equal? (incremental-input-visible s) 0)
      (incremental-input-append! s #"" #t)
      (check-equal? (incremental-input-visible s) 9))
    (test-case "oversized chunk rejects"
      (define s (make-incremental-input 100))
      (check-exn exn:fail? (lambda () (incremental-input-append! s (bytes-append #"\211PNG\r\n\32\n" #"\377\377\377\377IDAT") #f))))
    (test-case "chunk exceeding input budget rejects"
      (define s (make-incremental-input 50))
      (check-exn exn:fail? (lambda () (incremental-input-append! s (bytes-append header #"\0\0\0\20IDAT") #f))))
    (test-case "nonbytes feed rejects"
      (check-exn exn:fail? (lambda () (incremental-input-append! (make-incremental-input 30) "abc" #f))))
    (test-case "nonboolean final rejects"
      (check-exn exn:fail? (lambda () (incremental-input-append! (make-incremental-input 30) #"a" 1))))
    (test-case "zero and noninteger limits reject"
      (for ([limit '(0 -1 1.0 #f)]) (check-exn exn:fail? (lambda () (make-incremental-input limit)))))
    (test-case "success is terminal"
      (check-equal? (incremental-result-state 0 #f) 'complete)
      (check-true (incremental-terminal? 'complete)))
    (test-case "incomplete without final is resumable"
      (check-equal? (incremental-result-state 1 #f) 'needs-input)
      (check-false (incremental-terminal? 'needs-input)))
    (test-case "incomplete final is terminal"
      (check-equal? (incremental-result-state 1 #t) 'incomplete)
      (check-true (incremental-terminal? 'incomplete)))
    (test-case "native failure is not incomplete success"
      (for ([code '(2 3 4 5 6 7 8 9)]) (check-equal? (incremental-result-state code #f) 'failed)))
    (test-case "initialized rows are not a completion flag"
      (define p (make-incremental-progress 'needs-input 'incomplete-input 8))
      (check-equal? (incremental-progress-state p) 'needs-input)
      (check-equal? (incremental-progress-initialized-rows p) 8))
    (test-case "unset rows stay false"
      (check-false (incremental-progress-initialized-rows (make-incremental-progress 'needs-input 'incomplete-input #f))))
    (test-case "default options validate without native initialization"
      (check-equal? (image-info-color-type (incremental-options 'test 'rgba-8888 'unpremul 'srgb #f 4096)) 'rgba-8888))
    (test-case "BGRA premul options are explicit"
      (check-equal? (image-info-alpha-type (incremental-options 'test 'bgra-8888 'premul #f 64 4096)) 'premul))
    (test-case "unsupported target types reject"
      (for ([color '(rgba-f16 rgba-f32 gray-8 alpha-8)])
        (check-exn exn:fail? (lambda () (incremental-options 'test color 'unpremul 'srgb #f 4096)))))
    (test-case "opaque and invalid alpha reject"
      (for ([alpha '(opaque unknown #f)])
        (check-exn exn:fail? (lambda () (incremental-options 'test 'rgba-8888 alpha 'srgb #f 4096)))))
    (test-case "invalid stride rejects"
      (for ([stride '(0 -1 3 5 8.0)])
        (check-exn exn:fail? (lambda () (incremental-options 'test 'rgba-8888 'unpremul 'srgb stride 4096)))))
    (test-case "configured limit cannot exceed current limit"
      (parameterize ([current-skia-byte-limit 512])
        (check-exn exn:fail? (lambda () (incremental-options 'test 'rgba-8888 'unpremul 'srgb #f 1024)))))
    (test-case "detached progress stays readable"
      (define p (make-incremental-progress 'complete 'success 6))
      (check-equal? (incremental-progress-result p) 'success))
    (test-case "interlaced fixture also frames only complete chunks"
      (define s (make-incremental-input 8192))
      (for ([p (in-list (incremental-fixture-parts #:interlaced? #t))])
        (incremental-input-append! s p #f)
        (check-equal? (incremental-input-visible s) (incremental-input-size s))))))
(define codec-incremental-pure-test-count 36)
(module+ main
  (define failures (run-tests codec-incremental-pure-tests))
  (printf "codec-incremental-pure: ~a cases, ~a failures\n" codec-incremental-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
