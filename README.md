# XrayBar

**English** · [Русский](README.ru.md)

A small, native macOS menu-bar app that runs [Xray-core](https://github.com/XTLS/Xray-core)
with its **native TUN**: all traffic, routed by geosite/geoip rules, through one process,
with nothing else in between.

> Status: early, stages 1–3 of [docs/ROADMAP.md](docs/ROADMAP.md) mostly done; used daily by the author.

## How this was built — read this first

XrayBar was written almost entirely by an AI coding agent (Claude Code), directed by the
author in conversation: what is often called *vibe coding*. The author is **not a Swift or
macOS developer** and does not know Apple's development practices (Swift, SwiftUI/AppKit,
the SDKs, signing, launchd) well enough to judge the code as an expert would.

What the author did: decided what the app should and should not do, insisted on a small,
auditable design, and tested every step on a real Mac (macOS 26) with real servers. What was
done to make up for the missing expertise: every decision and its evidence is written down
([docs/DECISIONS.md](docs/DECISIONS.md)), including the mistakes; the code is small and meant to
be read in order; there are tests and a deterministic audit script ([scripts/audit.sh](scripts/audit.sh)).

What it means for you: **no experienced macOS engineer has reviewed this code.** It may be
unidiomatic, and it may be wrong in ways neither the author nor the AI noticed. Treat it as
you would any unreviewed code that asks for your administrator password: read it or have it
reviewed ([docs/AUDIT.md](docs/AUDIT.md)) before you trust it. Reviews and issues from people who
know the platform are very welcome.

## Why

macOS clients for Xray tend to be multi-core kitchen sinks, look nothing like a Mac app,
or both. XrayBar does one thing and tries to do it the way Apple would:
a menu like Wi-Fi's, a password prompt when it needs root, and nothing left behind
when you disconnect. See [docs/PRINCIPLES.md](docs/PRINCIPLES.md).

## Build and run

Requirements: macOS 15+, Command Line Tools (`xcode-select --install`). No Xcode.

```sh
scripts/make-app.sh                          # builds build/XrayBar.app (ad-hoc signed)
cp -R build/XrayBar.app /Applications/       # then open it from /Applications
```

For development, `swift run` works too.

**Xray Version ›** downloads the Xray release tested with XrayBar, or any newer one; versions
stay installed side by side, and the first connection with a new one is checked, with a
one-click switch back if no traffic passes. **Update Routing Data** fetches
`geoip.dat`/`geosite.dat`. Everything is checksum-verified. Until then an existing v2rayN
install is used (`~/Library/Application Support/v2rayN/bin`). Import servers with
**Import Link or QR Code from Clipboard** (copy a `vless://…` link, or press ⌘⇧⌃4 and select a
QR code — the screenshot goes to the clipboard), or **Import from v2rayN…** (read-only).
**Share Server…** shows a QR code. Hold **Option** with the menu open to remove a server or routing set, copy the server link, or
see technical details under the status line. With **Connect at Launch** (on by default) XrayBar
connects to the last used server when it starts; pair it with **Open at Login**.

Connect asks for your administrator password: creating a TUN interface needs root.
**Use Touch ID to Connect…** installs a small root-owned helper once; after that each Connect
asks for Touch ID (or the password) in a system dialog. Only short, readable code runs as root:
[`Sources/XrayBar/Resources/xraybar-session.sh`](Sources/XrayBar/Resources/xraybar-session.sh).

## Can I trust it?

You shouldn't have to take anyone's word for it. The app is ~1,400 lines of Swift in a handful of
numbered files meant to be read in order, plus ~200 lines of root scripts and an optional
~110-line root helper, with zero dependencies.

- [docs/SECURITY.md](docs/SECURITY.md) — what it does, threat model, known limitations.
- `scripts/audit.sh` — deterministic inventory of privilege, processes, network, file writes.
- [docs/AUDIT.md](docs/AUDIT.md) — review checklist, usable as instructions for an AI model.

## Tests

```sh
scripts/test.sh                 # unit tests
scripts/test.sh --integration   # also runs configs from your local v2rayN through xray (read-only)
```

## License and credits

MIT, see [LICENSE](LICENSE). Behaviour and formats are modelled on
[v2rayN](https://github.com/2dust/v2rayN) (no v2rayN code is used). Xray-core is a separate
program under MPL-2.0. Routing data:
[runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat),
[Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat).
