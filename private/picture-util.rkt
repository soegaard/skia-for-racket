#lang racket/base

;;;
;;; Picture Serialization Validation
;;;

;; Checks trust, byte budgets, bounds, and paths for recorded pictures.
;; Protects picture serialization and deserialization at the public API boundary.

(require racket/file racket/path "check.rkt")
(provide check-picture-trust picture-data-snapshot picture-header
         picture-size-override picture-output-path
         read-picture-file-bytes write-picture-file-bytes!)

;;;
;;; Trust Acknowledgement and SKP Headers
;;;

;; The pinned m119 SkPicture stream header is native-endian: magic[8],
;; uint32 version, four float cull coordinates, then a one-byte payload kind.
;; This is only a cheap framing check, NOT a validator/sandbox for the payload.
;; See SkPicture.cpp and SkPicturePriv.h at the pinned native revision.

; check-picture-trust : symbol? any/c -> void?
;   Requires an explicit true trust acknowledgement because deserializing SKP data may execute
;   embedded SkSL.
(define (check-picture-trust who trusted?)
  (boolean who trusted?)
  (unless trusted?
    (raise-arguments-error who
      "native picture loading requires #:trusted? #t; SKP may contain executable SkSL"
      "trusted?" trusted?))
  (void))

; picture-byte-count : symbol? bytes? -> exact-positive-integer?
;   Checks the minimum SKP header length and configured byte budget before copying or decoding.
(define (picture-byte-count who bs)
  (unless (bytes? bs) (raise-argument-error who "bytes?" bs))
  (define n (bytes-length bs))
  (unless (<= 29 n (current-skia-byte-limit))
    (raise-arguments-error who "SKP data is truncated or exceeds current-skia-byte-limit"
                           "bytes" n "limit" (current-skia-byte-limit)))
  n)

; picture-header : symbol? bytes? -> (values exact-integer? vector?)
;   Checks SKP magic, supported version, scalar bounds, and standard picture kind; returns the
;   version and immutable x/y/width/height bounds.
(define (picture-header who bs)
  (picture-byte-count who bs)
  (unless (bytes=? (subbytes bs 0 8) #"skiapict")
    (raise-arguments-error who "not a native SKP stream (missing skiapict header)"
                           "magic" (subbytes bs 0 8)))
  (define version (integer-bytes->integer bs #f (system-big-endian?) 8 12))
  (unless (<= 82 version 103)
    (raise-arguments-error who "unsupported SKP version for the pinned m119 native library"
                           "version" version "supported range" '(82 103)))
  (define coords
    (for/list ([at (in-range 12 28 4)])
      (scalar who (floating-point-bytes->real bs (system-big-endian?) at (+ at 4)))))
  (define left (car coords))
  (define top (cadr coords))
  (define width (nonnegative-scalar who (- (caddr coords) left)))
  (define height (nonnegative-scalar who (- (cadddr coords) top)))
  ;; The C shim supplies no custom picture deserializer. Kind 0 is failure;
  ;; kind 2 needs a custom callback. Only standard picture-data kind 1 is usable.
  (unless (= (bytes-ref bs 28) 1)
    (raise-arguments-error who "SKP stream has no supported standard picture payload"
                           "payload kind" (bytes-ref bs 28)))
  (values version (vector-immutable left top width height)))

; picture-data-snapshot : symbol? bytes? -> bytes?
;   Makes a bounded immutable SKP snapshot and validates its header before native deserialization.
(define (picture-data-snapshot who bs)
  (picture-byte-count who bs)
  ;; Never lend the caller's mutable buffer to native code. The SKData bridge
  ;; takes its own native copy too; neither buffer is retained by this helper.
  (define copy (bytes->immutable-bytes (bytes-copy bs)))
  (picture-header who copy)
  copy)

; picture-size-override : symbol? (or/c #f real?) (or/c #f real?) -> (or/c #f vector?)
;   Requires width and height together and checks nonnegative native scalars for the optional size
;   override.
(define (picture-size-override who width height)
  (cond [(and (eq? width #f) (eq? height #f)) #f]
        [(or (eq? width #f) (eq? height #f))
         (raise-arguments-error who "#:width and #:height must be supplied together"
                                "width" width "height" height)]
        [else (vector-immutable (nonnegative-scalar who width)
                                (nonnegative-scalar who height))]))

;;;
;;; Bounded File Input and Atomic Output
;;;

; picture-path : symbol? path-string? -> path?
;   Resolves a complete NUL-free path for picture input or output.
(define (picture-path who filename)
  (unless (path-string? filename) (raise-argument-error who "path-string?" filename))
  (define target (path->complete-path filename))
  (when (regexp-match? #rx#"\0" (path->bytes target))
    (raise-arguments-error who "picture path contains NUL" "path" filename))
  target)

; read-picture-file-bytes : symbol? path-string? -> bytes?
;   Reads SKP data in bounded chunks and returns a validated immutable snapshot without an
;   unbounded file allocation.
(define (read-picture-file-bytes who filename)
  (define target (picture-path who filename))
  ;; Do not use an unbounded file->bytes followed by a size check, or trust a
  ;; stat performed before opening. Read bounded chunks through the same port.
  (define limit (current-skia-byte-limit))
  (call-with-input-file target
    (lambda (in)
      (define out (open-output-bytes))
      (let loop ([total 0])
        (define chunk (read-bytes (min 65536 (+ 1 (- limit total))) in))
        (cond [(eof-object? chunk) (picture-data-snapshot who (get-output-bytes out))]
              [else
               (define next (+ total (bytes-length chunk)))
               (when (> next limit)
                 (raise-arguments-error who "picture file exceeds current-skia-byte-limit"
                                        "limit" limit "path" target))
               (write-bytes chunk out)
               (loop next)])))
    #:mode 'binary))

; picture-output-path : symbol? path-string? symbol? -> path?
;   Checks the output parent, directory conflicts, and error-or-replace policy before writing a
;   picture.
(define (picture-output-path who filename exists)
  (unless (memq exists '(error replace))
    (raise-argument-error who "'error or 'replace" exists))
  (define target (picture-path who filename))
  (when (directory-exists? target)
    (raise-arguments-error who "picture destination is a directory" "path" target))
  (unless (directory-exists? (path-only target))
    (raise-arguments-error who "picture destination directory does not exist" "path" target))
  (when (and (eq? exists 'error) (or (file-exists? target) (link-exists? target)))
    (raise-arguments-error who "picture destination already exists" "path" target))
  target)

; write-picture-file-bytes! : symbol? bytes? path-string? symbol? -> void?
;   Validates a picture snapshot and publishes it by same-directory atomic rename, removing the
;   temporary file on unsuccessful exit.
(define (write-picture-file-bytes! who bs filename exists)
  (define copy (picture-data-snapshot who bs))
  (define target (picture-output-path who filename exists))
  (define temporary #f)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       (lambda ()
         (parameterize-break #f
           (set! temporary (make-temporary-file ".skia-picture-~a.tmp" #f (path-only target)))))
       (lambda ()
         (call-with-output-file temporary
           (lambda (out) (write-bytes copy out) (void))
           #:exists 'truncate/replace #:mode 'binary)
         ;; Rename also enforces 'error against a concurrently created target.
         (rename-file-or-directory temporary target (eq? exists 'replace)))
       (lambda ()
         (when (and temporary (file-exists? temporary)) (delete-file temporary))))))
  (void))
