;;; dev-tools.el --- Unified entry point for developer utilities -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jiale Liu

;; Author: Jiale Liu
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, convenience
;; URL: https://github.com/nailuoGG/dev-tools.el

;;; Commentary:

;; `dev-tools' provides one searchable entry point for small developer
;; utilities.  The built-in tools operate on the active region when possible;
;; otherwise they read input from the minibuffer and show the result in a
;; dedicated buffer.

;;; Code:

(require 'json)
(require 'parse-time)
(require 'url-util)
(require 'xml)

(defgroup dev-tools nil
  "A unified entry point for developer utilities."
  :group 'tools)

(defcustom dev-tools-extra-tools nil
  "Additional tools displayed by `dev-tools'.

Each entry is (NAME . COMMAND).  NAME is the completion candidate and COMMAND
is an interactive command."
  :type '(repeat (cons (string :tag "Name") (function :tag "Command")))
  :group 'dev-tools)

(defvar dev-tools-history nil
  "Minibuffer history for `dev-tools'.")

(defconst dev-tools--hash-algorithms
  '(md5 sha1 sha224 sha256 sha384 sha512)
  "Hash algorithms supported by `secure-hash'.")

(defconst dev-tools--tools
  '(("Encoding / Base64 encode" . dev-tools-base64-encode)
    ("Encoding / Base64 decode" . dev-tools-base64-decode)
    ("Encoding / HTML entity encode" . dev-tools-html-encode)
    ("Encoding / HTML entity decode" . dev-tools-html-decode)
    ("Encoding / URL encode" . dev-tools-url-encode)
    ("Encoding / URL decode" . dev-tools-url-decode)
    ("Generate / Random number" . dev-tools-random-number)
    ("Generate / Random port" . dev-tools-random-port)
    ("Generate / UUID" . dev-tools-uuid)
    ("JSON / Diff" . dev-tools-json-diff)
    ("JSON / Format" . dev-tools-json-format)
    ("JSON / Minify" . dev-tools-json-minify)
    ("Text / Capitalize" . dev-tools-capitalize)
    ("Text / Downcase" . dev-tools-downcase)
    ("Text / Hash" . dev-tools-hash)
    ("Text / Statistics" . dev-tools-text-statistics)
    ("Text / Upcase" . dev-tools-upcase)
    ("Time / Date to Unix timestamp" . dev-tools-date-to-timestamp)
    ("Time / Unix timestamp to date" . dev-tools-timestamp-to-date))
  "Tools provided by dev-tools.el.")

(defun dev-tools--region-bounds ()
  "Return active region bounds, or nil when no region is active."
  (when (use-region-p)
    (cons (region-beginning) (region-end))))

(defun dev-tools--read-input (prompt bounds)
  "Read input using PROMPT, taking text from BOUNDS when non-nil."
  (if bounds
      (buffer-substring-no-properties (car bounds) (cdr bounds))
    (read-string prompt)))

(defun dev-tools--show-result (result)
  "Show RESULT and copy it to the kill ring."
  (let ((buffer (get-buffer-create "*Dev Tools*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert result)
        (goto-char (point-min))
        (special-mode)))
    (kill-new result)
    (display-buffer buffer)
    (message "Result copied to the kill ring")))

(defun dev-tools--transform (prompt function)
  "Apply FUNCTION to text read with PROMPT.

Replace the active region only after FUNCTION succeeds.  Without an active
region, show the result with `dev-tools--show-result'."
  (let* ((bounds (dev-tools--region-bounds))
         (input (dev-tools--read-input prompt bounds))
         (result (funcall function input)))
    (if bounds
        (progn
          (delete-region (car bounds) (cdr bounds))
          (goto-char (car bounds))
          (insert result))
      (dev-tools--show-result result))))

(defun dev-tools--inspect (prompt function)
  "Apply FUNCTION to text read with PROMPT and show its result."
  (let* ((bounds (dev-tools--region-bounds))
         (input (dev-tools--read-input prompt bounds)))
    (dev-tools--show-result (funcall function input))))

(defun dev-tools--json-parse (input)
  "Parse JSON INPUT while preserving JSON null and false values."
  (json-parse-string input
                     :null-object :null
                     :false-object :false))

(defun dev-tools--json-format (input)
  "Return formatted JSON INPUT."
  (dev-tools--json-parse input)
  (with-temp-buffer
    (insert input)
    (json-pretty-print-buffer)
    (buffer-string)))

(defun dev-tools--json-minify (input)
  "Return minified JSON INPUT."
  (json-serialize (dev-tools--json-parse input)
                  :null-object :null
                  :false-object :false))

(defun dev-tools--json-render (value &optional depth)
  "Render parsed JSON VALUE with sorted object keys at DEPTH."
  (let ((depth (or depth 0)))
    (cond
     ((hash-table-p value)
      (let (keys)
        (maphash (lambda (key _value) (push key keys)) value)
        (setq keys (sort keys #'string<))
        (if keys
            (concat
             "{\n"
             (mapconcat
              (lambda (key)
                (concat (make-string (* 2 (1+ depth)) ?\s)
                        (json-serialize key)
                        ": "
                        (dev-tools--json-render (gethash key value) (1+ depth))))
              keys
              ",\n")
             "\n" (make-string (* 2 depth) ?\s) "}")
          "{}")))
     ((vectorp value)
      (if (> (length value) 0)
          (concat
           "[\n"
           (mapconcat
            (lambda (item)
              (concat (make-string (* 2 (1+ depth)) ?\s)
                      (dev-tools--json-render item (1+ depth))))
            value
            ",\n")
           "\n" (make-string (* 2 depth) ?\s) "]")
        "[]"))
     (t
      (json-serialize value :null-object :null :false-object :false)))))

(defun dev-tools--json-canonicalize (input)
  "Return canonical JSON for INPUT with recursively sorted object keys."
  (concat (dev-tools--json-render (dev-tools--json-parse input)) "\n"))

(defun dev-tools--buffer-contents (buffer)
  "Return all text in BUFFER without properties."
  (with-current-buffer buffer
    (save-restriction
      (widen)
      (buffer-substring-no-properties (point-min) (point-max)))))

(defun dev-tools--json-diff-buffer (source text)
  "Create a temporary JSON diff buffer for SOURCE containing TEXT."
  (let ((buffer (generate-new-buffer
                 (format "*Dev Tools JSON Diff: %s*" (buffer-name source)))))
    (with-current-buffer buffer
      (insert text)
      (when (fboundp 'js-json-mode)
        (js-json-mode))
      (setq buffer-read-only t))
    buffer))

(defun dev-tools--html-decode (input)
  "Decode HTML entities in INPUT."
  (require 'mm-url)
  (mm-url-decode-entities-string input))

;;;###autoload
(defun dev-tools ()
  "Select and invoke a developer tool."
  (interactive)
  (let* ((tools (append dev-tools--tools dev-tools-extra-tools))
         (name (completing-read "Developer tool: " tools nil t nil
                                'dev-tools-history))
         (command (alist-get name tools nil nil #'string=)))
    (call-interactively command)))

;;;###autoload
(defun dev-tools-json-diff (buffer-a buffer-b)
  "Compare JSON in BUFFER-A and BUFFER-B after recursively sorting object keys."
  (interactive
   (let ((buffer-a (current-buffer)))
     (list buffer-a
           (read-buffer "Compare current JSON with buffer: "
                        (other-buffer buffer-a t)
                        t))))
  (setq buffer-a (get-buffer buffer-a)
        buffer-b (get-buffer buffer-b))
  (unless (and (buffer-live-p buffer-a) (buffer-live-p buffer-b))
    (user-error "Both JSON buffers must be live"))
  (when (eq buffer-a buffer-b)
    (user-error "Choose two different JSON buffers"))
  (let ((text-a (dev-tools--json-canonicalize
                 (dev-tools--buffer-contents buffer-a)))
        (text-b (dev-tools--json-canonicalize
                 (dev-tools--buffer-contents buffer-b)))
        diff-a diff-b)
    (condition-case error-data
        (progn
          (setq diff-a (dev-tools--json-diff-buffer buffer-a text-a)
                diff-b (dev-tools--json-diff-buffer buffer-b text-b))
          (require 'ediff)
          (let ((buffers (list diff-a diff-b)))
            (ediff-buffers
             diff-a diff-b
             (list
              (lambda ()
                (add-hook
                 'ediff-cleanup-hook
                 (lambda ()
                   (dolist (buffer buffers)
                     (when (buffer-live-p buffer)
                       (kill-buffer buffer))))
                 nil t))))))
      (error
       (dolist (buffer (list diff-a diff-b))
         (when (buffer-live-p buffer)
           (kill-buffer buffer)))
       (signal (car error-data) (cdr error-data))))))

;;;###autoload
(defun dev-tools-json-format ()
  "Format JSON in the active region or minibuffer input."
  (interactive)
  (dev-tools--transform "JSON: " #'dev-tools--json-format))

;;;###autoload
(defun dev-tools-json-minify ()
  "Minify JSON in the active region or minibuffer input."
  (interactive)
  (dev-tools--transform "JSON: " #'dev-tools--json-minify))

;;;###autoload
(defun dev-tools-base64-encode ()
  "Encode UTF-8 text as Base64."
  (interactive)
  (dev-tools--transform
   "Text: "
   (lambda (input)
     (base64-encode-string (encode-coding-string input 'utf-8) t))))

;;;###autoload
(defun dev-tools-base64-decode ()
  "Decode Base64 as UTF-8 text."
  (interactive)
  (dev-tools--transform
   "Base64: "
   (lambda (input)
     (decode-coding-string (base64-decode-string input) 'utf-8))))

;;;###autoload
(defun dev-tools-url-encode ()
  "Percent-encode text for use in a URL."
  (interactive)
  (dev-tools--transform "Text: " #'url-hexify-string))

;;;###autoload
(defun dev-tools-url-decode ()
  "Decode percent-encoded UTF-8 text."
  (interactive)
  (dev-tools--transform
   "Encoded text: "
   (lambda (input)
     (decode-coding-string (url-unhex-string input) 'utf-8))))

;;;###autoload
(defun dev-tools-html-encode ()
  "Encode XML-compatible HTML entities."
  (interactive)
  (dev-tools--transform "Text: " #'xml-escape-string))

;;;###autoload
(defun dev-tools-html-decode ()
  "Decode HTML entities."
  (interactive)
  (dev-tools--transform "Encoded text: " #'dev-tools--html-decode))

;;;###autoload
(defun dev-tools-hash (algorithm)
  "Hash text with ALGORITHM."
  (interactive
   (list (intern
          (completing-read "Algorithm: "
                           (mapcar #'symbol-name dev-tools--hash-algorithms)
                           nil t nil nil "sha256"))))
  (dev-tools--transform "Text: "
                        (lambda (input) (secure-hash algorithm input))))

;;;###autoload
(defun dev-tools-timestamp-to-date ()
  "Convert a Unix timestamp to a local date and time."
  (interactive)
  (dev-tools--transform
   "Unix timestamp: "
   (lambda (input)
     (unless (string-match-p "\\`[0-9]+\\(?:\\.[0-9]+\\)?\\'" input)
       (user-error "Invalid Unix timestamp: %s" input))
     (format-time-string "%Y-%m-%d %H:%M:%S %z"
                         (seconds-to-time (string-to-number input))))))

;;;###autoload
(defun dev-tools-date-to-timestamp ()
  "Convert a date and time to a Unix timestamp."
  (interactive)
  (dev-tools--transform
   "Date and time: "
   (lambda (input)
     (condition-case nil
         (format-time-string "%s" (encode-time (parse-time-string input)))
       (error (user-error "Invalid date and time: %s" input))))))

;;;###autoload
(defun dev-tools-uuid ()
  "Generate a UUID using the system uuidgen command."
  (interactive)
  (let ((uuidgen (executable-find "uuidgen")))
    (unless uuidgen
      (user-error "uuidgen is not installed"))
    (dev-tools--show-result (downcase (car (process-lines uuidgen))))))

;;;###autoload
(defun dev-tools-upcase ()
  "Convert text to uppercase."
  (interactive)
  (dev-tools--transform "Text: " #'upcase))

;;;###autoload
(defun dev-tools-downcase ()
  "Convert text to lowercase."
  (interactive)
  (dev-tools--transform "Text: " #'downcase))

;;;###autoload
(defun dev-tools-capitalize ()
  "Capitalize text."
  (interactive)
  (dev-tools--transform "Text: " #'capitalize))

;;;###autoload
(defun dev-tools-text-statistics ()
  "Count characters, words, and lines in text."
  (interactive)
  (dev-tools--inspect
   "Text: "
   (lambda (input)
     (with-temp-buffer
       (insert input)
       (format "Characters: %d\nWords: %d\nLines: %d"
               (length input)
               (count-words (point-min) (point-max))
               (line-number-at-pos (point-max)))))))

;;;###autoload
(defun dev-tools-random-number (limit)
  "Generate a random integer from zero up to, but excluding, LIMIT."
  (interactive "nUpper bound (exclusive): ")
  (unless (> limit 0)
    (user-error "Upper bound must be positive"))
  (dev-tools--show-result (number-to-string (random limit))))

;;;###autoload
(defun dev-tools-random-port ()
  "Generate a random dynamic/private TCP port number."
  (interactive)
  (dev-tools--show-result (number-to-string (+ 49152 (random 16384)))))

(provide 'dev-tools)
;;; dev-tools.el ends here
