;;; dokumat-elisp.el --- `Elisp' backend for dokumat. -*- lexical-binding: t; -*-

(require 'help)
(require 'help-fns)
(require 'help-fns+ 'noerror)

(require 's)
(require 'dash)

(require 'dokumat)

;; TODO: capture directly using analysis, messing with help-buffers is a pain
(defmacro dokumat-elisp--capture-to-string (&rest body)
  "Capture output written to `standard-output' (help functions,
etc.), and return it as a string."
  `(with-temp-buffer
     (let ((inhibit-message t)
           (standard-output (current-buffer))
           (help-xref-following t))
       (setq major-mode 'help-mode)
       (progn ,@body)
       (buffer-string))))

(defun dokumat-elisp--fontify-as-doc (doc)
  "Fontify a string as if it was a doc-string in
`emacs-lisp-mode'."
  (with-temp-buffer
    ;; we do some juggling here, inserting a comment-placeholder,
    ;; fontifying the documentation, and removing the placeholder again to
    ;; get the proper fontification for documentation.
    (let* ((inhibit-message t)
           (placeholder ";dap;   ")
           (lines (s-lines doc))
           (commented-lines (-map (lambda (l) (s-prepend placeholder l)) lines))
           (result (s-join "\n" commented-lines)))
      (insert result)
      (delay-mode-hooks (emacs-lisp-mode))
      (font-lock-fontify-buffer)

      ;; now the buffer is fontified, remove comment-placeholder
      (with-temp-message ""
        (replace-regexp placeholder "" nil (point-min) (point-max)))

      (buffer-string))))

(defun dokumat-elisp--fontify-as-code (code)
  "Fontify a string as if it was elisp in `emacs-lisp-mode'."
  (let ((inhibit-message t))
    (with-temp-buffer
      (insert (if (symbolp code) (symbol-name code) code))
      (delay-mode-hooks (emacs-lisp-mode))
      (when (boundp 'highlight-defined-mode)
        (highlight-defined-mode +1))
      (font-lock-fontify-buffer)
      (buffer-string))))

(defun dokumat-elisp--locate-source-file (sym type)
  "Try to locate where a SYM with TYPE is defined."
  (let ((source (find-lisp-object-file-name sym type)))
    (cond
     ((eq source 'C-source) "C source code")
     (source (format "%s" source))
     (t nil))))

(defun dokumat-elisp--construct-description (symbol doc source)
  "Construct a description of SYMBOL with DOC and SOURCE."
  (format "%s\n\n%s%s"
          (dokumat-elisp--fontify-as-code symbol)
          (dokumat-elisp--fontify-as-doc (or doc "no documentation found"))
          (if source (format "\n\ndefined in %s" source) "")))

(defun dokumat--analyze-function (fn-sym)
  (pcase-let* ((`(,real-function ,def ,_aliased ,real-def)
                (help-fns--analyze-function fn-sym)))
    '(real-function def aliased real-def)
    )
  )

(defun dokumat-elisp--arglist (fn doc)
  "Return the arglist for FN, extracted from documentation and
function analysis."
  (pcase-let* ((`(,real-function ,def ,_aliased ,real-def)
                (help-fns--analyze-function fn)))
    (dokumat-elisp--capture-to-string
     (help-fns--signature fn doc real-def real-function nil)
     (with-temp-message ""
       ;; fix for symbols having special characters, like questions marks.
       (replace-regexp "\\\\=\\\\" "" nil (point-min) (point-max))
       ;; remove trailing newline
       (goto-char (point-max))
       (skip-chars-backward "\n")
       (kill-region (point) (point-max))))))

;; FIXME: does not work with aliased functions
(defun dokumat-elisp--describe-function (fn)
  "Return description of FN."
  (let* ((raw-doc (documentation fn 'RAW))
         (arglist (dokumat-elisp--arglist fn raw-doc))
         (source-file (dokumat-elisp--locate-source-file
                       fn (symbol-function fn))))
    (dokumat-elisp--construct-description
     arglist
     ;; don't include superfluous arglist, we've already have one.
     (when raw-doc (replace-regexp-in-string "\n\n(fn.*)" "" raw-doc))
     source-file)))

(defun dokumat-elisp--describe-variable (symbol)
  "Return documentation for elisp variable."
  (let ((doc (documentation-property symbol 'variable-documentation t))
        (source-file (dokumat-elisp--locate-source-file symbol 'defvar)))
    (dokumat-elisp--construct-description symbol doc source-file)))

(defun dokumat-elisp--describe-face (symbol)
  "Return documentation for elisp face."
  (let ((doc (documentation-property symbol 'face-documentation t))
        (source-file (dokumat-elisp--locate-source-file symbol 'defface)))
    (dokumat-elisp--construct-description symbol doc source-file)))

(defun dokumat-elisp--describe-group (symbol)
  "Return documentation for elisp group."
  (let ((doc (documentation-property symbol 'group-documentation t)))
    (dokumat-elisp--construct-description symbol doc nil)))

;;;###autoload
(defun dokumat-elisp (symbol)
  "Return documentation for elisp symbol."
  (if (stringp symbol)
      (setq symbol (intern-soft symbol)))
  (ignore-errors
    (cond
     ((fboundp symbol)
      (dokumat-elisp--describe-function symbol))
     ((and (boundp symbol) (not (facep symbol)))
      (dokumat-elisp--describe-variable symbol))
     ((facep symbol)
      (dokumat-elisp--describe-face symbol))
     (t
      (dokumat-elisp--describe-group symbol)))))

;; register the default elisp handler for dokumat
(dokumat-register
  :id "default emacs lisp backend"
  :modes '(emacs-lisp-mode lisp-interaction-mode)
  :symbol-fn #'symbol-at-point
  :doc-fn #'dokumat-elisp
  :should-run-p t
  :order 99)

(provide 'dokumat-elisp)

;; TODO: truncate documentation if it's too big, make sure that definition string is shown if available.