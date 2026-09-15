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
- **Port from v2rayN, don't invent.** When porting, cite the v2rayN file/function in a
  comment. A shallow clone for reference lives in `.ref/v2rayN` (not tracked).
- **Record decisions** in `docs/DECISIONS.md` (context → decision → consequences), keep
  `docs/SECURITY.md` in sync with what the code does, and update `docs/ROADMAP.md`.

Build: `swift build`. Test: `swift test`. Integration (local v2rayN + xray, read-only):
`swift build --build-tests && XRAYBAR_INTEGRATION=1 swift test --skip-build`.

Never touch the user's v2rayN installation beyond read-only access to its database and
binaries. Never stop processes you did not start.
