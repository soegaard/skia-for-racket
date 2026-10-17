#lang racket/base

;;;
;;; DC Closure Example
;;;

;; Exports a described-font drawing callback through audited document output.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; One described-font callback, exported through the existing audited document
;; API and previewed as a PNG. No GUI or GPU initialization is requested.
;;;
;;; Imports and Exports
;;;

(require racket/class racket/cmdline racket/file racket/pretty
         (prefix-in rd: racket/draw) (prefix-in sk: "../main.rkt")
         "../dc.rkt" "../dc-output.rkt")
;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; directory : string?
  ;   Selects the destination used by this example's output.
  (define directory "output/dc-compatibility-example")
  (command-line #:once-each
    [("--directory") value "new or existing output directory" (set! directory value)]
    #:args () (void))

  ; family : string?
  ;   Records the actual default typeface family used to construct the described font.
  (define family
    (sk:with-skia ([face (sk:make-typeface)]) (sk:typeface-family-name face)))
  ;; font% size takes precedence over 72 in the description. The description
  ;; supplies bold/italic because font%'s weight and style remain 'normal.

  ; label-font : (is-a?/c font%)
  ;   Creates the Racket Draw font using the actual Skia-reported family.
  (define label-font
    (rd:make-font #:face (string-append family ", Bold Italic 72")
                  #:size 18 #:size-in-pixels? #t #:hinting 'unaligned))

  ; scene : (is-a?/c dc<%>) -> void?
  ;   Draws the described-font scene through the public drawing-context interface.
  (define (scene dc)
    (send dc set-pen "navy" 2 'solid)
    (send dc set-brush "lightblue" 'solid)
    (send dc draw-rounded-rectangle 12 12 316 86 8)
    (send dc set-font label-font)
    (send dc set-text-foreground "navy")
    (send dc draw-text "Skia / described font" 24 38 #t))
  (make-directory* directory)

  ; page : output-page?
  ;   Describes the page drawing and its export dimensions.
  (define page (make-dc-output-page 340 112 scene #:background 'white))
  (for ([format '(pdf svg)])
    (define target (build-path directory (string-append "described-font." (symbol->string format))))
    (sk:save-output/audit page target format #:policy 'error #:exists 'replace)
    (printf "Wrote ~a\n" target))
  (sk:with-skia ([image (sk:output-page->image page #:dpi 144)])
    (call-with-output-file (build-path directory "described-font.png")
      (lambda (out) (write-bytes (sk:image->png-bytes image) out))
      #:mode 'binary #:exists 'replace))
  (pretty-write (skia-dc-compatibility 'pdf)))
