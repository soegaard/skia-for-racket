#lang racket/base
(require racket/path "streams.rkt" (submod "streams.rkt" internals)
         "private/core.rkt" "private/native.rkt" "private/lifetime.rkt"
         "private/stream-resource.rkt" "private/stream-buffer.rkt")
(provide make-file-output-stream output-stream-flush!)
(define (make-file-output-stream filename #:exists [exists 'error] #:limit [limit (current-skia-byte-limit)])
  (define who 'make-file-output-stream) (stream-byte-limit who limit)
  (unless (path-string? filename) (raise-argument-error who "path-string?" filename))
  (unless (memq exists '(error replace)) (raise-argument-error who "'error or 'replace" exists))
  (define path (path->complete-path filename)) (define bytes (path->bytes path))
  (when (regexp-match? #rx#"\0" bytes) (error who "file path contains NUL"))
  (when (directory-exists? path) (error who "output target is a directory"))
  (unless (directory-exists? (path-only path)) (error who "output directory does not exist"))
  (when (and (eq? exists 'error) (or (file-exists? path) (link-exists? path))) (error who "output path exists"))
  (skia-check!)
  ;; Native constructor truncates. The caller must control the path for the
  ;; operation's lifetime; this is not an atomic O_EXCL/rename publication API.
  (make-native-stream
   (new-owned who 'stream-output
     (lambda ()
       (define ptr (sk_filewstream_new (bytes-append bytes #"\0")))
       (when (and ptr (not (sk_filewstream_is_valid ptr)))
         (sk_filewstream_destroy ptr) (error who "native output could not open destination"))
       ptr)
     sk_filewstream_destroy)
   'output 'file limit))
(define (output-stream-flush! stream)
  (with-output 'output-stream-flush! stream (lambda (p _n) (sk_wstream_flush p))) (void))
