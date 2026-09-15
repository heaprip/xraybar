# Principles

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
2. **Feels like macOS.** Native `NSMenu`, SF Symbols, system dialogs, system
   settings windows. No custom chrome, no web views, no invented widgets.
   When in doubt, do what a built-in Apple menu extra would do.
3. **Quiet.** No network access by the app itself except updates the user
   explicitly starts. No telemetry, no update pings, no analytics.
4. **Leaves the system as it found it.** Routes, DNS and processes are restored on
   disconnect, on quit and after a crash.

## Engineering principles

1. **Small enough to read in one sitting.** The whole app is a few linear Swift
   files meant to be read top to bottom, plus one privileged shell script.
   A hard size budget is enforced by `scripts/audit.sh`.
2. **Zero third-party code** in the app. Apple SDK only. Xray-core and the `.dat`
   files are the only external artifacts and are verified by checksum.
3. **Flow over abstraction.** Prefer a straight sequence of steps a reviewer can
   follow over layers, protocols and dependency injection. Split code only along
   real boundaries: UI, config generation, privileged execution.
4. **Privilege is tiny and visible.** Everything that runs as root lives in one
   short shell script with a fixed set of actions.
5. **Port, don't invent.** Behaviour that v2rayN already got right (TUN inbound,
   rule expansion, DNS split) is ported from its source, with a reference.
6. **Decisions are written down** in `docs/DECISIONS.md` when they are made.
