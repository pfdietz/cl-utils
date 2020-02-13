(uiop/package:define-package :gt
    (:nicknames :gt/gt)
  (:use-reexport :common-lisp :alexandria :serapeum :closer-mop
                 :trivia :iterate :fset :gmap :split-sequence :cl-ppcre
                 :named-readtables :curry-compose-reader-macros)
  (:shadow :mapconcat :~> :~~>)  ; Shadow serapeum arrows & mapconcat.
  (:shadowing-import-from :common-lisp
                          :map)         ; Shadow fset:map.
  (:shadowing-import-from :serapeum
                          :tuple)       ; Shadow fset:tuple.
  (:shadowing-import-from :alexandria
                          :compose)     ; Shadow fset:compose.
  (:shadowing-import-from :trivia
                          :alist)       ; Shadow fset:alist.
  (:shadowing-import-from :iterate
                          ;; Shadow serapeum macros.
                          :summing :collecting :sum :in)
  (:shadowing-import-from :closer-mop :defmethod
                          :defgeneric :standard-generic-function
                          :slot-definition-name :class-slots)
  (:shadowing-import-from :fset
                          :@
                          :unionf :appendf :with :removef
			  ;; Shadowed type/constructor names.
			  :set
			  ;; Shadowed set operations.
			  :union :intersection :set-difference :complement
			  ;; Shadowed sequence operations.
			  :first :last :subseq :reverse :sort :stable-sort
			  :reduce
			  :find :find-if :find-if-not
			  :count :count-if :count-if-not
			  :position :position-if :position-if-not
			  :remove :remove-if :remove-if-not
			  :substitute :substitute-if :substitute-if-not
			  :some :every :notany :notevery
                          ;; Shadowed sequence operations from serapeum.
                          :concat :range :partition :filter)
  (:shadowing-import-from :cl-ppcre
                          :scan))       ; Shadow serapeum:scan.

;;; A poor approximation of `serapium:@'.
(defmethod lookup ((table hash-table) key)
  (gethash key table))

(defgeneric mapconcat (function collection separator &key stream)
  (:documentation "Build a string by mapping FUNCTION over COLLECTION.
Separate each value with SEPARATOR.
An extension of `serapeum:mapconct' to include fset collections.")
  (:method (function (sequence sequence) separator &key stream)
    (serapeum:mapconcat function sequence separator :stream stream))
  (:method (function (seq seq) separator &key stream)
    (let ((function (coerce function 'function))
          (i 0)
          (ult (1- (size seq))))
      (with-string (stream stream)
        (do-seq (element seq)
          (write-string (funcall function element) stream)
          (unless (= (prog1 i (incf i)) ult)
            (write-string separator stream)))))))

(defvar negative-infinity
  #+sbcl
  sb-ext:double-float-negative-infinity
  #+ccl
  ccl::double-float-negative-infinity
  #+allegro
  excl:*infinity-double*
  #+ecl
  ext:long-float-negative-infinity
  #-(or ecl sbcl ccl allegro)
  (error "")
  "Most negative number.")

(defvar positive-infinity
  #+sbcl
  sb-ext:double-float-positive-infinity
  #+ccl
  ccl::double-float-positive-infinity
  #+allegro
  excl:*infinity-double*
  #+ecl
  ext:long-float-positive-infinity
  #-(or ecl sbcl ccl allegro)
  (error "")
  "Most positive number.")

(defvar infinity positive-infinity
  "Most positive number.")

(defmethod print-object ((obj (eql negative-infinity)) stream)
  (if *print-readably* (call-next-method) (format stream "negative-infinity")))

(defmethod print-object ((obj (eql positive-infinity)) stream)
  (if *print-readably* (call-next-method) (format stream "positive-infinity")))

(defmethod print-object ((obj (eql infinity)) stream)
  (if *print-readably* (call-next-method) (format stream "positive-infinity")))

;;; NOTE: *Consider* including Generic-cl less its new seq. stuff.
;;; TODO: Filesystem from UIOP.
;;; TODO: Process management from UIOP.
