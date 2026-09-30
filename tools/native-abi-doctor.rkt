#lang racket/base
(require json "../native-capabilities.rkt")
(module+ main
  (define report (skia-native-capabilities))
  (unless (and (hash-ref report 'required_cpu_symbols_resolved #f)
               (hash-ref report 'racket_layouts_checked #f))
    (error 'native-abi-doctor "incomplete native ABI preflight"))
  (write-json report)
  (newline))
