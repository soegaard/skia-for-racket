#lang racket/base
(require ffi/unsafe
         "streams.rkt" (submod "streams.rkt" internals)
         "private/core.rkt" "private/native.rkt" "private/lifetime.rkt"
         "private/stream-buffer.rkt" "private/picture-util.rkt"
         (prefix-in raw: (submod "private/core.rkt" stream-input-internals)))
(provide codec-from-stream typeface-from-stream picture-from-stream
         codec-from-port/buffered typeface-from-port/buffered
         image-from-port/buffered picture-from-port/buffered)

(define (checked-index who index)
  (unless (and (exact-nonnegative-integer? index) (<= index #x7fffffff))
    (raise-argument-error who "exact integer from 0 through 2147483647" index))
  index)

(define (consume-private-duplicate who kind stream constructor release)
  ;; Resolve every registered native symbol before creating a raw duplicate.
  ;; The reviewed C shims take a unique_ptr, even on construction failure.
  (skia-check!)
  (with-input who stream
    (lambda (ptr length _position)
      (new-owned who kind
        (lambda ()
          (define duplicate (sk_stream_duplicate ptr))
          (unless duplicate (error who "native input cannot be duplicated"))
          (define transferred? #f)
          (dynamic-wind
            void
            (lambda ()
              (unless (and (sk_stream_has_length duplicate) (sk_stream_has_position duplicate)
                           (= length (sk_stream_get_length duplicate))
                           (= 0 (sk_stream_get_position duplicate)))
                (error who "native duplicate has inconsistent extent or position"))
              ;; There are no user callbacks and the owner scope is atomic.
              ;; After this point native code owns the duplicate, including on
              ;; a null result. The original stream is NEVER handed off.
              (set! transferred? #t)
              (constructor duplicate))
            (lambda () (unless transferred? (sk_stream_destroy duplicate)))))
        release))))

(define (codec-from-stream stream)
  (define who 'codec-from-stream)
  (define result (malloc _int 'atomic))
  (ptr-set! result _int -1)
  (define handle
    (consume-private-duplicate who 'codec stream
      (lambda (ptr)
        (or (sk_codec_new_from_stream ptr result)
            (error who "native codec rejected the stream (result ~a)" (ptr-ref result _int))))
      sk_codec_destroy))
  (define codec (raw:make-codec-record handle))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! codec) (raise e))])
    (codec-info codec)
    codec))
(define (typeface-from-stream stream #:index [index 0])
  (define who 'typeface-from-stream)
  (checked-index who index)
  (raw:make-typeface-record
   (consume-private-duplicate who 'typeface stream
     (lambda (ptr) (sk_typeface_create_from_stream ptr index)) sk_typeface_unref)))

(define (picture-from-stream stream #:trusted? [trusted? #f]
                             #:width [width #f] #:height [height #f])
  (define who 'picture-from-stream)
  (check-picture-trust who trusted?)
  (define size (picture-size-override who width height))
  (with-skia ([copy (input-stream-duplicate stream)])
    (define header (input-stream-read-bytes copy 29))
    (unless (bytes? header) (error who "empty SKP stream"))
    (picture-header who header)
    (input-stream-rewind! copy)
    (define handle
      (with-input who copy
        (lambda (ptr _length _position)
          ;; MakeFromStream borrows synchronously rather than consuming this
          ;; stream. The picture owns its decoded content when it returns.
          (new-owned who 'picture
            (lambda () (sk_picture_deserialize_from_stream ptr)) sk_picture_unref))))
    (with-handlers ([(lambda (_) #t) (lambda (e) (owned-close! who handle) (raise e))])
      (define bounds
        (call-with-owned who (list handle)
          (lambda (ptr) (raw:stream-picture-bounds who ptr))))
      (raw:make-picture-record handle
        (if size (vector-ref size 0) (vector-ref bounds 2))
        (if size (vector-ref size 1) (vector-ref bounds 3))))))

(define (codec-from-port/buffered in #:limit [limit (current-skia-byte-limit)]
                                  #:close? [close? #f] #:cancel-evt [cancel #f])
  (with-skia ([stream (buffered-port->input-stream in #:limit limit #:close? close? #:cancel-evt cancel)])
    (codec-from-stream stream)))
(define (typeface-from-port/buffered in #:index [index 0] #:limit [limit (current-skia-byte-limit)]
                                     #:close? [close? #f] #:cancel-evt [cancel #f])
  (checked-index 'typeface-from-port/buffered index)
  (with-skia ([stream (buffered-port->input-stream in #:limit limit #:close? close? #:cancel-evt cancel)])
    (typeface-from-stream stream #:index index)))
(define (image-from-port/buffered in #:limit [limit (current-skia-byte-limit)]
                                  #:close? [close? #f] #:cancel-evt [cancel #f])
  (image-from-bytes (read-port-buffered 'image-from-port/buffered in limit close? cancel)))
(define (picture-from-port/buffered in #:trusted? [trusted? #f]
                                    #:width [width #f] #:height [height #f]
                                    #:limit [limit (current-skia-byte-limit)]
                                    #:close? [close? #f] #:cancel-evt [cancel #f])
  (check-picture-trust 'picture-from-port/buffered trusted?)
  (picture-size-override 'picture-from-port/buffered width height)
  (with-skia ([stream (buffered-port->input-stream in #:limit limit #:close? close? #:cancel-evt cancel)])
    (picture-from-stream stream #:trusted? trusted? #:width width #:height height)))
