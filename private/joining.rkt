#lang racket/base
(require racket/list racket/string)

(provide joining-type arabic-kashida-boundaries)

;; Unicode 15.1 joining data compacted from ArabicShaping-15.1.0.txt.
;; Only the joining types that can participate in cursive connections are
;; stored explicitly. Other spacing characters are U (non-joining); combining
;; marks default to T (transparent) for the boundary scan below.
(define packed-joining-data
  #<<JOINING-DATA
620-620:D 622-625:R 626-626:D 627-627:R 628-628:D 629-629:R 62a-62e:D 62f-632:R 633-63f:D 640-640:C 641-647:D 648-648:R 649-64a:D 66e-66f:D 671-673:R 675-677:R 678-687:D 688-699:R 69a-6bf:D 6c0-6c0:R 6c1-6c2:D 6c3-6cb:R 6cc-6cc:D 6cd-6cd:R 6ce-6ce:D 6cf-6cf:R 6d0-6d1:D 6d2-6d3:R 6d5-6d5:R 6ee-6ef:R 6fa-6fc:D 6ff-6ff:D 710-710:R 712-714:D 715-719:R 71a-71d:D 71e-71e:R 71f-727:D 728-728:R 729-729:D 72a-72a:R 72b-72b:D 72c-72c:R 72d-72e:D 72f-72f:R 74d-74d:R 74e-758:D 759-75b:R 75c-76a:D 76b-76c:R 76d-770:D 771-771:R 772-772:D 773-774:R 775-777:D 778-779:R 77a-77f:D 7ca-7ea:D 7fa-7fa:C 840-840:R 841-845:D 846-847:R 848-848:D 849-849:R 84a-853:D 854-854:R 855-855:D 856-858:R 860-860:D 862-865:D 867-867:R 868-868:D 869-86a:R 870-882:R 883-885:C 886-886:D 889-88d:D 88e-88e:R 8a0-8a9:D 8aa-8ac:R 8ae-8ae:R 8af-8b0:D 8b1-8b2:R 8b3-8b8:D 8b9-8b9:R 8ba-8c8:D 1807-1807:D 180a-180a:C 1820-1878:D 1887-18a8:D 18aa-18aa:D 200d-200d:C a840-a871:D a872-a872:L 10ac0-10ac4:D 10ac5-10ac5:R 10ac7-10ac7:R 10ac9-10aca:R 10acd-10acd:L 10ace-10ad2:R 10ad3-10ad6:D 10ad7-10ad7:L 10ad8-10adc:D 10add-10add:R 10ade-10ae0:D 10ae1-10ae1:R 10ae4-10ae4:R 10aeb-10aee:D 10aef-10aef:R 10b80-10b80:D 10b81-10b81:R 10b82-10b82:D 10b83-10b85:R 10b86-10b88:D 10b89-10b89:R 10b8a-10b8b:D 10b8c-10b8c:R 10b8d-10b8d:D 10b8e-10b8f:R 10b90-10b90:D 10b91-10b91:R 10ba9-10bac:R 10bad-10bae:D 10d00-10d00:L 10d01-10d21:D 10d22-10d22:R 10d23-10d23:D 10f30-10f32:D 10f33-10f33:R 10f34-10f44:D 10f51-10f53:D 10f54-10f54:R 10f70-10f73:D 10f74-10f75:R 10f76-10f81:D 10fb0-10fb0:D 10fb2-10fb3:D 10fb4-10fb6:R 10fb8-10fb8:D 10fb9-10fba:R 10fbb-10fbc:D 10fbd-10fbd:R 10fbe-10fbf:D 10fc1-10fc1:D 10fc2-10fc3:R 10fc4-10fc4:D 10fc9-10fc9:R 10fca-10fca:D 10fcb-10fcb:L 1e900-1e943:D
JOINING-DATA
  )

(struct joining-range (lo hi type) #:transparent)

(define joining-ranges
  (list->vector
   (for/list ([token (in-list (string-split packed-joining-data))])
     (define m (regexp-match #px"^([0-9a-f]+)-([0-9a-f]+):([DRLC])$" token))
     (unless m (error 'joining-data "bad compact token ~s" token))
     (joining-range (string->number (list-ref m 1) 16)
                    (string->number (list-ref m 2) 16)
                    (string->symbol (list-ref m 3))))))

(define (explicit-joining-type cp)
  (let loop ([lo 0] [hi (sub1 (vector-length joining-ranges))])
    (cond
      [(> lo hi) #f]
      [else
       (define mid (quotient (+ lo hi) 2))
       (define r (vector-ref joining-ranges mid))
       (cond [(< cp (joining-range-lo r)) (loop lo (sub1 mid))]
             [(> cp (joining-range-hi r)) (loop (add1 mid) hi)]
             [else (joining-range-type r)])])))

(define (joining-type ch)
  (unless (char? ch) (raise-argument-error 'joining-type "char?" ch))
  (or (explicit-joining-type (char->integer ch))
      (if (memq (char-general-category ch) '(mn me)) 'T 'U)))

(struct joining-cluster (start end type) #:transparent)

(define (cluster-joining-type text start end)
  ;; ZWNJ is non-joining even when it sits in the same default grapheme cluster
  ;; as a neighboring base. Otherwise transparent marks do not affect joining.
  (cond
    [(for/or ([i (in-range start end)])
       (= (char->integer (string-ref text i)) #x200C))
     'U]
    [else
     (or (for/or ([i (in-range start end)])
           (let ([t (joining-type (string-ref text i))])
             (and (not (eq? t 'T)) t)))
         'U)]))

(define (joining-clusters text)
  (define n (string-length text))
  (let loop ([start 0] [out '()])
    (cond
      [(>= start n) (reverse out)]
      [else
       (define end (+ start (string-grapheme-span text start n)))
       (loop end
             (cons (joining-cluster start end
                                    (cluster-joining-type text start end))
                   out))])))

(define (joins-forward? type)
  ;; In logical order D/L can connect to the following character.
  (and (memq type '(D L)) #t))

(define (joins-backward? type)
  ;; In logical order D/R can connect to the preceding character.
  (and (memq type '(D R)) #t))

(define (arabic-kashida-boundaries text)
  ;; Return conservative default-grapheme boundaries where inserting U+0640
  ;; keeps a cursive connection on both sides. The caller decides whether a
  ;; particular script/font actually uses these candidates for justification.
  (unless (string? text)
    (raise-argument-error 'arabic-kashida-boundaries "string?" text))
  (define cs (joining-clusters text))
  (for/list ([left (in-list cs)]
             [right (in-list (if (pair? cs) (cdr cs) '()))]
             #:when (and (joins-forward? (joining-cluster-type left))
                         (joins-backward? (joining-cluster-type right))))
    (joining-cluster-start right)))
