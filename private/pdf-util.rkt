#lang racket/base
(require racket/file racket/path "types.rkt" "check.rkt")
(provide pdf-page-dimension pdf-raster-dpi pdf-encoding-quality
         pdf-metadata-bytes pdf-date-time pdf-output-path write-pdf-file-bytes!)

;; Page dimensions are points, NOT pixels: do not apply check-dimensions or
;; charge a width*height*4 raster to the byte limit for an otherwise vector page.
(define (pdf-page-dimension who v)
  (unless (and (real? v) (<= 1/1000 v 14400))
    (raise-argument-error who "finite real from 0.001 through 14400 PDF points" v))
  (exact->inexact v))

(define (pdf-raster-dpi who v)
  (unless (and (real? v) (<= 1 v 9600))
    (raise-argument-error who "finite raster DPI from 1 through 9600" v))
  (exact->inexact v))

(define (pdf-encoding-quality who v)
  (unless (and (exact-integer? v) (<= 0 v 101))
    (raise-argument-error who "exact integer from 0 through 101 (101 is lossless)" v))
  v)

(define (pdf-metadata-bytes who strings)
  (define fields
    (for/list ([s (in-list strings)])
      (nul-free-string who s "NUL-free metadata string")
      (string->bytes/utf-8 s)))
  (define n (apply + (map bytes-length fields)))
  (unless (<= n (current-skia-byte-limit))
    (raise-arguments-error who "PDF metadata exceeds current-skia-byte-limit"
                           "UTF-8 bytes" n "limit" (current-skia-byte-limit)))
  fields)

(define (leap-year? y)
  (and (zero? (modulo y 4))
       (or (not (zero? (modulo y 100))) (zero? (modulo y 400)))))

(define (pdf-date-time who d)
  (cond
    [(not d) #f]
    [else
     (unless (date? d) (raise-argument-error who "(or/c #f date?)" d))
     (define y (date-year d))
     (define m (date-month d))
     (define day (date-day d))
     (define zone (date-time-zone-offset d))
     (unless (and (<= 1 y 9999) (<= 1 m 12)
                  (<= 1 day
                      (if (and (= m 2) (leap-year? y))
                          29 (vector-ref '#(31 28 31 30 31 30 31 31 30 31 30 31)
                                         (sub1 m))))
                  (<= 0 (date-hour d) 23) (<= 0 (date-minute d) 59)
                  (<= 0 (date-second d) 59)
                  (<= 0 (date-week-day d) 6)
                  (zero? (modulo zone 60)) (<= -86340 zone 86340))
       (raise-arguments-error who "invalid PDF date or non-minute UTC offset"
                              "date" d))
     ;; The ABI copies these values synchronously during document construction.
     (make-sk-pdf-datetime (quotient zone 60) y m (date-week-day d) day
                           (date-hour d) (date-minute d) (date-second d))]))

(define (pdf-output-path who filename exists)
  (unless (path-string? filename)
    (raise-argument-error who "path-string?" filename))
  (unless (memq exists '(error replace))
    (raise-argument-error who "'error or 'replace" exists))
  (define target (path->complete-path filename))
  (when (regexp-match? #rx#"\0" (path->bytes target))
    (raise-arguments-error who "PDF path contains NUL" "path" filename))
  (when (directory-exists? target)
    (raise-arguments-error who "PDF destination is a directory" "path" target))
  (unless (directory-exists? (path-only target))
    (raise-arguments-error who "PDF destination directory does not exist" "path" target))
  (when (and (eq? exists 'error)
             (or (file-exists? target) (link-exists? target)))
    (raise-arguments-error who "PDF destination already exists" "path" target))
  target)

(define (write-pdf-file-bytes! who bs filename exists)
  (unless (bytes? bs) (raise-argument-error who "bytes?" bs))
  (define target (pdf-output-path who filename exists))
  (define tmp #f)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       (lambda ()
         (parameterize-break #f
           (set! tmp (make-temporary-file ".skia-pdf-~a.tmp" #f (path-only target)))))
       (lambda ()
         (call-with-output-file tmp
           (lambda (out) (write-bytes bs out) (void))
           #:exists 'truncate/replace #:mode 'binary)
         ;; The completed file is renamed on the same filesystem. 'error is
         ;; checked again by rename, so a race never overwrites a new file.
         (rename-file-or-directory tmp target (eq? exists 'replace)))
       (lambda ()
         (when (and tmp (file-exists? tmp)) (delete-file tmp))))))
  (void))
