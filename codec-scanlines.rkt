#lang racket/base

;;;
;;; Scanline Image Decoding
;;;

;; Creates sequential decoder sessions and reads or skips output rows.
;; This public codec layer enforces session position and row-order rules while returning detached
;; batches for raster-buffer consumers.

;;;
;;; Imports and Exports
;;;

;; Native scanline decoding, not a complete-decode/crop/resampling adapter.
(require ffi/unsafe
         "private/core.rkt" "private/native.rkt" "private/lifetime.rkt"
         "private/codec-scanline-state.rkt" "private/codec-scanline-util.rkt"
         "private/image-info-native.rkt" "image-info.rkt" "codec-queries.rkt"
         "streams.rkt" "stream-inputs.rkt"
         (only-in "raster-buffers.rkt" make-raster-buffer-from-info raster-buffer-write-storage!)
         (submod "private/core.rkt" codec-query-internals))
(provide codec-scanline-session? codec-scanline-from-bytes codec-scanline-from-stream
         codec-scanline-from-port/buffered codec-scanline-state codec-scanline-info
         codec-scanline-source-info codec-scanline-order codec-scanline-position
         codec-scanline-next-row codec-scanline-output-row
         codec-scanline-read! codec-scanline-skip!
         scanline-batch? scanline-batch-info scanline-batch-row-bytes
         scanline-batch-first-row scanline-batch-requested-count
         scanline-batch-decoded-count scanline-batch-bytes scanline-batch-complete?
         scanline-batch->raster-buffer exn:fail:codec-scanline?
         exn:fail:codec-scanline-result exn:fail:codec-scanline-native-code)

; codec-scanline-session? : any/c -> boolean?
;;   Returns #t for a scanline session, including a closed one, and #f otherwise.
(define codec-scanline-session? scanline-session-record?)
; session : symbol? any/c -> codec-scanline-session?
;;   Checks the session wrapper and its creating Racket thread.
(define (session who value)
  (unless (codec-scanline-session? value)
    (raise-argument-error who "codec-scanline-session?" value))
  (unless (eq? (current-thread) (scanline-session-record-creator value))
    (error who "scanline session belongs to another Racket thread"))
  value)
; on-session : symbol? codec-scanline-session? procedure? -> any/c
;;   Locks the private codec while a callback accesses the session and native cursor.
(define (on-session who value proc)
  (define s (session who value))
  (call-with-owned who (list (scanline-session-record-handle s))
    (lambda (ptr) (proc s ptr))))
; session-height : codec-scanline-session? -> exact-positive-integer?
;;   Returns the destination height used to bound scanline progress.
(define (session-height s) (image-info-height (scanline-session-record-info s)))
; require-progress-state : symbol? codec-scanline-session? -> void?
;;   Allows cursor operations only for ready or complete sessions.
(define (require-progress-state who s)
  (unless (memq (scanline-session-record-status s) '(ready complete))
    (error who "scanline session is ~a; close it and construct a new session"
           (scanline-session-record-status s))))
; check-native-position! : symbol? codec-scanline-session? cpointer? exact-nonnegative-integer? ->
;   void?
;;   Checks row-order mapping against the native cursor without making an out-of-range end-of-image
;;   query.
(define (check-native-position! who s ptr position)
  ;; Calling nextScanline at height can assert inside Skia. EOF is a wrapper
  ;; state, never a native out-of-range query.
  (when (< position (session-height s))
    (define expected (scanline-row who (scanline-session-record-order s) (session-height s) position))
    (unless (= expected (sk_codec_next_scanline ptr))
      (error who "native next-row position disagrees with the scanline order"))))

; start-session : symbol? procedure? real? image-info? -> codec-scanline-session?
;;   Creates a private codec, validates scaled geometry and row order, and adopts the scanline
;;   cursor.
(define (start-session who create-codec scale template)
  ;; This codec is private: no public codec can reset the scanline cursor, and
  ;; closing a caller's native stream cannot invalidate its private duplicate.
  (define codec (create-codec))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! codec) (raise e))])
    (define source (codec-info codec))
    (define-values (width height) (codec-scaled-dimensions codec scale))
    (define info (image-info-with-dimensions template width height))
    ;; Check that at least a single row fits; do not allocate the full image.
    (define-values (_rb _minimum _size)
      (image-info-storage-layout (image-info-with-dimensions info width 1)))
    (define handle (codec-h who codec))
    (call-with-owned who (list handle)
      (lambda (ptr)
        (call-with-image-info-native who info
          (lambda (native _space)
            ;; Null options = first frame, full width, no subset. Native SkCodec
            ;; copies image-info (and its color-space reference) on success.
            (define result (sk_codec_start_scanline_decode ptr native #f))
            (unless (zero? result) (raise-scanline-result who result))))
        (define order (scanline-order-name who (sk_codec_get_scanline_order ptr)))
        ;; The pinned bottom-up mapping is in original encoded coordinates.
        ;; Do not invent scaled bottom-up row coordinates on a future codec.
        (when (and (eq? order 'bottom-up)
                   (not (= height (encoded-image-info-height source))))
          (error who "scaled bottom-up scanlines are not supported by this wrapper"))
        (define value
          (make-scanline-session-record handle (current-thread) info source order
                                       (current-skia-byte-limit) 0 'ready))
        (check-native-position! who value ptr 0)
        value))))

; codec-scanline-from-bytes : bytes? [#:scale (and/c real? (>/c 0))] [#:color-type (or/c 'rgba-8888
;   'bgra-8888 'rgb-888x 'alpha-8 'gray-8 'rgb-565 'rgba-1010102 'rgba-f16 'rgba-f32)] [#:alpha-type
;   (or/c 'opaque 'premul 'unpremul)] [#:color-space (or/c #f 'srgb 'linear-srgb bytes?)] ->
;   codec-scanline-session?
;;   Starts a session from copied, nonempty encoded bytes.
(define (codec-scanline-from-bytes bytes #:scale [scale 1]
                                   #:color-type [color 'rgba-8888]
                                   #:alpha-type [alpha 'unpremul]
                                   #:color-space [space 'srgb])
  (define who 'codec-scanline-from-bytes)
  (unless (bytes? bytes) (raise-argument-error who "bytes?" bytes))
  (define-values (requested template) (scanline-options who scale color alpha space))
  (start-session who (lambda () (codec-from-bytes bytes)) requested template))
; codec-scanline-from-stream : skia-input-stream? [#:scale (and/c real? (>/c 0))] [#:color-type
;   (or/c 'rgba-8888 'bgra-8888 'rgb-888x 'alpha-8 'gray-8 'rgb-565 'rgba-1010102 'rgba-f16
;   'rgba-f32)] [#:alpha-type (or/c 'opaque 'premul 'unpremul)] [#:color-space (or/c #f 'srgb
;   'linear-srgb bytes?)] -> codec-scanline-session?
;;   Starts a session through a private duplicate at byte zero.
(define (codec-scanline-from-stream stream #:scale [scale 1]
                                    #:color-type [color 'rgba-8888]
                                    #:alpha-type [alpha 'unpremul]
                                    #:color-space [space 'srgb])
  (define who 'codec-scanline-from-stream)
  (unless (skia-input-stream? stream) (raise-argument-error who "skia-input-stream?" stream))
  (define-values (requested template) (scanline-options who scale color alpha space))
  (start-session who (lambda () (codec-from-stream stream)) requested template))
; codec-scanline-from-port/buffered : input-port? [#:scale (and/c real? (>/c 0))] [#:color-type
;   (or/c 'rgba-8888 'bgra-8888 'rgb-888x 'alpha-8 'gray-8 'rgb-565 'rgba-1010102 'rgba-f16
;   'rgba-f32)] [#:alpha-type (or/c 'opaque 'premul 'unpremul)] [#:color-space (or/c #f 'srgb
;   'linear-srgb bytes?)] [#:limit exact-positive-integer?] [#:close? boolean?] [#:cancel-evt (or/c
;   evt? #f)] -> codec-scanline-session?
;;   Validates the requested output options, buffers the unread port input, and starts a session.
(define (codec-scanline-from-port/buffered in #:scale [scale 1]
                                           #:color-type [color 'rgba-8888]
                                           #:alpha-type [alpha 'unpremul]
                                           #:color-space [space 'srgb]
                                           #:limit [limit (current-skia-byte-limit)]
                                           #:close? [close? #f] #:cancel-evt [cancel #f])
  (define who 'codec-scanline-from-port/buffered)
  (define-values (requested template) (scanline-options who scale color alpha space))
  (with-skia ([stream (buffered-port->input-stream
                      in #:limit limit #:close? close? #:cancel-evt cancel)])
    (start-session who (lambda () (codec-from-stream stream)) requested template)))

; codec-scanline-state : codec-scanline-session? -> (or/c 'ready 'complete 'incomplete 'failed
;   'closed)
;;   Returns the session state.
(define (codec-scanline-state value)
  (define s (session 'codec-scanline-state value))
  (if (owned-closed? (scanline-session-record-handle s)) 'closed
      (scanline-session-record-status s)))
; metadata : symbol? codec-scanline-session? procedure? -> any/c
;;   Checks session ownership and liveness before reading retained metadata.
(define (metadata who s get) (on-session who s (lambda (s _ptr) (get s))))
; codec-scanline-info : codec-scanline-session? -> image-info?
;;   Returns the detached full-output pixel description, using negotiated dimensions and the
;;   selected output color/alpha format.
(define (codec-scanline-info s) (metadata 'codec-scanline-info s scanline-session-record-info))
; codec-scanline-source-info : codec-scanline-session? -> encoded-image-info?
;;   Returns detached metadata for the original encoded source, before scaling and orientation
;;   normalization.
(define (codec-scanline-source-info s)
  (metadata 'codec-scanline-source-info s scanline-session-record-source-info))
; codec-scanline-order : codec-scanline-session? -> (or/c 'top-down 'bottom-up)
;;   Returns the native row consumption order.
(define (codec-scanline-order s) (metadata 'codec-scanline-order s scanline-session-record-order))
; codec-scanline-position : codec-scanline-session? -> exact-nonnegative-integer?
;;   Returns the number of requested rows consumed by reads and skips.
(define (codec-scanline-position s)
  (metadata 'codec-scanline-position s scanline-session-record-position))
; codec-scanline-next-row : codec-scanline-session? -> (or/c exact-nonnegative-integer? #f)
;;   Returns the output row that would be consumed next, or #f at the end.
(define (codec-scanline-next-row s)
  (define who 'codec-scanline-next-row)
  (on-session who s
    (lambda (s ptr)
      (require-progress-state who s)
      (define at (scanline-session-record-position s))
      (and (< at (session-height s))
           (begin (check-native-position! who s ptr at) (sk_codec_next_scanline ptr))))))
; codec-scanline-output-row : codec-scanline-session? exact-nonnegative-integer? ->
;   exact-nonnegative-integer?
;;   Maps a zero-based consumption-order index to its output row.
(define (codec-scanline-output-row s input-row)
  (define who 'codec-scanline-output-row)
  (on-session who s
    (lambda (s ptr)
      (require-progress-state who s)
      (scanline-index who input-row (session-height s))
      (define expected
        (scanline-row who (scanline-session-record-order s) (session-height s) input-row))
      (define actual (sk_codec_output_scanline ptr input-row))
      (unless (= expected actual)
        (error who "native output-row mapping disagrees with scanline order"))
      actual)))

; codec-scanline-read! : codec-scanline-session? [exact-positive-integer?] [#:row-bytes (or/c
;   exact-nonnegative-integer? #f)] -> scanline-batch?
;;   Requests count rows and returns a detached batch.
(define (codec-scanline-read! s [count 1] #:row-bytes [row-bytes #f])
  (define who 'codec-scanline-read!)
  (on-session who s
    (lambda (s ptr)
      (require-progress-state who s)
      (define at (scanline-session-record-position s))
      (define height (session-height s))
      (scanline-count who count (- height at))
      (define info (scanline-session-record-info s))
      (parameterize ([current-skia-byte-limit
                      (min (current-skia-byte-limit) (scanline-session-record-limit s))])
        (define target (image-info-with-dimensions info (image-info-width info) count))
        (define-values (stride _minimum size)
          (image-info-storage-layout target #:row-bytes row-bytes))
        (define memory #f)
        (define attempted? #f)
        (with-handlers ([(lambda (_) #t)
                         (lambda (e)
                           (when attempted? (set-scanline-session-record-status! s 'failed))
                           (raise e))])
          (dynamic-wind
            (lambda ()
              (set! memory (malloc size 'raw))
              (unless memory (error who "scanline staging allocation failed")))
            (lambda ()
              ;; Zero padding and stage separately; no caller buffer is lent or
              ;; left partially mutated. Native fill rows are excluded below.
              (memset memory 0 size)
              (set! attempted? #t)
              (define decoded (sk_codec_get_scanlines ptr memory count stride))
              (define-values (offset first-row)
                (scanline-batch-layout who (scanline-session-record-order s) height at count decoded))
              ;; m119 advances by REQUESTED count even after a short native read.
              (set-scanline-session-record-position! s (+ at count))
              (set-scanline-session-record-status! s (scanline-read-state height at count decoded))
              (when (= decoded count) (check-native-position! who s ptr (+ at count)))
              (define bytes (make-bytes (* stride decoded) 0))
              (unless (zero? decoded)
                (memcpy bytes (ptr-add memory (* offset stride)) (bytes-length bytes)))
              (make-scanline-batch (image-info-with-dimensions info (image-info-width info) decoded)
                                   stride first-row count decoded (bytes->immutable-bytes bytes)))
            (lambda () (when memory (free memory) (set! memory #f)))))))))

; codec-scanline-skip! : codec-scanline-session? exact-nonnegative-integer? -> boolean?
;;   Skips a count no greater than the remaining rows.
(define (codec-scanline-skip! s count)
  (define who 'codec-scanline-skip!)
  (on-session who s
    (lambda (s ptr)
      (require-progress-state who s)
      (define at (scanline-session-record-position s))
      (define height (session-height s))
      (scanline-count who count (- height at) #:zero? #t)
      (cond [(zero? count) #t]
            [else
             (with-handlers ([(lambda (_) #t)
                              (lambda (e) (set-scanline-session-record-status! s 'failed) (raise e))])
               (define skipped? (sk_codec_skip_scanlines ptr count))
               ;; Native cursor advances even if a valid skip fails on input.
               (set-scanline-session-record-position! s (+ at count))
               (set-scanline-session-record-status! s
                 (if skipped? (if (= (+ at count) height) 'complete 'ready) 'failed))
               (when skipped? (check-native-position! who s ptr (+ at count)))
               skipped?)]))))

; scanline-batch->raster-buffer : scanline-batch? -> raster-buffer?
;;   Copies a nonempty batch into an independently owned raster buffer, preserving its format and
;;   stride.
(define (scanline-batch->raster-buffer batch)
  (define who 'scanline-batch->raster-buffer)
  (unless (scanline-batch? batch) (raise-argument-error who "scanline-batch?" batch))
  (when (zero? (scanline-batch-decoded-count batch)) (error who "batch has no decoded rows"))
  (define buffer (make-raster-buffer-from-info (scanline-batch-info batch)
                                               #:row-bytes (scanline-batch-row-bytes batch)))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! buffer) (raise e))])
    (raster-buffer-write-storage! buffer (scanline-batch-bytes batch))
    buffer))
