#lang racket/base
(require json racket/cmdline racket/file racket/list
         "../main.rkt" "../tests/typeface-fixtures.rkt")
(provide generate-stream-evidence)
(define (generate-stream-evidence directory token)
  (make-directory* directory)
  (define payload (apply bytes-append (make-list 16 (apply bytes (range 256)))))
  (define pixels (bytes 255 0 0 255 0 255 0 255 0 0 255 255 255 255 255 255))
  (define (save name bytes)
    (call-with-output-file (build-path directory name)
      (lambda (out) (write-bytes bytes out)) #:mode 'binary #:exists 'error))
  (define input #f) (define output #f) (define fork #f) (define duplicate #f)
  (define source-position #f) (define detached-length #f) (define family #f)
  (dynamic-wind void
    (lambda ()
      (set! output (make-memory-output-stream))
      (for ([at (in-range 0 (bytes-length payload) 17)])
        (output-stream-write-bytes! output payload at (min (+ at 17) (bytes-length payload))))
      (set! input (output-stream-detach-input! output))
      (set! detached-length (input-stream-length input))
      (unless (= 0 (output-stream-bytes-written output)) (error 'streams "writer was not reset"))
      (input-stream-seek! input 7)
      (set! fork (input-stream-fork input))
      (set! duplicate (input-stream-duplicate input))
      (save "stream.bin" (input-stream->bytes duplicate))
      (save "tail.bin" (input-stream->bytes fork))
      (set! source-position (input-stream-position input))
      (with-skia ([file (make-file-input-stream (build-path directory "stream.bin"))])
        (unless (bytes=? payload (input-stream->bytes file)) (error 'streams "file input differs")))
      (with-skia ([image (rgba-bytes->image 2 2 pixels)])
        (define png (image->png-bytes image))
        (with-skia ([source (make-memory-input-stream png)]
                    [codec (codec-from-stream source)])
          (skia-close! source) (collect-garbage)
          (with-skia ([decoded (codec->image codec)])
            (save "decoded.rgba" (image->rgba-bytes decoded)))))
      (with-skia ([font-input (make-memory-input-stream (fixture-font-bytes))]
                  [face (typeface-from-stream font-input)])
        (skia-close! font-input) (collect-garbage)
        (set! family (typeface-family-name face))))
    (lambda ()
      (for ([s (in-list (list duplicate fork input output))] #:when s) (skia-close! s))))
  (define report
    (hasheq 'schema 1 'stage "0.75a" 'run_token token 'status "passed"
            'native_version (skia-native-version) 'length detached-length
            'source_position source-position 'file_roundtrip #t 'family family
            'streams_closed (andmap skia-closed? (list duplicate fork input output))
            'live_port_callbacks #f 'gpu_executed #f))
  (call-with-output-file (build-path directory "streams.json")
    (lambda (out) (write-json report out) (newline out)) #:exists 'error)
  (displayln "stream-native-evidence: passed"))
(module+ main
  (define directory #f) (define token #f)
  (command-line #:once-each
    [("--directory") path "New evidence directory" (set! directory path)]
    [("--token") value "Unique validator run token" (set! token value)])
  (unless (and directory token) (error 'stream-doctor "--directory and --token are required"))
  (when (directory-exists? directory) (error 'stream-doctor "evidence directory already exists"))
  (generate-stream-evidence directory token))
