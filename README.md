<p align="center"><img src="docs/images/icon.png" width="128" alt=""></p>
<h1 align="center">XrayBar</h1>
<p align="center">A small, native macOS menu-bar app for Xray-core's native TUN.</p>
<p align="center">
  <a href="https://github.com/heaprip/xraybar/actions/workflows/ci.yml"><img src="https://github.com/heaprip/xraybar/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/heaprip/xraybar/releases"><img src="https://img.shields.io/github/v/release/heaprip/xraybar?include_prereleases&sort=semver" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-blue" alt="macOS 15+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT"></a>
</p>
<p align="center"><b>English</b> · <a href="README.ru.md">Русский</a></p>

A small, native macOS menu-bar app that runs [Xray-core](https://github.com/XTLS/Xray-core)
with its **native TUN**: all traffic, routed by geosite/geoip rules, through one process,
with nothing else in between.

<p align="center">
  <img src="docs/images/menus.png" width="931" alt="XrayBar menu, and the same menu with Option held: technical details and Remove items">
</p>
<p align="center"><sub>The menu, and the same menu with <b>Option</b> held (demo servers).</sub></p>

> Status: early; used daily by the author. Not verified yet: IPv6 through the tunnel on a real
> IPv6 network, the DNS override across a switch between network services (Wi-Fi to Ethernet).
> Not done: transports other than raw.

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

## Install

Requirements: macOS 15 or later, Apple silicon or Intel. The interface follows the system
language: English or Russian.

1. Download `XrayBar-x.y.z.pkg` (or the `.zip`) from [Releases](https://github.com/heaprip/xraybar/releases).
2. Open it. XrayBar is signed ad hoc, not notarized (there is no paid Apple Developer ID), so
   macOS refuses the first time: click **Done**, then **System Settings › Privacy & Security**,
   scroll to *"XrayBar… was blocked"*, **Open Anyway**, confirm. For the `.pkg` this is needed
   once per download; the app it installs into /Applications then opens normally.
3. Updating: quit XrayBar first. After an update macOS asks once whether XrayBar may use its
   keychain item: **Always Allow**. If the menu shows *Update Helper (Required)*, choose it.

Check what you downloaded (optional). The checksums come with the release; the attestation
proves the file was built by this repository's [release workflow](.github/workflows/release.yml)
from the tagged commit, not uploaded by hand:

```sh
shasum -a 256 -c SHA256SUMS
gh attestation verify XrayBar-x.y.z.pkg -R heaprip/xraybar
```

### Build from source

Command Line Tools are enough (`xcode-select --install`), no Xcode:

```sh
scripts/make-app.sh                          # builds build/XrayBar.app (ad-hoc signed)
cp -R build/XrayBar.app /Applications/       # then open it from /Applications
```

For development, `swift run` works too (English only: translations need the app bundle).

## Getting started

1. **Add a server.** *Import Link or QR Code from Clipboard*: copy a `vless://…` link, or press
   ⌘⇧⌃4 and select a QR code (the screenshot goes to the clipboard). Or *Import from v2rayN…*
   (read-only).
2. **Get Xray and routing data.** *Xray › Download v26.9.9* and *Update Routing Data*
   (checksum-verified). Installing Xray asks for your password once: it goes into a root-owned
   folder, the only place XrayBar runs it from as root. With v2rayN installed, *Copy Xray
   from v2rayN…* does the same with its copy; until then the routing data comes from v2rayN.
3. **Connect.** macOS asks for your administrator password: a TUN interface needs root.
   *Use Touch ID to Connect…* installs a small root-owned helper once; after that, Touch ID once per login.
4. **Forget about it.** *Connect at Launch* (on by default) plus *Open at Login*: the Mac starts,
   you touch the sensor, you're connected.

## The menu

| Item | What it does |
|---|---|
| Server, Routing | Choose the server and routing set (routing sets use v2rayN's format) |
| Share Server… | The selected server as a QR code |
| Xray › | Versions side by side; a new version's first connection is checked, with a one-click switch back. Routing data source and update. *Exclude from Tunnel…* for networks that must bypass Xray |
| Diagnostics › | Log, detailed log, data folder, uninstall the helper. XrayBar's own log: Console.app, subsystem `io.github.heaprip.xraybar` |
| **Option** held | *Remove* a server or routing set · *Copy Server Link* · technical details under the status line |

Only short, readable code runs as root: [the session script](Sources/XrayBar/Resources/xraybar-session.sh),
[the install script](Sources/XrayBar/Resources/xraybar-install.sh) and
[the helper](Sources/XrayBarHelper/main.swift): the session uses its event watch (it only
observes), and its Touch ID service is optional.

## Uninstall

1. Disconnect, then *Diagnostics › Uninstall Helper…* if you installed it (removes the helper,
   its LaunchDaemon and its authorization right).
2. Quit XrayBar and delete it from /Applications (its Open at Login item goes with it).
3. What remains:
   ```sh
   sudo rm -rf "/Library/Application Support/XrayBar" /var/db/xraybar  # installed Xray, saved DNS
   rm -rf ~/Library/Application\ Support/XrayBar                       # servers, routing sets, data
   sudo pkgutil --forget io.github.heaprip.xraybar                      # if installed from the .pkg
   ```
   and the keychain item *XrayBar server credentials* (Keychain Access). `/var/run/xraybar` is
   cleared at restart.

## Troubleshooting

- **No internet after a crash or power loss.** Open XrayBar: it offers *Restore Network
  Settings*. By hand: `networksetup -setdnsservers Wi-Fi empty`.
- **"Another VPN or TUN already routes all traffic".** Turn off the other VPN, or v2rayN's TUN mode.
- **The menu bar icon shows an exclamation mark.** Choose *Update Helper (Required)*: the app
  was updated, the root helper not yet.
- **Nothing appears when you open the app.** It is already running (one instance only): look in
  the menu bar, or quit it first.
- **Logs.** *Diagnostics › Show Xray Log*, and XrayBar's own:
  `log show --last 1h --predicate 'subsystem == "io.github.heaprip.xraybar"'`. When reporting an
  issue, include the macOS version, XrayBar's version (*About XrayBar*) and the relevant log
  lines, with server addresses removed.

## Can I trust it?

You shouldn't have to take anyone's word for it. The app is ~1,650 lines of Swift in a handful of
numbered files meant to be read in order, plus ~260 lines of root scripts and a
~150-line root helper, with zero dependencies.

- [docs/SECURITY.md](docs/SECURITY.md) — what it does, threat model, known limitations.
- `scripts/audit.sh` — deterministic inventory of privilege, processes, network, file writes.
- [docs/AUDIT.md](docs/AUDIT.md) — review checklist, usable as instructions for an AI model.
- Release builds come from CI with a provenance attestation (see Install); or build it yourself.

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
