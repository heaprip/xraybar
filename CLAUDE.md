# Working on XrayBar

Read `docs/PRINCIPLES.md` first. The short version:

- **Small and readable is a feature.** Keep the app a handful of numbered files read top to
  bottom (`Sources/XrayBar/1-Model.swift` … `8-Menu.swift`, then `App.swift`). Prefer straight-line code over
  abstractions. `scripts/audit.sh` enforces the size budget; run it before committing.
- **Small app, libraries allowed.** A well-known, maintained package is fine when it replaces
  code we would write; pin an exact version and list it in docs/SECURITY.md. It must build
  with the Command Line Tools (no Xcode-only macro plugins such as `@State` on SDK 27 or `#Preview`).
- **Root lives in one place:** `Sources/XrayBar/Resources/xraybar-session.sh`. Anything that
  needs root goes there, validated, and nowhere else. (The install script installs; the helper
  authorizes and starts the session, and its `--watch` mode only observes and reports events.) Never signal a PID the session did not
  start; never find processes by name or pattern.
- **No network I/O in the app** unless the user explicitly started it (future asset updates),
  and then only from one documented place.
- **Native look.** A standard `MenuBarExtra` menu (HIG; like Karabiner-Elements): SwiftUI
  `Button`/`Toggle`/`Menu`/`Section` with SF Symbols, `NSAlert` for dialogs. No custom styling. Avoid `@State` and
  other SwiftUI macros: the Command Line Tools lack their plugin (see App.swift).
- **Match v2rayN's behaviour, never copy its code.** v2rayN is GPL-3.0, XrayBar is MIT (D9).
  Read `.ref/v2rayN` (shallow clone, not tracked) to understand *what* it does, then write
  the Swift from Xray's documentation and observed behaviour. No line-by-line translation,
  no pasted snippets. Formats (routing-set JSON, share links) may be matched exactly.
- **Persisted fields added later must be optional** (or decode with a default), so an
  existing `library.json` keeps loading; `Store.load` sets unreadable files aside.
- **Record decisions** in `docs/DECISIONS.md` (context → decision → consequences), keep
  `docs/SECURITY.md` in sync with what the code does, and the README's "Not done yet" line.
- **Docs are bilingual.** English is primary; `README.ru.md` and `docs/ru/` mirror README,
  PRINCIPLES, SECURITY and AUDIT. Update the Russian file in the same commit.
  `DECISIONS.md` is English only. The UI is English and Russian: a new or changed user-facing
  string needs its entry in `Support/ru.lproj/Localizable.strings` (keyed by the English text;
  the tests catch unused keys and mismatched `%@`/`%ld`, not missing ones).

Build: `swift build`. Test: `scripts/test.sh` (plain `swift test` hits a CLT plugin bug, see
the script). Integration (local v2rayN + xray, read-only): `scripts/test.sh --integration`.
In this environment `grep` may be a shell function wrapping ugrep and `log` a shell builtin:
use `/usr/bin/grep` and `/usr/bin/log`, and to check what the root script will do, run
snippets under `/bin/bash --noprofile --norc`. shellcheck runs in CI (`-S warning`).

Never touch the user's v2rayN installation beyond read-only access to its database and
binaries. Never stop processes you did not start.

## Releasing

1. Set `CFBundleShortVersionString` in `Support/Info.plist` and add a `## x.y.z` section to
   `CHANGELOG.md` (it becomes the release notes; move the Unreleased items there).
2. Commit, scan for personal data, push, and wait for CI to pass.
3. `git tag -a vX.Y.Z -m "XrayBar X.Y.Z"` and push the tag. `release.yml` builds the universal
   app, `.pkg`, `.zip`, `SHA256SUMS`, the provenance attestation, and publishes it as Latest.
4. Check it as a user would: `gh release download vX.Y.Z`, `shasum -a 256 -c SHA256SUMS`,
   `gh attestation verify XrayBar-X.Y.Z.pkg -R heaprip/xraybar`, `lipo -archs`, `vtool
   -show-build` (minos 15.0). If the workflow fails, delete the tag, fix, tag again.

CI uses the `xcode-27` image (Swift 6.4); Swift 6.3 crashes compiling the menu (D48).
Local context that is not part of the project, if present: `CLAUDE.local.md` and `.notes/`.

Do not launch the built app to smoke-test it: with *Connect at Launch* it may start a
connection and put an authorization prompt on the user's screen. Build, run the tests, and
let the user try the app.
