;;;; Shell and system command helpers
;;;
;;; Wrappers for evaluating shell commands and returning the STDOUT,
;;; STDERR, and ERRNO as values.  Includes the special `*shell-debug*'
;;; variable which may be set to non-nil to dump all system and shell
;;; executions and results for diagnostics.
;;;
;;; The `write-shell', `read-shell', `write-shell-file',
;;; `read-shell-file' and `xz-pipe' functions provide for running
;;; shell commands and common lisp streams (in some cases flowing from
;;; or into files on disk).
(uiop/package:define-package :gt/shell
    (:use :common-lisp :alexandria :iterate :gt/misc :arrow-macros
          :cl-ppcre :split-sequence)
  (:import-from :uiop/run-program :run-program)
  (:import-from :uiop/os :getenv)
  (:export :*shell-debug*
           :*shell-error-codes*
           :*shell-non-error-codes*
           :shell-command-failed
           :shell
           :write-shell
           :read-shell
           :write-shell-file
           :read-shell-file
           :xz-pipe
           :escape-chars
           :split-quoted
           :escape-string
           :unescape-string
           :which
           #+windows :ensure-slash
           #+windows :convert-backslash-to-slash))
(in-package :gt/shell)

(defvar *shell-debug* nil
  "Set to true to print shell invocations.  If a list, print
shell cmd if :CMD is a membe, input if :INPUT is a member, and
print the shell outputs if :OUTPUT is a member.")

(defvar *shell-error-codes* '(126 127)
  "Raise a condition on these exit codes.")

(defvar *shell-non-error-codes* nil
  "Raise a condition on any but these exit codes.")

(define-condition shell-command-failed (error)
  ((commmand :initarg :command :initform nil :reader command)
   (exit-code :initarg :exit-code :initform nil :reader exit-code)
   (stderr :initarg :stderr :initform nil :reader stderr))
  (:report (lambda (condition stream)
             (format stream "Shell command ~S failed with [~A]:~%~S~&"
                     (command condition)
                     (exit-code condition)
                     (stderr condition)))))

(defun shell (control-string &rest format-arguments &aux input)
  "Apply CONTROL-STRING to FORMAT-ARGUMENTS and execute the result with a shell.
Return (values stdout stderr errno).  FORMAT-ARGUMENTS up to the first
keyword are passed to `format' with CONTROL-STRING to construct the
shell command.  All subsequent elements of FORMAT-ARGUMENTS are passed
through as keyword arguments to `uiop:run-program'.

Raise a `shell-command-failed' exception depending on the combination
of errno with `*shell-error-codes*' and `*shell-non-error-codes*'.

Optionally print debug information if `*shell-debug*' is non-nil."
  (let ((format-arguments (take-until #'keywordp format-arguments))
        (run-program-arguments (drop-until #'keywordp format-arguments))
        (debug *shell-debug*))
    ;; Manual handling of an :input keyword argument.
    (when-let ((input-arg (plist-get :input run-program-arguments)))
      (setq input
            (if (stringp input-arg)
                (make-string-input-stream input-arg)
                input-arg)))
    (setq run-program-arguments (plist-drop :input run-program-arguments))
    ;; Manual handling of :bash keyword argument.
    (when (plist-get :bash run-program-arguments)
      ;; Use bash instead of /bin/sh, this means setting bash -c "<command>"
      ;; with appropriate string escaping.  Use a formatter function instead
      ;; of a control-string.
      (if input
          (setf control-string
                (let ((cs control-string))
                  (lambda (stream &rest args)
                    (format stream "~a"
                            (concatenate 'string "bash -c \""
                                         (escape-chars "$\\\""
                                                       (apply #'format nil cs args))
                                         "\"")))))
          ;; When there is no input, send the command directly to bash
          (setf
           input (make-string-input-stream
                  (apply #'format nil control-string format-arguments))
           control-string "bash")))
    (setq run-program-arguments (plist-drop :bash run-program-arguments))
    (let ((cmd (apply #'format (list* nil control-string format-arguments)))
          (stdout-str nil)
          (stderr-str nil)
          (errno nil))
      (when (or (not (listp debug)) (member :cmd debug))
        (format t "  cmd: ~a~%" cmd))
      (when (and input (or (not (listp debug))
                           (member :input debug)))
        (format t "  input: ~a~%" input))

      ;; Direct shell execution with `uiop/run-program:run-program'.
      #+(and (not ccl) (not windows))
      (progn
        (setf stdout-str (make-array '(0)
                                     :element-type
                                     #+sbcl 'extended-char
                                     #-sbcl 'character
                                     :fill-pointer 0 :adjustable t))
        (setf stderr-str (make-array '(0)
                                     :element-type
                                     #+sbcl 'extended-char
                                     #-sbcl 'character
                                     :fill-pointer 0 :adjustable t))
        (with-output-to-string (stderr stderr-str)
          (with-output-to-string (stdout stdout-str)
            (setf errno (nth-value 2 (apply #'run-program
                                            cmd
                                            :force-shell t
                                            :ignore-error-status t
                                            :input input
                                            :output stdout
                                            :error-output stderr
                                            run-program-arguments))))))
      #+windows
      (multiple-value-setq (stdout-str stderr-str errno)
        (apply #'run-program cmd :force-shell nil
               :ignore-error-status t
               :input input
               :output :string
               :error-output :string
               run-program-arguments))

      #+(and ccl (not windows))
      (progn
        (with-temp-file (stdout-file)
          (with-temp-file (stderr-file)
            (setf errno (nth-value 2 (apply #'run-program
                                            (format nil "~a 1>~a 2>~a"
                                                    cmd stdout-file stderr-file)
                                            :force-shell t
                                            :ignore-error-status t
                                            :input input
                                            run-program-arguments)))
            (setf stdout-str (if (probe-file stdout-file)
                                 (file-to-string stdout-file)
                                 ""))
            (setf stderr-str (if (probe-file stderr-file)
                                 (file-to-string stderr-file)
                                 "")))))
      (when (or (not (listp debug)) (member :output debug))
        (format t "~&stdout:~a~%stderr:~a~%errno:~a"
                stdout-str stderr-str errno))
      (when (or (and *shell-non-error-codes*
                     (not (find errno *shell-non-error-codes*)))
                (find errno *shell-error-codes*))
        (restart-case (error (make-condition 'shell-command-failed
                               :command cmd
                               :exit-code errno
                               :stderr stderr-str))
          (ignore-shell-error () "Ignore error and continue")))
      (values stdout-str stderr-str errno))))

#-windows  ; IO-SHELL not yet supported on Windows
(defmacro io-shell ((io stream-var shell &rest args) &rest body)
  "Executes BODY with STREAM-VAR holding the input or output of SHELL.
ARGS (including keyword arguments) are passed through to `uiop:launch-program'."
  (assert (member io '(:input :output)) (io)
          "first argument ~a to `io-shell' is not one of :INPUT or :OUTPUT" io)
  (let ((proc-sym (gensym)))
    `(let* ((,proc-sym (uiop:launch-program ,shell ,@args
                                            ,io :stream
                                            :wait nil
                                            :element-type '(unsigned-byte 8))))
       (with-open-stream
           (,stream-var (make-flexi-stream
                         ,(ecase io
                            (:input `(process-info-input ,proc-sym))
                            (:output `(process-info-output ,proc-sym)))))
         ,@body))))

(defmacro write-shell ((stream-var shell &rest args) &rest body)
  "Executes BODY with STREAM-VAR passing the input to SHELL.
ARGS (including keyword arguments) are passed through to `uiop:launch-program'."
  `(io-shell (:input ,stream-var ,shell ,@args) ,@body))

(defmacro read-shell ((stream-var shell &rest args) &rest body)
  "Executes BODY with STREAM-VAR holding the output of SHELL.
ARGS (including keyword arguments) are passed through to `uiop:launch-program'."
  `(io-shell (:output ,stream-var ,shell ,@args) ,@body))

(defmacro write-shell-file ((stream-var file shell &rest args) &rest body)
  "Executes BODY with STREAM-VAR passing through SHELL to FILE.
ARGS (including keyword arguments) are passed through to `uiop:launch-program'."
  `(io-shell (:input ,stream-var ,shell ,@args :output ,file) ,@body))

(defmacro read-shell-file ((stream-var file shell &rest args) &rest body)
  "Executes BODY with STREAM-VAR passing through SHELL from FILE.
ARGS (including keyword arguments) are passed through to `uiop:launch-program'"
  `(io-shell (:output ,stream-var ,shell ,@args :input ,file) ,@body))

(defmacro xz-pipe ((in-stream in-file) (out-stream out-file) &rest body)
  "Execute BODY with IN-STREAM and OUT-STREAM read/writing data from xz files."
  `(read-shell-file (,in-stream ,in-file "unxz")
     (write-shell-file (,out-stream ,out-file "xz")
       ,@body)))

(defun escape-chars (chars str)
  "Returns a fresh string that is the same as str, except that
every character that occurs in CHARS is preceded by a backslash."
  (declare (type string str))
  (with-output-to-string (s)
    (map nil (lambda (c)
               (if (find c chars)
                   (format s "\\~a" c)
                   (format s "~a" c)))
         str)))

(defun split-quoted (str)
  "Split STR at spaces except when the spaces are escaped or within quotes.
Return a list of substrings with empty strings elided."
  (let ((subseqs nil)
        (in-single-quote-p nil)
        (in-double-quote-p nil)
        (prev 0)
        (pos 0)
        (len (length str)))
    (iter (while (< pos len))
          (let ((c (elt str pos)))
            (case c
              (#\Space
               (when (and (< prev pos)
                          (not in-single-quote-p)
                          (not in-double-quote-p))
                 (push (subseq str prev pos) subseqs)
                 (setf prev (1+ pos))))
              (#\\
               (incf pos)
               (when (>= pos len) (return)))
              (#\'
               (setf in-single-quote-p (not in-single-quote-p)))
              (#\"
               (setf in-double-quote-p (not in-double-quote-p))))
            (incf pos)))
    (assert (= len pos))
    (when (< prev pos)
      (push (subseq str prev pos) subseqs))
    (reverse subseqs)))

(defun escape-string (str)
  "Return a copy of STR with special characters escaped before output to SerAPI.
Control characters for whitespace (\\n, \\t, \\b, \\r in Lisp) should be
preceded by four backslashes, and double quotes should be preceded by 2.
Additionally, ~ must be escaped as ~~ so that the string can be formatted.
See also `unescape-string'."
  ;; Please be intimidated by the number of backslashes here, use *extreme*
  ;; caution if editing, and see the CL-PPCRE note on why backslashes in
  ;; regex-replace are confusing prior to thinking about editing this.
  (-<> str
       ;; replace all \\n with \\\\n unless already escaped (also other WS)
       ;; in regex \\\\ ==> \\ in Lisp string (which is \ in "real life")
       ;; (replace-all "\\" "\\\\")
       (regex-replace-all "(?<!\\\\)\\\\(n\|t\|b\|r)" <> "\\\\\\\\\\1")

       ;; replace all \" with \\" unless already escaped
       ;; in regex, \\\" ==> \" in Lisp string
       ;; (replace-all "\"" "\\\"")
       (regex-replace-all "(?<!\\\\)\\\"" <> "\\\\\"")

       ;; replace all ~ with ~~
       (regex-replace-all "~" <> "~~")))

(defun unescape-string (str)
  "Remove extra escape characters from STR prior to writing to screen or file.
Control characters for whitespace (\\n, \\t, \\b, \\r) and double quotes (\")
are preceded by an extra pair of backslashes. See also `escape-string'."
  (-<> str
       ;; change \\\\foo to \\foo
       (regex-replace-all "\\\\\\\\(n\|t\|b\|r)" <> "\\\\\\1")
       ;; change \\\" to \"
       (regex-replace-all "\\\\\\\"" <> "\"")))

#-windows
(defun which (file &key (path (getenv "PATH")))
  (iterate (for dir in (split-sequence #\: path))
           (let ((fullpath (merge-pathnames file
                                            (make-pathname :directory dir))))
             (when (probe-file fullpath)
               (return fullpath)))))
#+windows
(defun convert-backslash-to-slash (str)
  (let ((new (copy-sequence 'string str)))
    (dotimes (i (length new) new)
      (if (char= (aref new i) #\\)
          (setf (aref new i) #\/)))))

#+windows
(defun ensure-slash (dir)
  "Make sure the directory name ends with a slash (or backslash)"
  (if (member (char dir (- (length dir) 1)) (list #\/ #\\))
      dir
      (concatenate 'string dir "\\")))

#+windows
(defun which (file &key (path (convert-backslash-to-slash (getenv "PATH"))))
  (iterate (for dir in (remove "" (split-sequence #\; path) :test 'equal))
           (let ((fullpath (merge-pathnames file (ensure-slash dir))))
             (when (probe-file fullpath)
               (return fullpath)))))