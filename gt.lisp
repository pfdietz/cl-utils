;;;; gt.lisp --- GrammaTech Common Lisp utilities core package
;;;;
;;;; Copyright (C) 2020 GrammaTech, Inc.
;;;;
;;;; This code is licensed under the MIT license. See the LICENSE.txt
;;;; file in the project root for license terms.
;;;;
;;;; This project is sponsored by the Office of Naval Research, One
;;;; Liberty Center, 875 N. Randolph Street, Arlington, VA 22203 under
;;;; contract # N68335-17-C-0700.  The content of the information does
;;;; not necessarily reflect the position or policy of the Government
;;;; and no official endorsement should be inferred.
(uiop/package:define-package :gt
    (:nicknames :gt/gt)
  (:use-reexport :common-lisp :alexandria :serapeum :closer-mop
                 :trivia :iterate :gt/fset :fset :gmap :split-sequence :cl-ppcre
                 :bordeaux-threads
                 :functional-trees
                 :named-readtables :curry-compose-reader-macros)
  (:shadow :mapconcat :~> :~~>)  ; Shadow serapeum arrows & mapconcat.
  (:shadow :lines)                      ; We wrap in a defgeneric.
  (:shadow :exe)                        ; This isn't generically useful.
  (:shadow :equal?)                     ; We're rather this be generic.
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
  (:shadowing-import-from :closer-mop
                          :standard-method
                          :standard-class
                          :standard-generic-function
                          :defmethod
                          :defgeneric)
  (:shadowing-import-from :functional-trees :mapcar :mapc)
  (:shadowing-import-from :fset
                          :@
                          :unionf :appendf :with :removef :size :complement
                          ;; Shadowed type/constructor names.
                          :set
                          ;; Shadowed sequence operations.
                          :first :subseq :reverse :sort :stable-sort
                          :reduce
                          :find :find-if :find-if-not
                          :count :count-if :count-if-not
                          :position :position-if :position-if-not
                          :remove :remove-if :remove-if-not
                          :substitute :substitute-if :substitute-if-not
                          :some :every :notany :notevery
                          ;; Shadowed sequence operations from serapeum.
                          :concat :range :partition :filter)
  (:shadowing-import-from :gt/fset
                          :last :lastcar
                          :union :intersection :set-difference)
  (:shadowing-import-from :cl-ppcre
                          :scan)        ; Shadow serapeum:scan.
  (:export :mapconcat
           :negative-infinity
           :positive-infinity
           :infinity
           :parse-number
           :parse-numbers))
;;; NOTE: *Consider* including Generic-cl less its new seq. stuff.
(in-package :gt)

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

(define-condition parse-number (error)
  ((text :initarg :text :initform nil :reader text))
  (:report (lambda (condition stream)
             (format stream "Can't parse ~a as a number" (text condition)))))

(defun parse-number (string)
  "Parse the number located at the front of STRING or return an error."
  (let ((number-str
         (or (multiple-value-bind (whole matches)
                 (scan-to-strings
                  "^(-?.?[0-9]+(/[-e0-9]+|\\.[-e0-9]+)?)([^\\./A-Xa-x_-]$|$)"
                  string)
               (declare (ignorable whole))
               (when matches (aref matches 0)))
             (multiple-value-bind (whole matches)
                 (scan-to-strings "0([xX][0-9A-Fa-f]+)([^./]|$)"
                                  string)
               (declare (ignorable whole))
               (when matches (concatenate 'string "#" (aref matches 0)))))))
    (unless number-str
      (make-condition 'parse-number :text string))
    (read-from-string number-str)))

(defun parse-numbers (string &key (radix 10) (delim #\Space))
  (mapcar #'(lambda (num) (parse-integer num :radix radix))
          (split-sequence delim string :remove-empty-subseqs t)))


;;; Some functions become generic functions for extensibility.
(defgeneric lines (thing)
  (:documentation "A list of lines in THING.")
  (:method ((string string)) (serapeum:lines string)))

(defgeneric equal? (a b)
  (:documentation "Generic equality designed to descend into structures.")
  (:method ((a collection) (b collection)) (equal? a b)))
