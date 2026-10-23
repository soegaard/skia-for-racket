#lang racket/base

;;;
;;; Bad Apple!! Prepared Data
;;;

;; Loads the deliberately narrow, prepared data format used by the Bad Apple!! example.
;; This module has no GUI or Skia dependency: callers may validate/decompress assets off the
;; eventspace handler before native paths are compiled on that handler.

(require file/gunzip
         json
         racket/list
         racket/math
         racket/port
         racket/vector)

(provide bad-apple-asset?
         bad-apple-asset-fps-numerator
         bad-apple-asset-fps-denominator
         bad-apple-asset-frame-count
         bad-apple-asset-view-box
         bad-apple-asset-source->view-box
         bad-apple-asset-fill-rule
         bad-apple-asset-frames
         bad-apple-asset-source
         bad-apple-asset-from-jsexpr
         read-bad-apple-asset
         bad-apple-frame-rate
         bad-apple-duration-seconds)

;; An asset's frames are immutable vectors of immutable vectors of SVG path strings. An empty
;; vector is a real, white animation frame rather than an absent frame.
(struct bad-apple-asset (fps-numerator fps-denominator frame-count view-box source->view-box
                                                     fill-rule frames source)
  #:transparent)

(define expected-schema "skia-bad-apple-paths")
(define expected-version 1)

(define (asset-error who format-string . values)
  (apply raise-arguments-error who format-string values))

(define (finite-number? value)
  (and (real? value) (not (nan? value)) (not (infinite? value))))

(define (hash-required who value key predicate description)
  (unless (hash? value)
    (raise-argument-error who "JSON object" value))
  (unless (hash-has-key? value key)
    (raise-arguments-error who "prepared asset is missing a required field" "field" key))
  (define result (hash-ref value key))
  (unless (predicate result)
    (raise-arguments-error who "prepared asset field has the wrong shape"
                           "field" key "expected" description "received" result))
  result)

(define (json-vector who value key count predicate description)
  (define sequence (hash-required who value key list? "JSON array"))
  (unless (= (length sequence) count)
    (raise-arguments-error who "prepared asset array has the wrong length"
                           "field" key "expected" count "received" (length sequence)))
  (for ([item (in-list sequence)] [index (in-naturals)])
    (unless (predicate item)
      (raise-arguments-error who "prepared asset array has an invalid value"
                             "field" key "index" index "expected" description "received" item)))
  (vector->immutable-vector (list->vector sequence)))

(define (validate-source who source)
  (hash-required who source 'repository string? "string")
  (hash-required who source 'commit string? "string")
  (hash-required who source 'path string? "string")
  (hash-required who source 'sha256
                 (lambda (value) (and (string? value) (regexp-match? #px"^[0-9a-f]{64}$" value)))
                 "lowercase SHA-256 string")
  (hash-required who source 'first_source_index exact-nonnegative-integer?
                 "exact nonnegative integer")
  source)

;; bad-apple-asset-from-jsexpr : jsexpr? -> bad-apple-asset?
;; Performs structural validation before any native Skia resource is allocated.
(define (bad-apple-asset-from-jsexpr value)
  (define who 'bad-apple-asset-from-jsexpr)
  (unless (hash? value)
    (raise-argument-error who "JSON object" value))
  (define schema (hash-required who value 'schema string? "string"))
  (unless (string=? schema expected-schema)
    (raise-arguments-error who "unsupported prepared asset schema"
                           "expected" expected-schema "received" schema))
  (define version (hash-required who value 'version exact-integer? "exact integer"))
  (unless (= version expected-version)
    (raise-arguments-error who "unsupported prepared asset version"
                           "expected" expected-version "received" version))
  (define source (validate-source who (hash-required who value 'source hash? "JSON object")))
  (define numerator (hash-required who value 'fps_numerator exact-positive-integer?
                                   "exact positive integer"))
  (define denominator (hash-required who value 'fps_denominator exact-positive-integer?
                                     "exact positive integer"))
  (define declared-count (hash-required who value 'frame_count exact-nonnegative-integer?
                                       "exact nonnegative integer"))
  (define view-box (json-vector who value 'view_box 4 finite-number? "finite number"))
  (unless (and (= (vector-ref view-box 0) 0) (= (vector-ref view-box 1) 0)
               (positive? (vector-ref view-box 2)) (positive? (vector-ref view-box 3)))
    (raise-arguments-error who "view_box must begin at zero and have positive dimensions"
                           "view_box" view-box))
  (define source->view-box
    (json-vector who value 'source_to_view_box 6 finite-number? "finite number"))
  (define fill-rule (hash-required who value 'fill_rule string? "string"))
  (unless (string=? fill-rule "winding")
    (raise-arguments-error who "only the source winding fill rule is supported"
                           "fill_rule" fill-rule))
  (define source-frames (hash-required who value 'frames list? "JSON array"))
  (unless (= declared-count (length source-frames))
    (raise-arguments-error who "declared frame count does not match frames"
                           "frame_count" declared-count "actual" (length source-frames)))
  (when (zero? declared-count)
    (raise-arguments-error who "prepared asset contains no frames" "frame_count" declared-count))
  (define frames
    (for/vector ([frame (in-list source-frames)] [frame-index (in-naturals)])
      (unless (list? frame)
        (raise-arguments-error who "frame is not a JSON array" "frame" frame-index))
      (for/vector ([path-data (in-list frame)] [path-index (in-naturals)])
        (unless (string? path-data)
          (raise-arguments-error who "frame path is not a string"
                                 "frame" frame-index "path" path-index))
        path-data)))
  (bad-apple-asset numerator denominator declared-count view-box source->view-box 'winding
                   (vector->immutable-vector
                    (for/vector ([frame (in-vector frames)]) (vector->immutable-vector frame)))
                   source))

;; read-bad-apple-asset : path-string? -> bad-apple-asset?
;; Decompresses and validates a gzip JSON asset. The returned value contains ordinary immutable
;; Racket data and can safely cross from a loader worker to the GUI handler thread.
(define (read-bad-apple-asset path)
  (define who 'read-bad-apple-asset)
  (call-with-input-file path
    (lambda (input)
      (define output (open-output-bytes))
      (gunzip-through-ports input output)
      (define bytes (get-output-bytes output))
      (with-handlers ([exn:fail?
                       (lambda (error)
                         (raise-arguments-error who "cannot parse prepared gzip JSON asset"
                                                "path" path "detail" (exn-message error)))])
        (bad-apple-asset-from-jsexpr
         (call-with-input-bytes bytes read-json))))))

;; bad-apple-frame-rate : bad-apple-asset? -> exact-positive-rational?
(define (bad-apple-frame-rate asset)
  (unless (bad-apple-asset? asset)
    (raise-argument-error 'bad-apple-frame-rate "bad-apple-asset?" asset))
  (/ (bad-apple-asset-fps-numerator asset) (bad-apple-asset-fps-denominator asset)))

;; bad-apple-duration-seconds : bad-apple-asset? -> exact-positive-rational?
(define (bad-apple-duration-seconds asset)
  (unless (bad-apple-asset? asset)
    (raise-argument-error 'bad-apple-duration-seconds "bad-apple-asset?" asset))
  (/ (bad-apple-asset-frame-count asset) (bad-apple-frame-rate asset)))
