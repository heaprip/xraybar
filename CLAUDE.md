# Working on XrayBar

Read `docs/PRINCIPLES.md` first. The short version:

- **Small and readable is a feature.** Keep the app a handful of numbered files read top to
  bottom (`Sources/XrayBar/1-Model.swift` … `6-Menu.swift`). Prefer straight-line code over
  abstractions. `scripts/audit.sh` enforces the size budget; run it before committing.
- **Zero dependencies.** Apple SDK only. Never add a Swift package.
- **Root lives in one place:** `Sources/XrayBar/Resources/xraybar-session.sh`. Anything that
  needs root goes there, validated, and nowhere else. Never signal a PID the session did not
  start; never find processes by name or pattern.
- **No network I/O in the app** unless the user explicitly started it (future asset updates),
  and then only from one documented place.
- **Native look.** `NSMenu`/`NSStatusItem`, SF Symbols, `NSAlert`, SwiftUI only for editor
  windows. No custom styling.
- **Match v2rayN's behaviour, never copy its code.** v2rayN is GPL-3.0, XrayBar is MIT (D9).
  Read `.ref/v2rayN` (shallow clone, not tracked) to understand *what* it does, then write
  the Swift from Xray's documentation and observed behaviour. No line-by-line translation,
  no pasted snippets. Formats (routing-set JSON, share links) may be matched exactly.
- **Record decisions** in `docs/DECISIONS.md` (context → decision → consequences), keep
  `docs/SECURITY.md` in sync with what the code does, and update `docs/ROADMAP.md`.
- **Docs are bilingual.** English is primary; `README.ru.md` and `docs/ru/` mirror README,
  PRINCIPLES, SECURITY, AUDIT and ROADMAP. Update the Russian file in the same commit.
  `DECISIONS.md` is English only.

Build: `swift build`. Test: `swift test`. Integration (local v2rayN + xray, read-only):
`swift build --build-tests && XRAYBAR_INTEGRATION=1 swift test --skip-build`.

Never touch the user's v2rayN installation beyond read-only access to its database and
binaries. Never stop processes you did not start.
