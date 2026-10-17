#lang racket/base

;;;
;;; Stream-Backed Resource Input
;;;

;; Constructs codecs, typefaces, pictures, and images from native streams or buffered ports.
;; This public input layer centralizes stream duplication and ownership handoff for the resource
;; factories that consume encoded data.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe
         "streams.rkt" (submod "streams.rkt" internals)
         "typefaces.rkt"
         "private/core.rkt" "private/native.rkt" "private/lifetime.rkt"
         "private/stream-buffer.rkt" "private/picture-util.rkt"
         (prefix-in raw: (submod "private/core.rkt" stream-input-internals)))
(provide codec-from-stream typeface-from-stream picture-from-stream
         codec-from-port/buffered typeface-from-port/buffered
         image-from-port/buffered picture-from-port/buffered)

; checked-index : symbol? exact-nonnegative-integer? -> exact-nonnegative-integer?
;   Bounds a collection index to the native signed 32-bit range.
(define (checked-index who index)
  (unless (and (exact-nonnegative-integer? index) (<= index #x7fffffff))
    (raise-argument-error who "exact integer from 0 through 2147483647" index))
  index)

; consume-private-duplicate : symbol? symbol? skia-input-stream? procedure? procedure? -> (or/c
;   owned? domain-resource?)
;   Transfers a validated private duplicate to a native constructor, never handing off the caller's
;   stream.
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

; codec-from-stream : skia-input-stream? -> codec?
;   Returns an image codec using a private duplicate of stream.
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

; typeface-from-stream : skia-input-stream? [#:index (integer-in 0 2147483647)] -> typeface?
;   Returns a typeface from the stream's font data.
(define (typeface-from-stream stream #:index [index 0])
  (define who 'typeface-from-stream)
  (checked-index who index)
  (define (native-face)
    (raw:make-typeface-record
     (consume-private-duplicate who 'typeface stream
       (lambda (ptr) (sk_typeface_create_from_stream ptr index)) sk_typeface_unref)))
  ;; The pinned m119 CoreText host rejects TTC member selection through its
  ;; native stream loader. The established typeface-from-bytes path extracts
  ;; that member to a standalone SFNT on macOS. Probe a private duplicate at
  ;; byte zero: even when the caller's cursor is advanced, it is not touched.
  ;; Ordinary SFNT fonts and all other platforms retain native stream input.
  (if (eq? (system-type 'os) 'macosx)
      (with-skia ([probe (input-stream-duplicate stream)])
        (define magic (input-stream-read-bytes probe 4))
        (if (and (bytes? magic) (bytes=? magic #"ttcf"))
            (begin
              (input-stream-rewind! probe)
              (typeface-from-bytes (input-stream->bytes probe) #:index index))
            (native-face)))
      (native-face)))

; picture-from-stream : skia-input-stream? [#:trusted? boolean?] [#:width (or/c real? #f)] [#:height
;   (or/c real? #f)] -> picture?
;   Deserializes trusted SKP data using a private duplicate.
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

; codec-from-port/buffered : input-port? [#:limit exact-positive-integer?] [#:close? boolean?]
;   [#:cancel-evt (or/c evt? #f)] -> codec?
;   Buffers the unread port contents using buffered-port->input-stream, then constructs a codec.
(define (codec-from-port/buffered in #:limit [limit (current-skia-byte-limit)]
                                  #:close? [close? #f] #:cancel-evt [cancel #f])
  (with-skia ([stream (buffered-port->input-stream
                      in #:limit limit #:close? close? #:cancel-evt cancel)])
    (codec-from-stream stream)))

; typeface-from-port/buffered : input-port? [#:index (integer-in 0 2147483647)] [#:limit
;   exact-positive-integer?] [#:close? boolean?] [#:cancel-evt (or/c evt? #f)] -> typeface?
;   Buffers the unread font data, then constructs the selected collection member as in
;   typeface-from-stream.
(define (typeface-from-port/buffered in #:index [index 0] #:limit [limit (current-skia-byte-limit)]
                                     #:close? [close? #f] #:cancel-evt [cancel #f])
  (checked-index 'typeface-from-port/buffered index)
  (with-skia ([stream (buffered-port->input-stream
                      in #:limit limit #:close? close? #:cancel-evt cancel)])
    (typeface-from-stream stream #:index index)))

; image-from-port/buffered : input-port? [#:limit exact-positive-integer?] [#:close? boolean?]
;   [#:cancel-evt (or/c evt? #f)] -> image?
;   Buffers the unread encoded data and constructs an image as in image-from-bytes.
(define (image-from-port/buffered in #:limit [limit (current-skia-byte-limit)]
                                  #:close? [close? #f] #:cancel-evt [cancel #f])
  (image-from-bytes (read-port-buffered 'image-from-port/buffered in limit close? cancel)))

; picture-from-port/buffered : input-port? [#:trusted? boolean?] [#:width (or/c real? #f)] [#:height
;   (or/c real? #f)] [#:limit exact-positive-integer?] [#:close? boolean?] [#:cancel-evt (or/c evt?
;   #f)] -> picture?
;   Buffers trusted SKP input and constructs a picture as in picture-from-stream.
(define (picture-from-port/buffered in #:trusted? [trusted? #f]
                                    #:width [width #f] #:height [height #f]
                                    #:limit [limit (current-skia-byte-limit)]
                                    #:close? [close? #f] #:cancel-evt [cancel #f])
  (check-picture-trust 'picture-from-port/buffered trusted?)
  (picture-size-override 'picture-from-port/buffered width height)
  (with-skia ([stream (buffered-port->input-stream
                      in #:limit limit #:close? close? #:cancel-evt cancel)])
    (picture-from-stream stream #:trusted? trusted? #:width width #:height height)))
