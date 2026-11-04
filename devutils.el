;;; devutils.el --- Unified entry point for developer utilities -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jiale Liu
;; SPDX-License-Identifier: GPL-3.0-only

;; Author: Jiale Liu
;; Version: 0.2.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, convenience
;; URL: https://github.com/nailuoGG/devutils.el

;;; Commentary:

;; `devutils' provides one searchable entry point for small developer
;; utilities.  The built-in tools operate on the active region when possible;
;; otherwise they read input from the minibuffer and show the result in a
;; dedicated buffer.

;;; Code:

(require 'json)
(require 'parse-time)
(require 'subr-x)
(require 'url-util)
(require 'xml)

(defgroup devutils nil
  "A unified entry point for developer utilities."
  :group 'tools)

(defcustom devutils-extra-tools nil
  "Additional tools displayed by `devutils'.

Each entry is (NAME . COMMAND).  NAME is the completion candidate and COMMAND
is an interactive command."
  :type '(repeat (cons (string :tag "Name") (function :tag "Command")))
  :group 'devutils)

(defvar devutils-history nil
  "Minibuffer history for `devutils'.")

(defconst devutils--hash-algorithms
  '(md5 sha1 sha224 sha256 sha384 sha512)
  "Hash algorithms supported by `secure-hash'.")

(defconst devutils--tools
  '(("Encoding / Base64 encode" . devutils-base64-encode)
    ("Encoding / Base64 decode" . devutils-base64-decode)
    ("Encoding / HTML entity encode" . devutils-html-encode)
    ("Encoding / HTML entity decode" . devutils-html-decode)
    ("Encoding / URL encode" . devutils-url-encode)
    ("Encoding / URL decode" . devutils-url-decode)
    ("Generate / Random number" . devutils-random-number)
    ("Generate / Random port" . devutils-random-port)
    ("Generate / UUID" . devutils-uuid)
    ("JSON / Diff" . devutils-json-diff)
    ("JSON / Format" . devutils-json-format)
    ("JSON / Minify" . devutils-json-minify)
    ("QR / Decode clipboard image" . devutils-qr-decode-clipboard)
    ("QR / Decode image file" . devutils-qr-decode-file)
    ("QR / Generate" . devutils-qr-generate)
    ("Text / Capitalize" . devutils-capitalize)
    ("Text / Downcase" . devutils-downcase)
    ("Text / Hash" . devutils-hash)
    ("Text / Statistics" . devutils-text-statistics)
    ("Text / Upcase" . devutils-upcase)
    ("Time / Date to Unix timestamp" . devutils-date-to-timestamp)
    ("Time / Unix timestamp to date" . devutils-timestamp-to-date))
  "Tools provided by devutils.el.")

(defun devutils--region-bounds ()
  "Return active region bounds, or nil when no region is active."
  (when (use-region-p)
    (cons (region-beginning) (region-end))))

(defun devutils--read-input (prompt bounds)
  "Read input using PROMPT, taking text from BOUNDS when non-nil."
  (if bounds
      (buffer-substring-no-properties (car bounds) (cdr bounds))
    (read-string prompt)))

(defun devutils--show-result (result)
  "Show RESULT and copy it to the kill ring."
  (let ((buffer (get-buffer-create "*Devutils*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert result)
        (goto-char (point-min))
        (special-mode)))
    (kill-new result)
    (display-buffer buffer)
    (message "Result copied to the kill ring")))

(defun devutils--transform (prompt function)
  "Apply FUNCTION to text read with PROMPT.

Replace the active region only after FUNCTION succeeds.  Without an active
region, show the result with `devutils--show-result'."
  (let* ((bounds (devutils--region-bounds))
         (input (devutils--read-input prompt bounds))
         (result (funcall function input)))
    (if bounds
        (progn
          (delete-region (car bounds) (cdr bounds))
          (goto-char (car bounds))
          (insert result))
      (devutils--show-result result))))

(defun devutils--inspect (prompt function)
  "Apply FUNCTION to text read with PROMPT and show its result."
  (let* ((bounds (devutils--region-bounds))
         (input (devutils--read-input prompt bounds)))
    (devutils--show-result (funcall function input))))

(defun devutils--json-parse (input)
  "Parse JSON INPUT while preserving JSON null and false values."
  (json-parse-string input
                     :null-object :null
                     :false-object :false))

(defun devutils--json-format (input)
  "Return formatted JSON INPUT."
  (devutils--json-parse input)
  (with-temp-buffer
    (insert input)
    (json-pretty-print-buffer)
    (buffer-string)))

(defun devutils--json-minify (input)
  "Return minified JSON INPUT."
  (json-serialize (devutils--json-parse input)
                  :null-object :null
                  :false-object :false))

(defun devutils--json-render (value &optional depth)
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
                        (devutils--json-render (gethash key value) (1+ depth))))
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
                      (devutils--json-render item (1+ depth))))
            value
            ",\n")
           "\n" (make-string (* 2 depth) ?\s) "]")
        "[]"))
     (t
      (json-serialize value :null-object :null :false-object :false)))))

(defun devutils--json-canonicalize (input)
  "Return canonical JSON for INPUT with recursively sorted object keys."
  (concat (devutils--json-render (devutils--json-parse input)) "\n"))

(defun devutils--buffer-contents (buffer)
  "Return all text in BUFFER without properties."
  (with-current-buffer buffer
    (save-restriction
      (widen)
      (buffer-substring-no-properties (point-min) (point-max)))))

(defun devutils--json-diff-buffer (source text)
  "Create a temporary JSON diff buffer for SOURCE containing TEXT."
  (let ((buffer (generate-new-buffer
                 (format "*Devutils JSON Diff: %s*" (buffer-name source)))))
    (with-current-buffer buffer
      (insert text)
      (when (fboundp 'js-json-mode)
        (js-json-mode))
      (setq buffer-read-only t))
    buffer))

(defun devutils--install-command (mac-package arch-package)
  "Return an installation command for MAC-PACKAGE or ARCH-PACKAGE."
  (pcase system-type
    ('darwin (format "brew install %s" mac-package))
    ('gnu/linux (format "sudo pacman -S %s" arch-package))
    (_ "install it with your system package manager")))

(defun devutils--require-executable (program mac-package arch-package)
  "Return PROGRAM's executable or report its platform package."
  (or (executable-find program)
      (user-error "%s is required; install it with: %s"
                  program
                  (devutils--install-command mac-package arch-package))))

(defun devutils--process-output (program arguments binary error-message)
  "Run PROGRAM with ARGUMENTS and return its output.

When BINARY is non-nil, preserve output bytes.  Report ERROR-MESSAGE when the
process exits unsuccessfully."
  (with-temp-buffer
    (set-buffer-multibyte (not binary))
    (let ((coding-system-for-read (if binary 'binary 'utf-8-unix)))
      (let ((status (apply #'process-file program nil t nil arguments)))
        (unless (and (integerp status) (zerop status))
          (user-error "%s" error-message))
        (buffer-string)))))

(defun devutils--qr-generate-data (text)
  "Generate PNG QR code data for TEXT."
  (when (string-empty-p text)
    (user-error "QR code text must not be empty"))
  (let ((payload (if (string-match-p "[^[:ascii:]]" text)
                     (concat "\ufeff" text)
                   text)))
    (devutils--process-output
     (devutils--require-executable "qrencode" "qrencode" "qrencode")
     (list "-t" "PNG" "-s" "8" "-o" "-" "-8" "--" payload)
     t
     "qrencode could not generate a QR code")))

(defun devutils--show-qr-code (data)
  "Display PNG QR code DATA in a dedicated buffer."
  (unless (image-type-available-p 'png)
    (user-error "This Emacs build cannot display PNG images"))
  (let ((image (create-image data 'png t))
        (buffer (get-buffer-create "*Devutils QR Code*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert-image image "[QR Code]")
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buffer)
    buffer))

(defun devutils--qr-decode-file (file)
  "Return text decoded from QR codes in image FILE."
  (unless (and (file-regular-p file) (file-readable-p file))
    (user-error "QR code image is not a readable file: %s" file))
  (let ((result
         (string-trim-right
          (devutils--process-output
           (devutils--require-executable "zbarimg" "zbar" "zbar")
           (list "--quiet" "--raw" "--" (expand-file-name file))
           nil
           "No QR code could be decoded from the image"))))
    (when (string-empty-p result)
      (user-error "No QR code could be decoded from the image"))
    result))

(defun devutils--clipboard-image-data ()
  "Return PNG image data from the system clipboard."
  (pcase system-type
    ('darwin
     (devutils--process-output
      (devutils--require-executable "pngpaste" "pngpaste" "pngpaste")
      '("-") t "The clipboard does not contain a PNG image"))
    ('gnu/linux
     (cond
      ((executable-find "wl-paste")
       (devutils--process-output
        (executable-find "wl-paste")
        '("--no-newline" "--type" "image/png")
        t "The clipboard does not contain a PNG image"))
      ((executable-find "xclip")
       (devutils--process-output
        (executable-find "xclip")
        '("-selection" "clipboard" "-t" "image/png" "-o")
        t "The clipboard does not contain a PNG image"))
      (t
       (user-error
        (concat "Clipboard image access requires wl-paste or xclip; "
                "install with: sudo pacman -S wl-clipboard (Wayland) "
                "or sudo pacman -S xclip (X11)")))))
    (_ (user-error "Clipboard image decoding is unsupported on %s" system-type))))

(defun devutils--qr-decode-clipboard ()
  "Return text decoded from QR codes in the clipboard image."
  (let ((file (make-temp-file "devutils-qr-" nil ".png")))
    (unwind-protect
        (let ((coding-system-for-write 'binary))
          (write-region (devutils--clipboard-image-data) nil file nil 'silent)
          (devutils--qr-decode-file file))
      (when (file-exists-p file)
        (delete-file file)))))

(defun devutils--html-decode (input)
  "Decode HTML entities in INPUT."
  (require 'mm-url)
  (mm-url-decode-entities-string input))

;;;###autoload
(defun devutils ()
  "Select and invoke a developer tool."
  (interactive)
  (let* ((tools (append devutils--tools devutils-extra-tools))
         (name (completing-read "Developer tool: " tools nil t nil
                                'devutils-history))
         (command (alist-get name tools nil nil #'string=)))
    (call-interactively command)))

;;;###autoload
(defun devutils-json-diff (buffer-a buffer-b)
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
  (let ((text-a (devutils--json-canonicalize
                 (devutils--buffer-contents buffer-a)))
        (text-b (devutils--json-canonicalize
                 (devutils--buffer-contents buffer-b)))
        diff-a diff-b)
    (condition-case error-data
        (progn
          (setq diff-a (devutils--json-diff-buffer buffer-a text-a)
                diff-b (devutils--json-diff-buffer buffer-b text-b))
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
(defun devutils-qr-generate ()
  "Generate and display a QR code from the active region or minibuffer text."
  (interactive)
  (let* ((bounds (devutils--region-bounds))
         (text (devutils--read-input "QR code text: " bounds)))
    (devutils--show-qr-code (devutils--qr-generate-data text))))

;;;###autoload
(defun devutils-qr-decode-file (file)
  "Decode QR code text from image FILE."
  (interactive (list (read-file-name "QR code image: " nil nil t)))
  (devutils--show-result (devutils--qr-decode-file file)))

;;;###autoload
(defun devutils-qr-decode-clipboard ()
  "Decode QR code text from an image in the system clipboard."
  (interactive)
  (devutils--show-result (devutils--qr-decode-clipboard)))

;;;###autoload
(defun devutils-json-format ()
  "Format JSON in the active region or minibuffer input."
  (interactive)
  (devutils--transform "JSON: " #'devutils--json-format))

;;;###autoload
(defun devutils-json-minify ()
  "Minify JSON in the active region or minibuffer input."
  (interactive)
  (devutils--transform "JSON: " #'devutils--json-minify))

;;;###autoload
(defun devutils-base64-encode ()
  "Encode UTF-8 text as Base64."
  (interactive)
  (devutils--transform
   "Text: "
   (lambda (input)
     (base64-encode-string (encode-coding-string input 'utf-8) t))))

;;;###autoload
(defun devutils-base64-decode ()
  "Decode Base64 as UTF-8 text."
  (interactive)
  (devutils--transform
   "Base64: "
   (lambda (input)
     (decode-coding-string (base64-decode-string input) 'utf-8))))

;;;###autoload
(defun devutils-url-encode ()
  "Percent-encode text for use in a URL."
  (interactive)
  (devutils--transform "Text: " #'url-hexify-string))

;;;###autoload
(defun devutils-url-decode ()
  "Decode percent-encoded UTF-8 text."
  (interactive)
  (devutils--transform
   "Encoded text: "
   (lambda (input)
     (decode-coding-string (url-unhex-string input) 'utf-8))))

;;;###autoload
(defun devutils-html-encode ()
  "Encode XML-compatible HTML entities."
  (interactive)
  (devutils--transform "Text: " #'xml-escape-string))

;;;###autoload
(defun devutils-html-decode ()
  "Decode HTML entities."
  (interactive)
  (devutils--transform "Encoded text: " #'devutils--html-decode))

;;;###autoload
(defun devutils-hash (algorithm)
  "Hash text with ALGORITHM."
  (interactive
   (list (intern
          (completing-read "Algorithm: "
                           (mapcar #'symbol-name devutils--hash-algorithms)
                           nil t nil nil "sha256"))))
  (devutils--transform "Text: "
                        (lambda (input) (secure-hash algorithm input))))

;;;###autoload
(defun devutils-timestamp-to-date ()
  "Convert a Unix timestamp to a local date and time."
  (interactive)
  (devutils--transform
   "Unix timestamp: "
   (lambda (input)
     (unless (string-match-p "\\`[0-9]+\\(?:\\.[0-9]+\\)?\\'" input)
       (user-error "Invalid Unix timestamp: %s" input))
     (format-time-string "%Y-%m-%d %H:%M:%S %z"
                         (seconds-to-time (string-to-number input))))))

;;;###autoload
(defun devutils-date-to-timestamp ()
  "Convert a date and time to a Unix timestamp."
  (interactive)
  (devutils--transform
   "Date and time: "
   (lambda (input)
     (condition-case nil
         (format-time-string "%s" (encode-time (parse-time-string input)))
       (error (user-error "Invalid date and time: %s" input))))))

;;;###autoload
(defun devutils-uuid ()
  "Generate a UUID using the system uuidgen command."
  (interactive)
  (let ((uuidgen (executable-find "uuidgen")))
    (unless uuidgen
      (user-error "uuidgen is not installed"))
    (devutils--show-result (downcase (car (process-lines uuidgen))))))

;;;###autoload
(defun devutils-upcase ()
  "Convert text to uppercase."
  (interactive)
  (devutils--transform "Text: " #'upcase))

;;;###autoload
(defun devutils-downcase ()
  "Convert text to lowercase."
  (interactive)
  (devutils--transform "Text: " #'downcase))

;;;###autoload
(defun devutils-capitalize ()
  "Capitalize text."
  (interactive)
  (devutils--transform "Text: " #'capitalize))

;;;###autoload
(defun devutils-text-statistics ()
  "Count characters, words, and lines in text."
  (interactive)
  (devutils--inspect
   "Text: "
   (lambda (input)
     (with-temp-buffer
       (insert input)
       (format "Characters: %d\nWords: %d\nLines: %d"
               (length input)
               (count-words (point-min) (point-max))
               (line-number-at-pos (point-max)))))))

;;;###autoload
(defun devutils-random-number (limit)
  "Generate a random integer from zero up to, but excluding, LIMIT."
  (interactive "nUpper bound (exclusive): ")
  (unless (> limit 0)
    (user-error "Upper bound must be positive"))
  (devutils--show-result (number-to-string (random limit))))

;;;###autoload
(defun devutils-random-port ()
  "Generate a random dynamic/private TCP port number."
  (interactive)
  (devutils--show-result (number-to-string (+ 49152 (random 16384)))))

(provide 'devutils)
;;; devutils.el ends here
