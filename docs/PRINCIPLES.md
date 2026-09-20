# Principles

**English** · [Русский](ru/PRINCIPLES.md)

XrayBar is a menu-bar control panel for [Xray-core](https://github.com/XTLS/Xray-core) on macOS.
It exists because the available macOS clients are either buggy multi-core
kitchen sinks or look and behave nothing like a Mac app.

## What it is

- One job: run Xray-core with its **native TUN** and **geosite/geoip routing**,
  and manage a handful of connection profiles (import, QR, switch).
- One data plane: Xray-core. No sing-box, no mihomo, no tun2socks, no SOCKS hop.
- One process doing the networking, started and stopped by the app, never left orphaned.

## What it is not

- Not a VPN implementation. Xray is the trusted networking component; XrayBar only
  writes its config and supervises the process.
- Not a v2rayN clone. No subscriptions, speed tests, balancers, proxy chains,
  multiple cores, system-proxy mode or theming, unless a concrete need proves otherwise.
- Not a NetworkExtension app. No App Store, no entitlements, no provisioning.

## Product principles

1. **Narrow and whole.** Fewer features, each finished. A feature that cannot be
   done well is left out, not shipped half-way.
2. **Feels like macOS.** A menu bar panel like Wi-Fi's, system controls and menus, SF Symbols, system dialogs, system
   settings windows. No custom chrome, no web views, no invented widgets.
   When in doubt, do what a built-in Apple menu extra would do.
3. **Quiet.** No network access by the app itself except updates the user
   explicitly starts. No telemetry, no update pings, no analytics.
4. **Leaves the system as it found it.** Routes, DNS and processes are restored on
   disconnect, on quit and after a crash.

## Engineering principles

1. **Small enough to read in one sitting.** The whole app is a few linear Swift
   files meant to be read top to bottom, plus the short root scripts and helper.
   A hard size budget is enforced by `scripts/audit.sh`.
2. **The app stays small; libraries are welcome when they earn their place.** A
   well-known, maintained package may replace code we would otherwise write, pinned to
   an exact version so an audit covers exactly that code. Xray-core and the `.dat` files
   are verified by checksum.
3. **Flow over abstraction.** Prefer a straight sequence of steps a reviewer can
   follow over layers, protocols and dependency injection. Split code only along
   real boundaries: UI, config generation, privileged execution.
4. **Privilege is tiny and visible.** Everything that runs as root is the session script,
   the install script and the optional helper, each short, with a fixed set of actions.
5. **Compatible, not copied.** Where v2rayN already got behaviour right (TUN inbound,
   rule expansion, DNS split) or defined a format people use (routing sets), XrayBar
   matches that behaviour and format, implemented from scratch. v2rayN is GPL-3.0 and
   XrayBar is MIT: its code is read to understand behaviour, never translated (D9).
6. **Decisions are written down** in `docs/DECISIONS.md` when they are made.
