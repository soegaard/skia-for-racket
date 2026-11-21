#lang racket/base

;; No native loading, filesystem writes or font probing on import. Old natipkg
;; fontconfig cannot resolve portable relative font paths here. Materialize a
;; verified template in the user font cache, keeping source/lib data read-only
;; and native bytes unmodified.
(require racket/file racket/path racket/string racket/list
         (only-in file/sha1 bytes->hex-string))
(provide prepare-managed-fontconfig)

(define max-configuration (* 64 1024))
(define (digest bytes) (bytes->hex-string (sha256-bytes bytes)))
(define (xml-text value)
  (string-replace (string-replace (string-replace value "&" "&amp;") "<" "&lt;") ">" "&gt;"))

;; Inputs are Racket's declared share/addon directories, never a checkout.
;; Return template/derived-file provenance without opening a native font.
(define (prepare-managed-fontconfig template font-directories font-cache)
  (unless (and (file-exists? template) (not (link-exists? template))
               (<= (file-size template) max-configuration))
    (error 'skia-fontconfig "missing, linked or oversized managed configuration template"))
  (define directories
    (for/list ([directory (in-list font-directories)])
      (define path (simplify-path (path->complete-path directory)))
      (unless (for/and ([name '("FreeSans.ttf" "FreeSerif.ttf" "FreeMono.ttf")])
                (file-exists? (build-path path name)))
        (error 'skia-fontconfig "declared draw-ttf data is incomplete: ~a" path))
      path))
  (unless (pair? directories) (error 'skia-fontconfig "declared draw-ttf support has no font directory"))
  (define original (file->bytes template))
  (define text (bytes->string/utf-8 original))
  (for ([placeholder '("@FONT_DIRECTORIES@" "@CACHE_DIRECTORY@")])
    (unless (= (length (regexp-match* (regexp (regexp-quote placeholder)) text)) 1)
      (error 'skia-fontconfig "invalid managed template placeholder: ~a" placeholder)))
  (define cache (simplify-path (path->complete-path font-cache)))
  (define configured
    (string->bytes/utf-8
     (string-replace
      (string-replace text "@FONT_DIRECTORIES@"
                      (string-join (for/list ([path (in-list directories)])
                                     (string-append "<dir>" (xml-text (path->string path)) "</dir>")) "\n  "))
      "@CACHE_DIRECTORY@" (xml-text (path->string cache)))))
  (unless (<= (bytes-length configured) max-configuration)
    (error 'skia-fontconfig "materialized configuration exceeds size limit"))
  (define hash (digest configured))
  (define configuration-directory (build-path cache "skia-native-1"))
  (make-directory* configuration-directory)
  (define target (build-path configuration-directory (string-append hash ".conf")))
  (when (link-exists? target) (error 'skia-fontconfig "configuration cache entry is a link: ~a" target))
  (unless (and (file-exists? target) (= (file-size target) (bytes-length configured))
               (equal? (file->bytes target) configured))
    (define temporary (make-temporary-file ".fontconfig-~a.tmp" #f configuration-directory))
    (dynamic-wind
      void
      (lambda ()
        (call-with-output-file temporary #:exists 'truncate (lambda (out) (write-bytes configured out)))
        (rename-file-or-directory temporary target #t))
      (lambda () (when (file-exists? temporary) (delete-file temporary)))))
  (hasheq 'origin "managed-cache" 'template_path (path->string (path->complete-path template))
          'template_sha256 (digest original) 'materialized_path (path->string target)
          'materialized_sha256 hash 'font_directories (map path->string directories)
          'cache_directory (path->string cache)))
