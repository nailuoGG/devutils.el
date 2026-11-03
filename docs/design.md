# devutils.el design

This document is the implementation index for `devutils.el`. Source changes
must preserve the contracts below or update this document in the same change.

## Goals

- Provide one searchable entry point for small developer utilities.
- Make region, minibuffer, result buffer, and kill-ring behavior consistent.
- Reuse Emacs built-ins before adding code, packages, or external programs.
- Let a user expose existing interactive commands without changing this
  package.

## Non-goals

- Recreate DevHub's SwiftUI layout or its 68 tools as separate pages.
- Implement formatters, HTTP clients, OCR, QR algorithms, image processing, or
  cryptography engines in Emacs Lisp.
- Manage third-party package installation.
- Provide a plugin framework, transient hierarchy, or persistent database.

## Package boundary

The package owns:

- the `devutils` completion entry point;
- the built-in tool catalog;
- common input and output behavior;
- small transformations supported by Emacs or its standard library.

User configuration owns keybindings, personal aliases such as `my/devutils`,
and entries in `devutils-extra-tools`. Optional integrations own their package
or executable dependencies.

## Interaction contract

Transformation commands read the active region when one exists. A successful
transformation replaces that region as one undoable buffer change. A failed
transformation leaves it unchanged. Without a region, the command reads from
the minibuffer, writes the result to `*Devutils*`, and copies it to the kill
ring.

Inspection commands use the same result buffer and kill-ring destination.
QR generation instead displays binary PNG output in `*Devutils QR Code*` and
does not insert binary data into the kill ring.

`devutils-json-diff` reads the current buffer and one selected buffer without
modifying either source. It parses both documents, recursively sorts object
keys, preserves array order, and opens two generated canonical buffers in
Ediff. Ediff cleanup removes only the buffers created by that comparison.
Invalid JSON stops before any generated buffer is created.

QR generation invokes `qrencode` directly in 8-bit mode and captures PNG bytes
without shell parsing. Non-ASCII payloads include a UTF-8 byte-order marker so
`zbarimg` and compatible scanners preserve the payload encoding. QR decoding
invokes `zbarimg` directly and treats its output only as untrusted text: decoded
URLs are not opened and decoded content is never executed. Clipboard decoding
uses `pngpaste` on macOS, `wl-paste` on Wayland, or `xclip` on X11. Its temporary
PNG file is removed after both successful and failed decoding.

Canonical JSON uses two-space indentation and one object member per line.
Object keys use ascending string order at every nesting level. Array elements
retain their original order and are compared by index. Primitive values retain
their JSON types. Duplicate object keys follow the JSON parser's last-value
behavior; callers must not use duplicate keys to represent distinct data.

`devutils` uses `completing-read`; completion frontends such as Vertico can
enhance it without becoming package dependencies.

## Implementation index

| Responsibility | Source symbol |
| --- | --- |
| Completion entry point | `devutils` |
| Built-in catalog | `devutils--tools` |
| User-supplied commands | `devutils-extra-tools` |
| Region/minibuffer input | `devutils--region-bounds`, `devutils--read-input` |
| Transform behavior | `devutils--transform` |
| Inspection behavior | `devutils--inspect` |
| Result buffer and kill ring | `devutils--show-result` |
| JSON parsing and rendering | `devutils--json-*` |
| JSON canonical key ordering | `devutils--json-render`, `devutils--json-canonicalize` |
| JSON Ediff buffers and lifecycle | `devutils-json-diff`, `devutils--json-diff-buffer` |
| External process boundary | `devutils--require-executable`, `devutils--process-output` |
| QR generation and display | `devutils--qr-generate-data`, `devutils--show-qr-code` |
| QR file and clipboard decoding | `devutils--qr-decode-file`, `devutils--qr-decode-clipboard` |
| HTML entity decoding | `devutils--html-decode` |

## Initial feature set

| Category | Commands | Backend |
| --- | --- | --- |
| JSON | format, minify, semantic diff | `json.el`, Ediff |
| Encoding | Base64 encode/decode | Emacs Base64 primitives |
| Encoding | URL encode/decode | `url-util.el` |
| Encoding | HTML entities | `xml.el`, `mm-url.el` |
| Text | hash | `secure-hash` |
| Text | uppercase, lowercase, capitalize, statistics | Emacs primitives |
| Time | timestamp to date, date to timestamp | Emacs time primitives |
| Generate | UUID | system `uuidgen` |
| Generate | random number, random dynamic port | Emacs `random` |
| QR | generate | `qrencode` |
| QR | decode image file | `zbarimg` |
| QR | decode clipboard image | macOS `pngpaste`; Wayland `wl-paste`; X11 `xclip` |

Random number and port commands are convenience tools, not cryptographic
generators. Password and RSA key generation remain outside the package until a
secure backend is selected.

## DevHub coverage index

| Backend decision | DevHub capabilities |
| --- | --- |
| Core package | JSON, Base64 text, URL encoding, HTML entities, Unicode/text case, hashes, timestamps, dates, random numbers, random ports, UUID, word counts |
| Emacs built-in command | regular expressions (`re-builder`), text comparison (Ediff), file information/Dired, chmod/Dired, world clock, unit conversion/Calc, HTML preview/EWW |
| Optional package | HTTP requests (`restclient` or Verb), developer documentation (`devdocs`) |
| External CLI adapter | QR codes (`qrencode`, `zbarimg`, and platform clipboard tools), Prettier, HTML-to-Markdown/Pandoc, OCR/Tesseract or macOS Vision, EXIF/ExifTool, SSL/OpenSSL, image conversion/ImageMagick, text-to-speech |
| Outside Emacs scope | desktop privacy masks, global cursor highlighting, general screenshot UI, application icon design, image composition editors |

Different QR payload types share one QR backend; they do not require separate
tools. Formatters must use project-local executables and environment selection
owned by the user's configuration.

## Extension rule

Use `devutils-extra-tools` when an existing interactive command already solves
the problem. Add a core command when Emacs or its standard library can implement
the operation directly, or when a small cross-platform CLI adapter has a narrow
process boundary and benefits from the shared interaction contract. Add a
separate adapter package when an integration requires lifecycle management,
multiple cooperating services, or a large configuration surface.

## Verification index

`test/devutils-test.el` covers JSON round trips, recursive key ordering, array
order, Ediff input and cleanup, failed-transform data safety, Base64 and URL
Unicode round trips, HTML entities, and catalog command validity. Live
verification must additionally exercise the completion entry point, a region
replacement, a minibuffer-style result, JSON Ediff startup, UUID generation,
and a real QR Unicode generate/decode round trip in the running Emacs instance.
QR tests cover command arguments, platform clipboard selection, invalid input,
temporary-file cleanup on success and failure, missing dependencies, and the
plain-text trust boundary.
