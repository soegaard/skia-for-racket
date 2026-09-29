#lang racket/base
;; No Skia/GUI dependency: validate the selected interpreter before installing.
(require json ffi/unsafe)
(module+ main
  (write-json
   (hasheq 'os (symbol->string (system-type 'os))
           'architecture (symbol->string (system-type 'arch))
           'vm (symbol->string (system-type 'vm))
           'version (version)
           'pointer_bytes (ctype-sizeof _pointer)))
  (newline))
