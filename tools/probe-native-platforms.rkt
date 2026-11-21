#lang racket/base

;; Stage A selection probe: Racket's target path semantics, never host uname.
(require setup/matching-platform json)

(module+ main
  (define selectors
    (list #rx"^(aarch64|x86_64)-macosx$"
          "win32\\x86_64"
          #rx"^x86_64-linux(-natipkg)?$"))
  (define cases
    '(("aarch64-macosx" unix 1) ("x86_64-macosx" unix 1)
      ("win32\\x86_64" windows 1)
      ("x86_64-linux" unix 1) ("x86_64-linux-natipkg" unix 1)
      ("aarch64-linux" unix 0) ("aarch64-linux-natipkg" unix 0)
      ("i386-linux" unix 0) ("win32\\i386" windows 0)
      ("win32\\arm64" windows 0) ("ppc-macosx" unix 0)
      ("x86_64-linux-musl" unix 0)))
  (for ([row (in-list cases)])
    (define target (car row))
    (define convention (cadr row))
    (define count
      (for/sum ([selector (in-list selectors)])
        (if (matching-platform?
             selector
             #:system-type (if (eq? convention 'windows) 'windows 'unix)
             #:system-library-subpath
             (bytes->path (string->bytes/utf-8 target) convention))
            1 0)))
    (unless (= count (caddr row))
      (error 'probe-native-platforms "wrong selection count for ~s: ~a" target count)))
  (write-json (hasheq 'status "passed" 'cases (length cases)
                      'racket_version (version)
                      'native_execution_qualified #f))
  (newline))
