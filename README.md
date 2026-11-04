# devutils.el

`devutils.el` provides one searchable Emacs entry point for small developer
utilities. It uses Emacs built-ins where possible and keeps third-party package
or external CLI integrations outside the core package.

## Installation

Clone the repository and add it to `load-path`, or install it with an Elpaca
local recipe:

```elisp
(use-package devutils
  :ensure (:repo "~/Code/github.com/nailuoGG/devutils.el")
  :commands devutils)
```

Run `M-x devutils` and select an operation. Commands transform the active
region when one exists. Otherwise they read minibuffer input, display the
result in `*Devutils*`, and copy the result to the kill ring.

Add existing interactive commands without changing the package:

```elisp
(add-to-list 'devutils-extra-tools
             '("Documentation / DevDocs lookup" . devdocs-lookup))
```

## Included tools

- JSON formatting, minification, and semantic diff
- Base64, URL, and HTML entity encoding and decoding
- Text hashing, case conversion, and statistics
- Unix timestamp conversion
- UUID, random number, and random port generation
- QR code generation and decoding from image files or clipboard images

UUID generation calls the system `uuidgen` command. HTML entity decoding uses
Emacs's built-in `mm-url` entity table.

## JSON diff

Open both JSON documents as buffers, switch to the buffer that should appear on
the left, and run `M-x devutils-json-diff`. Select the other buffer when
prompted. The command recursively sorts object keys, preserves array order, and
opens the canonical JSON buffers in Ediff. Quitting Ediff removes only the two
temporary buffers created for that comparison.

Invalid JSON stops the command before Ediff starts and leaves both source
buffers unchanged.

## QR codes

Use `M-x devutils-qr-generate` to generate a QR code from the active region or
minibuffer input. The command displays the image in `*Devutils QR Code*`.

Use `M-x devutils-qr-decode-file` to decode an image file, or
`M-x devutils-qr-decode-clipboard` to decode an image from the system
clipboard. Decoded payloads are displayed as plain text and copied to the kill
ring. The package never opens decoded URLs or executes decoded content.

QR support requires external command-line tools:

```sh
# macOS
brew install qrencode zbar pngpaste

# Arch Linux with Wayland
sudo pacman -S qrencode zbar wl-clipboard

# Arch Linux with X11
sudo pacman -S qrencode zbar xclip
```

## Design and development

[The design document](docs/design.md) is the implementation index and records
package boundaries, behavior contracts, source symbols, and the DevHub feature
coverage matrix.

Run tests from an existing Emacs server:

```sh
emacsclient --eval '(progn (add-to-list (quote load-path) "/path/to/devutils.el") (load "/path/to/devutils.el/test/devutils-test.el" nil t) (ert-stats-completed-unexpected (ert-run-tests "^devutils-test-" (lambda (&rest _event) nil))))'
```

## License

Copyright (C) 2026 Jiale Liu. This project is licensed under the GNU General
Public License version 3 only. See [LICENSE](LICENSE).
