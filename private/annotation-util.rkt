#lang racket/base
(require racket/list racket/string "check.rkt")
(provide annotation-uri annotation-name annotation-name->id annotation-svg-id
         annotation-c-string annotation-define! annotation-reference!
         annotation-check! annotation-forget! finish-svg-annotations)

;; These tables contain only copied Racket data. Values never retain their
;; weak keys (native document wrappers), canvases, or native pointers. Access
;; from the drawing layer is inside its ordinary thread/ownership checks.
(struct annotation-state (destinations references))
(define states (make-weak-hasheq))
(define (state-for scope)
  (hash-ref! states scope (lambda () (annotation-state (make-hash) (make-hash)))))

(define (check-size who size)
  (unless (<= size (current-skia-byte-limit))
    (raise-arguments-error who "annotation data exceeds current-skia-byte-limit"
                           "required bytes" size "limit" (current-skia-byte-limit))))

(define (annotation-name who name)
  (unless (and (string? name) (positive? (string-length name)))
    (raise-argument-error who "nonempty destination-name string" name))
  (when (for/or ([c (in-string name)])
          (define n (char->integer c))
          (or (< n 32) (= n 127) (= n #xfffe) (= n #xffff)))
    (raise-arguments-error who "destination name contains a control or non-XML character"
                           "name" name))
  ;; Names are case-sensitive; no normalization or implicit symbol conversion.
  (check-size who (add1 (bytes-length (string->bytes/utf-8 name))))
  (string->immutable-string name))

(define (annotation-name->id who name)
  (define s (annotation-name who name))
  (define bs (string->bytes/utf-8 s))
  ;; An ASCII identifier is also a valid PDF string and SVG fragment. Hex is
  ;; injective for UTF-8 names; punctuation cannot collide or inject XML.
  (check-size who (+ 5 (* 2 (bytes-length bs)) 1))
  (define digits "0123456789abcdef")
  (define out (open-output-string))
  (display "dest-" out)
  (for ([b (in-bytes bs)])
    (write-char (string-ref digits (quotient b 16)) out)
    (write-char (string-ref digits (remainder b 16)) out))
  (string->immutable-string (get-output-string out)))

(define (annotation-svg-id who name prefix)
  (unless (and (string? prefix) (<= 1 (string-length prefix) 64)
               (regexp-match? #rx"^[A-Za-z_][A-Za-z0-9_.-]*$" prefix))
    (raise-argument-error who "valid SVG ID prefix (1 to 64 ASCII characters)" prefix))
  (define id (string-append prefix "-" (annotation-name->id who name)))
  (check-size who (add1 (string-length id)))
  (string->immutable-string id))

(define (annotation-uri who uri)
  (unless (and (string? uri) (positive? (string-length uri)))
    (raise-argument-error who "nonempty URI string" uri))
  ;; A portable URI, not a general browser URL parser. Non-ASCII characters
  ;; and spaces must already be percent encoded. No network is accessed.
  (unless (for/and ([c (in-string uri)])
            (and (<= 33 (char->integer c) 126)
                 (not (memv c '(#\" #\< #\> #\\ #\^ #\` #\{ #\| #\})))))
    (raise-arguments-error who "URI contains a character that must be percent encoded"
                           "URI" uri))
  (when (char=? (string-ref uri 0) #\#)
    (raise-arguments-error who
                           "use canvas-link-destination! for a same-document destination"
                           "URI" uri))
  (when (regexp-match? #px"%(?![0-9A-Fa-f]{2})" uri)
    (raise-arguments-error who "URI has an incomplete percent escape" "URI" uri))
  (define scheme (regexp-match #px"^([A-Za-z][A-Za-z0-9+.-]*):" uri))
  (when scheme
    (define name (string-downcase (cadr scheme)))
    (unless (member name '("http" "https" "mailto"))
      (raise-arguments-error who "only http, https, mailto, and relative URI links are supported"
                             "scheme" name))
    (when (and (member name '("http" "https"))
               (not (regexp-match? #px"^[A-Za-z]+://[^/?#]+" uri)))
      (raise-arguments-error who "HTTP(S) URI requires an authority" "URI" uri))
    (when (and (string=? name "mailto") (= (string-length uri) 7))
      (raise-arguments-error who "mailto URI is empty" "URI" uri)))
  ;; A colon in the first relative-path segment would be parsed as a scheme
  ;; by viewers, even when it failed the scheme pattern above.
  (when (and (not scheme) (regexp-match? #px"^[^/?#]*:" uri))
    (raise-arguments-error who "invalid URI scheme or relative first segment" "URI" uri))
  (check-size who (add1 (string-length uri)))
  (string->immutable-string uri))

(define (annotation-c-string who text)
  (define bs (string->bytes/utf-8 text))
  (when (regexp-match? #rx#"\0" bs)
    (raise-arguments-error who "annotation contains NUL" "text" text))
  (check-size who (add1 (bytes-length bs)))
  (bytes-append bs #"\0"))

(define (annotation-define! who scope name x y)
  (define s (annotation-name who name))
  (define point (vector-immutable (scalar who x) (scalar who y)))
  (define destinations (annotation-state-destinations (state-for scope)))
  (when (hash-has-key? destinations s)
    (raise-arguments-error who "destination is already defined in this document" "name" s))
  (hash-set! destinations s point)
  (void))

(define (annotation-reference! who scope name)
  (define s (annotation-name who name))
  (hash-set! (annotation-state-references (state-for scope)) s #t)
  (void))

(define (annotation-check! who scope)
  (define st (hash-ref states scope #f))
  (when st
    (define missing
      (sort (for/list ([name (in-hash-keys (annotation-state-references st))]
                       #:unless (hash-has-key? (annotation-state-destinations st) name))
              name) string<?))
    (unless (null? missing)
      (raise-arguments-error who "undefined document destinations" "names" missing)))
  (void))

(define (annotation-forget! scope)
  (hash-remove! states scope)
  (void))

(define native-anchor-pattern #px#"<a(?:[ \t\r\n][^>]*)?>(?s:.*?)</a>")
(define native-href-pattern #rx#" xlink:href=\"([^\"]*)\"")
(define destination-token-pattern #rx#"^urn:racket-skia:destination:(dest-[0-9a-f]+)$")

(define (finish-svg-annotations who scope input width height prefix)
  ;; Called ONLY on finalized Skia-generated XML, after resource-ID rewriting.
  ;; It is not an SVG importer or sanitizer. Annotation rectangles are already
  ;; in device/root coordinates. The native SVG writer emits them inside its
  ;; last synchronized graphics clip group (which may be stale); move them to
  ;; the root overlay, never transform or clip those rectangles a second time.
  (unless (and (bytes? input) (bytes? prefix))
    (raise-argument-error who "SVG and ID-prefix byte strings" (list input prefix)))
  (check-size who (bytes-length input))
  (annotation-check! who scope)
  (define st (hash-ref states scope #f))
  (define dests (if st (annotation-state-destinations st) (hash)))
  (define ids
    (for/hash ([name (in-hash-keys dests)])
      (values (string->bytes/utf-8 (annotation-name->id who name)) name)))
  (define anchors '())
  (define body
    (regexp-replace*
     native-anchor-pattern input
     (lambda (whole)
       (define href (regexp-match native-href-pattern whole))
       (unless (and href (regexp-match? #rx#"<rect[ \t\r\n]" whole))
         (error who "unexpected native SVG annotation structure"))
       (define old (cadr href))
       (define token (regexp-match destination-token-pattern old))
       (define target
         (if token
             (let ([id (cadr token)])
               (unless (hash-has-key? ids id)
                 (error who "native SVG refers to an unknown destination ID: ~s" id))
               (bytes-append #"#" prefix #"-" id))
             old))
       ;; Preserve the already-escaped URI; never XML-escape it a second time.
       ;; href is the SVG 2 attribute; xlink:href is its compatibility alias.
       (define link
         (regexp-replace native-href-pattern whole
           (lambda (_all _value)
             (bytes-append #" href=\"" target #"\" xlink:href=\"" target #"\""))))
       (check-size who (bytes-length link))
       (set! anchors (cons link anchors))
       #"")))
  (cond
    [(and (null? anchors) (zero? (hash-count dests))) input]
    [else
     (define ending (regexp-match-positions #rx#"</svg>[ \t\r\n]*$" body))
     (unless ending (error who "SVG annotation finalization requires a closed root"))
     (define at (caar ending))
     (define out (open-output-bytes))
     (define (put bs)
       (check-size who (+ (file-position out) (bytes-length bs)))
       (write-bytes bs out))
     (put (subbytes body 0 at))
     ;; Predefined SVG views preserve the root viewBox extent, panning its
     ;; top-left to the captured point. Destination definitions ignore clipping,
     ;; as PDF named point destinations do. IDs are stable and prefix-scoped.
     (for ([name (in-list (sort (hash-keys dests) string<?))])
       (define point (hash-ref dests name))
       (define id (bytes-append prefix #"-"
                                (string->bytes/utf-8 (annotation-name->id who name))))
       (put (string->bytes/utf-8
             (format "\n<view id=\"~a\" viewBox=\"~a ~a ~a ~a\"/>"
                     (bytes->string/utf-8 id)
                     (vector-ref point 0) (vector-ref point 1) width height))))
     (for ([a (in-list (reverse anchors))]) (put #"\n") (put a))
     (put #"\n")
     (put (subbytes body at))
     (bytes->immutable-bytes (get-output-bytes out))]))
