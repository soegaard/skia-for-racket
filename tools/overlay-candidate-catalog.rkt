#lang racket/base
;; catalog-archive repacks inputs. Restore candidate catalog records after the
;; Python stager restores the original byte-identical candidate ZIPs/checksums.
(require racket/file racket/path racket/cmdline)
(module+ main
  (command-line #:args (candidates destination)
    (define original (file->value (build-path candidates "pkgs-all")))
    (define snapshot (file->value (build-path destination "pkgs-all")))
    (define result
      (for/fold ([result snapshot]) ([(name data) (in-hash original)])
        (define updated (hash-set data 'source (string-append "../pkgs/" name ".zip")))
        (write-to-file updated (build-path destination "pkg" name) #:exists 'truncate)
        (hash-set result name updated)))
    (write-to-file result (build-path destination "pkgs-all") #:exists 'truncate)
    (write-to-file (sort (hash-keys result) string<?) (build-path destination "pkgs") #:exists 'truncate)))
