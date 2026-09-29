#lang racket/base
;; Collection imports, run with cwd outside the source and installed package.
(require json "../main.rkt")
(module+ main
  ;; Resolve the public collection as well as this collection-invoked helper.
  (unless (eq? make-surface (dynamic-require 'skia 'make-surface))
    (error 'ci-package-smoke "public collection resolved to another package"))
  (skia-check!)
  (harfbuzz-check!)
  (with-skia ([surface (make-surface 8 8 #:background 'red)])
    (for* ([y (in-range 8)] [x (in-range 8)])
      (unless (equal? (surface-pixel surface x y) (rgb 255 0 0))
        (error 'ci-package-smoke "unexpected CPU raster pixel")))
    (with-skia ([image (image-from-bytes (surface->png-bytes surface))])
      (unless (and (= (image-width image) 8) (= (image-height image) 8))
        (error 'ci-package-smoke "PNG roundtrip dimensions differ"))
      (define pixels (image->rgba-bytes image))
      (unless (and (= (bytes-length pixels) 256)
                   (for/and ([i (in-range 0 256 4)])
                     (equal? (subbytes pixels i (+ i 4)) (bytes 255 0 0 255))))
        (error 'ci-package-smoke "PNG roundtrip pixels differ"))))
  (write-json
   (hasheq 'status "passed" 'collection (path->string (collection-path "skia"))
           'native_package_versions
           (hasheq 'skia native-package-version 'harfbuzz harfbuzz-package-version)
           'native_versions
           (hasheq 'skia (skia-native-version) 'harfbuzz (harfbuzz-native-version))
           'libraries
           (hasheq 'skia (format "~a" (skia-native-library-path))
                   'harfbuzz (format "~a" (harfbuzz-native-library-path)))
           'pixels_verified #t 'encoded_roundtrip_verified #t))
  (newline))
