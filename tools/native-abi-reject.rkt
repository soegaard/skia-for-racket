#lang racket/base
(require json racket/cmdline
         (only-in "../private/native.rkt" skia-check!)
         (only-in "../private/native-abi.rkt"
                  exn:fail:native-abi? exn:fail:native-abi-milestone
                  exn:fail:native-abi-increment))
(module+ main
  (define expected
    (command-line #:args (milestone)
      (define n (string->number milestone))
      (unless (exact-positive-integer? n) (error 'native-abi-reject "invalid milestone"))
      n))
  (define rejected #f)
  (with-handlers ([exn:fail:native-abi?
                   (lambda (e)
                     (unless (= expected (exn:fail:native-abi-milestone e)) (raise e))
                     (set! rejected #t)
                     (write-json (hasheq 'status "rejected-unsupported-abi"
                                         'milestone (exn:fail:native-abi-milestone e)
                                         'increment (exn:fail:native-abi-increment e)))
                     (newline))])
    ;; Ordinary missing-file/symbol errors deliberately fail this process.
    (skia-check!))
  (unless rejected (error 'native-abi-reject "unsupported candidate was not rejected")))
