#lang racket/base

;;;
;;; Reference I/O Test
;;;

;; Checks native stream ownership, codec snapshots, bottom-up rows, incremental completion, and live
;; ports.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Native CPU and managed-stream acceptance. No fonts, GUI, or GPU are required.
;; These tests must fail rather than skip when the required native bridge is absent.
(require rackunit racket/file racket/list skia)


;;;
;;; Diagnostic Operations
;;;

; sample-png : -> bytes?
;;   Encodes a two-by-three red raster image for image and codec examples.
(define (sample-png)
  (with-skia ([surface (make-surface 2 3 #:background 'red)])
    (surface->png-bytes surface)))


; bottom-up-bmp : -> bytes?
;;   Builds a two-by-three 24-bit BMP with padded bottom-up rows and distinguishable pixel colors.
(define (bottom-up-bmp)
  ;; Two pixels per row, three rows, uncompressed BGR24, four-byte row alignment.
  ;; Top-to-bottom colors: red/green, blue/white, yellow/black.
  (define output (make-bytes 78))
  (define (put offset value size)
    (bytes-copy! output offset (integer->integer-bytes value size #f #f)))
  (bytes-copy! output 0 #"BM")
  (for ([offset '(2 10 14 18 22 26 28 34)] [value '(78 54 40 2 3 1 24 24)]
        [size '(4 4 4 4 4 2 2 4)])
    (put offset value size))
  (bytes-copy! output 54 (bytes 0 255 255 0 0 0 0 0))
  (bytes-copy! output 62 (bytes 255 0 0 255 255 255 0 0))
  (bytes-copy! output 70 (bytes 0 0 255 0 255 0 0 0))
  output)

(module+ test
  (test-case "memory input copies bytes and distinguishes zero reads from EOF"
    (define bytes (bytes-copy #"abc"))
    (with-skia ([input (make-memory-input-stream bytes)])
      (bytes-fill! bytes 0)
      (check-equal? (input-stream-peek-bytes input 2) #"ab")
      (check-equal? (input-stream-position input) 0)
      (check-equal? (input-stream-read-bytes input 9) #"abc")
      (check-equal? (input-stream-read-bytes input 0) #"")
      (check-true (eof-object? (input-stream-read-bytes input 1)))
      (check-equal? (input-stream->bytes input) #"")))

  (test-case "fork and duplicate preserve different initial cursors and independent owners"
    (with-skia ([input (make-memory-input-stream #"abcdef")])
      (input-stream-seek! input 2)
      (with-skia ([duplicate (input-stream-duplicate input)] [fork (input-stream-fork input)])
        (skia-close! input)
        (check-equal? (input-stream-length fork) 6)
        (check-equal? (input-stream->bytes fork) #"cdef")
        (check-equal? (input-stream->bytes duplicate) #"abcdef"))))

  (test-case "invalid seek does not consume bytes and relative motion uses current position"
    (with-skia ([input (make-memory-input-stream #"abcdef")])
      (input-stream-seek! input 3)
      (input-stream-move! input -2)
      (check-equal? (input-stream-position input) 1)
      (check-exn exn:fail? (lambda () (input-stream-seek! input 7)))
      (check-equal? (input-stream-position input) 1)
      (check-equal? (input-stream-skip! input 100) 5)
      (input-stream-rewind! input)
      (check-equal? (input-stream-position input) 0)))

  (test-case "lowered current limits constrain existing input and output streams"
    (with-skia ([input (make-memory-input-stream #"abcdef" #:limit 8)]
                [output (make-memory-output-stream #:limit 8)])
      (output-stream-write-bytes! output #"abc")
      (parameterize ([current-skia-byte-limit 4])
        (check-exn exn:fail? (lambda () (input-stream-position input)))
        (check-exn exn:fail? (lambda () (output-stream-write-bytes! output #"de"))))
      (check-equal? (output-stream->bytes output) #"abc")))

  (test-case "memory-output copy does not detach and detach leaves a reusable writer"
    (with-skia ([output (make-memory-output-stream)])
      (check-equal? (output-stream-write-bytes! output #"abcdef" 1 4) 3)
      (define copied (output-stream->bytes output))
      (bytes-fill! copied 0)
      (check-equal? (output-stream->bytes output) #"bcd")
      (with-skia ([input (output-stream-detach-input! output)])
        (check-equal? (output-stream-bytes-written output) 0)
        (output-stream-write-bytes! output #"next")
        (skia-close! output)
        (check-equal? (input-stream->bytes input) #"bcd"))))

  (test-case "file streams flush bytes but do not implement memory detach"
    (define directory (make-temporary-file "reference-stream~a" 'directory))
    (dynamic-wind void
      (lambda ()
        (define path (build-path directory "bytes.bin"))
        (with-skia ([output (make-file-output-stream path)])
          (output-stream-write-bytes! output #"file data")
          (output-stream-flush! output)
          (check-equal? (file->bytes path) #"file data")
          (check-exn exn:fail? (lambda () (output-stream->bytes output)))
          (check-exn exn:fail? (lambda () (output-stream-detach-input! output))))
        (with-skia ([input (make-file-input-stream path)])
          (check-equal? (input-stream->bytes input) #"file data")))
      (lambda () (delete-directory/files directory))))

  (test-case "codec stream construction reads byte zero without moving the original"
    (define png (sample-png))
    (with-skia ([input (make-memory-input-stream png)])
      (input-stream-seek! input 5)
      (with-skia ([codec (codec-from-stream input)])
        (check-equal? (input-stream-position input) 5)
        (skia-close! input)
        (with-skia ([image (codec->image codec)])
          (check-equal? (list (image-width image) (image-height image)) '(2 3))))))

  (test-case "invalid encoded stream leaves the original cursor and lifetime intact"
    (with-skia ([input (make-memory-input-stream #"not an image")])
      (input-stream-seek! input 2)
      (check-exn exn:fail? (lambda () (codec-from-stream input)))
      (check-equal? (input-stream-position input) 2)
      (check-false (skia-closed? input))))

  (test-case "still-image frame access differs from absent animation metadata"
    (define png (sample-png))
    (with-skia ([codec (codec-from-bytes png)])
      (define info (codec-info codec))
      (check-equal? (encoded-image-info-format info) 'png)
      (check-equal? (codec-frame-count codec) 1)
      (check-equal? (encoded-image-info-frame-count info) 0)
      (check-false (codec-frame-info codec 0))
      (check-exn exn:fail? (lambda () (codec-frame-info codec 1)))
      (with-skia ([image (codec->image codec)])
        (skia-close! codec)
        (check-equal? (image-alpha-type image) 'premul)
        (check-equal? (bytes-length (image->rgba-bytes image)) 24)
        (check-equal? (encoded-image-info-width info) 2))))

  (test-case "codec bytes are copied and format negotiation does not decode pixels"
    (define png (bytes-copy (sample-png)))
    (with-skia ([codec (codec-from-bytes png)])
      (bytes-fill! png 0)
      (define-values (width height) (codec-scaled-dimensions codec 0.5))
      (check-true (<= 1 width 2))
      (check-true (<= 1 height 3))
      (define subset (codec-supported-subset codec 0 0 1 1))
      (when subset
        (check-true (immutable? subset))
        (check-equal? (vector-length subset) 4))
      (with-skia ([image (codec->image codec)])
        (check-equal? (image-width image) 2))))

  (test-case "buffered codec owns copied input after its port closes"
    (define input (open-input-bytes (sample-png)))
    (with-skia ([codec (codec-from-port/buffered input #:close? #t)])
      (check-true (port-closed? input))
      (check-equal? (codec-frame-count codec) 1)))

  (test-case "bottom-up scanlines return top-down detached batches and no phantom rows"
    (with-skia ([session (codec-scanline-from-bytes (bottom-up-bmp))])
      (check-equal? (codec-scanline-order session) 'bottom-up)
      (check-equal? (codec-scanline-next-row session) 2)
      (check-equal? (codec-scanline-output-row session 0) 2)
      (check-exn exn:fail? (lambda () (codec-scanline-read! session 4)))
      (check-equal? (codec-scanline-position session) 0)
      (define batch (codec-scanline-read! session 3 #:row-bytes 12))
      (check-equal? (codec-scanline-state session) 'complete)
      (check-false (codec-scanline-next-row session))
      (check-true (codec-scanline-skip! session 0))
      (check-equal? (scanline-batch-first-row batch) 0)
      (check-true (scanline-batch-complete? batch))
      (check-true (immutable? (scanline-batch-bytes batch)))
      (check-equal? (subbytes (scanline-batch-bytes batch) 0 8)
                    (bytes 255 0 0 255 0 255 0 255))
      (check-equal? (subbytes (scanline-batch-bytes batch) 8 12) (make-bytes 4))
      (skia-close! session)
      (with-skia ([buffer (scanline-batch->raster-buffer batch)]
                  [image (raster-buffer->image buffer)])
        (skia-close! buffer)
        (check-equal? (image-height image) 3))))

  (test-case "animation frame rectangles are immutable detached vectors"
    (define encoded
      (bytes-append
        #"GIF89a\001\000\001\000\201\000\000\377\000\000"
        #"\000\000\000\000\000\000\000\000\000!\377\013NETS"
        #"CAPE2.0\003\001\000\000\000!\371\004\010"
        #"\012\000\000\000,\000\000\000\000\001\000\001\000\000\010\004"
        #"\000\001\004\004\000!\371\004\010\012\000\000\000,\000\000"
        #"\000\000\001\000\001\000\201\000\377\000\000\000\000\000\000\000"
        #"\000\000\000\010\004\000\001\004\004\000;"))
    (with-skia ([codec (codec-from-bytes encoded)])
      (check-equal? (codec-frame-count codec) 2)
      (define info (codec-frame-info codec 1))
      (check-true (codec-frame-info? info))
      (define rectangle (codec-frame-info-rect info))
      (check-equal? rectangle (vector-immutable 0 0 1 1))
      (check-true (immutable? rectangle))
      (skia-close! codec)
      (check-equal? (codec-frame-info-rect info) rectangle)
      (check-exn exn:fail:contract? (lambda () (vector-set! rectangle 0 7)))))

  (test-case "successive bottom-up batches must be placed by their output origins"
    (with-skia ([session (codec-scanline-from-bytes (bottom-up-bmp))])
      (check-equal? (codec-scanline-order session) 'bottom-up)
      (define lower-batch (codec-scanline-read! session 2))
      (check-equal? (codec-scanline-position session) 2)
      (define upper-batch (codec-scanline-read! session 1))
      (check-equal? (codec-scanline-state session) 'complete)
      (check-equal? (list (scanline-batch-first-row lower-batch)
                          (scanline-batch-first-row upper-batch)) '(1 0))
      (skia-close! session)
      (define assembled (make-bytes 24))
      (for ([batch (in-list (list lower-batch upper-batch))])
        (check-true (scanline-batch-complete? batch))
        (check-equal? (scanline-batch-row-bytes batch) 8)
        (bytes-copy! assembled (* 8 (scanline-batch-first-row batch))
                     (scanline-batch-bytes batch)))
      (define expected
        (bytes 255 0 0 255 0 255 0 255
               0 0 255 255 255 255 255 255
               255 255 0 255 0 0 0 255))
      (check-equal? assembled expected)
      (check-not-equal? (bytes-append (scanline-batch-bytes lower-batch)
                                     (scanline-batch-bytes upper-batch))
                        expected)))

  (test-case "incremental feed waits for new visible input and owns its final snapshot"
    (define png (sample-png))
    (with-skia ([session (make-codec-incremental)])
      (check-equal? (codec-incremental-state session) 'awaiting-input)
      (check-false (codec-incremental-info session))
      (check-equal? (codec-incremental-feed! session (subbytes png 0 8)) 8)
      (define first (codec-incremental-step! session))
      (check-equal? (incremental-progress-state first) 'needs-input)
      (define before (codec-incremental-statistics session))
      (codec-incremental-step! session)
      (check-equal? (codec-incremental-statistics session) before)
      (codec-incremental-feed! session (subbytes png 8) #:final? #t)
      (define done (codec-incremental-step! session))
      (check-equal? (incremental-progress-state done) 'complete)
      (check-equal? (incremental-progress-initialized-rows done) 3)
      (check-equal? (hash-ref (codec-incremental-statistics session) 'start-calls) 1)
      (define snapshot (codec-incremental-snapshot session))
      (check-true (immutable? (incremental-snapshot-bytes snapshot)))
      (skia-close! session)
      (with-skia ([buffer (incremental-snapshot->raster-buffer snapshot)]
                  [image (raster-buffer->image buffer)])
        (check-equal? (list (image-width image) (image-height image)) '(2 3)))))

  (test-case "incremental final truncation cannot become successful completion"
    (with-skia ([session (make-codec-incremental)])
      (codec-incremental-feed! session #"\211PNG\r\n\32\n" #:final? #t)
      (define result (codec-incremental-step! session))
      (check-not-equal? (incremental-progress-state result) 'complete)
      (check-true (and (memq (incremental-progress-state result) '(incomplete failed)) #t))
      (check-exn exn:fail? (lambda () (codec-incremental-feed! session #"more")))
      (check-exn exn:fail? (lambda () (codec-incremental-snapshot session)))))

  (test-case "incremental quota rejection does not seal input and cancellation is terminal"
    (with-skia ([session (make-codec-incremental #:limit 32)])
      (codec-incremental-feed! session #"abc")
      (check-exn exn:fail?
                 (lambda () (codec-incremental-feed! session (make-bytes 40) #:final? #t)))
      (check-equal? (hash-ref (codec-incremental-statistics session) 'input-bytes) 3)
      (check-false (hash-ref (codec-incremental-statistics session) 'input-final?))
      (define cancelled (codec-incremental-step! session #:cancel-evt always-evt))
      (check-equal? (incremental-progress-state cancelled) 'cancelled)
      (check-false (skia-closed? session))
      (check-exn exn:fail? (lambda () (codec-incremental-feed! session #"")))))

  (test-case "live copy returns a count and closes only the selected port"
    (define input (open-input-bytes #"abc"))
    (define output (open-output-bytes))
    (dynamic-wind void
      (lambda ()
        (check-equal? (copy-port/streaming input output #:close-input? #t) 3)
        (check-true (port-closed? input))
        (check-false (port-closed? output))
        (check-equal? (get-output-bytes output) #"abc"))
      (lambda ()
        (unless (port-closed? input) (close-input-port input))
        (close-output-port output))))

  (test-case "live writers reject inactive options without touching or closing a port"
    (with-skia ([image (image-from-bytes (sample-png))])
      (define output (open-output-bytes))
      (dynamic-wind void
        (lambda ()
          (check-exn exn:fail?
                     (lambda () (image->port image output 'png #:quality 'unused #:close? #t)))
          (check-exn exn:fail? (lambda () (image->port image output 'webp #:quality 90.5)))
          (check-exn exn:fail?
                     (lambda () (image->port image output 'png #:jpeg-alpha 'unused)))
          (check-false (port-closed? output))
          (check-equal? (get-output-bytes output) #""))
        (lambda () (close-output-port output)))))

  (test-case "live image writes preserve ownership and report this call's byte count"
    (with-skia ([image (image-from-bytes (sample-png))]
                [stream (make-memory-output-stream)])
      (output-stream-write-bytes! stream #"prefix")
      (define written (image-write-stream! image stream 'png))
      (check-equal? (output-stream-bytes-written stream) (+ 6 written))
      (check-false (skia-closed? image))
      (check-false (skia-closed? stream))
      (with-skia ([decoded (image-from-bytes (subbytes (output-stream->bytes stream) 6))])
        (check-equal? (image-width decoded) 2))))

  (test-case "live PDF publication invokes the application author only once"
    (define calls 0)
    (define page
      (make-output-page 20 10
        (lambda (canvas)
          (set! calls (add1 calls))
          (with-skia ([paint (make-paint #:color 'red)])
            (draw-rect canvas 1 1 8 6 paint)))))
    (define output (open-output-bytes))
    (dynamic-wind void
      (lambda ()
        (define count (output->port page output 'pdf))
        (check-equal? calls 1)
        (check-equal? count (bytes-length (get-output-bytes output)))
        (check-equal? (subbytes (get-output-bytes output) 0 5) #"%PDF-"))
      (lambda () (close-output-port output)))))
