;;; dev-tools-test.el --- Tests for dev-tools.el -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'dev-tools)

(defun dev-tools-test--run-with-input (command input)
  "Run COMMAND with INPUT and return the displayed result."
  (let (result)
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) input))
              ((symbol-function 'dev-tools--show-result)
               (lambda (value) (setq result value))))
      (funcall command))
    result))

(ert-deftest dev-tools-test-json-round-trip ()
  (let* ((input "{\"name\":\"DevHub\",\"enabled\":false,\"value\":null}")
         (formatted (dev-tools--json-format input)))
    (should (string-match-p "\n" formatted))
    (should (equal (dev-tools--json-minify formatted) input))))

(ert-deftest dev-tools-test-json-canonicalize-sorts-recursively ()
  (should
   (equal
    (dev-tools--json-canonicalize
     "{\"z\":1,\"a\":{\"d\":2,\"b\":3},\"arr\":[{\"y\":2,\"x\":1},0]}")
    "{\n  \"a\": {\n    \"b\": 3,\n    \"d\": 2\n  },\n  \"arr\": [\n    {\n      \"x\": 1,\n      \"y\": 2\n    },\n    0\n  ],\n  \"z\": 1\n}\n")))

(ert-deftest dev-tools-test-json-canonicalize-ignores-key-order ()
  (should
   (equal (dev-tools--json-canonicalize "{\"b\":2,\"a\":1}")
          (dev-tools--json-canonicalize "{\"a\":1,\"b\":2}")))
  (should-not
   (equal (dev-tools--json-canonicalize "[1,2]")
          (dev-tools--json-canonicalize "[2,1]"))))

(ert-deftest dev-tools-test-json-diff-validates-before-creating-buffers ()
  (let ((buffer-a (generate-new-buffer " *dev-tools-invalid-a*"))
        (buffer-b (generate-new-buffer " *dev-tools-invalid-b*"))
        created)
    (unwind-protect
        (progn
          (with-current-buffer buffer-a (insert "{invalid}"))
          (with-current-buffer buffer-b (insert "{}"))
          (cl-letf (((symbol-function 'dev-tools--json-diff-buffer)
                     (lambda (&rest _) (setq created t))))
            (should-error (dev-tools-json-diff buffer-a buffer-b))
            (should-not created)))
      (kill-buffer buffer-a)
      (kill-buffer buffer-b))))

(ert-deftest dev-tools-test-json-diff-ediff-and-cleanup ()
  (let ((buffer-a (generate-new-buffer " *dev-tools-a*"))
        (buffer-b (generate-new-buffer " *dev-tools-b*"))
        diff-a diff-b startup-hooks)
    (unwind-protect
        (progn
          (with-current-buffer buffer-a (insert "{\"b\":2,\"a\":1}"))
          (with-current-buffer buffer-b (insert "{\"a\":3,\"b\":2}"))
          (cl-letf (((symbol-function 'ediff-buffers)
                     (lambda (a b &optional hooks _job)
                       (setq diff-a a diff-b b startup-hooks hooks))))
            (dev-tools-json-diff buffer-a buffer-b))
          (should (equal (dev-tools--buffer-contents diff-a)
                         "{\n  \"a\": 1,\n  \"b\": 2\n}\n"))
          (should (equal (dev-tools--buffer-contents diff-b)
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

(ert-deftest dev-tools-test-invalid-json-does-not-replace-region ()
  (with-temp-buffer
    (let ((transient-mark-mode t))
      (insert "{invalid}")
      (goto-char (point-min))
      (push-mark (point-max) t t)
      (should-error (dev-tools-json-format))
      (should (equal (buffer-string) "{invalid}")))))

(ert-deftest dev-tools-test-base64-round-trip ()
  (let* ((input "Hello, 世界")
         (encoded (dev-tools-test--run-with-input
                   #'dev-tools-base64-encode input))
         (decoded (dev-tools-test--run-with-input
                   #'dev-tools-base64-decode encoded)))
    (should (equal decoded input))))

(ert-deftest dev-tools-test-url-round-trip ()
  (let* ((input "https://example.com/路径?q=hello world")
         (encoded (dev-tools-test--run-with-input
                   #'dev-tools-url-encode input))
         (decoded (dev-tools-test--run-with-input
                   #'dev-tools-url-decode encoded)))
    (should (equal decoded input))))

(ert-deftest dev-tools-test-html-entity-round-trip ()
  (let* ((input "<tag title=\"A&B\">文本</tag>")
         (encoded (dev-tools-test--run-with-input
                   #'dev-tools-html-encode input))
         (decoded (dev-tools-test--run-with-input
                   #'dev-tools-html-decode encoded)))
    (should (equal decoded input))))

(ert-deftest dev-tools-test-tools-reference-interactive-commands ()
  (dolist (tool dev-tools--tools)
    (should (commandp (cdr tool)))))

(provide 'dev-tools-test)
;;; dev-tools-test.el ends here
