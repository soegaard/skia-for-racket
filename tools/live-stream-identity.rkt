#lang racket/base
(require json ffi/unsafe/os-thread "../private/native.rkt")
(module+ main
  (define p (skia-native-library-path))
  (write-json (hasheq 'path (if (path? p) (path->string p) p)
                      'racket_version (version) 'vm (symbol->string (system-type 'vm))
                      'os_threads (os-thread-enabled?)))
  (newline))
