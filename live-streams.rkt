#lang racket/base
(require ffi/unsafe ffi/unsafe/atomic racket/list
         "private/core.rkt" "private/native.rkt" "private/lifetime.rkt"
         "private/check.rkt" "private/stream-buffer.rkt" "private/stream-resource.rkt"
         "private/live-port-util.rkt" "private/live-native-lease.rkt"
         (prefix-in worker: "private/live-port-native.rkt")
         (only-in "private/live-port-runtime.rkt" in-port-service? active-operation-count)
         "private/picture-util.rkt" "private/codec-util.rkt"
         "private/output-util.rkt" "private/pdf-util.rkt" "private/audit-trace.rkt"
         "streams.rkt" "pictures.rkt" "output.rkt" (submod "streams.rkt" internals)
         (prefix-in raw: (submod "private/core.rkt" live-stream-internals)))
(provide live-streams-check! live-streams-available?
         image-from-port picture-from-port copy-port/streaming image->port picture->port output->port
         image-write-stream! picture-write-stream! output-write-stream!)
(define initialized? #f)
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
(define (live-streams-available?)
  (with-handlers ([exn:fail? (lambda (_) #f)]) (live-streams-check!) #t))
(define (options! who in out length seek? close-in? close-out? limit cancel)
  (live-port-options who in out length seek? close-in? close-out? limit cancel)
  (check-live-cancel who cancel)
  (when (positive? (active-operation-count))
    (error who "another live port operation is active"))
  (live-streams-check!))
;; The protected service thread calls finish once after native teardown, even
;; when the initiating thread is killed. Validation errors do not take ownership
;; of the user's ports. Always finish every cleanup; preserve the first error.
(define (make-finish in out close-in? close-out? refs [after void])
  (lambda (okay?)
    (define first #f)
    (define (attempt thunk)
      (with-handlers ([(lambda (_) #t) (lambda (e) (unless first (set! first (cons #t e))))]) (thunk)))
    (attempt (lambda () (after okay?)))
    (for ([ref (in-list refs)]) (attempt (lambda () (reference-close! ref))))
    (when (and close-in? in (not (port-closed? in))) (attempt (lambda () (close-input-port in))))
    (when (and close-out? out (not (port-closed? out))) (attempt (lambda () (close-output-port out))))
    (when first (raise (cdr first)))))
(define (written-result _answer _stats _read written) written)
(define (with-ref ref proc)
  ;; finish owns release after launch; this covers errors before launch. Both
  ;; paths are idempotent. A private finalizer covers forced caller termination.
  (dynamic-wind void (lambda () (proc ref)) (lambda () (reference-close! ref))))
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
          (orient-rgba-bytes who w h bytes (enum-name who origin encoded-origin-values "encoded origin"))
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
(define (picture-from-port in #:trusted? [trusted? #f] #:width [width #f] #:height [height #f]
                           #:length [length #f] #:seekable? [seek? #f]
                           #:limit [limit (current-skia-byte-limit)] #:close? [close? #f] #:cancel-evt [cancel #f])
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
        (define bounds (call-with-owned who (list handle) (lambda (p) (raw:stream-picture-bounds who p))))
        (raw:make-picture-record handle (if size (vector-ref size 0) (vector-ref bounds 2))
                                   (if size (vector-ref size 1) (vector-ref bounds 3)))))))
(define (copy-port/streaming in out #:limit [limit (current-skia-byte-limit)]
                            #:close-input? [close-in? #f] #:close-output? [close-out? #f] #:cancel-evt [cancel #f])
  (define who 'copy-port/streaming)
  (unless (input-port? in) (raise-argument-error who "input-port?" in))
  (unless (output-port? out) (raise-argument-error who "output-port?" out))
  (options! who in out #f #f close-in? close-out? limit cancel)
  (call-with-values
   (lambda () (worker:native-copy in out #:limit limit #:cancel-evt cancel
                                #:finish (make-finish in out close-in? close-out? '())))
   written-result))
(define (encoding who format quality compression downsample alpha lossless?)
  (unless (memq format '(png jpeg webp)) (raise-argument-error who "'png, 'jpeg or 'webp" format))
  (quality-integer who quality)
  (unless (and (exact-integer? compression) (<= 0 compression 9))
    (raise-argument-error who "PNG compression integer 0 through 9" compression))
  (boolean who lossless?)
  (values (choice who downsample jpeg-downsample-values) (choice who alpha jpeg-alpha-values)))
(define (raster-reference who image)
  ;; Execute the established CPU-only gate before obtaining a private immutable
  ;; raster reference. Float/color-space storage remains native, not RGBA8 staging.
  (call-with-owned 'image->encoded-bytes (list (raw:image-h who image)) worker:make-raster-reference))
(define (picture-reference who picture)
  (call-with-owned 'picture->bytes (list (raw:picture-h who picture)) worker:make-picture-reference))
(define (image->port image out format #:quality [quality 90] #:png-compression [compression 6]
                     #:jpeg-downsample [downsample 'yuv-420] #:jpeg-alpha [alpha 'ignore]
                     #:webp-lossless? [lossless? #f] #:limit [limit (current-skia-byte-limit)]
                     #:close? [close? #f] #:cancel-evt [cancel #f])
  (define who 'image->port)
  (unless (output-port? out) (raise-argument-error who "output-port?" out))
  (define-values (ds a) (encoding who format quality compression downsample alpha lossless?))
  (options! who #f out #f #f #f close? limit cancel)
  (with-ref (raster-reference who image)
    (lambda (ref)
      (call-with-values
       (lambda () (worker:native-encode-image ref out format quality compression ds a lossless? limit cancel
                                             (make-finish #f out #f close? (list ref))))
       written-result))))
(define (picture->port picture out #:limit [limit (current-skia-byte-limit)] #:close? [close? #f] #:cancel-evt [cancel #f])
  (define who 'picture->port)
  (unless (output-port? out) (raise-argument-error who "output-port?" out))
  (options! who #f out #f #f #f close? limit cancel)
  (with-ref (picture-reference who picture)
    (lambda (ref)
      (call-with-values
       (lambda () (worker:native-write-picture ref out limit cancel (make-finish #f out #f close? (list ref))))
       written-result))))

(define (call-with-recorded-pages who source format policy mode dpi limit proc)
  (unless (memq format '(pdf svg)) (raise-argument-error who "'pdf or 'svg" format))
  (define pages
    (cond [(output-page? source) (list source)]
          [(and (list? source) (pair? source) (andmap output-page? source)) source]
          [else (raise-argument-error who "output-page? or nonempty list of output-page?" source)]))
  (unless (and (<= (length pages) 1024) (or (eq? format 'pdf) (= (length pages) 1)))
    (error who "PDF accepts at most 1024 pages; SVG requires exactly one"))
  (output-text-mode who mode #:auto? #t) (pdf-raster-dpi who dpi) (stream-byte-limit who limit)
  (call-with-values (lambda () (call-with-audit-collector format policy #t (length pages) void)) (lambda ignored (void)))
  (define effective (if (eq? mode 'auto) (if (eq? format 'svg) 'outline 'native) mode))
  (define captured '()) (define charged 0)
  (define sizes (for/list ([p (in-list pages)]) (call-with-values (lambda () (output-page-size-in-points p)) list)))
  (dynamic-wind void
    (lambda ()
      (for ([page (in-list pages)] [size (in-list sizes)])
        (with-skia ([rec (make-picture-recorder)])
          (define c (picture-recorder-begin-recording! rec 0 0 (car size) (cadr size)))
          (draw-output-page c page #:text-mode effective #:raster-dpi dpi)
          (define picture #f)
          (parameterize-break #f (set! picture (picture-recorder-finish-recording! rec)) (set! captured (cons picture captured)))
          (call-with-owned 'picture->bytes (list (raw:picture-h who picture)) (lambda (_) (void)))
          (set! charged (+ charged (picture-approximate-bytes-used picture))) (stream-count who charged limit)))
      (define pictures (reverse captured))
      (define snapshots
        (for/list ([picture (in-list pictures)] [size (in-list sizes)])
          (make-output-page (car size) (cadr size) (lambda (c) (draw-picture c picture)) #:clip? #f)))
      ;; Preflight exact retained commands against the actual PDF/SVG backend.
      ;; Only our draw-picture wrapper is replayed: application authoring runs once.
      (call-with-values
       (lambda () (call-with-audit-collector format policy #t (length pages)
                    (lambda () (output->bytes snapshots format #:text-mode effective #:raster-dpi dpi))))
       (lambda ignored (void)))
      (proc pictures sizes))
    (lambda () (for ([picture (in-list captured)]) (skia-close! picture)))))
(define (call-with-page-references who pictures proc)
  (define refs '())
  (dynamic-wind void
    (lambda ()
      (for ([picture (in-list pictures)])
        (call-as-atomic
         (lambda () (set! refs (cons (picture-reference who picture) refs)))))
      (proc (reverse refs)))
    (lambda () (for ([ref (in-list refs)]) (reference-close! ref)))))
(define (output->port source out format #:policy [policy 'error] #:text-mode [mode 'auto]
                      #:raster-dpi [dpi 144] #:limit [limit (current-skia-byte-limit)]
                      #:close? [close? #f] #:cancel-evt [cancel #f])
  (define who 'output->port)
  (unless (output-port? out) (raise-argument-error who "output-port?" out))
  (options! who #f out #f #f #f close? limit cancel)
  ;; Exact commands are preflighted before any output is published. Validation
  ;; or authoring errors do not take ownership of the destination port.
  (call-with-recorded-pages who source format policy mode dpi limit
    (lambda (pictures sizes)
      (call-with-page-references who pictures
        (lambda (refs)
          (define-values (filter finish-filter)
            (if (eq? format 'svg)
                (make-svg-header-filter who (caar sizes) (cadar sizes))
                (values values void)))
          (parameterize ([worker:current-output-transform filter])
            (call-with-values
             (lambda ()
               (worker:native-write-pages refs
                 (for/list ([size (in-list sizes)]) (map (lambda (n) (scalar who n)) size))
                 out format (scalar who dpi) limit cancel
                 (make-finish #f out #f close? refs (lambda (okay?) (when okay? (finish-filter))))))
             written-result)))))))

;; Forward native writer callbacks into an exclusively pinned FILE/memory
;; WStream. No arbitrary Racket callback runs while its native write is active.
;; The whole publication quota is enforced by the managed writer BEFORE each
;; output chunk. A failure poisons the mutable stream until explicit close.
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
(define (image-write-stream! image stream format #:quality [quality 90] #:png-compression [compression 6]
                             #:jpeg-downsample [downsample 'yuv-420] #:jpeg-alpha [alpha 'ignore]
                             #:webp-lossless? [lossless? #f])
  (define who 'image-write-stream!)
  (with-output who stream (lambda (_p _n) (void)))
  (define-values (ds a) (encoding who format quality compression downsample alpha lossless?))
  (live-streams-check!)
  (with-ref (raster-reference who image)
    (lambda (ref)
      (native-publication who stream (list ref)
        (lambda (out limit finish)
          (call-with-values
           (lambda () (worker:native-encode-image ref out format quality compression ds a lossless? limit #f finish))
           written-result))))))
(define (picture-write-stream! picture stream)
  (define who 'picture-write-stream!)
  (with-output who stream (lambda (_p _n) (void)))
  (live-streams-check!)
  (with-ref (picture-reference who picture)
    (lambda (ref)
      (native-publication who stream (list ref)
        (lambda (out limit finish)
          (call-with-values (lambda () (worker:native-write-picture ref out limit #f finish)) written-result))))))
(define (output-write-stream! source stream #:policy [policy 'error] #:text-mode [mode 'auto] #:raster-dpi [dpi 144])
  ;; Native file/memory document publication is PDF. SVG physical-root filtering
  ;; is offered by output->port, not silently omitted for native output streams.
  (define who 'output-write-stream!)
  (with-output who stream (lambda (_p _n) (void)))
  (live-streams-check!)
  (call-with-recorded-pages who source 'pdf policy mode dpi (budget stream)
    (lambda (pictures sizes)
      (call-with-page-references who pictures
        (lambda (refs)
          (native-publication who stream refs
            (lambda (out limit finish)
              (call-with-values
               (lambda () (worker:native-write-pages refs
                 (for/list ([size (in-list sizes)]) (map (lambda (n) (scalar who n)) size))
                 out 'pdf (scalar who dpi) limit #f finish))
               written-result))))))))
