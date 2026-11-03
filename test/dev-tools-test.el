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
