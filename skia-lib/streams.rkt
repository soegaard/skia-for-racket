#lang racket/base

;;;
;;; Native Input and Output Streams
;;;

;; Wraps native memory and file streams with checked seeking, copying, and byte transfer operations.
;; This public I/O layer gives codecs and document consumers a shared owned-stream interface and
;; explicit buffered-port adapters.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe racket/path racket/file
         "private/core.rkt" "private/native.rkt" "private/lifetime.rkt"
         "private/stream-resource.rkt" "private/stream-buffer.rkt")
(provide skia-input-stream? skia-output-stream?
         make-memory-input-stream make-file-input-stream make-memory-output-stream
         input-stream-length input-stream-position input-stream-at-end?
         input-stream-read-bytes input-stream-peek-bytes input-stream-skip!
         input-stream-seek! input-stream-rewind! input-stream-move!
         input-stream-duplicate input-stream-fork input-stream->bytes
         output-stream-write-bytes! output-stream-bytes-written output-stream->bytes
         output-stream-detach-input! buffered-port->input-stream
         output-stream-write-port/buffered)

;;;
;;; Stream Ownership and Budgets
;;;

; skia-input-stream? : any/c -> boolean?
;   Returns #t for a native input stream, including a closed one, and #f otherwise.
(define (skia-input-stream? value)
  (and (native-stream? value) (eq? (native-stream-direction value) 'input)))

; skia-output-stream? : any/c -> boolean?
;   Returns #t for a native output stream, including a closed one, and #f otherwise.
(define (skia-output-stream? value)
  (and (native-stream? value) (eq? (native-stream-direction value) 'output)))

; stream-h : symbol? any/c boolean? -> (or/c owned? domain-resource?)
;   Checks input/output stream direction and retrieves the managed native handle.
(define (stream-h who stream input?)
  (unless ((if input? skia-input-stream? skia-output-stream?) stream)
    (raise-argument-error who (if input? "skia-input-stream?" "skia-output-stream?") stream))
  (native-stream-handle stream))

; budget : native-stream? -> exact-positive-integer?
;   Uses the stricter of the stream's retained limit and the current global byte limit.
(define (budget stream) (min (native-stream-limit stream) (current-skia-byte-limit)))

; input-meta : symbol? native-stream? cpointer? -> (values integer? integer?)
;   Checks native length and cursor capabilities, extent budget, and position bounds.
(define (input-meta who stream ptr)
  (unless (and (sk_stream_has_length ptr) (sk_stream_has_position ptr))
    (error who "native stream lacks the required length/position capabilities"))
  (define length (sk_stream_get_length ptr))
  (define position (sk_stream_get_position ptr))
  (stream-count who length (budget stream))
  (unless (<= position length) (error who "native stream position exceeds length"))
  (values length position))

; with-input : symbol? skia-input-stream? procedure? -> any/c
;   Lends a locked native input pointer with its validated length and current position.
(define (with-input who stream proc)
  (call-with-owned who (list (stream-h who stream #t))
    (lambda (ptr)
      (define-values (length position) (input-meta who stream ptr))
      (proc ptr length position))))

; wrap-input : symbol? symbol? exact-positive-integer? procedure? -> skia-input-stream?
;   Adopts an owned input stream and closes it if initial capability or budget checks fail.
(define (wrap-input who storage limit create)
  (define stream (make-native-stream (new-owned who 'stream-input create sk_stream_destroy)
                                    'input storage limit))
  (with-handlers ([(lambda (_) #t) (lambda (error) (skia-close! stream) (raise error))])
    (with-input who stream (lambda (_ptr _length _position) (void)))
    stream))

; make-memory-input-stream : bytes? [#:limit exact-positive-integer?] -> skia-input-stream?
;   Returns an input stream at byte position zero containing a copy of data.
(define (make-memory-input-stream bytes #:limit [limit (current-skia-byte-limit)])
  (define who 'make-memory-input-stream)
  (stream-byte-limit who limit)
  (unless (bytes? bytes) (raise-argument-error who "bytes?" bytes))
  (stream-count who (bytes-length bytes) limit)
  (define snapshot (bytes->immutable-bytes bytes))
  (skia-check!)
  (wrap-input who 'memory limit
    (lambda () (sk_memorystream_new_with_data snapshot (bytes-length snapshot) #t))))

; make-file-input-stream : path-string? [#:limit exact-positive-integer?] -> skia-input-stream?
;   Opens an existing regular file at position zero.
(define (make-file-input-stream filename #:limit [limit (current-skia-byte-limit)])
  (define who 'make-file-input-stream)
  (stream-byte-limit who limit)
  (unless (path-string? filename) (raise-argument-error who "path-string?" filename))
  (define path (path->complete-path filename))
  (define bytes (path->bytes path))
  (when (regexp-match? #rx#"\0" bytes) (error who "file path contains NUL"))
  (unless (file-exists? path) (error who "input file does not exist: ~a" path))
  (define stat (file-or-directory-stat path))
  (unless (= (bitwise-and (hash-ref stat 'mode) file-type-bits) regular-file-type-bits)
    (error who "native file streams require a regular file"))
  (stream-count who (hash-ref stat 'size) limit)
  (skia-check!)
  (wrap-input who 'file limit
    (lambda ()
      (define ptr (sk_filestream_new (bytes-append bytes #"\0")))
      (when (and ptr (not (sk_filestream_is_valid ptr)))
        (sk_stream_destroy ptr)
        (error who "native file stream could not open the file"))
      ptr)))

; input-stream-length : skia-input-stream? -> exact-nonnegative-integer?
;   Returns the total byte length, independently of the current cursor.
(define (input-stream-length stream)
  (with-input 'input-stream-length stream (lambda (_ptr length _position) length)))

; input-stream-position : skia-input-stream? -> exact-nonnegative-integer?
;   Returns the current zero-based byte position.
(define (input-stream-position stream)
  (with-input 'input-stream-position stream (lambda (_ptr _length position) position)))

; input-stream-at-end? : skia-input-stream? -> boolean?
;   Returns #t when the cursor equals the length or the native stream reports end-of-input.
(define (input-stream-at-end? stream)
  (with-input 'input-stream-at-end? stream
    (lambda (ptr length position) (or (= position length) (sk_stream_is_at_end ptr)))))

;;;
;;; Input Reads and Cursor Operations
;;;

; input-bytes : symbol? skia-input-stream? exact-nonnegative-integer? boolean? -> (or/c bytes?
;   eof-object?)
;   Reads or peeks bounded bytes, distinguishing end-of-stream from a native no-progress failure.
(define (input-bytes who stream count peek?)
  (stream-h who stream #t)
  (stream-count who count (budget stream))
  (with-input who stream
    (lambda (ptr length position)
      (define size (min count (- length position)))
      (cond [(zero? count) #""]
            [(zero? size) eof]
            [else
             (define bytes (make-bytes size))
             (define n ((if peek? sk_stream_peek sk_stream_read) ptr bytes size))
             (unless (<= n size) (error who "native read returned an invalid count"))
             (cond [(positive? n) (subbytes bytes 0 n)]
                   [(sk_stream_is_at_end ptr) eof]
                   [else (error who (if peek? "native peek unsupported or failed"
                                       "native read made no progress"))])]))))

; input-stream-read-bytes : skia-input-stream? exact-nonnegative-integer? -> (or/c bytes?
;   eof-object?)
;   Reads up to count bytes and advances the cursor by the returned byte count.
(define (input-stream-read-bytes stream count)
  (input-bytes 'input-stream-read-bytes stream count #f))

; input-stream-peek-bytes : skia-input-stream? exact-nonnegative-integer? -> (or/c bytes?
;   eof-object?)
;   Like input-stream-read-bytes, without advancing the cursor.
(define (input-stream-peek-bytes stream count)
  (input-bytes 'input-stream-peek-bytes stream count #t))

; input-stream-skip! : skia-input-stream? exact-nonnegative-integer? -> exact-nonnegative-integer?
;   Skips up to count remaining bytes and returns the number skipped.
(define (input-stream-skip! stream count)
  (define who 'input-stream-skip!)
  (stream-h who stream #t)
  (stream-count who count (budget stream))
  (with-input who stream
    (lambda (ptr length position)
      (define request (min count (- length position)))
      (define n (sk_stream_skip ptr request))
      (unless (<= n request) (error who "native skip returned an invalid count"))
      n)))

; input-stream-seek! : skia-input-stream? exact-nonnegative-integer? -> void?
;   Moves to the absolute byte position position, which must not exceed the stream length.
(define (input-stream-seek! stream position)
  (define who 'input-stream-seek!)
  (with-input who stream
    (lambda (ptr length _position)
      (stream-count who position length)
      (unless (and (sk_stream_seek ptr position) (= position (sk_stream_get_position ptr)))
        (error who "native seek failed"))))
  (void))

; input-stream-rewind! : skia-input-stream? -> void?
;   Moves the stream cursor to byte position zero.
(define (input-stream-rewind! stream)
  (with-input 'input-stream-rewind! stream
    (lambda (ptr _length _position)
      (unless (and (sk_stream_rewind ptr) (= 0 (sk_stream_get_position ptr)))
        (error 'input-stream-rewind! "native rewind failed"))))
  (void))

; input-stream-move! : skia-input-stream? exact-integer? -> void?
;   Moves by the signed byte offset relative to the current position.
(define (input-stream-move! stream offset)
  (define who 'input-stream-move!)
  (define edge (expt 2 (sub1 (* 8 (ctype-sizeof _long)))))
  (unless (and (exact-integer? offset) (<= (- edge) offset (sub1 edge)))
    (raise-argument-error who "exact integer representable as native long" offset))
  (with-input who stream
    (lambda (ptr length position)
      (stream-count who (+ position offset) length)
      (unless (and (sk_stream_move ptr offset) (= (+ position offset) (sk_stream_get_position ptr)))
        (error who "native relative seek failed"))))
  (void))

; copy-input : symbol? skia-input-stream? boolean? -> skia-input-stream?
;   Creates a checked fork at the current cursor or a duplicate at the beginning.
(define (copy-input who stream fork?)
  (with-input who stream
    (lambda (ptr length position)
      (define copied
        (wrap-input who (native-stream-storage stream) (budget stream)
          (lambda () ((if fork? sk_stream_fork sk_stream_duplicate) ptr))))
      (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! copied) (raise e))])
        (unless (and (= length (input-stream-length copied))
                     (= (if fork? position 0) (input-stream-position copied)))
          (error who "native duplicate/fork changed extent or cursor semantics"))
        copied))))

; input-stream-duplicate : skia-input-stream? -> skia-input-stream?
;   Returns an independently owned input stream at position zero with the same length and backing
;   kind.
(define (input-stream-duplicate stream) (copy-input 'input-stream-duplicate stream #f))

; input-stream-fork : skia-input-stream? -> skia-input-stream?
;   Like input-stream-duplicate, but starts at the original stream's current position.
(define (input-stream-fork stream) (copy-input 'input-stream-fork stream #t))

; input-stream->bytes : skia-input-stream? -> bytes?
;   Reads the entire unread suffix into an independent byte string and advances the cursor to the
;   end on success.
(define (input-stream->bytes stream)
  (define who 'input-stream->bytes)
  (with-input who stream
    (lambda (ptr length position)
      (define n (- length position))
      (cond [(zero? n) #""]
            [else
             ;; SkData::MakeFromStream borrows the input; it does NOT take it.
             ;; It requires exactly n bytes. A truncated file is an error.
             (define data
               (new-owned who 'data (lambda () (sk_data_new_from_stream ptr n)) sk_data_unref))
             (dynamic-wind void
               (lambda ()
                 (call-with-owned who (list data)
                   (lambda (dp)
                     (unless (= n (sk_data_get_size dp)) (error who "native data size disagrees"))
                     (define bytes (make-bytes n))
                     (define source (sk_data_get_data dp))
                     (unless source (error who "native data has no storage"))
                     (memcpy bytes source n)
                     bytes)))
               (lambda () (owned-close! who data)))]))))

;;;
;;; Output Streams and Memory Snapshots
;;;

; make-memory-output-stream : [#:limit exact-positive-integer?] -> skia-output-stream?
;   Returns an empty memory output stream.
(define (make-memory-output-stream #:limit [limit (current-skia-byte-limit)])
  (stream-byte-limit 'make-memory-output-stream limit)
  (skia-check!)
  (make-native-stream
   (new-owned 'make-memory-output-stream 'stream-output
              sk_dynamicmemorywstream_new sk_dynamicmemorywstream_destroy)
   'output 'memory limit))

; with-output : symbol? skia-output-stream? procedure? -> any/c
;   Lends a locked native output pointer with its checked written-byte count.
(define (with-output who stream proc)
  (call-with-owned who (list (stream-h who stream #f))
    (lambda (ptr)
      (define n (sk_wstream_bytes_written ptr))
      (stream-count who n (budget stream))
      (proc ptr n))))

; output-stream-write-bytes! : skia-output-stream? bytes? [exact-nonnegative-integer?] [(or/c
;   exact-nonnegative-integer? #f)] -> exact-nonnegative-integer?
;   Writes the slice from start, inclusive, to end, exclusive, and returns its byte count.
(define (output-stream-write-bytes! stream bytes [start 0] [end #f])
  (define who 'output-stream-write-bytes!)
  (define-values (from to) (stream-slice who bytes start end))
  (stream-h who stream #f)
  (stream-count who (- to from) (budget stream))
  (with-output who stream
    (lambda (ptr prior)
      (define n (- to from))
      ;; Check the full resulting logical size BEFORE allocating native blocks.
      (stream-count who (+ prior n) (budget stream))
      (define snapshot (subbytes bytes from to))
      (unless (and (sk_wstream_write ptr snapshot n)
                   (= (+ prior n) (sk_wstream_bytes_written ptr)))
        ;; A failed write may be partial. Poison this wrapper by closing it.
        (owned-close! who (native-stream-handle stream))
        (error who "native write failed; stream closed"))
      n)))

; output-stream-bytes-written : skia-output-stream? -> exact-nonnegative-integer?
;   Returns the current accumulated byte count.
(define (output-stream-bytes-written stream)
  (with-output 'output-stream-bytes-written stream (lambda (_ptr n) n)))

; memory-output-only : symbol? skia-output-stream? -> void?
;   Rejects file-backed output for operations that require memory-stream storage.
(define (memory-output-only who stream)
  (stream-h who stream #f)
  (unless (eq? (native-stream-storage stream) 'memory)
    (error who "operation requires a memory output stream, not file output")))

; output-stream->bytes : skia-output-stream? -> (and/c bytes? (not/c immutable?))
;   Returns an independent mutable copy of all bytes in a memory output stream, without clearing
;   it.
(define (output-stream->bytes stream)
  (memory-output-only 'output-stream->bytes stream)
  (with-output 'output-stream->bytes stream
    (lambda (ptr n)
      (define bytes (make-bytes n))
      (unless (zero? n) (sk_dynamicmemorywstream_copy_to ptr bytes))
      bytes)))

; output-stream-detach-input! : skia-output-stream? -> skia-input-stream?
;   Detaches a memory output stream's contents into an independently owned input stream at position
;   zero.
(define (output-stream-detach-input! stream)
  (define who 'output-stream-detach-input!)
  (memory-output-only who stream)
  (with-output who stream
    (lambda (ptr _n)
      (wrap-input who 'memory (budget stream)
        (lambda () (sk_dynamicmemorywstream_detach_as_stream ptr))))))

;;;
;;; Buffered Racket Port Adapters
;;;

; buffered-port->input-stream : input-port? [#:limit exact-positive-integer?] [#:close? boolean?]
;   [#:cancel-evt (or/c evt? #f)] -> skia-input-stream?
;   Buffers the unread port contents and returns a new memory input stream at zero.
(define (buffered-port->input-stream in #:limit [limit (current-skia-byte-limit)]
                                    #:close? [close? #f] #:cancel-evt [cancel #f])
  (define who 'buffered-port->input-stream)
  ;; Finish Racket I/O and its callbacks before entering any native allocation.
  (define bytes (read-port-buffered who in limit close? cancel))
  (make-memory-input-stream bytes #:limit limit))

; output-stream-write-port/buffered : skia-output-stream? output-port? [#:close? boolean?]
;   [#:cancel-evt (or/c evt? #f)] -> exact-nonnegative-integer?
;   Copies all contents of a memory output stream to the Racket output port and returns the number
;   of bytes written.
(define (output-stream-write-port/buffered stream out #:close? [close? #f] #:cancel-evt [cancel #f])
  ;; Snapshot first, then release all native borrows before running port code.
  (define bytes (output-stream->bytes stream))
  (write-port-buffered 'output-stream-write-port/buffered bytes out close? cancel))

(module* internals #f (provide with-input budget with-output stream-h))
