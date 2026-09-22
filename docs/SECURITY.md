# Security and trust

**English** · [Русский](ru/SECURITY.md)

XrayBar asks for your administrator password and sits in the path of all your traffic.
You should not have to trust the author to use it. This document says what the app
does, what it can and cannot protect against, and how to check it yourself.

## Trust model in one paragraph

Don't trust binaries you cannot trace: build from source (`scripts/make-app.sh`, Command Line
Tools only), or take a release, which CI builds from the tagged commit and attests
(`gh attestation verify XrayBar-x.y.z.pkg -R heaprip/xraybar` proves which workflow and commit
produced the file; it does not prove the code is benign, reading it does).
Don't trust the author's word about the source: it is small enough to read, and
`scripts/audit.sh` plus `docs/AUDIT.md` let you (or an AI model you run) check it.
Don't trust downloads: Xray-core and `.dat` files are verified against upstream checksums.
Xray-core itself is trusted as the upstream XTLS project; XrayBar does not modify it.

## What the app does

| Area | Behaviour | Where |
|---|---|---|
| Root | Without the helper: one admin prompt per Connect runs `xraybar-session.sh`. With the helper (optional, *Use Touch ID to Connect…*): a root-owned LaunchDaemon asks macOS to authorize Connect (Touch ID or password, system dialog; once per app run, kept only in XrayBar's own authorization, not shared with other rights or processes) and runs its root-owned copy of the same script | `xraybar-session.sh`, `xraybar-install.sh`, `Sources/XrayBarHelper/main.swift` |
| As root | copies the config to `/var/run/xraybar` and replaces its log section (stdout only), starts xray (only a root-owned version, see below), sets DNS (and moves that setting to the new network service when the network switches), waits for events (`XrayBarHelper --watch`, which only observes: processes, the stop file, the network), stops xray, restores DNS; `--restore` cleans up after a session that died | same script |
| Xray versions | a download or v2rayN's xray is staged in the user's folder, then copied by root (one administrator prompt, `xraybar-install.sh --xray`) into `/Library/Application Support/XrayBar/xray/<version>/xray`, root-owned, and checked against the SHA-256 the app took. The session refuses any other xray | `xraybar-install.sh`, `6-Actions.swift` |
| Network (app) | only on request: Xray downloads (the version tested with XrayBar is checked against a SHA-256 pinned in the source, others against their release's `.dgst`), the list of Xray releases (api.github.com), routing data (`.dat`, checked against its published SHA-256). Plus one request to `cp.cloudflare.com/generate_204` through the tunnel after connecting with an Xray version that has not carried traffic yet. Ephemeral session, no cookies or cache | `7-Assets.swift` |
| Files written | `~/Library/Application Support/XrayBar/` (library, generated config, stop file, `core/` with the `.dat` files, `download/` while a download waits for installation); `/Library/Application Support/XrayBar/xray/` (root: installed Xray versions; kept when the helper is uninstalled); `/var/run/xraybar/` (root: config copy while connected, pids; `/var/db/xraybar/dns.saved` survives reboots; log readable by admin users only, errors only unless Detailed Log is on) | `2-Store.swift`, script |
| Files read | the above; optionally v2rayN's database for one-time import (read-only); the clipboard only when you choose *Import Link or QR Code from Clipboard* (QR decoded on-device by Vision; the app never captures the screen) | `3-Import.swift`, `6-Actions.swift` |
| Processes | the admin prompt (`NSAppleScript`), `xray run -test` for validation; `ditto` to unzip and `xray version` after a download; `route -n get` before Connect (is another VPN active?) | `5-Session.swift`, `7-Assets.swift` |
| Secrets | each server's VLESS id (its credential) is kept in one login-keychain item, "XrayBar server credentials"; `library.json` (mode 600) holds the rest. If the keychain cannot be read or written, the ids stay in `library.json`. While connecting, the generated config (mode 600) holds them until the root session has its own copy | `2-Store.swift` |

Nothing else: no telemetry, no crash reporting, no update checks, no analytics. The link in
*About XrayBar* opens in your browser only when you click it. The app logs its state changes and
alerts to the system log (subsystem `io.github.heaprip.xraybar`); server names, addresses and
error details are marked private there.

## Threat model

Protects against:
- The app doing something other than what its source says (build it yourself).
- Hidden network activity by the app (single place allowed to do network I/O, grep-able).
- Leftover state: orphaned root processes, leaked routes, DNS left pointing at the tunnel —
  including after a power loss or a killed root script (offered as "Restore" on next launch).
- Root running a binary from your user account: the session runs only an xray that root
  installed into its own folder, so replacing a file in your folders changes nothing that
  runs as root. Installing a version asks for your password.
- Root running a config that writes arbitrary files: the script runs its own root-owned
  copy of the config and writes its log section itself (plutil re-serializes the whole file,
  so escaped or duplicate keys cannot smuggle a log path in).

Does not protect against (known limitations):
- **Malware already running as your user.** Without the helper it could replace the
  session script before you type your password. With the helper installed, the root logic
  (helper, script and xray) is root-owned and cannot be changed without admin rights. The
  config and the routing data (`.dat`) still come from your user account: root rewrites the
  config's log section, but its servers and routes are taken as your choice, so such malware
  could send your traffic elsewhere. It could also trigger the authorization dialog itself.
  v2rayN runs its cores from user-writable folders and pipes your sudo password through stdin.
- A compromised Xray-core release upstream. The pinned hash proves you got exactly the
  release that was tested, not that it is benign. You can build Xray from source with Go
  and compare. Routing data is checked only against its same-origin checksum.
- Traffic analysis or anything outside Xray's own security properties.
- Mistakes nobody has caught yet: the code was written with an AI agent and no independent
  macOS specialist has reviewed it yet (README, "How it was built").

## About the app bundle

`scripts/make-app.sh` signs the bundle ad hoc. `codesign --verify --strict XrayBar.app` then
tells you whether anything in it, including the root script, changed since it was built. An
ad-hoc signature carries no identity: whoever can modify the bundle can also re-sign it, so it
detects accidents and naive tampering, not a determined local attacker. There is no Developer
ID and no notarization (D48): macOS asks you to allow the first open, and the keychain item
asks once more after each update, since an ad-hoc signed update is a different app to it.
Open at Login uses a standard login item (System Settings › General › Login Items).

## How to verify

1. `scripts/audit.sh` — deterministic inventory: size budget, every use of process
   execution, networking, file writes, privilege, dynamic loading, obfuscation-like code.
   Its output should match the table above.
2. `docs/AUDIT.md` — a review checklist that doubles as a prompt for an AI model.
3. Read `Sources/XrayBar/*.swift` in numeric order and the session script. That is the
   whole app.
4. Watch it run: `sudo fs_usage -w -f filesys XrayBar`, `nettop -p XrayBar`, and
   `ps -axo pid,user,command | grep xray` before and after Disconnect.

## Reporting

A vulnerability: report it privately with *Report a vulnerability* on the repository's
[Security tab](https://github.com/heaprip/xraybar/security/advisories/new), not in an issue.
Anything else: open an issue.
