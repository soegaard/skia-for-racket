#lang racket/base

;;;
;;; Native ABI Validation
;;;

;; Checks Skia versions and native layout sizes before using the FFI.
;; Rejects incompatible libraries before their layouts can corrupt native calls.

;; Pure policy and metadata. Reading these installed source files never loads a
;; native library, GUI, GPU driver, or network resource.
(require json racket/file racket/list racket/runtime-path racket/string)
(provide native-package-version native-abi-catalog native-abi-profiles
         native-abi-profile-for native-abi-require! native-abi-check-layouts!
         (struct-out exn:fail:native-abi))

; version-file : path?
;;   Locates the installed default native package-version metadata.
(define-runtime-path version-file "native-default-version.txt")
; catalog-file : path?
;;   Locates the reviewed ABI version and C-layout policy catalogue.
(define-runtime-path catalog-file "native-abi.json")
; native-package-version : string?
;;   Reads the immutable default NuGet package version, which is not inferred from loaded native
;;   version functions.
(define native-package-version (string->immutable-string (string-trim (file->string version-file))))
(unless (regexp-match? #px"^[0-9]+[.][0-9]+[.][0-9]+$" native-package-version)
  (error 'native-abi "malformed native-default-version.txt"))

; freeze : any/c -> any/c
;;   Recursively snapshots JSON hashes, lists, and strings as detached immutable catalogue data.
(define (freeze value)
  (cond [(hash? value) (for/hasheq ([(k v) (in-hash value)]) (values k (freeze v)))]
        [(list? value) (map freeze value)]
        [(string? value) (string->immutable-string value)]
        [else value]))
; catalog : hash?
;;   Loads the installed ABI policy catalogue without loading a native library.
(define catalog (freeze (call-with-input-file catalog-file read-json)))
(unless (equal? (hash-ref catalog 'schema #f) 1)
  (error 'native-abi "unsupported native ABI catalog schema"))
; profiles : (listof hash?)
;;   Retains the nonempty supported ABI profiles, requiring a unique profile per milestone.
(define profiles (hash-ref catalog 'profiles))
(unless (and (list? profiles) (pair? profiles)
             (= (length profiles)
                (length (remove-duplicates (map (lambda (p) (hash-ref p 'milestone)) profiles)))))
  (error 'native-abi "empty or ambiguous ABI profiles"))
; native-abi-catalog : -> (and/c hash? immutable?)
;;   Returns the immutable installed ABI catalogue.
(define (native-abi-catalog) catalog)
; native-abi-profiles : -> (listof hash?)
;;   Returns the supported profiles from the installed catalogue, as detached immutable data.
(define (native-abi-profiles) profiles)

(struct exn:fail:native-abi exn:fail (milestone increment pointer-bytes) #:transparent)
;; Fields:
;;   milestone and increment: detected Skia version components. pointer-bytes: host/native pointer
;;   width in bytes. Inherited fields explain the rejected ABI combination.

; valid-version! : symbol? exact-nonnegative-integer? exact-nonnegative-integer?
;   exact-positive-integer? -> void?
;;   Checks version components and pointer width before ABI profile lookup.
(define (valid-version! who milestone increment pointer-bytes)
  (unless (exact-nonnegative-integer? milestone)
    (raise-argument-error who "exact-nonnegative-integer?" milestone))
  (unless (exact-nonnegative-integer? increment)
    (raise-argument-error who "exact-nonnegative-integer?" increment))
  (unless (exact-positive-integer? pointer-bytes)
    (raise-argument-error who "exact-positive-integer?" pointer-bytes)))

; native-abi-profile-for : exact-nonnegative-integer? exact-nonnegative-integer?
;   exact-positive-integer? -> (or/c #f hash?)
;;   Finds a profile matching milestone and pointer width whose minimum increment is satisfied.
(define (native-abi-profile-for milestone increment pointer-bytes)
  (valid-version! 'native-abi-profile-for milestone increment pointer-bytes)
  (for/first ([profile (in-list profiles)]
              #:when (and (= milestone (hash-ref profile 'milestone))
                          (>= increment (hash-ref profile 'minimum_increment))
                          (= pointer-bytes (hash-ref profile 'pointer_bytes))))
    profile))

; native-abi-require! : exact-nonnegative-integer? exact-nonnegative-integer?
;   exact-positive-integer? -> hash?
;;   Returns the supported profile or raises a typed ABI rejection before any unchecked native
;;   layout is used.
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

; native-abi-check-layouts! : hash? hash? -> void?
;;   Requires the observed FFI layout names and byte sizes to match the supported profile exactly.
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
