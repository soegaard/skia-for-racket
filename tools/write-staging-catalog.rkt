#lang racket/base

;; Write ordinary Racket catalog data using Racket's own metadata reader. Only
;; locally generated info.rkt files and the candidate's info.rkt are evaluated.
(require json racket/file racket/path racket/cmdline setup/getinfo net/url)
(module+ main
  (command-line
   #:args (request-file destination)
   (define request (call-with-input-file request-file read-json))
   (make-directory* (build-path destination "pkg"))
   (define catalog
     (for/hash ([row (in-list request)])
       (define info (get-info/full (string->path (hash-ref row 'metadata_directory))))
       (unless info (error 'write-staging-catalog "missing candidate metadata"))
       (define name (hash-ref row 'name))
       (define data
         (hash 'name name 'source
               (cond [(hash-ref row 'source #f) => values]
                     [(hash-ref row 'directory #f) (hash-ref row 'archive)]
                     [else (url->string (path->url (string->path (hash-ref row 'archive))))])
               'checksum (hash-ref row 'sha1) 'description (info 'pkg-desc (lambda () name))
               ;; Racket catalogs put build and runtime dependencies together;
               ;; catalog-archive otherwise omits registered manual references.
               'author "local unpublished candidate" 'dependencies
               (append (info 'deps (lambda () '())) (info 'build-deps (lambda () '())))
               'build-dependencies (info 'build-deps (lambda () '()))
               'collection (info 'collection (lambda () 'multi))
               'modules '() 'tags '("local-candidate")))
       (write-to-file data (build-path destination "pkg" name) #:exists 'error)
       (values name data)))
   (write-to-file (sort (hash-keys catalog) string<?) (build-path destination "pkgs") #:exists 'error)
   (write-to-file catalog (build-path destination "pkgs-all") #:exists 'error)))
