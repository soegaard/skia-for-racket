#lang racket/base
;; Pure policy and metadata. Reading these installed source files never loads a
;; native library, GUI, GPU driver, or network resource.
(require json racket/file racket/list racket/runtime-path racket/string)
(provide native-package-version native-abi-catalog native-abi-profiles
         native-abi-profile-for native-abi-require! native-abi-check-layouts!
         (struct-out exn:fail:native-abi))

(define-runtime-path version-file "native-default-version.txt")
(define-runtime-path catalog-file "native-abi.json")
(define native-package-version (string->immutable-string (string-trim (file->string version-file))))
(unless (regexp-match? #px"^[0-9]+[.][0-9]+[.][0-9]+$" native-package-version)
  (error 'native-abi "malformed native-default-version.txt"))

(define (freeze value)
  (cond [(hash? value) (for/hasheq ([(k v) (in-hash value)]) (values k (freeze v)))]
        [(list? value) (map freeze value)]
        [(string? value) (string->immutable-string value)]
        [else value]))
(define catalog (freeze (call-with-input-file catalog-file read-json)))
(unless (equal? (hash-ref catalog 'schema #f) 1)
  (error 'native-abi "unsupported native ABI catalog schema"))
(define profiles (hash-ref catalog 'profiles))
(unless (and (list? profiles) (pair? profiles)
             (= (length profiles) (length (remove-duplicates (map (lambda (p) (hash-ref p 'milestone)) profiles)))))
  (error 'native-abi "empty or ambiguous ABI profiles"))
(define (native-abi-catalog) catalog)
(define (native-abi-profiles) profiles)

(struct exn:fail:native-abi exn:fail (milestone increment pointer-bytes) #:transparent)
(define (valid-version! who milestone increment pointer-bytes)
  (unless (exact-nonnegative-integer? milestone)
    (raise-argument-error who "exact-nonnegative-integer?" milestone))
  (unless (exact-nonnegative-integer? increment)
    (raise-argument-error who "exact-nonnegative-integer?" increment))
  (unless (exact-positive-integer? pointer-bytes)
    (raise-argument-error who "exact-positive-integer?" pointer-bytes)))

(define (native-abi-profile-for milestone increment pointer-bytes)
  (valid-version! 'native-abi-profile-for milestone increment pointer-bytes)
  (for/first ([profile (in-list profiles)]
              #:when (and (= milestone (hash-ref profile 'milestone))
                          (>= increment (hash-ref profile 'minimum_increment))
                          (= pointer-bytes (hash-ref profile 'pointer_bytes))))
    profile))

(define (native-abi-require! milestone increment pointer-bytes)
  (or (native-abi-profile-for milestone increment pointer-bytes)
      (raise
       (exn:fail:native-abi
        (format (string-append
                 "skia: unsupported native ABI ~a.~a on a ~a-byte-pointer interpreter; "
                 "supported profiles: ~a. Default NuGet package: ~a. "
                 "A matching symbol name does not establish its signature or ownership contract. "
                 "Use tools/native-abi-lab.py for an isolated investigation; "
                 "there is no unsafe version-check bypass.")
                milestone increment pointer-bytes (map (lambda (p) (hash-ref p 'id)) profiles)
                native-package-version)
        (current-continuation-marks) milestone increment pointer-bytes))))

(define (native-abi-check-layouts! profile observed)
  (unless (member profile profiles)
    (raise-argument-error 'native-abi-check-layouts! "a supported native ABI profile" profile))
  (unless (hash? observed)
    (raise-argument-error 'native-abi-check-layouts! "hash?" observed))
  (define expected (hash-ref profile 'layout_sizes))
  (unless (and (= (hash-count observed) (hash-count expected))
               (for/and ([(name size) (in-hash expected)])
                 (equal? (hash-ref observed name #f) size)))
    (error 'native-abi-check-layouts! "FFI layouts disagree with ~a; expected ~e, observed ~e"
           (hash-ref profile 'id) expected observed))
  (void))
