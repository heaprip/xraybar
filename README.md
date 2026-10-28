<p align="center"><img src="docs/images/icon.png" width="128" alt=""></p>
<h1 align="center">XrayBar</h1>
<p align="center">A small, native macOS menu-bar client built on Xray-core.</p>
<p align="center">
  <a href="https://github.com/heaprip/xraybar/actions/workflows/ci.yml"><img src="https://github.com/heaprip/xraybar/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/heaprip/xraybar/releases"><img src="https://img.shields.io/github/v/release/heaprip/xraybar?include_prereleases&sort=semver" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-blue" alt="macOS 15+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT"></a>
</p>
<p align="center"><b>English</b> · <a href="README.ru.md">Русский</a></p>

XrayBar keeps your servers and connects through [Xray-core](https://github.com/XTLS/Xray-core)
and its **native TUN**: VLESS (REALITY, TLS) and Hysteria 2, routed by geosite/geoip rules,
all traffic through one process with nothing else in between.

<p align="center">
  <img src="docs/images/menus.png" width="931" alt="XrayBar menu, and the same menu with Option held: technical details and Remove items">
</p>
<p align="center"><sub>The menu, and the same menu with <b>Option</b> held (demo servers).</sub></p>

> Status: early; used daily by the author. Not verified yet: IPv6 through the tunnel on a real
> IPv6 network, the DNS override across a switch between network services (Wi-Fi to Ethernet).
> Not done: VLESS transports other than raw (ws, grpc, xhttp…); Hysteria 2's gecko obfuscation and realm.

## Why

The clients that exist did not fit. v2rayN works, and this project owes it a lot, but it is a
cross-platform tool for many cores and many settings, and it does not feel like a Mac app.
Closed-source clients, and most of those in the App Store, add accounts, dashboards and screens
to look at, and you cannot see what they do as root.

XrayBar does less on purpose. It keeps your servers, connects quickly, and otherwise stays out
of the way: turn on *Open at Login*, touch the sensor once after you log in, and that is all,
with nothing to click in normal use. It does not create or edit routing rules, and probably
never will: routing sets come from v2rayN or runetfreedom's templates, and XrayBar applies
them. A menu like Wi-Fi's, a password prompt only when root is needed, nothing left behind
when you disconnect. See [docs/PRINCIPLES.md](docs/PRINCIPLES.md).

## Don't trust, verify

XrayBar asks for root and carries all your traffic, so it should not ask you to trust its
author either. It is built to be checked instead:

- **Small and linear.** About 1,860 lines of Swift in numbered files read in order. The code
  that runs as root is ~270 lines of shell and a ~150-line helper, held to hard size limits.
  No third-party dependencies.
- **Root does only what the scripts say:** [the session script](Sources/XrayBar/Resources/xraybar-session.sh)
  (TUN, DNS, start and stop Xray), [the install script](Sources/XrayBar/Resources/xraybar-install.sh)
  and [the helper](Sources/XrayBarHelper/main.swift). Root runs only an Xray copied into a
  root-owned folder and checked against its SHA-256; it never signals a process it did not start.
- **Quiet.** No telemetry or analytics. The network is used only when you ask (downloads,
  checksum-verified) and for one check after connecting with a new Xray version.
- **Credentials** live in your login keychain.
- [docs/SECURITY.md](docs/SECURITY.md): what it does, the threat model, known limitations.
  `scripts/audit.sh`: a deterministic inventory of privilege, processes, network and file
  writes. [docs/AUDIT.md](docs/AUDIT.md): a review checklist, usable as instructions for an AI model.
- **Release builds** come from CI with a provenance attestation (see Install), or build it yourself.

Found a problem? Report it privately on the [Security tab](https://github.com/heaprip/xraybar/security).

## How it was built

XrayBar is built with an AI coding agent (Claude Code), directed and tested on a real Mac by
the author, an experienced developer who is new to Apple's desktop platform. Every decision is
written down in [docs/DECISIONS.md](docs/DECISIONS.md), and the code is small enough to read in
one sitting. It has not been reviewed by a macOS specialist yet: reviews and issues are very
welcome, and [docs/AUDIT.md](docs/AUDIT.md) is a checklist for checking it yourself.

## Install

Requirements: macOS 15 or later, Apple silicon or Intel. The interface follows the system
language: English or Russian.

1. Download `XrayBar-x.y.z.pkg` (or the `.zip`) from the [latest release](https://github.com/heaprip/xraybar/releases/latest).
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

1. **Add a server.** *Import Link or QR Code from Clipboard*: copy a `vless://…` or
   `hysteria2://…` link, or press ⌘⇧⌃4 and select a QR code (the screenshot goes to the
   clipboard). Or *Import from v2rayN…* (read-only, see below).
2. **Get Xray and routing data.** *Xray › Download v26.10.21* and *Update Routing Data*
   (checksum-verified). Installing Xray asks for your password once: it goes into a root-owned
   folder, the only place XrayBar runs it from as root. With v2rayN installed, *Copy Xray
   from v2rayN…* does the same with its copy; until then the routing data comes from v2rayN.
3. **Connect.** macOS asks for your administrator password: a TUN interface needs root.
   *Use Touch ID to Connect…* installs a small root-owned helper once; after that, Touch ID once per login.
4. **Forget about it.** *Connect at Launch* (on by default) plus *Open at Login*: the Mac starts,
   you touch the sensor, you're connected.

### Import from v2rayN

*Import from v2rayN…* reads v2rayN's database (`~/Library/Application Support/v2rayN/guiConfigs/guiNDB.db`),
opened read-only: v2rayN is never changed and may keep running. It can be chosen again at any
time; what is already in XrayBar is skipped (a server with the same address, port and
credential; a routing set with the same name and rules).

| From v2rayN | Imported |
|---|---|
| VLESS servers (REALITY or TLS) | yes; the credential goes to the keychain |
| Hysteria 2 servers (password, SNI, salamander, port hopping, certificate pin) | yes; gecko obfuscation and realm are not supported by XrayBar, such servers are left out |
| VMess, Trojan, Shadowsocks, WireGuard, … | no |
| Routing sets (all of them, e.g. runetfreedom's *RUv1-…*) | yes, rules unchanged; choose one under *Routing* |
| Subscriptions, DNS settings, the active server or routing set, Xray settings | no |

Routing *data* (`geoip.dat`, `geosite.dat`) is not routing *rules*: *Update Routing Data*
downloads the lists, and a routing set decides what goes direct, through the proxy or is
blocked. Without an imported set XrayBar has only *Global* (everything through the proxy,
except the local network and ads).

## The menu

| Item | What it does |
|---|---|
| Server, Routing | Choose the server and routing set (routing sets use v2rayN's format) |
| Share Server… | The selected server as a QR code |
| Xray › | Versions side by side; a new version's first connection is checked, with a one-click switch back. Routing data source and update. *Exclude from Tunnel…* for networks that must bypass Xray |
| Diagnostics › | Log, detailed log, data folder, uninstall the helper. XrayBar's own log: Console.app, subsystem `io.github.heaprip.xraybar` |
| **Option** held | *Remove* a server or routing set · *Copy Server Link* · technical details under the status line · *Diagnostics › Reset XrayBar…* |

Only short, readable code runs as root: [the session script](Sources/XrayBar/Resources/xraybar-session.sh),
[the install script](Sources/XrayBar/Resources/xraybar-install.sh) and
[the helper](Sources/XrayBarHelper/main.swift): the session uses its event watch (it only
observes), and its Touch ID service is optional.

## Uninstall

The simplest way: disconnect, hold **Option**, choose *Diagnostics › Reset XrayBar…* (one
password: removes servers, settings, routing data, every installed Xray, the helper and the
keychain item, then quits), and delete XrayBar from /Applications. By hand:

1. Disconnect, then *Diagnostics › Uninstall Helper…* if you installed it (removes the helper,
   its LaunchDaemon and its authorization right).
2. Quit XrayBar and delete it from /Applications (its Open at Login item goes with it).
3. What remains:
   ```sh
   sudo rm -rf "/Library/Application Support/XrayBar" /var/db/xraybar  # installed Xray, saved DNS
   rm -rf ~/Library/Application\ Support/XrayBar                       # servers, routing sets, data
   rm -rf ~/Library/Caches/io.github.heaprip.xraybar                   # a cache macOS keeps
   sudo pkgutil --forget io.github.heaprip.xraybar                      # if installed from the .pkg
   ```
   and the keychain item *XrayBar server credentials* (Keychain Access). `/var/run/xraybar` is
   cleared at restart.

## Troubleshooting

- **No internet after a crash or power loss.** Open XrayBar: it offers *Restore Network
  Settings*. By hand: `networksetup -setdnsservers Wi-Fi empty`.
- **"Another VPN or TUN already routes all traffic".** Turn off the other VPN, or v2rayN's TUN mode.
- **The menu bar icon has a dot.** Choose *Update Helper (Required)*: the app was updated, the
  root helper not yet.
- **Nothing appears when you open the app.** It is already running (one instance only): look in
  the menu bar, or quit it first.
- **Logs.** *Diagnostics › Show Xray Log*, and XrayBar's own:
  `log show --last 1h --predicate 'subsystem == "io.github.heaprip.xraybar"'`. When reporting an
  issue, include the macOS version, XrayBar's version (*About XrayBar*) and the relevant log
  lines, with server addresses removed.

## Tests

```sh
scripts/test.sh                 # unit tests
scripts/test.sh --integration   # also runs configs from your local v2rayN through xray (read-only)
```

## Feedback and contributions

The author uses XrayBar every day and wants to hear how it works for you. Welcome:

- what breaks or feels awkward;
- protocols and features you need (more VLESS transports, Hysteria 2 options, …), as long as
  XrayBar stays simple and narrow;
- visual and usability improvements;
- issues and pull requests. Read [docs/PRINCIPLES.md](docs/PRINCIPLES.md) and
  [docs/DECISIONS.md](docs/DECISIONS.md) first: a change that keeps the code small and linear
  is the easiest to accept.

## License and credits

MIT, see [LICENSE](LICENSE). Behaviour and formats are modelled on
[v2rayN](https://github.com/2dust/v2rayN) (no v2rayN code is used). Xray-core is a separate
program under MPL-2.0. Routing data:
[runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat),
[Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat).
