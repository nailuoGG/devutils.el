# dev-tools.el design

This document is the implementation index for `dev-tools.el`. Source changes
must preserve the contracts below or update this document in the same change.

## Goals

- Provide one searchable entry point for small developer utilities.
- Make region, minibuffer, result buffer, and kill-ring behavior consistent.
- Reuse Emacs built-ins before adding code, packages, or external programs.
- Let a user expose existing interactive commands without changing this
  package.

## Non-goals

- Recreate DevHub's SwiftUI layout or its 68 tools as separate pages.
- Implement formatters, HTTP clients, OCR, image processing, or cryptography
  engines in Emacs Lisp.
- Manage third-party package installation.
- Provide a plugin framework, transient hierarchy, or persistent database.

## Package boundary

The package owns:

- the `dev-tools` completion entry point;
- the built-in tool catalog;
- common input and output behavior;
- small transformations supported by Emacs or its standard library.

User configuration owns keybindings, personal aliases such as `my/dev-tools`,
and entries in `dev-tools-extra-tools`. Optional integrations own their package
or executable dependencies.

## Interaction contract

Transformation commands read the active region when one exists. A successful
transformation replaces that region as one undoable buffer change. A failed
transformation leaves it unchanged. Without a region, the command reads from
the minibuffer, writes the result to `*Dev Tools*`, and copies it to the kill
ring.

Inspection and generation commands never replace the region. They use the same
result buffer and kill-ring destination.

`dev-tools` uses `completing-read`; completion frontends such as Vertico can
enhance it without becoming package dependencies.

## Implementation index

| Responsibility | Source symbol |
| --- | --- |
| Completion entry point | `dev-tools` |
| Built-in catalog | `dev-tools--tools` |
| User-supplied commands | `dev-tools-extra-tools` |
| Region/minibuffer input | `dev-tools--region-bounds`, `dev-tools--read-input` |
| Transform behavior | `dev-tools--transform` |
| Inspection behavior | `dev-tools--inspect` |
| Result buffer and kill ring | `dev-tools--show-result` |
| JSON parsing and rendering | `dev-tools--json-*` |
| HTML entity decoding | `dev-tools--html-decode` |

## Initial feature set

| Category | Commands | Backend |
| --- | --- | --- |
| JSON | format, minify | `json.el` |
| Encoding | Base64 encode/decode | Emacs Base64 primitives |
| Encoding | URL encode/decode | `url-util.el` |
| Encoding | HTML entities | `xml.el`, `mm-url.el` |
| Text | hash | `secure-hash` |
| Text | uppercase, lowercase, capitalize, statistics | Emacs primitives |
| Time | timestamp to date, date to timestamp | Emacs time primitives |
| Generate | UUID | system `uuidgen` |
| Generate | random number, random dynamic port | Emacs `random` |

Random number and port commands are convenience tools, not cryptographic
generators. Password and RSA key generation remain outside the package until a
secure backend is selected.

## DevHub coverage index

| Backend decision | DevHub capabilities |
| --- | --- |
| Core package | JSON, Base64 text, URL encoding, HTML entities, Unicode/text case, hashes, timestamps, dates, random numbers, random ports, UUID, word counts |
| Emacs built-in command | regular expressions (`re-builder`), text comparison (Ediff), file information/Dired, chmod/Dired, world clock, unit conversion/Calc, HTML preview/EWW |
| Optional package | HTTP requests (`restclient` or Verb), QR codes (`qrencode`), developer documentation (`devdocs`) |
| External CLI adapter | Prettier, HTML-to-Markdown/Pandoc, OCR/Tesseract or macOS Vision, EXIF/ExifTool, SSL/OpenSSL, image conversion/ImageMagick, text-to-speech |
| Outside Emacs scope | desktop privacy masks, global cursor highlighting, general screenshot UI, application icon design, image composition editors |

Different QR payload types share one QR backend; they do not require separate
tools. Formatters must use project-local executables and environment selection
owned by the user's configuration.

## Extension rule

Use `dev-tools-extra-tools` when an existing interactive command already solves
the problem. Add a core command only when Emacs or its standard library can
implement the operation without a new dependency and the operation benefits
from the shared input/output contract. Add a separate adapter package when an
integration requires lifecycle management, external dependencies, or a large
configuration surface.

## Verification index

`test/dev-tools-test.el` covers JSON round trips, failed-transform data safety,
Base64 and URL Unicode round trips, HTML entities, and catalog command validity.
Live verification must additionally exercise the completion entry point, a
region replacement, a minibuffer-style result, and UUID generation in the
running Emacs instance.
