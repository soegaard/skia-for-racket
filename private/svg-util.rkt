#lang racket/base
(require racket/file racket/path "check.rkt")
(provide svg-dimension svg-metadata svg-id-prefix finish-svg-xml
         svg-output-path write-svg-file-bytes! rasterized-dimensions)

;; SVG dimensions are user units, not an instruction to allocate an RGBA plane.
;; Keep the rounded native device dimensions comfortably within signed int32.
(define (svg-dimension who v)
  (unless (and (real? v) (<= 1/1000 v 32768))
    (raise-argument-error who "finite real from 0.001 through 32768 SVG units" v))
  (exact->inexact v))

(define (check-svg-size who n)
  (unless (<= n (current-skia-byte-limit))
    (raise-arguments-error who "SVG output exceeds current-skia-byte-limit"
                           "required bytes" n "limit" (current-skia-byte-limit))))

(define (xml-character? ch)
  (define n (char->integer ch))
  (or (= n 9) (= n 10) (= n 13)
      (<= #x20 n #xd7ff) (<= #xe000 n #xfffd) (<= #x10000 n #x10ffff)))

(define (escape-svg-metadata who s)
  (unless (string? s) (raise-argument-error who "XML-compatible string" s))
  (unless (for/and ([ch (in-string s)]) (xml-character? ch))
    (raise-arguments-error who "metadata contains a character forbidden by XML 1.0"
                           "string" s))
  ;; Escape only our metadata, never already-escaped native SVG text.
  (define out (open-output-bytes))
  (for ([ch (in-string s)])
    (define bs
      (case ch
        [(#\&) #"&amp;"] [(#\<) #"&lt;"] [(#\>) #"&gt;"]
        [(#\") #"&quot;"] [(#\') #"&apos;"]
        [else (string->bytes/utf-8 (string ch))]))
    (check-svg-size who (+ (file-position out) (bytes-length bs)))
    (write-bytes bs out))
  (get-output-bytes out))

(define (svg-metadata who title description)
  (define t (escape-svg-metadata who title))
  (define d (escape-svg-metadata who description))
  (check-svg-size who (+ (bytes-length t) (bytes-length d)))
  (values t d))

(define (svg-id-prefix who v)
  (unless (and (string? v) (<= 1 (string-length v) 64)
               (regexp-match? #rx"^[A-Za-z_][A-Za-z0-9_.-]*$" v))
    (raise-argument-error who
                          "1 to 64 ASCII characters: initial letter/underscore, then letters, digits, _, ., -"
                          v))
  (string->bytes/utf-8 v))

(define (limited-replace* who pattern input replace)
  (define size (bytes-length input))
  (check-svg-size who size)
  (regexp-replace*
   pattern input
   (lambda args
     (define bs (apply replace args))
     (set! size (+ size (- (bytes-length bs) (bytes-length (car args)))))
     (check-svg-size who size)
     bs)))

(define (canonical-svg-ids who input prefix)
  ;; The pinned backend uses process-global clip generation IDs. Renumber ALL
  ;; native resource IDs in definition order and update their attribute refs.
  ;; This is deliberately for Skia-generated XML, not a general SVG sanitizer.
  ;; Native text escapes quotes, so these attribute patterns cannot rewrite
  ;; label text that happens to mention an ID or a url(#...) expression.
  (define names (make-hash))
  (define definitions
    (limited-replace*
     who #rx#" id=\"([^\"]+)\"" input
     (lambda (whole old)
       (when (hash-has-key? names old)
         (error who "native SVG has a duplicate resource ID: ~s" old))
       (define new (bytes-append prefix #"-"
                                 (string->bytes/utf-8 (number->string (hash-count names)))))
       (hash-set! names old new)
       (bytes-append #" id=\"" new #"\""))))
  (define (lookup old)
    (hash-ref names old (lambda () (error who "unresolved native SVG resource: ~s" old))))
  (limited-replace*
   who #rx#"([A-Za-z_][A-Za-z0-9_.:-]*)=\"([^\"]*)\"" definitions
   (lambda (whole name value)
     (define replacement
       (cond
         [(bytes=? name #"id") value]
         [(and (or (bytes=? name #"href") (bytes=? name #"xlink:href"))
               (positive? (bytes-length value)) (= (bytes-ref value 0) 35))
          (bytes-append #"#" (lookup (subbytes value 1)))]
         [else
          (regexp-replace* #rx#"url\\(#([^)]*)\\)" value
                           (lambda (_ old) (bytes-append #"url(#" (lookup old) #")")))]))
     (bytes-append name #"=\"" replacement #"\""))))

(define (finish-svg-xml who input width height title description prefix)
  (unless (bytes? input) (raise-argument-error who "bytes?" input))
  (check-svg-size who (bytes-length input))
  (define bs (canonical-svg-ids who input prefix))
  (define opening (regexp-match-positions #rx#"<svg[ \t\r\n][^>]*>" bs))
  (unless opening (error who "native SVG has no root element"))
  (define start (caar opening))
  (define end (cdar opening))
  (define empty? (= (bytes-ref bs (- end 2)) 47))
  (unless (or empty? (regexp-match? #rx#"</svg>[ \t\r\n]*$" bs))
    (error who "native SVG root was not closed; destroy the canvas before reading the stream"))
  ;; m119's C shim rounds its device size to integers and emits no viewBox.
  ;; Replace ONLY the native root opening, preserving its body verbatim apart
  ;; from ID canonicalization. There is no implicit pixel or image conversion.
  (define w (string->bytes/utf-8 (number->string width)))
  (define h (string->bytes/utf-8 (number->string height)))
  (define root
    (bytes-append #"<svg xmlns=\"http://www.w3.org/2000/svg\""
                  #" xmlns:xlink=\"http://www.w3.org/1999/xlink\""
                  #" width=\"" w #"\" height=\"" h #"\" viewBox=\"0 0 " w #" " h #"\">"))
  (define metadata
    (bytes-append
     (if (zero? (bytes-length title)) #""
         (bytes-append #"\n\t<title>" title #"</title>"))
     (if (zero? (bytes-length description)) #""
         (bytes-append #"\n\t<desc>" description #"</desc>"))))
  (define ending (if empty? #"\n</svg>" #""))
  (check-svg-size who (+ (- (bytes-length bs) (- end start))
                        (bytes-length root) (bytes-length metadata) (bytes-length ending)))
  (bytes->immutable-bytes
   (bytes-append (subbytes bs 0 start) root metadata ending (subbytes bs end))))

(define (svg-output-path who filename exists)
  (unless (path-string? filename) (raise-argument-error who "path-string?" filename))
  (unless (memq exists '(error replace))
    (raise-argument-error who "'error or 'replace" exists))
  (define target (path->complete-path filename))
  (when (regexp-match? #rx#"\0" (path->bytes target))
    (raise-arguments-error who "SVG path contains NUL" "path" filename))
  (when (directory-exists? target)
    (raise-arguments-error who "SVG destination is a directory" "path" target))
  (unless (directory-exists? (path-only target))
    (raise-arguments-error who "SVG destination directory does not exist" "path" target))
  (when (and (eq? exists 'error) (or (file-exists? target) (link-exists? target)))
    (raise-arguments-error who "SVG destination already exists" "path" target))
  target)

(define (write-svg-file-bytes! who bs filename exists)
  (unless (bytes? bs) (raise-argument-error who "bytes?" bs))
  (check-svg-size who (bytes-length bs))
  (define target (svg-output-path who filename exists))
  (define tmp #f)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       (lambda ()
         (parameterize-break #f
           (set! tmp (make-temporary-file ".skia-svg-~a.tmp" #f (path-only target)))))
       (lambda ()
         (call-with-output-file tmp
           (lambda (out) (write-bytes bs out) (void))
           #:exists 'truncate/replace #:mode 'binary)
         ;; Check 'error again atomically at publication: a file created by the
         ;; callback or a racing process is not overwritten.
         (rename-file-or-directory tmp target (eq? exists 'replace)))
       (lambda ()
         (when (and tmp (file-exists? tmp)) (delete-file tmp))))))
  (void))

(define (rasterized-dimensions who width height scale)
  (define w (positive-scalar who width))
  (define h (positive-scalar who height))
  (unless (and (real? scale) (<= 1/1024 scale 1024))
    (raise-argument-error who "finite raster scale from 1/1024 through 1024" scale))
  (define pw (inexact->exact (ceiling (* w scale))))
  (define ph (inexact->exact (ceiling (* h scale))))
  (check-dimensions who pw ph)
  (values pw ph))
