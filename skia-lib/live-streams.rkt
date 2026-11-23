#lang racket/base

;;;
;;; Live Port Streaming
;;;

;; Reads and writes encoded images, pictures, and documents through Racket ports.
;; This public streaming layer coordinates native callbacks, port lifetimes, and explicit
;; publication or completion behavior.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe ffi/unsafe/atomic racket/list
         "private/core.rkt" "private/native.rkt" "private/lifetime.rkt"
         "private/check.rkt" "private/stream-buffer.rkt" "private/stream-resource.rkt"
         "private/live-port-util.rkt" "private/live-native-lease.rkt"
         "private/color-output-util.rkt" "private/icc-encoding.rkt"
         (prefix-in worker: "private/live-port-native.rkt")
         (only-in "private/live-port-runtime.rkt" in-port-service? active-operation-count)
         "private/picture-util.rkt" "private/codec-util.rkt"
         "private/output-util.rkt" "private/pdf-util.rkt" "private/audit-trace.rkt"
         "streams.rkt" "pictures.rkt" "output.rkt" (submod "streams.rkt" internals)
         (prefix-in raw: (submod "private/core.rkt" live-stream-internals)))
(provide live-streams-check! live-streams-available?
         image-from-port picture-from-port copy-port/streaming image->port picture->port output->port
         image-write-stream! picture-write-stream! output-write-stream!)

;;;
;;; Callback Bridge Initialization
;;;

; initialized? : boolean?
;   Records whether the process-wide live-stream callback bridge has been initialized.
(define initialized? #f)

; live-streams-check! : -> void?
;   Initializes and checks the live-stream support library and its native bridge.
(define (live-streams-check!)
  (when (in-port-service?) (error 'live-streams-check! "live port operations cannot re-enter"))
  ;; Resolve the pinned library on the Racket thread, never on an OS worker.
  (unless initialized?
    (skia-check!)
    (define path (skia-native-library-path))
    (call-as-atomic
     (lambda ()
       (unless initialized?
         (worker:initialize-native! path)
         (set! initialized? #t)))))
  (void))

; live-streams-available? : -> boolean?
;   Calls live-streams-check!
(define (live-streams-available?)
  (with-handlers ([exn:fail? (lambda (_) #f)]) (live-streams-check!) #t))

;;;
;;; Operation Validation and Cleanup
;;;

; options! : symbol? any/c any/c any/c boolean? boolean? boolean? any/c any/c -> void?
;   Validates live-port options and cancellation before requiring an idle callback bridge.
(define (options! who in out length seek? close-in? close-out? limit cancel)
  (live-port-options who in out length seek? close-in? close-out? limit cancel)
  (check-live-cancel who cancel)
  (when (positive? (active-operation-count))
    (error who "another live port operation is active"))
  (live-streams-check!))
;; The protected service thread calls finish once after native teardown, even
;; when the initiating thread is killed. Validation errors do not take ownership
;; of the user's ports. Always finish every cleanup; preserve the first error.

; make-finish : any/c any/c boolean? boolean? list? [procedure?] -> procedure?
;   Builds cleanup that releases references and selected ports, preserving the first cleanup
;   failure.
(define (make-finish in out close-in? close-out? refs [after void])
  (lambda (okay?)
    (define first #f)
    (define (attempt thunk)
      (with-handlers ([(lambda (_) #t) (lambda (e) (unless first (set! first (cons #t e))))])
        (thunk)))
    (attempt (lambda () (after okay?)))
    (for ([ref (in-list refs)]) (attempt (lambda () (reference-close! ref))))
    (when (and close-in? in (not (port-closed? in))) (attempt (lambda () (close-input-port in))))
    (when (and close-out? out (not (port-closed? out))) (attempt (lambda () (close-output-port out))))
    (when first (raise (cdr first)))))

; written-result : any/c any/c any/c exact-nonnegative-integer? -> exact-nonnegative-integer?
;   Selects the written-byte count from a completed live-stream operation.
(define (written-result _answer _stats _read written) written)

; with-ref : any/c procedure? -> any/c
;   Ensures a retained native reference is released even if launch fails or control escapes.
(define (with-ref ref proc)
  ;; finish owns release after launch; this covers errors before launch. Both
  ;; paths are idempotent. A private finalizer covers forced caller termination.
  (dynamic-wind void (lambda () (proc ref)) (lambda () (reference-close! ref))))

;;;
;;; Live Input and Copying
;;;

; image-from-port : input-port? [#:length (or/c exact-nonnegative-integer? #f)] [#:seekable?
;   boolean?] [#:normalize-origin? boolean?] [#:limit exact-positive-integer?] [#:close? boolean?]
;   [#:cancel-evt (or/c evt? #f)] -> image?
;   Decodes the first image from live input and returns an independently owned CPU image.
(define (image-from-port in #:length [length #f] #:seekable? [seek? #f]
                         #:normalize-origin? [normalize? #t] #:limit [limit (current-skia-byte-limit)]
                         #:close? [close? #f] #:cancel-evt [cancel #f])
  (define who 'image-from-port)
  (boolean who normalize?)
  (unless (input-port? in) (raise-argument-error who "input-port?" in))
  (options! who in #f length seek? close? #f limit cancel)
  (define (normalize w h bytes origin)
    (define-values (width height copied)
      (if normalize?
          (orient-rgba-bytes
           who w h bytes (enum-name who origin encoded-origin-values "encoded origin"))
          (values w h bytes)))
    (define memory (malloc (bytes-length copied) 'atomic-interior))
    (memcpy memory copied (bytes-length copied))
    (values width height memory))
  (define-values (answer _notes _read _written)
    (worker:native-decode-image in length seek? limit cancel normalize
                               (make-finish in #f close? #f '())))
  (define ref (vector-ref answer 1))
  (with-ref ref
    (lambda (lease)
      (raw:make-image-record
       (new-owned who 'image (lambda () (adopt-reference! lease)) sk_image_unref)
       (vector-ref answer 2) (vector-ref answer 3)))))

; picture-from-port : input-port? [#:trusted? boolean?] [#:width (or/c real? #f)] [#:height (or/c
;   real? #f)] [#:length (or/c exact-nonnegative-integer? #f)] [#:seekable? boolean?] [#:limit
;   exact-positive-integer?] [#:close? boolean?] [#:cancel-evt (or/c evt? #f)] -> picture?
;   Loads a picture from trusted live SKP input.
(define (picture-from-port in #:trusted? [trusted? #f] #:width [width #f] #:height [height #f]
                           #:length [length #f] #:seekable? [seek? #f]
                           #:limit [limit (current-skia-byte-limit)]
                           #:close? [close? #f]
                           #:cancel-evt [cancel #f])
  (define who 'picture-from-port)
  (check-picture-trust who trusted?)
  (define size (picture-size-override who width height))
  (stream-byte-limit who limit) (stream-count who 29 limit)
  (unless (input-port? in) (raise-argument-error who "input-port?" in))
  (options! who in #f length seek? close? #f limit cancel)
  (define-values (answer _notes _read _written)
    (worker:native-load-picture in length seek? limit cancel
      (lambda (bytes) (picture-header who bytes) (void))
      (make-finish in #f close? #f '())))
  (with-ref (vector-ref answer 1)
    (lambda (lease)
      (define handle (new-owned who 'picture (lambda () (adopt-reference! lease)) sk_picture_unref))
      (with-handlers ([(lambda (_) #t) (lambda (e) (owned-close! who handle) (raise e))])
        (define bounds
          (call-with-owned who (list handle)
            (lambda (p) (raw:stream-picture-bounds who p))))
        (raw:make-picture-record handle (if size (vector-ref size 0) (vector-ref bounds 2))
                                   (if size (vector-ref size 1) (vector-ref bounds 3)))))))

; copy-port/streaming : input-port? output-port? [#:limit exact-positive-integer?] [#:close-input?
;   boolean?] [#:close-output? boolean?] [#:cancel-evt (or/c evt? #f)] -> exact-nonnegative-integer?
;   Copies input through EOF to a distinct output port and returns the number of bytes written.
(define (copy-port/streaming in out #:limit [limit (current-skia-byte-limit)]
                            #:close-input? [close-in? #f]
                            #:close-output? [close-out? #f]
                            #:cancel-evt [cancel #f])
  (define who 'copy-port/streaming)
  (unless (input-port? in) (raise-argument-error who "input-port?" in))
  (unless (output-port? out) (raise-argument-error who "output-port?" out))
  (options! who in out #f #f close-in? close-out? limit cancel)
  (call-with-values
   (lambda () (worker:native-copy in out #:limit limit #:cancel-evt cancel
                                #:finish (make-finish in out close-in? close-out? '())))
   written-result))

;;;
;;; Encoded Image and Picture Output
;;;

; call-with-encoding-references : symbol? image? any/c any/c any/c procedure? -> any/c
;   Prepares converted pixels and independent native profile storage for worker-owned encoding.
(define (call-with-encoding-references who image space profile description proc)
  (define checked (checked-encoding-profile who profile))
  (icc-description-bytes who checked description)
  (call-with-owned 'image->encoded-bytes (list (raw:image-h who image)) (lambda (_) (void)))
  (raw:call-with-output-image who image space
    (lambda (source)
      (with-ref (raster-reference who source)
        (lambda (ref)
          (define-values (icc text sentinel)
            (make-encoder-profile-reference who checked description))
          (dynamic-wind void
            (lambda () (proc ref icc text sentinel (if icc (list ref icc) (list ref))))
            (lambda () (when icc (reference-close! icc)))))))))

; raster-reference : symbol? image? -> any/c
;   Pins a CPU-only raster image reference without converting its pixel format or color space.
(define (raster-reference who image)
  ;; Execute the established CPU-only gate before obtaining a private immutable
  ;; raster reference. Float/color-space storage remains native, not RGBA8 staging.
  (call-with-owned 'image->encoded-bytes (list (raw:image-h who image)) worker:make-raster-reference))

; picture-reference : symbol? picture? -> any/c
;   Acquires a worker-owned picture reference while its managed handle is locked.
(define (picture-reference who picture)
  (call-with-owned 'picture->bytes (list (raw:picture-h who picture)) worker:make-picture-reference))

; image->port : image? output-port? (or/c 'png 'jpeg 'webp)
;   [#:quality (or/c #f (real-in 0 100))] [#:png-compression (or/c #f (integer-in 0 9))]
;   [#:jpeg-downsample (or/c #f 'yuv-420 'yuv-422 'yuv-444)]
;   [#:jpeg-alpha (or/c #f 'ignore 'blend-on-black)] [#:webp-lossless? boolean?]
;   [#:color-space (or/c color-space? #f)] [#:icc-profile (or/c bytes? #f)]
;   [#:icc-description (or/c string? #f)] [#:limit exact-positive-integer?]
;   [#:close? boolean?] [#:cancel-evt (or/c evt? #f)] -> exact-nonnegative-integer?
;   Encodes a CPU-compatible image directly to a Racket port and returns the bytes written.
(define (image->port image out format #:quality [quality #f] #:png-compression [compression #f]
                     #:jpeg-downsample [downsample #f] #:jpeg-alpha [alpha #f]
                     #:webp-lossless? [lossless? #f] #:color-space [space #f]
                     #:icc-profile [profile #f] #:icc-description [description #f]
                     #:limit [limit (current-skia-byte-limit)]
                     #:close? [close? #f] #:cancel-evt [cancel #f])
  (define who 'image->port)
  (unless (output-port? out) (raise-argument-error who "output-port?" out))
  (define-values (q c ds a lossless)
    (encoding-options who format quality compression downsample alpha lossless?))
  (options! who #f out #f #f #f close? limit cancel)
  (call-with-encoding-references who image space profile description
    (lambda (ref icc text sentinel refs)
      (call-with-values
       (lambda ()
         (worker:native-encode-image
          ref out format q c (choice who ds jpeg-downsample-values)
          (choice who a jpeg-alpha-values) lossless icc text sentinel limit cancel
          (make-finish #f out #f close? refs)))
       written-result))))

; picture->port : picture? output-port? [#:limit exact-positive-integer?] [#:close? boolean?]
;   [#:cancel-evt (or/c evt? #f)] -> exact-nonnegative-integer?
;   Serializes a CPU-compatible picture as SKP to a Racket port and returns the bytes written.
(define (picture->port picture out
                       #:limit [limit (current-skia-byte-limit)]
                       #:close? [close? #f]
                       #:cancel-evt [cancel #f])
  (define who 'picture->port)
  (unless (output-port? out) (raise-argument-error who "output-port?" out))
  (options! who #f out #f #f #f close? limit cancel)
  (with-ref (picture-reference who picture)
    (lambda (ref)
      (call-with-values
       (lambda ()
         (worker:native-write-picture ref out limit cancel (make-finish #f out #f close? (list ref))))
       written-result))))


;;;
;;; Capture-Once Document Output
;;;

; call-with-recorded-pages : symbol? any/c symbol? symbol? symbol? real? exact-positive-integer?
;   procedure? procedure? -> any/c
;   Captures authoring once, preflights retained page commands, and closes pictures after the
;   callback.
(define (call-with-recorded-pages who source format policy mode dpi limit preflight proc)
  (unless (memq format '(pdf svg)) (raise-argument-error who "'pdf or 'svg" format))
  (define pages
    (cond [(output-page? source) (list source)]
          [(and (list? source) (pair? source) (andmap output-page? source)) source]
          [else (raise-argument-error who "output-page? or nonempty list of output-page?" source)]))
  (unless (and (<= (length pages) 1024) (or (eq? format 'pdf) (= (length pages) 1)))
    (error who "PDF accepts at most 1024 pages; SVG requires exactly one"))
  (output-text-mode who mode #:auto? #t) (pdf-raster-dpi who dpi) (stream-byte-limit who limit)
  (call-with-values
   (lambda () (call-with-audit-collector format policy #t (length pages) void))
   (lambda ignored (void)))
  (define effective (if (eq? mode 'auto) (if (eq? format 'svg) 'outline 'native) mode))
  (define captured '()) (define charged 0)
  (define sizes
    (for/list ([p (in-list pages)])
      (call-with-values (lambda () (output-page-size-in-points p)) list)))
  (dynamic-wind void
    (lambda ()
      (for ([page (in-list pages)] [size (in-list sizes)])
        (with-skia ([rec (make-picture-recorder)])
          (define c (picture-recorder-begin-recording! rec 0 0 (car size) (cadr size)))
          (draw-output-page c page #:text-mode effective #:raster-dpi dpi)
          (define picture #f)
          (parameterize-break #f
            (set! picture (picture-recorder-finish-recording! rec))
            (set! captured (cons picture captured)))
          (call-with-owned 'picture->bytes (list (raw:picture-h who picture)) (lambda (_) (void)))
          (set! charged (+ charged (picture-approximate-bytes-used picture)))
          (stream-count who charged limit)))
      (define pictures (reverse captured))
      (define snapshots
        (for/list ([picture (in-list pictures)] [size (in-list sizes)])
          (make-output-page (car size) (cadr size) (lambda (c) (draw-picture c picture)) #:clip? #f)))
      ;; Preflight exact retained commands against the actual PDF/SVG backend.
      ;; Only our draw-picture wrapper is replayed: application authoring runs once.
      (call-with-values
       (lambda () (call-with-audit-collector format policy #t (length pages)
                    (lambda () (preflight snapshots effective))))
       (lambda ignored (void)))
      (proc pictures sizes))
    (lambda () (for ([picture (in-list captured)]) (skia-close! picture)))))

; call-with-page-references : symbol? (listof picture?) procedure? -> any/c
;   Retains page pictures in page order for a callback and releases every reference afterward.
(define (call-with-page-references who pictures proc)
  (define refs '())
  (dynamic-wind void
    (lambda ()
      (for ([picture (in-list pictures)])
        (call-as-atomic
         (lambda () (set! refs (cons (picture-reference who picture) refs)))))
      (proc (reverse refs)))
    (lambda () (for ([ref (in-list refs)]) (reference-close! ref)))))

; output->port : (or/c output-page? (cons/c output-page? (listof output-page?))) output-port? (or/c
;   'pdf 'svg) [#:policy (or/c 'report 'error 'vector-only)] [#:text-mode (or/c 'auto 'native
;   'outline)] [#:raster-dpi (real-in 1 9600)] [#:limit exact-positive-integer?] [#:close? boolean?]
;   [#:title string?] [#:description string?] [#:id-prefix (or/c string? #f)]
;   [#:encoding-quality (or/c (integer-in 0 101) #f)] [#:pdfa? boolean?]
;   [#:cancel-evt (or/c evt? #f)] -> exact-nonnegative-integer?
;   Exports output pages to a Racket port and returns the byte count.
(define (output->port source out format #:policy [policy 'error] #:text-mode [mode 'auto]
                      #:title [title ""] #:description [description ""]
                      #:id-prefix [prefix #f] #:encoding-quality [quality #f] #:pdfa? [pdfa? #f]
                      #:raster-dpi [dpi 144] #:limit [limit (current-skia-byte-limit)]
                      #:close? [close? #f] #:cancel-evt [cancel #f])
  (define who 'output->port)
  (unless (output-port? out) (raise-argument-error who "output-port?" out))
  (define-values (t d id q)
    (document-output-options who format title description prefix quality pdfa?))
  (options! who #f out #f #f #f close? limit cancel)
  ;; Exact commands are preflighted before any output is published. Validation
  ;; or authoring errors do not take ownership of the destination port.
  (call-with-recorded-pages who source format policy mode dpi limit
    (lambda (pages effective)
      (output->bytes pages format #:title title #:description description #:id-prefix prefix
                     #:encoding-quality quality #:pdfa? pdfa? #:text-mode effective #:raster-dpi dpi))
    (lambda (pictures sizes)
      (call-with-document-references who pictures format t d
        (lambda (refs all-refs tp dp)
          (define-values (filter finish-filter)
            (if (eq? format 'svg)
                (make-svg-header-filter who (caar sizes) (cadar sizes) t d id)
                (values values void)))
          (parameterize ([worker:current-output-transform filter])
            (call-with-values
             (lambda ()
               (worker:native-write-pages refs
                 (for/list ([size (in-list sizes)]) (map (lambda (n) (scalar who n)) size))
                 out format (scalar who dpi) tp dp q pdfa? limit cancel
                 (make-finish #f out #f close? all-refs
                              (lambda (okay?) (when okay? (finish-filter))))))
             written-result)))))))

; call-with-document-references : symbol? list? symbol? bytes? bytes? procedure? -> any/c
;   Keeps page pictures and PDF metadata alive independently until live output finishes.
(define (call-with-document-references who pictures format title description proc)
  (call-with-page-references who pictures
    (lambda (refs)
      (define (text-reference bytes)
        (call-as-atomic
         (lambda ()
           (make-native-reference (sk_string_new_with_copy bytes (bytes-length bytes))
                                  sk_string_destructor))))
      (if (eq? format 'svg)
          (proc refs refs #f #f)
          (with-ref (text-reference title)
            (lambda (t)
              (with-ref (text-reference description)
                (lambda (d)
                  (proc refs (append refs (list t d)) (reference-pointer t)
                        (reference-pointer d))))))))))

;; Forward native writer callbacks into an exclusively pinned FILE/memory
;; WStream. No arbitrary Racket callback runs while its native write is active.
;; The whole publication quota is enforced by the managed writer BEFORE each
;; output chunk. A failure poisons the mutable stream until explicit close.

;;;
;;; Publication to Native Streams
;;;

; native-publication : symbol? any/c list? procedure? -> any/c
;   Pins a budgeted native destination for live output, poisoning partial failures before release.
(define (native-publication who stream refs execute)
  (define-values (pin remaining)
    (with-output who stream
      (lambda (p prior)
        (define remaining (- (budget stream) prior))
        (unless (positive? remaining) (error who "destination has no remaining byte budget"))
        (values (pin-live-output! who (native-stream-handle stream) p) remaining))))
  (define pointer (live-pin-pointer pin))
  (define out
    (make-output-port 'skia-native-destination always-evt
      (lambda (bytes start end _non-block? _breakable?)
        (worker:native-output-write! pointer bytes start end))
      void))
  (define finish
    (make-finish #f out #f #t refs
      (lambda (okay?)
        (unless okay? (poison-live-pin! pin))
        (release-live-pin! pin))))
  (dynamic-wind void
    (lambda ()
      (with-handlers ([(lambda (_) #t)
                       (lambda (e) (poison-live-pin! pin) (raise e))])
        (execute out remaining finish)))
    (lambda ()
      (release-live-pin! pin)
      (unless (port-closed? out) (close-output-port out)))))

; image-write-stream! : image? skia-output-stream? (or/c 'png 'jpeg 'webp)
;   [#:quality (or/c #f (real-in 0 100))] [#:png-compression (or/c #f (integer-in 0 9))]
;   [#:jpeg-downsample (or/c #f 'yuv-420 'yuv-422 'yuv-444)]
;   [#:jpeg-alpha (or/c #f 'ignore 'blend-on-black)] [#:webp-lossless? boolean?]
;   [#:color-space (or/c color-space? #f)] [#:icc-profile (or/c bytes? #f)]
;   [#:icc-description (or/c string? #f)] -> exact-nonnegative-integer?
;   Encodes a CPU-compatible image to a memory or file output stream.
(define (image-write-stream! image stream format
                             #:quality [quality #f] #:png-compression [compression #f]
                             #:jpeg-downsample [downsample #f] #:jpeg-alpha [alpha #f]
                             #:webp-lossless? [lossless? #f] #:color-space [space #f]
                             #:icc-profile [profile #f] #:icc-description [description #f])
  (define who 'image-write-stream!)
  (with-output who stream (lambda (_p _n) (void)))
  (define-values (q c ds a lossless)
    (encoding-options who format quality compression downsample alpha lossless?))
  (live-streams-check!)
  (call-with-encoding-references who image space profile description
    (lambda (ref icc text sentinel refs)
      (native-publication who stream refs
        (lambda (out limit finish)
          (call-with-values
           (lambda ()
             (worker:native-encode-image
              ref out format q c (choice who ds jpeg-downsample-values)
              (choice who a jpeg-alpha-values) lossless icc text sentinel limit #f finish))
           written-result))))))

; picture-write-stream! : picture? skia-output-stream? -> exact-nonnegative-integer?
;   Serializes a CPU-compatible picture to a memory or file output stream.
(define (picture-write-stream! picture stream)
  (define who 'picture-write-stream!)
  (with-output who stream (lambda (_p _n) (void)))
  (live-streams-check!)
  (with-ref (picture-reference who picture)
    (lambda (ref)
      (native-publication who stream (list ref)
        (lambda (out limit finish)
          (call-with-values
           (lambda () (worker:native-write-picture ref out limit #f finish))
           written-result))))))

; output-write-stream! : (or/c output-page? (cons/c output-page? (listof output-page?)))
;   skia-output-stream? (or/c 'pdf 'svg) [#:policy (or/c 'report 'error 'vector-only)]
;   [#:text-mode (or/c 'auto 'native 'outline)] [#:raster-dpi (real-in 1 9600)]
;   [#:title string?] [#:description string?] [#:id-prefix (or/c string? #f)]
;   [#:encoding-quality (or/c (integer-in 0 101) #f)] [#:pdfa? boolean?]
;   -> exact-nonnegative-integer?
;   Publishes PDF pages or a single SVG page to a native output stream.
(define (output-write-stream! source stream format
                              #:title [title ""] #:description [description ""]
                              #:id-prefix [prefix #f] #:encoding-quality [quality #f]
                              #:pdfa? [pdfa? #f]
                              #:policy [policy 'error]
                              #:text-mode [mode 'auto]
                              #:raster-dpi [dpi 144])
  (define who 'output-write-stream!)
  (define-values (t d id q)
    (document-output-options who format title description prefix quality pdfa?))
  (with-output who stream (lambda (_p _n) (void)))
  (live-streams-check!)
  (call-with-recorded-pages who source format policy mode dpi (budget stream)
    (lambda (pages effective)
      (output->bytes pages format #:title title #:description description #:id-prefix prefix
                     #:encoding-quality quality #:pdfa? pdfa? #:text-mode effective #:raster-dpi dpi))
    (lambda (pictures sizes)
      (call-with-document-references who pictures format t d
        (lambda (refs all-refs tp dp)
          (define-values (filter finish-filter)
            (if (eq? format 'svg)
                (make-svg-header-filter who (caar sizes) (cadar sizes) t d id)
                (values values void)))
          (parameterize ([worker:current-output-transform filter])
            (native-publication who stream all-refs
              (lambda (out limit finish)
                (call-with-values
                 (lambda ()
                   (worker:native-write-pages refs
                     (for/list ([size (in-list sizes)]) (map (lambda (n) (scalar who n)) size))
                     out format (scalar who dpi) tp dp q pdfa? limit #f
                     (lambda (okay?)
                       (with-handlers ([(lambda (_) #t) (lambda (e) (finish #f) (raise e))])
                         (when okay? (finish-filter))
                         (finish okay?)))))
                 written-result)))))))))
