#lang racket/base

;; Declared test/document data. This helper never changes the system font
;; manager and reads/opens fonts only when explicitly called.
(require racket/path)
(provide catalog-font-directory catalog-font-path)
(define (catalog-font-directory)
  (build-path (collection-path "skia-fonts-1") "fonts"))
(define (catalog-font-path filename)
  (unless (member filename '("NotoSans-Regular.ttf" "NotoSansArabic-Regular.ttf"
                             "NotoSansHebrew-Regular.ttf" "NotoSansCJKjp-Regular.otf"))
    (raise-argument-error 'catalog-font-path "a declared catalog font filename" filename))
  (build-path (catalog-font-directory) filename))
