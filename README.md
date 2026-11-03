# dev-tools.el

`dev-tools.el` provides one searchable Emacs entry point for small developer
utilities. It uses Emacs built-ins where possible and keeps third-party package
or external CLI integrations outside the core package.

## Installation

Clone the repository and add it to `load-path`, or install it with an Elpaca
local recipe:

```elisp
(use-package dev-tools
  :ensure (:repo "~/Code/github.com/nailuoGG/dev-tools.el")
  :commands dev-tools)
```

Run `M-x dev-tools` and select an operation. Commands transform the active
region when one exists. Otherwise they read minibuffer input, display the
result in `*Dev Tools*`, and copy the result to the kill ring.

Add existing interactive commands without changing the package:

```elisp
(add-to-list 'dev-tools-extra-tools
             '("Documentation / DevDocs lookup" . devdocs-lookup))
```

## Included tools

- JSON formatting, minification, and semantic diff
- Base64, URL, and HTML entity encoding and decoding
- Text hashing, case conversion, and statistics
- Unix timestamp conversion
- UUID, random number, and random port generation

UUID generation calls the system `uuidgen` command. HTML entity decoding uses
Emacs's built-in `mm-url` entity table.

## JSON diff

Open both JSON documents as buffers, switch to the buffer that should appear on
the left, and run `M-x dev-tools-json-diff`. Select the other buffer when
prompted. The command recursively sorts object keys, preserves array order, and
opens the canonical JSON buffers in Ediff. Quitting Ediff removes only the two
temporary buffers created for that comparison.

Invalid JSON stops the command before Ediff starts and leaves both source
buffers unchanged.

## Design and development

[The design document](docs/design.md) is the implementation index and records
package boundaries, behavior contracts, source symbols, and the DevHub feature
coverage matrix.

Run tests from an existing Emacs server:

```sh
emacsclient --eval '(progn (add-to-list (quote load-path) "/path/to/dev-tools.el") (load "/path/to/dev-tools.el/test/dev-tools-test.el" nil t) (ert-stats-completed-unexpected (ert-run-tests "^dev-tools-test-" (lambda (&rest _event) nil))))'
```
