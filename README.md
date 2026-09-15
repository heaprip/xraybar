# XrayBar

**English** · [Русский](README.ru.md)

A small, native macOS menu-bar app that runs [Xray-core](https://github.com/XTLS/Xray-core)
with its **native TUN**: all traffic, routed by geosite/geoip rules, through one process,
with nothing else in between.

> Status: early. Stage 1 (connect from the menu) works; see [docs/ROADMAP.md](docs/ROADMAP.md).

## Why

macOS clients for Xray tend to be multi-core kitchen sinks, look nothing like a Mac app,
or both. XrayBar does one thing and tries to do it the way Apple would:
a menu like Wi-Fi's, a password prompt when it needs root, and nothing left behind
when you disconnect. See [docs/PRINCIPLES.md](docs/PRINCIPLES.md).

## Build and run

Requirements: macOS 14+, Command Line Tools (`xcode-select --install`). No Xcode.

```sh
swift build -c release
.build/release/XrayBar
```

Stage 1 uses an existing Xray install for the `xray` binary and `geoip.dat`/`geosite.dat`
(default: v2rayN's `~/Library/Application Support/v2rayN/bin`). Import servers with
**Import Link from Clipboard** (`vless://…`) or **Import from v2rayN…** (read-only).

Connect asks for your administrator password: creating a TUN interface needs root.
Only one short, readable script runs as root:
[`Sources/XrayBar/Resources/xraybar-session.sh`](Sources/XrayBar/Resources/xraybar-session.sh).

## Can I trust it?

You shouldn't have to take anyone's word for it. The app is ~600 lines of Swift in six files
meant to be read in order, plus a ~100-line root script, with zero dependencies.

- [docs/SECURITY.md](docs/SECURITY.md) — what it does, threat model, known limitations.
- `scripts/audit.sh` — deterministic inventory of privilege, processes, network, file writes.
- [docs/AUDIT.md](docs/AUDIT.md) — review checklist, usable as instructions for an AI model.

## Tests

```sh
swift test
# against your local v2rayN data and xray binary (read-only):
swift build --build-tests && XRAYBAR_INTEGRATION=1 swift test --skip-build
```

## License and credits

MIT, see [LICENSE](LICENSE). Behaviour and formats are modelled on
[v2rayN](https://github.com/2dust/v2rayN) (no v2rayN code is used). Xray-core is a separate
program under MPL-2.0. Routing data:
[runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat),
[Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat).
