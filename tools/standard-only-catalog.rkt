#lang racket/base
;; Retain exact staged standard dependencies, excluding all candidate names.
;; Absolute file URLs keep the dependency snapshot relocations unambiguous.
(require racket/file racket/path racket/cmdline net/url)
(module+ main
  (command-line #:args (source destination)
    (define base (path->url (path->directory-path (path->complete-path source))))
    (define candidates '("skia" "skia-lib" "skia-doc" "skia-native-macos-1"
                         "skia-native-win32-x86_64-1" "skia-native-x86_64-linux-1"))
    (define all (file->value (build-path source "pkgs-all")))
    (define result
      (for/hash ([(name data) (in-hash all)] #:unless (member name candidates))
        (values name (hash-set data 'source
                              (url->string (combine-url/relative base (hash-ref data 'source)))))))
    (make-directory* (build-path destination "pkg"))
    (for ([(name data) (in-hash result)])
      (write-to-file data (build-path destination "pkg" name) #:exists 'error))
    (write-to-file result (build-path destination "pkgs-all") #:exists 'error)
    (write-to-file (sort (hash-keys result) string<?) (build-path destination "pkgs") #:exists 'error)))
