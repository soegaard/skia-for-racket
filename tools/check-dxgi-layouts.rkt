#lang racket/base
(require json "../private/gpu-dxgi-types.rkt")
(module+ main
  (check-dxgi-layouts!)
  (write-json (hasheq 'kind "racket-ffi-layouts" 'status "passed" 'sizes (dxgi-layout-sizes)))
  (newline))
