#lang racket/base
(require ffi/unsafe racket/list
         "core.rkt" "check.rkt" "types.rkt" "native.rkt" "lifetime.rkt"
         "filter-util.rkt" "../matrix.rkt" "../color.rkt"
         (submod "core.rkt" filter-internals))
(provide make-crop-image-filter make-offset-image-filter
         make-merge-image-filter make-blend-image-filter make-arithmetic-image-filter
         make-dilate-image-filter make-erode-image-filter make-displacement-map-image-filter
         make-matrix-convolution-image-filter make-matrix-transform-image-filter
         make-image-source-filter make-shader-image-filter make-picture-image-filter
         make-tile-image-filter make-magnifier-image-filter
         make-distant-lit-diffuse-image-filter make-point-lit-diffuse-image-filter
         make-spot-lit-diffuse-image-filter make-distant-lit-specular-image-filter
         make-point-lit-specular-image-filter make-spot-lit-specular-image-filter)

;; Validate/retain all inputs through construction. Missing slots mean the
;; dynamic source, NOT an empty image. An identity Offset node represents that
;; source when a native optimizer returns an input directly (e.g. Blend Src).
;; This keeps valid identity results owned, rather than misreporting NULL as an
;; allocation error. The native shim refs every retained child synchronously.
(define (graph-filter who handles create)
  (new-image-filter
   who
   (lambda ()
     (call-with-owned
      who (filter values handles)
      (lambda ptrs
        (define (run source)
          (define remaining ptrs)
          (define args
            (for/list ([h (in-list handles)])
              (if h (begin0 (car remaining) (set! remaining (cdr remaining))) source)))
          (apply create args))
        (if (memq #f handles)
            (call-with-native-temporary
             who 'filter-source
             (lambda () (sk_imagefilter_new_offset 0.0 0.0 #f #f))
             sk_imagefilter_unref run)
            (run #f)))))))

;; Native factories without crop arguments get an explicit output crop. Adopt
;; the intermediate reference before wrapping it so an exception cannot leak it.
(define (crop-result who crop create)
  (if crop
      (call-with-native-temporary who 'uncropped-filter create sk_imagefilter_unref
        (lambda (fp) (sk_imagefilter_new_offset 0.0 0.0 fp crop)))
      (create)))

(define (make-crop-image-filter rectangle #:input [input #f])
  (define who 'make-crop-image-filter)
  (define crop (filter-rectangle who rectangle))
  (define ih (optional-image-filter-h who input))
  (graph-filter who (list ih)
    (lambda (ip) (sk_imagefilter_new_offset 0.0 0.0 ip crop))))

(define (make-offset-image-filter dx dy #:input [input #f] #:crop [crop #f])
  (define who 'make-offset-image-filter)
  (define x (filter-float who dx))
  (define y (filter-float who dy))
  (define cr (optional-filter-crop who crop))
  (define ih (optional-image-filter-h who input))
  (graph-filter who (list ih) (lambda (ip) (sk_imagefilter_new_offset x y ip cr))))

(define (make-merge-image-filter inputs #:crop [crop #f])
  (define who 'make-merge-image-filter)
  (define ins (filter-input-list who inputs))
  (define cr (optional-filter-crop who crop))
  (define hs (map (lambda (f) (optional-image-filter-h who f)) ins))
  (graph-filter who hs
    (lambda ptrs
      (define array (malloc (length ptrs) _pointer 'atomic))
      (for ([p (in-list ptrs)] [i (in-naturals)]) (ptr-set! array _pointer i p))
      (begin0 (sk_imagefilter_new_merge array (length ptrs) cr)
        (void/reference-sink array ptrs)))))

(define (make-blend-image-filter mode background foreground #:crop [crop #f])
  (define who 'make-blend-image-filter)
  (define bm (choice who mode blend-values))
  (define cr (optional-filter-crop who crop))
  (define bg (optional-image-filter-h who background))
  (define fg (optional-image-filter-h who foreground))
  (graph-filter who (list bg fg)
    (lambda (b f) (sk_imagefilter_new_blend bm b f cr))))

(define (make-arithmetic-image-filter k1 k2 k3 k4 background foreground
                                      #:enforce-premul? [enforce? #t] #:crop [crop #f])
  (define who 'make-arithmetic-image-filter)
  (define ks (map (lambda (v) (filter-float who v)) (list k1 k2 k3 k4)))
  (boolean who enforce?)
  (define cr (optional-filter-crop who crop))
  (define bg (optional-image-filter-h who background))
  (define fg (optional-image-filter-h who foreground))
  (graph-filter who (list bg fg)
    (lambda (b f) (apply sk_imagefilter_new_arithmetic (append ks (list enforce? b f cr))))))

(define (morphology who native rx ry input crop)
  (define x (filter-float who (nonnegative-scalar who rx)))
  (define y (filter-float who (nonnegative-scalar who ry)))
  (define cr (optional-filter-crop who crop))
  (define ih (optional-image-filter-h who input))
  (graph-filter who (list ih) (lambda (ip) (native x y ip cr))))

(define (make-dilate-image-filter rx ry #:input [input #f] #:crop [crop #f])
  (morphology 'make-dilate-image-filter sk_imagefilter_new_dilate rx ry input crop))
(define (make-erode-image-filter rx ry #:input [input #f] #:crop [crop #f])
  (morphology 'make-erode-image-filter sk_imagefilter_new_erode rx ry input crop))

(define (make-displacement-map-image-filter x-channel y-channel scale displacement color
                                           #:crop [crop #f])
  (define who 'make-displacement-map-image-filter)
  (define xc (filter-channel who x-channel))
  (define yc (filter-channel who y-channel))
  (define s (filter-float who scale))
  (define cr (optional-filter-crop who crop))
  (define dh (optional-image-filter-h who displacement))
  (define ch (optional-image-filter-h who color))
  (graph-filter who (list dh ch)
    (lambda (dp cp) (sk_imagefilter_new_displacement_map_effect xc yc s dp cp cr))))

(define (make-matrix-convolution-image-filter width height kernel
                                             #:offset [offset #f] #:gain [gain 1] #:bias [bias 0]
                                             #:tile-mode [mode 'decal] #:convolve-alpha? [alpha? #t]
                                             #:input [input #f] #:crop [crop #f])
  (define who 'make-matrix-convolution-image-filter)
  (define-values (size off coefficients) (filter-kernel who width height kernel offset))
  (define g (filter-float who gain))
  (define b (filter-float who bias))
  (boolean who alpha?)
  (define cr (optional-filter-crop who crop))
  (define tile (filter-tile-mode who mode cr #:require-crop? #t))
  (define ih (optional-image-filter-h who input))
  (graph-filter who (list ih)
    (lambda (ip)
      (define array (malloc (length coefficients) _float 'atomic))
      (for ([v (in-list coefficients)] [i (in-naturals)]) (ptr-set! array _float i v))
      (begin0 (sk_imagefilter_new_matrix_convolution size array g b off tile alpha? ip cr)
        (void/reference-sink size off array)))))

(define (filter-matrix who m)
  (unless (matrix? m) (raise-argument-error who "matrix?" m))
  (unless (matrix-invert m)
    (raise-arguments-error who "filter matrix must have a representable inverse" "matrix" m))
  (make-sk-matrix (matrix-xx m) (matrix-xy m) (matrix-x0 m)
                  (matrix-yx m) (matrix-yy m) (matrix-y0 m) 0.0 0.0 1.0))

(define (make-matrix-transform-image-filter m #:sampling [mode 'linear]
                                           #:input [input #f] #:crop [crop #f])
  (define who 'make-matrix-transform-image-filter)
  (define nm (filter-matrix who m))
  (define sm (sampling who mode))
  (define cr (optional-filter-crop who crop))
  (define ih (optional-image-filter-h who input))
  (graph-filter who (list ih)
    (lambda (ip) (crop-result who cr (lambda () (sk_imagefilter_new_matrix_transform nm sm ip))))))

(define (make-image-source-filter image #:source [source #f] #:destination [destination #f]
                                   #:sampling [mode 'linear] #:crop [crop #f])
  (define who 'make-image-source-filter)
  (define ih (image-h who image))
  (define src (filter-rectangle who (or source (list 0 0 (image-width image) (image-height image)))
                                #:positive? #t))
  (unless (and (>= (sk-rect-left src) 0) (>= (sk-rect-top src) 0)
               (<= (sk-rect-right src) (image-width image))
               (<= (sk-rect-bottom src) (image-height image)))
    (raise-arguments-error who "source rectangle lies outside the image" "source" source))
  ;; With no destination, source coordinates and pixel scale are preserved.
  (define dst (if destination (filter-rectangle who destination #:positive? #t) src))
  (define sm (sampling who mode))
  (define cr (optional-filter-crop who crop))
  (graph-filter who (list ih)
    (lambda (ip) (crop-result who cr (lambda () (sk_imagefilter_new_image ip src dst sm))))))

(define (make-shader-image-filter shader #:dither? [dither? #f] #:crop [crop #f])
  (define who 'make-shader-image-filter)
  (define sh (shader-h who shader))
  (boolean who dither?)
  (define cr (optional-filter-crop who crop))
  (graph-filter who (list sh) (lambda (sp) (sk_imagefilter_new_shader sp dither? cr))))

(define (make-picture-image-filter picture #:crop [crop #f])
  (define who 'make-picture-image-filter)
  (define ph (picture-h who picture))
  (define cr (optional-filter-crop who crop))
  (graph-filter who (list ph)
    (lambda (pp) (crop-result who cr (lambda () (sk_imagefilter_new_picture pp))))))

(define (make-tile-image-filter source destination #:input [input #f] #:crop [crop #f])
  (define who 'make-tile-image-filter)
  (define src (filter-rectangle who source #:positive? #t))
  (define dst (filter-rectangle who destination #:positive? #t))
  (define cr (optional-filter-crop who crop))
  (define ih (optional-image-filter-h who input))
  (graph-filter who (list ih)
    (lambda (ip) (crop-result who cr (lambda () (sk_imagefilter_new_tile src dst ip))))))

(define (make-magnifier-image-filter lens zoom #:inset [inset 0] #:sampling [mode 'linear]
                                    #:input [input #f] #:crop [crop #f])
  (define who 'make-magnifier-image-filter)
  (define bounds (filter-rectangle who lens #:positive? #t))
  (define z (filter-float who zoom))
  (unless (>= z 1) (raise-argument-error who "finite zoom factor at least 1" zoom))
  (define i (filter-float who (nonnegative-scalar who inset)))
  (define sm (sampling who mode))
  (define cr (optional-filter-crop who crop))
  (define ih (optional-image-filter-h who input))
  (graph-filter who (list ih)
    (lambda (ip) (sk_imagefilter_new_magnifier bounds z i sm ip cr))))

(define (lighting who native geometry color surface-scale coefficient shininess input crop)
  (define argb (color->argb color))
  (define-values (s k shine) (filter-light-parameters who surface-scale coefficient shininess))
  (define cr (optional-filter-crop who crop))
  (define ih (optional-image-filter-h who input))
  (graph-filter who (list ih)
    (lambda (ip)
      (apply native (append geometry (list argb s k) (if shine (list shine) '()) (list ip cr))))))

(define (make-distant-lit-diffuse-image-filter direction color
                #:surface-scale [surface-scale 1] #:coefficient [coefficient 1]
                #:input [input #f] #:crop [crop #f])
  (define who 'make-distant-lit-diffuse-image-filter)
  (define pt (filter-point3 who direction #:direction? #t))
  (lighting who sk_imagefilter_new_distant_lit_diffuse (list pt)
            color surface-scale coefficient #f input crop))

(define (make-point-lit-diffuse-image-filter location color
                #:surface-scale [surface-scale 1] #:coefficient [coefficient 1]
                #:input [input #f] #:crop [crop #f])
  (define who 'make-point-lit-diffuse-image-filter)
  (define pt (filter-point3 who location))
  (lighting who sk_imagefilter_new_point_lit_diffuse (list pt)
            color surface-scale coefficient #f input crop))

(define (make-spot-lit-diffuse-image-filter location target color
                #:exponent [exponent 1] #:cutoff-angle [cutoff 45]
                #:surface-scale [surface-scale 1] #:coefficient [coefficient 1]
                #:input [input #f] #:crop [crop #f])
  (define who 'make-spot-lit-diffuse-image-filter)
  (define-values (loc dst e c) (filter-spot-parameters who location target exponent cutoff))
  (lighting who sk_imagefilter_new_spot_lit_diffuse (list loc dst e c)
            color surface-scale coefficient #f input crop))

(define (make-distant-lit-specular-image-filter direction color
                #:surface-scale [surface-scale 1] #:coefficient [coefficient 1]
                #:shininess [shininess 16]
                #:input [input #f] #:crop [crop #f])
  (define who 'make-distant-lit-specular-image-filter)
  (unless shininess (raise-argument-error who "shininess from 1 through 128" shininess))
  (define pt (filter-point3 who direction #:direction? #t))
  (lighting who sk_imagefilter_new_distant_lit_specular (list pt)
            color surface-scale coefficient shininess input crop))

(define (make-point-lit-specular-image-filter location color
                #:surface-scale [surface-scale 1] #:coefficient [coefficient 1]
                #:shininess [shininess 16]
                #:input [input #f] #:crop [crop #f])
  (define who 'make-point-lit-specular-image-filter)
  (unless shininess (raise-argument-error who "shininess from 1 through 128" shininess))
  (define pt (filter-point3 who location))
  (lighting who sk_imagefilter_new_point_lit_specular (list pt)
            color surface-scale coefficient shininess input crop))

(define (make-spot-lit-specular-image-filter location target color
                #:exponent [exponent 1] #:cutoff-angle [cutoff 45]
                #:surface-scale [surface-scale 1] #:coefficient [coefficient 1]
                #:shininess [shininess 16]
                #:input [input #f] #:crop [crop #f])
  (define who 'make-spot-lit-specular-image-filter)
  (unless shininess (raise-argument-error who "shininess from 1 through 128" shininess))
  (define-values (loc dst e c) (filter-spot-parameters who location target exponent cutoff))
  (lighting who sk_imagefilter_new_spot_lit_specular (list loc dst e c)
            color surface-scale coefficient shininess input crop))
