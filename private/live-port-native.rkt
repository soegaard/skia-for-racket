#lang racket/base
(require "codec-incremental-source.rkt")
(provide make-incremental-source/native)
;; 0.75b native worker callouts and callbacks, from the tested pure-FFI probe.
;; This private registry bypasses public Racket affinity/audit wrappers only for
;; independently referenced CPU inputs or exclusively leased native streams.
(require ffi/unsafe ffi/unsafe/global ffi/unsafe/os-thread racket/path racket/list "live-port-runtime.rkt" "live-native-lease.rkt")
(provide initialize-native! native-copy native-decode native-encode native-document
         native-seek-copy active-operation-count last-operation-report in-port-service?
         make-raster-reference make-picture-reference adopt-reference! reference-close!
         native-decode-image native-load-picture native-encode-image native-write-picture
         native-write-pages native-output-write! native-output-count
         native-symbols)
(define initializers '())
(define native-symbols '())
(define-syntax-rule (define-raw name type)
  (begin
    (define name #f)
    (set! native-symbols (cons 'name native-symbols))
    (set! initializers
          (cons (lambda (lib) (set! name (get-ffi-obj 'name lib type))) initializers))))
(define-cstruct _read-procs
  ([read _fpointer] [peek _fpointer] [at-end _fpointer] [has-position _fpointer]
   [has-length _fpointer] [rewind _fpointer] [position _fpointer] [seek _fpointer]
   [move _fpointer] [length _fpointer] [duplicate _fpointer] [fork _fpointer]
   [destroy _fpointer]) #:malloc-mode 'atomic-interior)
(define-cstruct _write-procs
  ([write _fpointer] [flush _fpointer] [written _fpointer] [destroy _fpointer])
  #:malloc-mode 'atomic-interior)
(define-cstruct _info
  ([space _pointer] [width _int32] [height _int32] [color _int] [alpha _int])
  #:malloc-mode 'atomic-interior)
(define-cstruct _rect ([left _float] [top _float] [right _float] [bottom _float])
  #:malloc-mode 'atomic-interior)
(define-cstruct _png
  ([filters _int] [zlib _int] [comments _pointer] [icc _pointer] [description _pointer])
  #:malloc-mode 'atomic-interior)
(define-cstruct _jpeg
  ([quality _int] [downsample _int] [alpha _int] [xmp _pointer] [icc _pointer] [description _pointer])
  #:malloc-mode 'atomic-interior)
(define-cstruct _webp
  ([compression _int] [quality _float] [icc _pointer] [description _pointer])
  #:malloc-mode 'atomic-interior)
(define-cstruct _pdf
  ([title _pointer] [author _pointer] [subject _pointer] [keywords _pointer]
   [creator _pointer] [producer _pointer] [creation _pointer] [modified _pointer]
   [dpi _float] [pdfa _stdbool] [quality _int]) #:malloc-mode 'atomic-interior)
(define-raw sk_version_get_milestone (_fun -> _int))
(define-raw sk_version_get_increment (_fun -> _int))
(define-raw sk_managedstream_set_procs (_fun _read-procs -> _void))
(define-raw sk_managedwstream_set_procs (_fun _write-procs -> _void))
(define-raw sk_managedstream_new (_fun #:blocking? #t _pointer -> _pointer))
(define-raw sk_managedstream_destroy (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_managedwstream_new (_fun #:blocking? #t _pointer -> _pointer))
(define-raw sk_managedwstream_destroy (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_stream_read (_fun #:blocking? #t _pointer _pointer _size -> _size))
(define-raw sk_stream_seek (_fun #:blocking? #t _pointer _size -> _stdbool))
(define-raw sk_wstream_write (_fun #:blocking? #t _pointer _pointer _size -> _stdbool))
(define-raw sk_wstream_flush (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_codec_new_from_stream (_fun #:blocking? #t _pointer _pointer -> _pointer))
(define-raw sk_codec_get_info (_fun #:blocking? #t _pointer _pointer -> _void))
(define-raw sk_codec_get_origin (_fun #:blocking? #t _pointer -> _int))
(define-raw sk_codec_get_pixels (_fun #:blocking? #t _pointer _pointer _pointer _size _pointer -> _int))
(define-raw sk_codec_destroy (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_colorspace_unref (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_data_new_uninitialized (_fun #:blocking? #t _size -> _pointer))
(define-raw sk_data_get_data (_fun #:blocking? #t _pointer -> _pointer))
(define-raw sk_data_unref (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_image_new_raster_copy (_fun #:blocking? #t _pointer _pointer _size -> _pointer))
(define-raw sk_image_unref (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_image_peek_pixels (_fun #:blocking? #t _pointer _pointer -> _stdbool))
(define-raw sk_pixmap_new (_fun #:blocking? #t -> _pointer))
(define-raw sk_pixmap_destructor (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_pngencoder_encode (_fun #:blocking? #t _pointer _pointer _pointer -> _stdbool))
(define-raw sk_jpegencoder_encode (_fun #:blocking? #t _pointer _pointer _pointer -> _stdbool))
(define-raw sk_webpencoder_encode (_fun #:blocking? #t _pointer _pointer _pointer -> _stdbool))
(define-raw sk_document_create_pdf_from_stream_with_metadata (_fun #:blocking? #t _pointer _pointer -> _pointer))
(define-raw sk_document_begin_page (_fun #:blocking? #t _pointer _float _float _pointer -> _pointer))
(define-raw sk_document_end_page (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_document_close (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_document_abort (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_document_unref (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_svgcanvas_create_with_stream (_fun #:blocking? #t _pointer _pointer -> _pointer))
(define-raw sk_canvas_destroy (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_paint_new (_fun #:blocking? #t -> _pointer))
(define-raw sk_paint_delete (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_paint_set_color (_fun #:blocking? #t _pointer _uint32 -> _void))
(define-raw sk_canvas_draw_rect (_fun #:blocking? #t _pointer _pointer _pointer -> _void))

(define-raw sk_colorspace_ref (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_image_make_raster_image (_fun #:blocking? #t _pointer -> _pointer))
(define-raw sk_picture_ref (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_picture_unref (_fun #:blocking? #t _pointer -> _void))
(define-raw sk_picture_serialize_to_stream (_fun #:blocking? #t _pointer _pointer -> _void))
(define-raw sk_picture_deserialize_from_stream (_fun #:blocking? #t _pointer -> _pointer))
(define-raw sk_stream_peek (_fun #:blocking? #t _pointer _pointer _size -> _size))
(define-raw sk_canvas_draw_picture (_fun #:blocking? #t _pointer _pointer _pointer _pointer -> _void))
(define-raw sk_wstream_bytes_written (_fun #:blocking? #t _pointer -> _size))

(define (dispatch-managed-callback thunk)
  (if (zero? (active-operation-count)) (thunk) (dispatch-callback thunk)))
(define _read-cb (_fun #:async-apply dispatch-managed-callback _pointer _pointer _pointer _size -> _size))
(define _bool-cb (_fun #:async-apply dispatch-managed-callback _pointer _pointer -> _stdbool))
(define _size-cb (_fun #:async-apply dispatch-managed-callback _pointer _pointer -> _size))
(define _seek-cb (_fun #:async-apply dispatch-managed-callback _pointer _pointer _size -> _stdbool))
(define _move-cb (_fun #:async-apply dispatch-managed-callback _pointer _pointer _long -> _stdbool))
(define _clone-cb (_fun #:async-apply dispatch-managed-callback _pointer _pointer -> _pointer))
(define _void-cb (_fun #:async-apply dispatch-managed-callback _pointer _pointer -> _void))
(define _write-cb (_fun #:async-apply dispatch-managed-callback _pointer _pointer _pointer _size -> _stdbool))
(define current-output-transform (make-parameter values))
(provide current-output-transform)
(define callback-roots '())
(define callback-pointers '())
(define callback-tables #f)
(define library #f)
(define (cb type fallback proc [input-kind #f])
  (define ordinary (guarded-callback fallback proc))
  (define wrapped
    (lambda arguments
      (if (and input-kind (cadr arguments))
          (incremental-source-callback input-kind fallback arguments)
          (apply ordinary arguments))))
  (define pointer (function-ptr wrapped type))
  (set! callback-roots (cons wrapped callback-roots))
  (set! callback-pointers (cons pointer callback-pointers))
  pointer)
(define (remaining j)
  (if (operation-length j)
      (- (operation-length j) (operation-position j))
      (add1 (- (operation-limit j) (operation-position j)))))
(define (read-chunk j n peek?)
  (define buffer (make-bytes n))
  (let loop ([at 0])
    (check-cancel! j)
    (cond
      [(= at n) (values buffer #f)]
      [else
       (define got
         (if peek?
             (peek-bytes-avail!* buffer at #f (operation-input j) at n)
             (read-bytes-avail!* buffer (operation-input j) at n)))
       (cond
         [(eof-object? got) (values (subbytes buffer 0 at) #t)]
         [(procedure? got) (error 'live-ffi "binary input contains a special value")]
         [(zero? got)
          ;; For a partially satisfied peek, the port itself can already be
          ;; ready because the earlier peeked prefix remains unread. A short
          ;; alarm avoids spinning on that prefix; cancellation remains live.
          (wait-port! j (if (and peek? (positive? at))
                           (alarm-evt (+ (current-inexact-milliseconds) 1))
                           (operation-input j)))
          (loop at)]
         [else (loop (+ at got))])])) )
(define (read-callback j _stream _context destination n)
  (operation-note! 'reads)
  (let loop ([total 0])
    (check-cancel! j)
    (cond
      [(or (= total n) (zero? (remaining j))) total]
      [else
       (define ask (min CHUNK (- n total) (remaining j)))
       (define-values (bytes eof?) (read-chunk j ask #f))
       (define got (bytes-length bytes))
       (unless (<= (+ (operation-position j) got) (operation-limit j))
         (error 'live-ffi "input exceeds logical byte limit"))
       (when (and destination (positive? got)) (memcpy (ptr-add destination total) bytes got))
       (set-operation-position! j (+ (operation-position j) got))
       (set-operation-eof?! j eof?)
       (when (and eof? (operation-length j) (< (operation-position j) (operation-length j)))
         (error 'live-ffi "input ended before declared length"))
       (if eof? (+ total got) (loop (+ total got)))])))
(define (peek-callback j _stream _context destination n)
  (operation-note! 'peeks)
  (check-cancel! j)
  (define ask (min CHUNK n (remaining j)))
  (cond
    [(or (zero? ask) (not destination)) 0]
    [else
     (define-values (bytes eof?) (read-chunk j ask #t))
     (define got (bytes-length bytes))
     (unless (<= (+ (operation-position j) got) (operation-limit j))
       (error 'live-ffi "peek exceeds logical byte limit"))
     (when (positive? got) (memcpy destination bytes got))
     (when (and (zero? got) eof?) (set-operation-eof?! j #t))
     got]))
(define (seek-callback j _stream _context offset)
  (check-cancel! j)
  (and (operation-seekable? j)
       (<= offset (operation-length j))
       (begin
         (file-position (operation-input j) (+ (operation-base j) offset))
         (unless (= (file-position (operation-input j)) (+ (operation-base j) offset))
           (error 'live-ffi "port seek did not reach the requested position"))
         (set-operation-position! j offset)
         (set-operation-eof?! j #f)
         (operation-note! 'seeks)
         #t)))
(define (write-callback j _stream _context source n)
  (operation-note! 'writes)
  (check-cancel! j)
  (unless (<= n (- (operation-limit j) (operation-written j)))
    (error 'live-ffi "output exceeds logical byte limit"))
  (let chunks ([offset 0])
    (when (< offset n)
      (check-cancel! j)
      (define amount (min CHUNK (- n offset)))
      (define bytes (make-bytes amount))
      (memcpy bytes (ptr-add source offset) amount)
      (operation-note-max! 'max-copy amount)
      (define transformed ((current-output-transform) bytes))
      (unless (bytes? transformed) (error 'live-ffi "invalid private output transform"))
      (unless (<= (bytes-length transformed) (- (operation-limit j) (operation-written j)))
        (error 'live-ffi "transformed output exceeds logical byte limit"))
      (let write ([at 0])
        (check-cancel! j)
        (when (< at (bytes-length transformed))
          (define got (write-bytes-avail* transformed (operation-output j) at
                                        (min (bytes-length transformed) (+ at CHUNK))))
          (if (and got (positive? got))
              (begin (set-operation-written! j (+ (operation-written j) got)) (write (+ at got)))
              (begin (wait-port! j (operation-output j)) (write at)))))
      (chunks (+ offset amount))))
  #t)
(define (initialize-native! path)
  (unless (and (eq? (system-type 'vm) 'chez-scheme) (os-thread-enabled?) (= (ctype-sizeof _pointer) 8))
    (error 'live-ffi "live streaming requires 64-bit Racket CS"))
  (when library (error 'live-ffi "already initialized in this process"))
  (for ([size (in-list (list (ctype-sizeof _read-procs) (ctype-sizeof _write-procs)
                            (ctype-sizeof _info) (ctype-sizeof _png) (ctype-sizeof _jpeg)
                            (ctype-sizeof _webp) (ctype-sizeof _pdf)))]
        [expected (in-list '(104 32 24 32 40 24 80))])
    (unless (= size expected) (error 'live-ffi "FFI record layout differs from reviewed m119")))
  (define lib (ffi-lib path))
  (for ([initialize (in-list initializers)]) (initialize lib))
  (unless (and (= (sk_version_get_milestone) 119) (= (sk_version_get_increment) 0))
    (error 'live-ffi "requires the pinned m119.0 native library"))
  (define r
    (make-read-procs
     (cb _read-cb 0 read-callback 'read)
     (cb _read-cb 0 peek-callback 'peek)
     (cb _bool-cb #t (lambda (j s c)
                       (or (and (operation-error j) #t) (operation-eof? j)
                           (and (operation-length j) (= (operation-position j) (operation-length j))))) 'at-end)
     (cb _bool-cb #f (lambda (j s c) #t) 'has-position)
     (cb _bool-cb #f (lambda (j s c) (and (operation-length j) #t)) 'has-length)
     (cb _bool-cb #f (lambda (j s c) (seek-callback j s c 0)) 'rewind)
     (cb _size-cb 0 (lambda (j s c) (operation-position j)) 'position)
     (cb _seek-cb #f seek-callback 'seek)
     (cb _move-cb #f (lambda (j s c by)
                       (and (>= (+ (operation-position j) by) 0)
                            (seek-callback j s c (+ (operation-position j) by)))) 'move)
     (cb _size-cb 0 (lambda (j s c) (or (operation-length j) 0)) 'length)
     (cb _clone-cb #f (lambda (j s c) #f) 'duplicate)
     (cb _clone-cb #f (lambda (j s c) #f) 'fork)
     (cb _void-cb (void) (lambda (j s c) (operation-note! 'input-destroyed)) 'destroy)))
  (define w
    (make-write-procs
     (cb _write-cb #f write-callback)
     ;; Borrowed Racket output ports are intentionally not flushed by Skia.
     (cb _void-cb (void) (lambda (j s c) (operation-note! 'flushes)))
     (cb _size-cb 0 (lambda (j s c) (operation-written j)))
     (cb _void-cb (void) (lambda (j s c) (operation-note! 'output-destroyed)))))
  ;; Claim once per process. A second module instance/place must not replace
  ;; installed callbacks. Another noncooperating Skia binding is unsupported.
  (define marker (malloc 1 'raw))
  (when (register-process-global #"skia-for-racket/pure-live-ffi-probe/m119/v1" marker)
    (free marker)
    (error 'live-ffi "managed callbacks already claimed by another module or place"))
  (set! callback-tables (list r w))
  (sk_managedstream_set_procs r)
  (sk_managedwstream_set_procs w)
  (set! library lib)
  (void))

(define (checked-ready)
  (unless library (error 'live-ffi "initialize-native! must succeed first")))
(define (checked-result answer stats read written)
  (unless (and (vector? answer) (eq? (vector-ref answer 0) 'ok))
    (error 'live-ffi "native operation rejected input or allocation: ~s" answer))
  (values answer stats read written))
(define (native-copy in out #:limit [limit (* 16 1024 1024)] #:cancel-evt [cancel #f] #:finish [finish void])
  (checked-ready)
  (define scratch (malloc CHUNK 'atomic-interior))
  (call-with-values
   (lambda ()
     (run-operation
      (lambda ()
        (define input (sk_managedstream_new #f))
        (define output (sk_managedwstream_new #f))
        (define okay
          (and input output
               (let loop ()
                 (define n (sk_stream_read input scratch CHUNK))
                 (and (or (zero? n) (sk_wstream_write output scratch n))
                      (or (< n CHUNK) (loop))))))
        (when output (sk_managedwstream_destroy output))
        (when input (sk_managedstream_destroy input))
        (void/reference-sink scratch)
        (vector (if okay 'ok 'native-failure)))
      #:input in #:output out #:limit limit #:cancel-evt cancel #:finish finish))
   checked-result))
(define (native-seek-copy in out length offset #:limit [limit (* 16 1024 1024)])
  (checked-ready)
  (unless (and (exact-nonnegative-integer? offset) (<= offset length))
    (error 'native-seek-copy "invalid offset"))
  (define scratch (malloc CHUNK 'atomic-interior))
  (call-with-values
   (lambda ()
     (run-operation
      (lambda ()
        (define input (sk_managedstream_new #f))
        (define output (sk_managedwstream_new #f))
        (define okay
          (and input output (sk_stream_seek input offset)
               (let loop ()
                 (define n (sk_stream_read input scratch CHUNK))
                 (and (or (zero? n) (sk_wstream_write output scratch n))
                      (or (< n CHUNK) (loop))))))
        (when output (sk_managedwstream_destroy output))
        (when input (sk_managedstream_destroy input))
        (void/reference-sink scratch)
        (vector (if okay 'ok 'native-failure)))
      #:input in #:output out #:length length #:seekable? #t #:limit limit))
   checked-result))
(define (native-decode in #:limit [limit (* 16 1024 1024)] #:length [length #f]
                       #:seekable? [seekable? #f] #:cancel-evt [cancel #f])
  (checked-ready)
  (define info (make-info #f 0 0 0 0))
  (define result-code (malloc _int 'atomic-interior))
  (ptr-set! result-code _int -1)
  (call-with-values
   (lambda ()
     (run-operation
      (lambda ()
        (define stream (sk_managedstream_new #f))
        ;; MakeFromStream consumes the stream even on a null codec result.
        (define codec (and stream (sk_codec_new_from_stream stream result-code)))
        (define answer '#(native-codec-rejection))
        (when codec
          (sk_codec_get_info codec info)
          (define w (info-width info)) (define h (info-height info))
          (define origin (sk_codec_get_origin codec))
          (define count (* w h 4))
          (when (and (<= 1 w 32768) (<= 1 h 32768) (<= count limit) (= origin 1))
            (set-info-color! info 4) (set-info-alpha! info 2)
            (define data (sk_data_new_uninitialized count))
            (when data
              (define pixels (sk_data_get_data data))
              (when pixels
                ;; Notify the Racket side while this real codec retains input.
                (request-in-racket (lambda () (operation-note! 'codec-created) #t))
                (when (= (sk_codec_get_pixels codec info pixels (* w 4) #f) 0)
                  (define copied
                    (request-in-racket
                     (lambda ()
                       (define bytes (make-bytes count))
                       (memcpy bytes pixels count)
                       bytes)))
                  (when copied (set! answer (vector 'ok copied w h)))))
              (sk_data_unref data)))
          (when (info-space info) (sk_colorspace_unref (info-space info)))
          (sk_codec_destroy codec))
        (void/reference-sink info result-code)
        answer)
      #:input in #:limit limit #:length length #:seekable? seekable? #:cancel-evt cancel))
   checked-result))
(define (native-encode bytes width height out #:format [format 'png]
                       #:limit [limit (* 16 1024 1024)] #:cancel-evt [cancel #f])
  (checked-ready)
  (unless (and (bytes? bytes) (exact-positive-integer? width) (exact-positive-integer? height)
               (<= width 32768) (<= height 32768)
               (= (bytes-length bytes) (* width height 4))
               (<= (bytes-length bytes) limit) (memq format '(png jpeg webp)))
    (error 'native-encode "invalid RGBA input, dimensions, format, or byte limit"))
  (define count (bytes-length bytes))
  (define storage (malloc count 'atomic-interior))
  (memcpy storage (bytes-copy bytes) count)
  (define info (make-info #f width height 4 3))
  (define options (case format [(png) (make-png #xf8 6 #f #f #f)]
                              [(jpeg) (make-jpeg 95 0 0 #f #f #f)]
                              [(webp) (make-webp 1 100.0 #f #f)]))
  (define encode (case format [(png) sk_pngencoder_encode] [(jpeg) sk_jpegencoder_encode]
                             [(webp) sk_webpencoder_encode]))
  (call-with-values
   (lambda ()
     (run-operation
      (lambda ()
        (define image (sk_image_new_raster_copy info storage (* width 4)))
        (define pixmap (sk_pixmap_new))
        (define output (sk_managedwstream_new #f))
        (define okay (and image pixmap output (sk_image_peek_pixels image pixmap)
                           (encode output pixmap options)))
        (when output (sk_managedwstream_destroy output))
        (when pixmap (sk_pixmap_destructor pixmap))
        (when image (sk_image_unref image))
        (void/reference-sink info storage options)
        (vector (if okay 'ok 'native-encode-failure)))
      #:output out #:limit limit #:cancel-evt cancel))
   checked-result))
(define (native-document out format #:limit [limit (* 16 1024 1024)] #:cancel-evt [cancel #f])
  (checked-ready)
  (unless (memq format '(pdf svg)) (error 'native-document "expected pdf or svg"))
  (define bounds (make-rect 0.0 0.0 64.0 48.0))
  (define metadata (make-pdf #f #f #f #f #f #f #f #f 144.0 #f 101))
  (call-with-values
   (lambda ()
     (run-operation
      (lambda ()
        (define output (sk_managedwstream_new #f))
        (define paint (sk_paint_new))
        (define okay #f)
        (when (and output paint)
          (sk_paint_set_color paint #xff336699)
          (cond
            [(eq? format 'pdf)
             (define doc (sk_document_create_pdf_from_stream_with_metadata output metadata))
             (when doc
               (define canvas (sk_document_begin_page doc 64.0 48.0 #f))
               (cond
                 [canvas
                  (sk_canvas_draw_rect canvas bounds paint)
                  (sk_document_end_page doc)
                  (request-in-racket (lambda () (operation-note! 'before-close) #t))
                  (sk_document_close doc)
                  (set! okay #t)]
                 [else (sk_document_abort doc)])
               (sk_document_unref doc))]
            [else
             (define canvas (sk_svgcanvas_create_with_stream bounds output))
             (when canvas
               (sk_canvas_draw_rect canvas bounds paint)
               (request-in-racket
                (lambda ()
                  (operation-note! 'bytes-before-close (operation-written current-operation))
                  #t))
               (sk_canvas_destroy canvas)
               (set! okay #t))]))
        (when paint (sk_paint_delete paint))
        (when output (sk_managedwstream_destroy output))
        (void/reference-sink bounds metadata)
        (vector (if okay 'ok 'native-document-failure)))
      #:output out #:limit limit #:cancel-evt cancel))
   checked-result))

;; Production consumers. Public wrappers have already validated affinity and
;; acquire immutable CPU references. No existing public wrapper is run on the
;; OS worker. Leases are retained through its last call, then released by the
;; service-owned finish hook. Default probe operations above remain available
;; only for the retained acceptance harness.
(define (make-raster-reference pointer)
  (make-native-reference (sk_image_make_raster_image pointer) sk_image_unref))
(define (make-picture-reference pointer)
  (sk_picture_ref pointer)
  (make-native-reference pointer sk_picture_unref))
(define (native-output-count pointer) (sk_wstream_bytes_written pointer))
(define (native-output-write! pointer bytes start end)
  ;; This sink is called on the Racket service thread. It never invokes user
  ;; code or managed streams: pointer is an exclusively pinned file/memory sink.
  (define n (- end start))
  (define scratch (malloc (max 1 n) 'atomic-interior))
  (when (positive? n) (memcpy scratch (subbytes bytes start end) n))
  (define prior (sk_wstream_bytes_written pointer))
  (unless (and (sk_wstream_write pointer scratch n)
               (= (+ prior n) (sk_wstream_bytes_written pointer)))
    (error 'live-streams "native output write failed (partial output is possible)"))
  (void/reference-sink scratch)
  n)

(define (native-encode-image ref out format quality compression downsample alpha lossless?
                             limit cancel finish)
  (checked-ready)
  (define image (reference-pointer ref))
  (define options
    (case format
      [(png) (make-png #xf8 compression #f #f #f)]
      [(jpeg) (make-jpeg quality downsample alpha #f #f #f)]
      [(webp) (make-webp (if lossless? 1 0) (exact->inexact quality) #f #f)]))
  (define encode (case format [(png) sk_pngencoder_encode] [(jpeg) sk_jpegencoder_encode]
                              [(webp) sk_webpencoder_encode]))
  (call-with-values
   (lambda ()
     (run-operation
      (lambda ()
        (define pixmap (sk_pixmap_new))
        (define output (sk_managedwstream_new #f))
        (define okay (and pixmap output (sk_image_peek_pixels image pixmap)
                           (encode output pixmap options)))
        (when output (sk_managedwstream_destroy output))
        (when pixmap (sk_pixmap_destructor pixmap))
        (void/reference-sink ref options)
        (vector (if okay 'ok 'native-encode-failure)))
      #:output out #:limit limit #:cancel-evt cancel #:finish finish))
   checked-result))
(define (native-write-picture ref out limit cancel finish)
  (checked-ready)
  (define pointer (reference-pointer ref))
  (call-with-values
   (lambda ()
     (run-operation
      (lambda ()
        (define output (sk_managedwstream_new #f))
        (define written 0)
        (when output
          (sk_picture_serialize_to_stream pointer output)
          (set! written (sk_wstream_bytes_written output))
          (sk_managedwstream_destroy output))
        (void/reference-sink ref)
        (vector (if (positive? written) 'ok 'native-picture-write-failure)))
      #:output out #:limit limit #:cancel-evt cancel #:finish finish))
   checked-result))

(define (native-decode-image in length seekable? limit cancel normalize finish)
  (checked-ready)
  (define info (make-info #f 0 0 0 0))
  (define result-code (malloc _int 'atomic-interior))
  (ptr-set! result-code _int -1)
  (call-with-values
   (lambda ()
     (run-operation
      (lambda ()
        (define stream (sk_managedstream_new #f))
        (define codec (and stream (sk_codec_new_from_stream stream result-code)))
        (define answer '#(native-codec-rejection))
        (when codec
          (sk_codec_get_info codec info)
          (define w (info-width info)) (define h (info-height info))
          (define origin (sk_codec_get_origin codec))
          (define count (* w h 4))
          (when (and (<= 1 w 32768) (<= 1 h 32768) (<= count limit) (<= 1 origin 8))
            ;; Keep the codec's color-space reference while making an independent
            ;; premultiplied RGBA image. This is one-shot decode, not a session.
            (set-info-color! info 4) (set-info-alpha! info 2)
            (define data (sk_data_new_uninitialized count))
            (when data
              (define pixels (sk_data_get_data data))
              (when (and pixels (= (sk_codec_get_pixels codec info pixels (* w 4) #f) 0))
                (define transformed
                  (request-in-racket
                   (lambda ()
                     (define bytes (make-bytes count))
                     (memcpy bytes pixels count)
                     (call-with-values (lambda () (normalize w h bytes origin)) vector))))
                (when transformed
                  (define width (vector-ref transformed 0))
                  (define height (vector-ref transformed 1))
                  (define storage (vector-ref transformed 2))
                  ;; The service supplies immobile storage, not a movable byte
                  ;; string, so GC during later native callbacks is safe.
                  (set-info-width! info width) (set-info-height! info height)
                  (define image (sk_image_new_raster_copy info storage (* width 4)))
                  (when image
                    (define ref (request-in-racket (lambda () (make-native-reference image sk_image_unref))))
                    (if ref (set! answer (vector 'ok ref width height)) (sk_image_unref image)))
                  (void/reference-sink transformed)))
              (sk_data_unref data)))
          (when (info-space info) (sk_colorspace_unref (info-space info)))
          (sk_codec_destroy codec))
        (void/reference-sink info result-code)
        answer)
      #:input in #:length length #:seekable? seekable? #:limit limit #:cancel-evt cancel #:finish finish))
   checked-result))
(define (native-load-picture in length seekable? limit cancel check-header finish)
  (checked-ready)
  (define header (malloc 29 'atomic-interior))
  (call-with-values
   (lambda ()
     (run-operation
      (lambda ()
        (define stream (sk_managedstream_new #f))
        (define answer '#(native-picture-read-failure))
        (when stream
          (define count (sk_stream_peek stream header 29))
          (define valid
            (request-in-racket
             (lambda ()
               (define bytes (make-bytes count))
               (when (positive? count) (memcpy bytes header count))
               (check-header bytes)
               #t)))
          (when valid
            ;; This constructor BORROWS the managed stream. Destroy it after
            ;; deserialization; the result has its own immutable content.
            (define picture (sk_picture_deserialize_from_stream stream))
            (when picture
              (define ref (request-in-racket (lambda () (make-native-reference picture sk_picture_unref))))
              (if ref (set! answer (vector 'ok ref)) (sk_picture_unref picture))))
          (sk_managedstream_destroy stream))
        (void/reference-sink header)
        answer)
      #:input in #:length length #:seekable? seekable? #:limit limit #:cancel-evt cancel #:finish finish))
   checked-result))
(define (native-write-pages refs sizes out format dpi limit cancel finish)
  (checked-ready)
  (define pointers (map reference-pointer refs))
  (define bounds (make-rect 0.0 0.0 (caar sizes) (cadar sizes)))
  (define metadata (make-pdf #f #f #f #f #f #f #f #f dpi #f 101))
  (call-with-values
   (lambda ()
     (run-operation
      (lambda ()
        (define output (sk_managedwstream_new #f))
        (define okay #f)
        (when output
          (cond
            [(eq? format 'pdf)
             (define doc (sk_document_create_pdf_from_stream_with_metadata output metadata))
             (when doc
               (set! okay
                 (let pages ([ps pointers] [ss sizes])
                   (cond [(null? ps) #t]
                         [else
                          (define canvas (sk_document_begin_page doc (caar ss) (cadar ss) #f))
                          (and canvas
                               (begin
                                 (sk_canvas_draw_picture canvas (car ps) #f #f)
                                 (sk_document_end_page doc)
                                 (pages (cdr ps) (cdr ss))))])))
               (if okay (sk_document_close doc) (sk_document_abort doc))
               (sk_document_unref doc))]
            [else
             (define canvas (sk_svgcanvas_create_with_stream bounds output))
             (when canvas
               (sk_canvas_draw_picture canvas (car pointers) #f #f)
               (sk_canvas_destroy canvas)
               (set! okay #t))])
          (sk_managedwstream_destroy output))
        (void/reference-sink refs bounds metadata)
        (vector (if okay 'ok 'native-document-failure)))
      #:output out #:limit limit #:cancel-evt cancel #:finish finish))
   checked-result))

;; Private retained-memory sources share the process-global provider with live
;; ports. Their non-null context selects only bounded, nonblocking memory work.
(define (make-incremental-source/native input)
  (checked-ready)
  (define context (incremental-source-register! input))
  (with-handlers ([(lambda (_) #t)
                   (lambda (e) (incremental-source-unregister! context) (raise e))])
    (or (sk_managedstream_new context)
        (error 'codec-incremental-step! "native managed input allocation failed"))))
