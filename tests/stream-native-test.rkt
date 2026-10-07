#lang racket/base
(require rackunit rackunit/text-ui racket/file racket/list
         "../main.rkt" "typeface-fixtures.rkt")
(provide stream-native-tests stream-native-test-count)
(define stream-native-test-count 39) ; replaced from actual source case count
(define (with-file bytes proc)
  (define path (make-temporary-file "skia-stream-~a.bin"))
  (dynamic-wind
    (lambda () (call-with-output-file path (lambda (out) (write-bytes bytes out)) #:exists 'truncate))
    (lambda () (proc path))
    (lambda () (delete-file path))))
(define (fixture-png)
  (with-skia ([im (rgba-bytes->image 2 2 (apply bytes-append (make-list 4 (bytes 255 0 0 255))))])
    (image->png-bytes im)))
(define (fixture-picture)
  (call-with-picture 16 12
    (lambda (c) (with-skia ([p (make-paint #:color 'red)]) (draw-rect c 0 0 16 12 p)))))
(define stream-native-tests
  (test-suite "Native streams and buffered port consumers"
    (test-case "empty memory input"
      (with-skia ([s (make-memory-input-stream #"")])
        (check-true (skia-resource? s)) (check-true (skia-input-stream? s))
        (check-equal? (input-stream-length s) 0)
        (check-equal? (input-stream-read-bytes s 0) #"")
        (check-true (eof-object? (input-stream-read-bytes s 1)))))
    (test-case "input copies caller bytes"
      (define source (bytes 1 2 3))
      (with-skia ([s (make-memory-input-stream source)])
        (bytes-set! source 0 99) (check-equal? (input-stream->bytes s) (bytes 1 2 3))))
    (test-case "read position and EOF"
      (with-skia ([s (make-memory-input-stream #"abc")])
        (check-equal? (input-stream-read-bytes s 2) #"ab")
        (check-equal? (input-stream-position s) 2)
        (check-equal? (input-stream-read-bytes s 10) #"c")
        (check-true (input-stream-at-end? s))
        (check-true (eof-object? (input-stream-read-bytes s 1)))))
    (test-case "peek does not advance"
      (with-skia ([s (make-memory-input-stream #"abc")])
        (check-equal? (input-stream-peek-bytes s 2) #"ab")
        (check-equal? (input-stream-position s) 0)))
    (test-case "absolute and relative seek"
      (with-skia ([s (make-memory-input-stream #"abcdef")])
        (input-stream-seek! s 4) (input-stream-move! s -2)
        (check-equal? (input-stream-read-bytes s 2) #"cd")
        (input-stream-rewind! s) (check-equal? (input-stream-position s) 0)))
    (test-case "out-of-range seeks are not silently clamped"
      (with-skia ([s (make-memory-input-stream #"abc")])
        (check-exn exn:fail? (lambda () (input-stream-seek! s 4)))
        (check-exn exn:fail? (lambda () (input-stream-move! s -1)))
        (check-equal? (input-stream-position s) 0)))
    (test-case "skip returns actual byte count"
      (with-skia ([s (make-memory-input-stream #"abc")])
        (check-equal? (input-stream-skip! s 9) 3)
        (check-equal? (input-stream-skip! s 1) 0)))
    (test-case "duplicate starts at zero; fork at current cursor"
      (with-skia ([s (make-memory-input-stream #"abcdef")])
        (input-stream-seek! s 2)
        (with-skia ([d (input-stream-duplicate s)] [f (input-stream-fork s)])
          (check-equal? (input-stream-position d) 0)
          (check-equal? (input-stream-position f) 2)
          (check-equal? (input-stream->bytes d) #"abcdef")
          (check-equal? (input-stream->bytes f) #"cdef")
          (check-equal? (input-stream-position s) 2))))
    (test-case "duplicate survives original close and GC"
      (define s (make-memory-input-stream #"abc"))
      (with-skia ([copy (input-stream-duplicate s)])
        (skia-close! s) (collect-garbage)
        (check-equal? (input-stream->bytes copy) #"abc")))
    (test-case "native file input and independent fork"
      (with-file #"abcdef"
        (lambda (path)
          (with-skia ([s (make-file-input-stream path)])
            (input-stream-seek! s 2)
            (with-skia ([f (input-stream-fork s)])
              (check-equal? (input-stream->bytes f) #"cdef")
              (check-equal? (input-stream-position s) 2))))))
    (test-case "file constructor rejects over-limit input"
      (with-file #"abc" (lambda (path)
                         (check-exn exn:fail? (lambda () (make-file-input-stream path #:limit 2))))))
    (test-case "memory constructor rejects over-limit input"
      (check-exn exn:fail? (lambda () (make-memory-input-stream #"abc" #:limit 2))))
    (test-case "data construction uses remaining bytes and advances"
      (with-skia ([s (make-memory-input-stream #"abcdef")])
        (input-stream-seek! s 3)
        (check-equal? (input-stream->bytes s) #"def")
        (check-equal? (input-stream-position s) 6)
        (check-equal? (input-stream->bytes s) #"")))
    (test-case "all operations reject a closed stream"
      (define s (make-memory-input-stream #"abc")) (skia-close! s)
      (check-true (skia-closed? s)) (skia-close! s)
      (for ([operation (in-list (list input-stream-length input-stream-position input-stream->bytes
                                      input-stream-fork input-stream-duplicate input-stream-at-end?))])
        (check-exn exn:fail? (lambda () (operation s)))))
    (test-case "input cross-thread access rejects"
      (with-skia ([s (make-memory-input-stream #"abc")])
        (define result (make-channel))
        (thread (lambda () (channel-put result (with-handlers ([exn:fail? (lambda (_) 'rejected)])
                                                   (input-stream->bytes s)))))
        (check-equal? (channel-get result) 'rejected)))
    (test-case "output accumulates binary writes"
      (with-skia ([s (make-memory-output-stream)])
        (check-true (skia-output-stream? s)) (check-true (skia-resource? s))
        (check-equal? (output-stream-write-bytes! s #"abc") 3)
        (check-equal? (output-stream-write-bytes! s (bytes 0 255)) 2)
        (check-equal? (output-stream-bytes-written s) 5)
        (check-equal? (output-stream->bytes s) (bytes 97 98 99 0 255))))
    (test-case "output byte slice"
      (with-skia ([s (make-memory-output-stream)])
        (output-stream-write-bytes! s #"012345" 1 4)
        (check-equal? (output-stream->bytes s) #"123")))
    (test-case "output snapshot is independent and non-destructive"
      (with-skia ([s (make-memory-output-stream)])
        (output-stream-write-bytes! s #"abc")
        (define bytes (output-stream->bytes s))
        (bytes-set! bytes 0 0)
        (check-equal? (output-stream->bytes s) #"abc")))
    (test-case "output budget fails before mutation"
      (with-skia ([s (make-memory-output-stream #:limit 3)])
        (output-stream-write-bytes! s #"ab")
        (check-exn exn:fail? (lambda () (output-stream-write-bytes! s #"cd")))
        (check-equal? (output-stream->bytes s) #"ab")))
    (test-case "empty write and detach"
      (with-skia ([s (make-memory-output-stream)])
        (check-equal? (output-stream-write-bytes! s #"") 0)
        (with-skia ([input (output-stream-detach-input! s)])
          (check-equal? (input-stream->bytes input) #""))))
    (test-case "detach resets writer but owns the old blocks"
      (define s (make-memory-output-stream))
      (output-stream-write-bytes! s #"first")
      (with-skia ([input (output-stream-detach-input! s)])
        (check-equal? (output-stream-bytes-written s) 0)
        (output-stream-write-bytes! s #"second") (skia-close! s) (collect-garbage)
        (check-equal? (input-stream->bytes input) #"first")))
    (test-case "lower current limit is respected"
      (with-skia ([s (make-memory-input-stream #"abcdef")])
        (parameterize ([current-skia-byte-limit 4])
          (check-exn exn:fail? (lambda () (input-stream->bytes s))))))
    (test-case "buffered input drops dependence on Racket port"
      (define in (open-input-bytes #"abc"))
      (with-skia ([s (buffered-port->input-stream in #:close? #t)])
        (check-true (port-closed? in)) (check-equal? (input-stream->bytes s) #"abc")))
    (test-case "buffered output leaves source untouched"
      (with-skia ([s (make-memory-output-stream)])
        (output-stream-write-bytes! s #"abc")
        (define out (open-output-bytes))
        (check-equal? (output-stream-write-port/buffered s out) 3)
        (check-equal? (get-output-bytes out) #"abc")
        (check-equal? (output-stream->bytes s) #"abc")))
    (test-case "codec takes private duplicate; source cursor unchanged"
      (define s (make-memory-input-stream (fixture-png)))
      (input-stream-seek! s 3)
      (with-skia ([codec (codec-from-stream s)])
        (check-equal? (input-stream-position s) 3)
        (skia-close! s) (collect-garbage)
        (with-skia ([image (codec->image codec)])
          (check-equal? (image-width image) 2)
          (check-equal? (image->rgba-bytes image) (apply bytes-append (make-list 4 (bytes 255 0 0 255)))))))
    (test-case "file-backed codec outlives its original stream"
      (with-file (fixture-png)
        (lambda (path)
          (define s (make-file-input-stream path))
          (with-skia ([codec (codec-from-stream s)])
            (skia-close! s) (collect-garbage)
            (with-skia ([image (codec->image codec)]) (check-equal? (image-width image) 2))))))
    (test-case "file-backed typeface outlives its original stream"
      (with-file (fixture-font-bytes)
        (lambda (path)
          (define s (make-file-input-stream path))
          (with-skia ([face (typeface-from-stream s)])
            (skia-close! s) (collect-garbage)
            (check-equal? (typeface-family-name face) fixture-family)))))
    (test-case "buffered nonseekable codec input"
      (define-values (in out) (make-pipe))
      (write-bytes (fixture-png) out) (close-output-port out)
      (with-skia ([codec (codec-from-port/buffered in #:close? #t)])
        (check-true (port-closed? in))
        (check-equal? (encoded-image-info-height (codec-info codec)) 2)))
    (test-case "codec rejection does not consume caller stream"
      (with-skia ([s (make-memory-input-stream #"not an image")])
        (check-exn exn:fail? (lambda () (codec-from-stream s)))
        (check-equal? (input-stream->bytes s) #"not an image")))
    (test-case "buffered port codec"
      (with-skia ([codec (codec-from-port/buffered (open-input-bytes (fixture-png)))])
        (check-equal? (encoded-image-info-width (codec-info codec)) 2)))
    (test-case "buffered port image"
      (with-skia ([image (image-from-port/buffered (open-input-bytes (fixture-png)))])
        (check-equal? (image-height image) 2)))
    (test-case "typeface retains native data after stream close"
      (define s (make-memory-input-stream (fixture-font-bytes)))
      (input-stream-seek! s 7)
      (with-skia ([tf (typeface-from-stream s)])
        (check-equal? (input-stream-position s) 7) (skia-close! s) (collect-garbage)
        (check-equal? (typeface-family-name tf) fixture-family)
        (with-skia ([f (make-font tf)]) (check-true (positive? (font-char->glyph f #\A))))))
    (test-case "typeface constructor failure leaves source valid"
      (with-skia ([s (make-memory-input-stream #"bad font")])
        (check-exn exn:fail? (lambda () (typeface-from-stream s)))
        (check-equal? (input-stream-position s) 0)))
    (test-case "buffered TTC face index"
      (with-skia ([tf (typeface-from-port/buffered (open-input-bytes (fixture-collection-bytes)) #:index 1)])
        (check-equal? (typeface-weight tf) 700)))
    (test-case "invalid font index rejected before reading port"
      (define in (open-input-bytes #"abc"))
      (check-exn exn:fail? (lambda () (typeface-from-port/buffered in #:index -1)))
      (check-equal? (read-byte in) 97))
    (test-case "picture stream remains independent and preserves cull size"
      (with-skia ([picture (fixture-picture)] [s (make-memory-input-stream (picture->bytes picture))])
        (input-stream-seek! s 5)
        (with-skia ([copy (picture-from-stream s #:trusted? #t)])
          (check-equal? (input-stream-position s) 5) (skia-close! s)
          (with-skia ([image (picture->image copy 16 12)])
            (check-equal? (image->rgba-bytes image) (apply bytes-append (make-list (* 16 12) (bytes 255 0 0 255))))))))
    (test-case "untrusted picture is rejected before port I/O"
      (define in (open-input-bytes #"not read"))
      (check-exn exn:fail? (lambda () (picture-from-port/buffered in)))
      (check-equal? (read-byte in) 110))
    (test-case "bad SKP header rejects without consuming original"
      (with-skia ([s (make-memory-input-stream (make-bytes 40))])
        (check-exn exn:fail? (lambda () (picture-from-stream s #:trusted? #t)))
        (check-equal? (input-stream-position s) 0)))
    (test-case "loaded picture keeps unknown audit provenance"
      (with-skia ([pic (fixture-picture)]
                  [copy (picture-from-port/buffered (open-input-bytes (picture->bytes pic)) #:trusted? #t)])
        (define page (make-output-page 16 12 (lambda (c) (draw-picture c copy))))
        (check-exn exn:fail:output-audit? (lambda () (output->bytes/audit page 'pdf #:policy 'error)))))))
(module+ main
  (define failures (run-tests stream-native-tests))
  (printf "stream-native: ~a cases, ~a failures\n" stream-native-test-count failures)
  (exit (if (zero? failures) 0 1)))
