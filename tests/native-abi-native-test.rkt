#lang racket/base
(require rackunit "../native-capabilities.rkt"
         (only-in "../private/native.rkt" skia-check! skia-native-version skia-native-library-handle))
(provide native-abi-native-tests)
(define native-abi-native-tests
  (test-suite
   "native ABI diagnostics on the accepted library"
   (test-case "CPU preflight" (check-not-exn skia-check!))
   (test-case "runtime identity"
     (check-equal? (hash-ref (skia-native-capabilities) 'native_version) (skia-native-version)))
   (test-case "all CPU bindings resolved"
     (check-true (hash-ref (skia-native-capabilities) 'required_cpu_symbols_resolved)))
   (test-case "Racket layouts checked" (check-true (hash-ref (skia-native-capabilities) 'racket_layouts_checked)))
   (test-case "required registry preserved"
     (check-true (> (hash-ref (skia-native-capabilities) 'required_cpu_symbol_count) 300)))
   (test-case "present and absent exports"
     (check-equal? (map (lambda (row) (hash-ref row 'available))
                       (skia-native-symbol-inventory '(sk_version_get_milestone sk_stage047_nonexistent_export)))
                   '(#t #f)))
   (test-case "inventory arguments"
     (check-exn exn:fail:contract? (lambda () (skia-native-symbol-inventory '(123)))))
   (test-case "one shared library handle"
     (define handle (skia-native-library-handle))
     (define environment (environment-variables-copy (current-environment-variables)))
     (environment-variables-set! environment #"RACKET_SKIA_LIBRARY" #"/absent/stage047-library")
     (parameterize ([current-environment-variables environment])
       (check-eq? handle (skia-native-library-handle))))
   (test-case "no backend/device claims"
     (define report (skia-native-capabilities))
     (check-false (hash-ref report 'backend_creation_verified))
     (check-false (hash-ref report 'hardware_acceleration_verified)))
   (test-case "NuGet pin is not inferred loaded provenance"
     (check-false (hash-ref (skia-native-capabilities) 'package_identity_from_version_functions)))))
(module+ test
  (require rackunit/text-ui)
  (define failures (run-tests native-abi-native-tests))
  (unless (zero? failures) (error 'native-abi-native-tests "tests failed")))
