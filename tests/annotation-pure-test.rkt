#lang racket/base
(require rackunit rackunit/text-ui racket/string
         "../annotations.rkt" "../private/annotation-util.rkt"
         "../private/svg-util.rkt" "../private/check.rkt")
(provide annotation-pure-tests)

(define native-svg
  #"<svg width=\"100\" height=\"80\"><defs><clipPath id=\"old\"><rect width=\"2\" height=\"2\"/></clipPath></defs><g clip-path=\"url(#old)\"><a xlink:href=\"https://example.invalid/?a=1&amp;b=2\"><rect fill-opacity=\"0.0\" x=\"10\" y=\"20\" width=\"30\" height=\"40\"/></a></g></svg>")
(define (finish-native scope bs [prefix #"probe"])
  (finish-svg-annotations 'test scope
    (finish-svg-xml 'test bs 100 80 #"" #"" prefix) 100 80 prefix))
(define (internal-svg name)
  (string->bytes/utf-8
   (format "<svg width=\"100\" height=\"80\"><a xlink:href=\"urn:racket-skia:destination:~a\"><rect fill-opacity=\"0\" width=\"30\" height=\"20\"/></a></svg>"
           (destination-id name))))

(define annotation-pure-tests
  (test-suite
   "Document annotations: pure contracts and SVG finishing"
   (test-case "portable absolute URI schemes"
     (for ([s '("https://example.invalid/a?x=1&y=2#t" "http://example.invalid/"
                "mailto:reader@example.invalid" "HTTPS://example.invalid/")])
       (check-equal? (annotation-uri 'test s) s)))
   (test-case "relative links and escaped Unicode"
     (for ([s '("chapter-2.svg#target" "../notes.pdf" "/manual/index.html"
                "https://example.invalid/%CE%B1")])
       (check-equal? (annotation-uri 'test s) s)))
   (test-case "active and unsupported URI schemes are rejected"
     (for ([s '("javascript:alert(1)" "data:text/html,test" "file:///tmp/a" "urn:x:y")])
       (check-exn exn:fail:contract? (lambda () (annotation-uri 'test s)))))
   (test-case "URI controls, whitespace, and raw Unicode are rejected"
     (for ([s (list "" "https://x/a b" "https://x/\n" "https://x/\0" "https://x/ø"
                     "https://x/<x>" "https://x/\"x" "a\\b")])
       (check-exn exn:fail:contract? (lambda () (annotation-uri 'test s)))))
   (test-case "URI scheme and percent-escape validation"
     (for ([s '("https:/x" "https://" "mailto:" "1a:b" "x%" "x%2" "x%GG" "#here")])
       (check-exn exn:fail:contract? (lambda () (annotation-uri 'test s)))))
   (test-case "URI data is copied and NUL terminated"
     (define s (string-copy "https://example.invalid/"))
     (define copy (annotation-uri 'test s))
     (string-set! s 0 #\X)
     (check-equal? copy "https://example.invalid/")
     (check-true (immutable? copy))
     (check-equal? (annotation-c-string 'test "abc") #"abc\0"))
   (test-case "names have stable injective ASCII IDs"
     (check-equal? (destination-id "intro") "dest-696e74726f")
     (check-equal? (destination-id "α") "dest-ceb1")
     (check-not-equal? (destination-id "A") (destination-id "a"))
     (check-not-equal? (destination-id "a-b") (destination-id "a_b")))
   (test-case "names permit punctuation without XML injection"
     (define n "α & <section> \"one\"")
     (check-true (regexp-match? #rx"^dest-[0-9a-f]+$" (destination-id n)))
     (check-true (immutable? (destination-id n))))
   (test-case "invalid destination names"
     (for ([s (list #f 'intro "" "a\0b" "a\nb" (string #\rubout))])
       (check-exn exn:fail:contract? (lambda () (destination-id s)))))
   (test-case "SVG IDs are prefix scoped"
     (check-equal? (svg-destination-id "intro") "skia-dest-696e74726f")
     (check-equal? (svg-destination-id "intro" #:id-prefix "page_2") "page_2-dest-696e74726f")
     (for ([p '("" "2bad" "a b" "<x>" #f)])
       (check-exn exn:fail:contract? (lambda () (svg-destination-id "intro" #:id-prefix p)))))
   (test-case "annotation buffers respect the byte limit"
     (parameterize ([current-skia-byte-limit 8])
       (check-exn exn:fail? (lambda () (annotation-uri 'test "https://example.invalid/")))
       (check-exn exn:fail? (lambda () (destination-id "intro")))
       (check-exn exn:fail? (lambda () (annotation-c-string 'test "12345678")))))
   (test-case "duplicate definitions are rejected within one scope"
     (define scope (box #f))
     (annotation-define! 'test scope "intro" 1 2)
     (check-exn #rx"already defined" (lambda () (annotation-define! 'test scope "intro" 3 4)))
     (annotation-forget! scope))
   (test-case "independent documents can reuse names"
     (define a (box #f)) (define b (box #f))
     (annotation-define! 'test a "intro" 1 2)
     (annotation-define! 'test b "intro" 3 4)
     (check-not-exn (lambda () (annotation-check! 'test a)))
     (check-not-exn (lambda () (annotation-check! 'test b)))
     (annotation-forget! a) (annotation-forget! b))
   (test-case "forward references are checked at finish"
     (define s (box #f))
     (annotation-reference! 'test s "later")
     (check-exn #rx"undefined" (lambda () (annotation-check! 'test s)))
     (annotation-define! 'test s "later" 9 8)
     (check-not-exn (lambda () (annotation-check! 'test s)))
     (annotation-forget! s))
   (test-case "registered names are independent of mutable input"
     (define s (box #f)) (define n (string-copy "intro"))
     (annotation-reference! 'test s n)
     (string-set! n 0 #\X)
     (annotation-define! 'test s "intro" 0 0)
     (check-not-exn (lambda () (annotation-check! 'test s)))
     (annotation-forget! s))
   (test-case "forget clears unresolved state"
     (define s (box #f))
     (annotation-reference! 'test s "missing")
     (annotation-forget! s)
     (check-not-exn (lambda () (annotation-check! 'test s))))
   (test-case "SVG links move outside stale graphics clip groups"
     (define out (finish-native (box #f) native-svg))
     (check-true (regexp-match? #px#"</g>(?s:.*?)<a " out))
     (check-true (regexp-match? #rx#"href=\"https://example.invalid/\\?a=1&amp;b=2\"" out))
     (check-false (regexp-match? #rx#"amp;amp" out)))
   (test-case "external href text is not rewritten as a paint server"
     (define bs #"<svg width=\"100\" height=\"80\"><a xlink:href=\"https://example.invalid/?q=url(#not-a-resource)\"><rect width=\"2\" height=\"2\"/></a></svg>")
     (check-true (regexp-match? #rx#"url\\(#not-a-resource\\)" (finish-native (box #f) bs))))
   (test-case "native graphics resource references still resolve"
     (define out (finish-native (box #f) native-svg))
     (check-true (regexp-match? #rx#"id=\"probe-0\"" out))
     (check-true (regexp-match? #rx#"clip-path=\"url\\(#probe-0\\)\"" out)))
   (test-case "SVG destination links resolve to prefixed views"
     (define s (box #f))
     (annotation-reference! 'test s "intro")
     (annotation-define! 'test s "intro" 12 34)
     (define out (finish-native s (internal-svg "intro")))
     (check-true (regexp-match? #rx#"href=\"#probe-dest-696e74726f\"" out))
     (check-true (regexp-match? #rx#"<view id=\"probe-dest-696e74726f\" viewBox=\"12.0 34.0 100 80\"" out))
     (check-false (regexp-match? #rx#"urn:racket-skia" out))
     (annotation-forget! s))
   (test-case "definitions work on an otherwise empty SVG"
     (define s (box #f))
     (annotation-define! 'test s "empty" 0 0)
     (check-true (regexp-match? #rx#"<view " (finish-native s #"<svg width=\"100\" height=\"80\"/>")))
     (annotation-forget! s))
   (test-case "dangling or forged native destination tokens fail"
     (check-exn exn:fail? (lambda () (finish-native (box #f) (internal-svg "missing")))))
   (test-case "SVG view ordering is deterministic"
     (define a (box #f)) (define b (box #f))
     (for ([n '("a" "b")]) (annotation-define! 'test a n 1 2))
     (for ([n '("b" "a")]) (annotation-define! 'test b n 1 2))
     (check-equal? (finish-native a #"<svg width=\"100\" height=\"80\"/>") (finish-native b #"<svg width=\"100\" height=\"80\"/>"))
     (annotation-forget! a) (annotation-forget! b))
   (test-case "SVG added output is bounded"
     (define s (box #f))
     (annotation-define! 'test s "intro" 0 0)
     (parameterize ([current-skia-byte-limit 40])
       (check-exn exn:fail? (lambda () (finish-svg-annotations 'test s #"<svg></svg>" 100 80 #"x"))))
     (annotation-forget! s))
   (test-case "invalid public rectangles fail before native use"
     (check-exn exn:fail:contract? (lambda () (canvas-annotate-url! #f 0 0 -1 2 "https://x/")))
     (check-exn exn:fail:contract? (lambda () (canvas-link-destination! #f 0 0 2 +nan.0 "intro")))
     (check-exn exn:fail:contract? (lambda () (canvas-define-destination! #f "intro" +inf.0 0))))))
(module+ test (run-tests annotation-pure-tests))
