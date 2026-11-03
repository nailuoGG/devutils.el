;;; devutils-test.el --- Tests for devutils.el -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'devutils)

(defun devutils-test--run-with-input (command input)
  "Run COMMAND with INPUT and return the displayed result."
  (let (result)
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) input))
              ((symbol-function 'devutils--show-result)
               (lambda (value) (setq result value))))
      (funcall command))
    result))

(ert-deftest devutils-test-json-round-trip ()
  (let* ((input "{\"name\":\"DevHub\",\"enabled\":false,\"value\":null}")
         (formatted (devutils--json-format input)))
    (should (string-match-p "\n" formatted))
    (should (equal (devutils--json-minify formatted) input))))

(ert-deftest devutils-test-json-canonicalize-sorts-recursively ()
  (should
   (equal
    (devutils--json-canonicalize
     "{\"z\":1,\"a\":{\"d\":2,\"b\":3},\"arr\":[{\"y\":2,\"x\":1},0]}")
    "{\n  \"a\": {\n    \"b\": 3,\n    \"d\": 2\n  },\n  \"arr\": [\n    {\n      \"x\": 1,\n      \"y\": 2\n    },\n    0\n  ],\n  \"z\": 1\n}\n")))

(ert-deftest devutils-test-json-canonicalize-ignores-key-order ()
  (should
   (equal (devutils--json-canonicalize "{\"b\":2,\"a\":1}")
          (devutils--json-canonicalize "{\"a\":1,\"b\":2}")))
  (should-not
   (equal (devutils--json-canonicalize "[1,2]")
          (devutils--json-canonicalize "[2,1]"))))

(ert-deftest devutils-test-json-diff-validates-before-creating-buffers ()
  (let ((buffer-a (generate-new-buffer " *devutils-invalid-a*"))
        (buffer-b (generate-new-buffer " *devutils-invalid-b*"))
        created)
    (unwind-protect
        (progn
          (with-current-buffer buffer-a (insert "{invalid}"))
          (with-current-buffer buffer-b (insert "{}"))
          (cl-letf (((symbol-function 'devutils--json-diff-buffer)
                     (lambda (&rest _) (setq created t))))
            (should-error (devutils-json-diff buffer-a buffer-b))
            (should-not created)))
      (kill-buffer buffer-a)
      (kill-buffer buffer-b))))

(ert-deftest devutils-test-json-diff-ediff-and-cleanup ()
  (let ((buffer-a (generate-new-buffer " *devutils-a*"))
        (buffer-b (generate-new-buffer " *devutils-b*"))
        diff-a diff-b startup-hooks)
    (unwind-protect
        (progn
          (with-current-buffer buffer-a (insert "{\"b\":2,\"a\":1}"))
          (with-current-buffer buffer-b (insert "{\"a\":3,\"b\":2}"))
          (cl-letf (((symbol-function 'ediff-buffers)
                     (lambda (a b &optional hooks _job)
                       (setq diff-a a diff-b b startup-hooks hooks))))
            (devutils-json-diff buffer-a buffer-b))
          (should (equal (devutils--buffer-contents diff-a)
                         "{\n  \"a\": 1,\n  \"b\": 2\n}\n"))
          (should (equal (devutils--buffer-contents diff-b)
                         "{\n  \"a\": 3,\n  \"b\": 2\n}\n"))
          (should (buffer-local-value 'buffer-read-only diff-a))
          (with-temp-buffer
            (dolist (hook startup-hooks)
              (funcall hook))
            (run-hooks 'ediff-cleanup-hook))
          (should-not (buffer-live-p diff-a))
          (should-not (buffer-live-p diff-b)))
      (dolist (buffer (list buffer-a buffer-b diff-a diff-b))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest devutils-test-invalid-json-does-not-replace-region ()
  (with-temp-buffer
    (let ((transient-mark-mode t))
      (insert "{invalid}")
      (goto-char (point-min))
      (push-mark (point-max) t t)
      (should-error (devutils-json-format))
      (should (equal (buffer-string) "{invalid}")))))

(ert-deftest devutils-test-base64-round-trip ()
  (let* ((input "Hello, 世界")
         (encoded (devutils-test--run-with-input
                   #'devutils-base64-encode input))
         (decoded (devutils-test--run-with-input
                   #'devutils-base64-decode encoded)))
    (should (equal decoded input))))

(ert-deftest devutils-test-url-round-trip ()
  (let* ((input "https://example.com/路径?q=hello world")
         (encoded (devutils-test--run-with-input
                   #'devutils-url-encode input))
         (decoded (devutils-test--run-with-input
                   #'devutils-url-decode encoded)))
    (should (equal decoded input))))

(ert-deftest devutils-test-html-entity-round-trip ()
  (let* ((input "<tag title=\"A&B\">文本</tag>")
         (encoded (devutils-test--run-with-input
                   #'devutils-html-encode input))
         (decoded (devutils-test--run-with-input
                   #'devutils-html-decode encoded)))
    (should (equal decoded input))))

(ert-deftest devutils-test-qr-generate-uses-8-bit-mode-and-utf-8-marker ()
  (let (calls)
    (cl-letf (((symbol-function 'devutils--require-executable)
               (lambda (&rest _) "/usr/bin/qrencode"))
              ((symbol-function 'devutils--process-output)
               (lambda (program arguments binary error-message)
                 (push (list program arguments binary error-message) calls)
                 "PNG")))
      (should (equal (devutils--qr-generate-data "ASCII") "PNG"))
      (should (equal (devutils--qr-generate-data "测试") "PNG")))
    (should
     (equal
      (mapcar #'cadr (nreverse calls))
      (list '("-t" "PNG" "-s" "8" "-o" "-" "-8" "--" "ASCII")
            (list "-t" "PNG" "-s" "8" "-o" "-" "-8" "--"
                  (concat "\ufeff" "测试")))))))

(ert-deftest devutils-test-qr-generate-rejects-empty-text ()
  (should-error (devutils--qr-generate-data "") :type 'user-error))

(ert-deftest devutils-test-qr-decode-file-uses-zbarimg ()
  (let ((file (make-temp-file "devutils-test-qr-" nil ".png"))
        arguments)
    (unwind-protect
        (cl-letf (((symbol-function 'devutils--require-executable)
                   (lambda (&rest _) "/usr/bin/zbarimg"))
                  ((symbol-function 'devutils--process-output)
                   (lambda (_program args binary _error-message)
                     (setq arguments args)
                     (should-not binary)
                     "decoded text\n")))
          (should (equal (devutils--qr-decode-file file) "decoded text"))
          (should
           (equal arguments
                  (list "--quiet" "--raw" "--" (expand-file-name file)))))
      (delete-file file))))

(ert-deftest devutils-test-qr-decode-file-rejects-invalid-input ()
  (should-error (devutils--qr-decode-file "/missing/devutils-qr.png")
                :type 'user-error)
  (let ((file (make-temp-file "devutils-test-qr-" nil ".png")))
    (unwind-protect
        (cl-letf (((symbol-function 'devutils--require-executable)
                   (lambda (&rest _) "/usr/bin/zbarimg"))
                  ((symbol-function 'devutils--process-output)
                   (lambda (&rest _) "")))
          (should-error (devutils--qr-decode-file file) :type 'user-error))
      (delete-file file))))

(ert-deftest devutils-test-clipboard-image-selects-platform-backend ()
  (let (calls)
    (cl-letf (((symbol-function 'devutils--require-executable)
               (lambda (program &rest _) (concat "/usr/bin/" program)))
              ((symbol-function 'devutils--process-output)
               (lambda (program arguments binary _error-message)
                 (push (list program arguments binary) calls)
                 "PNG"))
              ((symbol-function 'executable-find)
               (lambda (program)
                 (pcase program
                   ("wl-paste" "/usr/bin/wl-paste")
                   ("xclip" "/usr/bin/xclip")))))
      (let ((system-type 'darwin))
        (devutils--clipboard-image-data))
      (let ((system-type 'gnu/linux))
        (devutils--clipboard-image-data)))
    (should
     (equal
      (nreverse calls)
      '(("/usr/bin/pngpaste" ("-") t)
        ("/usr/bin/wl-paste" ("--no-newline" "--type" "image/png") t))))))

(ert-deftest devutils-test-clipboard-image-falls-back-to-xclip ()
  (let ((system-type 'gnu/linux)
        call)
    (cl-letf (((symbol-function 'executable-find)
               (lambda (program)
                 (and (equal program "xclip") "/usr/bin/xclip")))
              ((symbol-function 'devutils--process-output)
               (lambda (program arguments binary _error-message)
                 (setq call (list program arguments binary))
                 "PNG")))
      (devutils--clipboard-image-data))
    (should
     (equal call
            '("/usr/bin/xclip"
              ("-selection" "clipboard" "-t" "image/png" "-o") t)))))

(ert-deftest devutils-test-qr-clipboard-removes-temporary-file ()
  (let (file)
    (cl-letf (((symbol-function 'devutils--clipboard-image-data)
               (lambda () "PNG"))
              ((symbol-function 'devutils--qr-decode-file)
               (lambda (path)
                 (setq file path)
                 "decoded")))
      (should (equal (devutils--qr-decode-clipboard) "decoded")))
    (should file)
    (should-not (file-exists-p file))))

(ert-deftest devutils-test-qr-clipboard-cleans-up-after-error ()
  (let (file)
    (cl-letf (((symbol-function 'devutils--clipboard-image-data)
               (lambda () "PNG"))
              ((symbol-function 'devutils--qr-decode-file)
               (lambda (path)
                 (setq file path)
                 (user-error "decode failed"))))
      (should-error (devutils--qr-decode-clipboard) :type 'user-error))
    (should file)
    (should-not (file-exists-p file))))

(ert-deftest devutils-test-qr-decoded-url-remains-text ()
  (let (shown)
    (cl-letf (((symbol-function 'devutils--qr-decode-file)
               (lambda (_) "https://example.com"))
              ((symbol-function 'devutils--show-result)
               (lambda (text) (setq shown text)))
              ((symbol-function 'browse-url)
               (lambda (&rest _) (ert-fail "Decoded URL was opened"))))
      (devutils-qr-decode-file "/unused"))
    (should (equal shown "https://example.com"))))

(ert-deftest devutils-test-missing-qr-executable-reports-install-command ()
  (let ((system-type 'darwin))
    (cl-letf (((symbol-function 'executable-find) (lambda (_) nil)))
      (let ((error-data
             (should-error
              (devutils--require-executable "zbarimg" "zbar" "zbar")
              :type 'user-error)))
        (should (string-match-p "brew install zbar"
                                (error-message-string error-data)))))))

(ert-deftest devutils-test-tools-reference-interactive-commands ()
  (dolist (tool devutils--tools)
    (should (commandp (cdr tool)))))

(provide 'devutils-test)
;;; devutils-test.el ends here
