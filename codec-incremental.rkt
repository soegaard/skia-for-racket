#lang racket/base
;; Retained native incremental decoding. Input bytes are explicitly fed by the
;; caller, not read by retained live Racket-port callbacks. No getPixels fallback.
(require ffi/unsafe
         "private/core.rkt" "private/native.rkt" "private/types.rkt"
         "private/lifetime.rkt" "private/check.rkt" "private/codec-util.rkt"
         "private/codec-incremental-state.rkt" "private/codec-incremental-input.rkt"
         "private/codec-incremental-util.rkt" "private/image-info-native.rkt"
         "image-info.rkt" (only-in "live-streams.rkt" live-streams-check!)
         (only-in "private/live-port-native.rkt" make-incremental-source/native)
         (only-in "raster-buffers.rkt" make-raster-buffer-from-info raster-buffer-write-storage!))
(provide codec-incremental-session? make-codec-incremental codec-incremental-feed!
         codec-incremental-step! codec-incremental-cancel! codec-incremental-state
         codec-incremental-info codec-incremental-origin codec-incremental-statistics
         codec-incremental-snapshot incremental-snapshot->raster-buffer
         incremental-progress? incremental-progress-state incremental-progress-result
         incremental-progress-initialized-rows
         incremental-snapshot? incremental-snapshot-info incremental-snapshot-row-bytes
         incremental-snapshot-bytes incremental-snapshot-progress)

(define codec-incremental-session? incremental-session-record?)
(define (session who value)
  (unless (codec-incremental-session? value)
    (raise-argument-error who "codec-incremental-session?" value))
  (unless (eq? (current-thread) (incremental-session-record-creator value))
    (error who "incremental session belongs to another Racket thread"))
  value)
(define (on-session who value proc)
  (define s (session who value))
  (call-with-owned who (list (incremental-session-record-handle s))
    (lambda (_token) (proc (incremental-session-record-cell s)))))
(define (progress c)
  (make-incremental-progress (incremental-cell-status c) (incremental-cell-result c)
                            (incremental-cell-rows c)))
(define (destroy-codec! c)
  (define p (incremental-cell-codec c))
  (when p
    (set-incremental-cell-codec! c #f)
    ;; Its stream destructor routes by non-null context to memory-only code,
    ;; never to the live-port service, even when run by a resource finalizer.
    (sk_codec_destroy p)))
(define (release-pixels! c)
  (define p (incremental-cell-pixels c))
  (when p (set-incremental-cell-pixels! c #f) (free p)))
(define (release-cell! c)
  ;; Skia retains this destination between incremental calls. Destroy the codec
  ;; BEFORE freeing pixels on explicit close, failure, cancellation, or GC.
  (destroy-codec! c)
  (release-pixels! c)
  (incremental-input-discard! (incremental-cell-input c)))
(define (finish-native! c)
  (destroy-codec! c)
  (incremental-input-discard! (incremental-cell-input c)))
(define (raise-source-error! c)
  (define failed (incremental-input-error (incremental-cell-input c)))
  (when failed (raise (cdr failed))))
(define (make-codec-incremental #:color-type [color 'rgba-8888]
                               #:alpha-type [alpha 'unpremul]
                               #:color-space [space 'srgb]
                               #:row-bytes [row-bytes #f]
                               #:limit [limit (current-skia-byte-limit)])
  (define who 'make-codec-incremental)
  (define template (incremental-options who color alpha space row-bytes limit))
  (live-streams-check!) ; reuse exactly one process-global callback provider
  (define c (incremental-cell (make-incremental-input limit) template row-bytes limit
                             #f #f #f #f 0 0 #f 'awaiting-input 'not-started #f
                             -1 #f 0 0 0 0))
  (make-incremental-session-record
   (new-owned who 'codec-incremental (lambda () (malloc 1 'raw))
     (lambda (token) (release-cell! c) (free token)))
   (current-thread) c))
(define (codec-incremental-feed! s bytes #:final? [final? #f])
  (define who 'codec-incremental-feed!)
  (unless (bytes? bytes) (raise-argument-error who "bytes?" bytes))
  (unless (boolean? final?) (raise-argument-error who "boolean?" final?))
  (on-session who s
    (lambda (c)
      (when (incremental-terminal? (incremental-cell-status c))
        (error who "session is ~a; create a new session" (incremental-cell-status c)))
      ;; Quota failures are checked before changing the prefix. Framing errors
      ;; poison the input and session rather than continuing a broken source.
      (define input (incremental-cell-input c))
      (define before (incremental-input-size input))
      (with-handlers ([(lambda (_) #t)
                       (lambda (e)
                         (when (> (incremental-input-size input) before)
                           (set-incremental-cell-status! c 'failed)
                           (set-incremental-cell-result! c 'invalid-input)
                           (finish-native! c))
                         (raise e))])
        (incremental-input-append! input bytes final? (current-skia-byte-limit))))))
(define (codec-incremental-state value)
  (define s (session 'codec-incremental-state value))
  (if (owned-closed? (incremental-session-record-handle s)) 'closed
      (incremental-cell-status (incremental-session-record-cell s))))
(define (codec-incremental-info s)
  (on-session 'codec-incremental-info s incremental-cell-info))
(define (codec-incremental-origin s)
  (on-session 'codec-incremental-origin s incremental-cell-origin))
(define (codec-incremental-statistics s)
  (on-session 'codec-incremental-statistics s
    (lambda (c)
      (define input (incremental-cell-input c))
      (hasheq 'header-attempts (incremental-cell-header-attempts c)
              'start-calls (incremental-cell-starts c) 'decode-calls (incremental-cell-decodes c)
              'pixel-allocations (incremental-cell-allocations c)
              'input-bytes (incremental-input-size input)
              'visible-input-bytes (incremental-input-visible input)
              'input-final? (incremental-input-final? input)
              'stream-creations (incremental-input-streams input)
              'stream-destructions (incremental-input-destroys input)
              'decoder-retained? (and (incremental-cell-codec c) #t)
              'pixel-bytes (if (incremental-cell-pixels c) (incremental-cell-size c) 0)))))
(define (cancel-cell! c)
  (unless (incremental-terminal? (incremental-cell-status c))
    (set-incremental-cell-status! c 'cancelled)
    (set-incremental-cell-result! c 'cancelled)
    (set-incremental-cell-rows! c #f)
    (release-cell! c))
  (progress c))
(define (codec-incremental-cancel! s)
  (on-session 'codec-incremental-cancel! s cancel-cell!))
(define (report-result! c code [rows #f])
  (unless (and (exact-integer? code) (<= 0 code 9))
    (error 'codec-incremental-step! "unknown native codec result: ~a" code))
  (set-incremental-cell-result! c (codec-result-name code))
  (set-incremental-cell-rows! c rows)
  (set-incremental-cell-status! c
    (incremental-result-state code (incremental-input-final? (incremental-cell-input c))))
  (when (incremental-terminal? (incremental-cell-status c)) (finish-native! c))
  (progress c))
(define (make-native-codec! c)
  (set-incremental-cell-header-attempts! c (add1 (incremental-cell-header-attempts c)))
  (define code (malloc _int 'atomic-interior))
  (ptr-set! code _int -1)
  (define stream (make-incremental-source/native (incremental-cell-input c)))
  ;; The C shim consumes this stream even when no codec is returned. The source
  ;; registry never retains the session; destroy unroots only its memory input.
  (define codec (sk_codec_new_from_stream stream code))
  (when codec (set-incremental-cell-codec! c codec))
  (raise-source-error! c)
  (if codec 0 (ptr-ref code _int)))
(define (allocate-destination! c)
  (define who 'codec-incremental-step!)
  (define cp (incremental-cell-codec c))
  (define memory (malloc (ctype-sizeof _sk-image-info) 'atomic-interior))
  (memset memory 0 (ctype-sizeof _sk-image-info))
  (define source (cast memory _pointer _sk-image-info-pointer))
  (dynamic-wind void
    (lambda ()
      (sk_codec_get_info cp source)
      (define width (sk-image-info-width source))
      (define height (sk-image-info-height source))
      (unless (and (<= 1 width 32768) (<= 1 height 32768))
        (error who "native image dimensions exceed the supported bounds"))
      (define info (image-info-with-dimensions (incremental-cell-template c) width height))
      (define-values (stride _minimum size)
        (image-info-storage-layout info #:row-bytes (incremental-cell-requested-row-bytes c)))
      (set-incremental-cell-info! c info)
      (set-incremental-cell-origin! c
        (enum-name who (sk_codec_get_origin cp) encoded-origin-values "encoded origin"))
      (define pixels (malloc size 'raw))
      (unless pixels (error who "incremental pixel allocation failed"))
      (set-incremental-cell-pixels! c pixels)
      (set-incremental-cell-stride! c stride)
      (set-incremental-cell-size! c size)
      (set-incremental-cell-allocations! c (add1 (incremental-cell-allocations c)))
      ;; Incremental decode does not fill incomplete rows. Initialize every byte
      ;; including padding before Skia can retain the address.
      (memset pixels 0 size))
    (lambda ()
      (when (sk-image-info-colorspace source)
        (sk_colorspace_unref (sk-image-info-colorspace source))))))
(define (start-native! c)
  (unless (incremental-cell-pixels c) (allocate-destination! c))
  (set-incremental-cell-starts! c (add1 (incremental-cell-starts c)))
  (define result
    (call-with-image-info-native 'codec-incremental-step! (incremental-cell-info c)
      (lambda (info _space)
        ;; The native start copies its image-info but may make source callbacks
        ;; before returning. Do not lend a movable Racket cstruct during them.
        (define fixed (malloc (ctype-sizeof _sk-image-info) 'atomic-interior))
        (memcpy fixed info (ctype-sizeof _sk-image-info))
        (define code
          (sk_codec_start_incremental_decode (incremental-cell-codec c) fixed
            (incremental-cell-pixels c) (incremental-cell-stride c) #f))
        (void/reference-sink fixed info)
        code)))
  (raise-source-error! c)
  (when (zero? result) (set-incremental-cell-started?! c #t))
  result)
(define (decode-native! c)
  (define rows (malloc _int 'atomic-interior))
  (ptr-set! rows _int -1)
  (set-incremental-cell-decodes! c (add1 (incremental-cell-decodes c)))
  (define code (sk_codec_incremental_decode (incremental-cell-codec c) rows))
  (raise-source-error! c)
  (define initialized
    (cond [(zero? code) (image-info-height (incremental-cell-info c))]
          [(= code 1)
           ;; Only kIncompleteInput makes the out-parameter meaningful. Some
           ;; decoders leave it unset; -1 becomes #f, never an invented count.
           (define count (ptr-ref rows _int))
           (cond [(= count -1) #f]
                 [(<= 0 count (image-info-height (incremental-cell-info c))) count]
                 [else (error 'codec-incremental-step! "invalid initialized-row count: ~a" count)])]
          [else #f]))
  (report-result! c code initialized))
(define (codec-incremental-step! s #:cancel-evt [cancel #f])
  (define who 'codec-incremental-step!)
  (unless (or (not cancel) (evt? cancel))
    (raise-argument-error who "#f or evt?" cancel))
  (session who s)
  ;; Poll a user-supplied event before the atomic native/ownership scope. Event
  ;; guards can execute Racket code; no such callback belongs inside Skia.
  (define cancelled? (and cancel (sync/timeout 0 (wrap-evt cancel (lambda ignored #t)))))
  (on-session who s
    (lambda (c)
      (define input (incremental-cell-input c))
      (cond
        [(incremental-terminal? (incremental-cell-status c)) (progress c)]
        [cancelled? (cancel-cell! c)]
        [(and (= (incremental-cell-last-visible c) (incremental-input-visible input))
              (eq? (incremental-cell-last-final? c) (incremental-input-final? input)))
         (progress c)]
        [else
         (parameterize ([current-skia-byte-limit
                         (min (current-skia-byte-limit) (incremental-cell-limit c))])
           (unless (<= (incremental-input-size input) (current-skia-byte-limit))
             (error who "retained input exceeds the current byte limit"))
           (when (incremental-cell-pixels c)
             (unless (<= (incremental-cell-size c) (current-skia-byte-limit))
               (error who "retained destination exceeds the current byte limit")))
           (set-incremental-cell-last-visible! c (incremental-input-visible input))
           (set-incremental-cell-last-final?! c (incremental-input-final? input))
           (with-handlers ([(lambda (_) #t)
                            (lambda (e)
                              (set-incremental-cell-status! c 'failed)
                              (set-incremental-cell-result! c 'wrapper-error)
                              (release-cell! c)
                              (raise e))])
             (cond
               [(zero? (incremental-input-visible input)) (report-result! c 1)]
               [else
                (define header (if (incremental-cell-codec c) 0 (make-native-codec! c)))
                (cond [(not (zero? header)) (report-result! c header)]
                      [else
                       (define started (if (incremental-cell-started? c) 0 (start-native! c)))
                       (if (zero? started) (decode-native! c) (report-result! c started))])])))]))))
(define (codec-incremental-snapshot s)
  (define who 'codec-incremental-snapshot)
  (on-session who s
    (lambda (c)
      (unless (and (incremental-cell-started? c) (incremental-cell-pixels c))
        (error who "no initialized incremental destination is available"))
      (unless (<= (incremental-cell-size c) (min (current-skia-byte-limit) (incremental-cell-limit c)))
        (error who "snapshot exceeds the current byte limit"))
      (define bytes (make-bytes (incremental-cell-size c)))
      (memcpy bytes (incremental-cell-pixels c) (bytes-length bytes))
      (make-incremental-snapshot (incremental-cell-info c) (incremental-cell-stride c)
                                (bytes->immutable-bytes bytes) (progress c)))))
(define (incremental-snapshot->raster-buffer snapshot)
  (unless (incremental-snapshot? snapshot)
    (raise-argument-error 'incremental-snapshot->raster-buffer "incremental-snapshot?" snapshot))
  (define b (make-raster-buffer-from-info (incremental-snapshot-info snapshot)
               #:row-bytes (incremental-snapshot-row-bytes snapshot)))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! b) (raise e))])
    (raster-buffer-write-storage! b (incremental-snapshot-bytes snapshot))
    b))
