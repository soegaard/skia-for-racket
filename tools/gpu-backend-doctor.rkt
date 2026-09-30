#lang racket/base
;; This metadata command must also work with nonexistent native-library paths.
(require json "../gpu.rkt")
(module+ main
  (write-json
   (hasheq 'schema 1 'native_probe_performed #f
           'backends (map gpu-backend-capabilities (gpu-backends))))
  (newline))
