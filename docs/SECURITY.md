# Security and trust

**English** · [Русский](ru/SECURITY.md)

XrayBar asks for your administrator password and sits in the path of all your traffic.
You should not have to trust the author to use it. This document says what the app
does, what it can and cannot protect against, and how to check it yourself.

## Trust model in one paragraph

Don't trust binaries: build from source (`swift build`, ~30 s, Command Line Tools only).
Don't trust the author's word about the source: it is small enough to read, and
`scripts/audit.sh` plus `docs/AUDIT.md` let you (or an AI model you run) check it.
Don't trust downloads: Xray-core and `.dat` files are verified against upstream checksums.
Xray-core itself is trusted as the upstream XTLS project; XrayBar does not modify it.

## What the app does

| Area | Behaviour | Where |
|---|---|---|
| Root | One admin prompt per Connect runs `xraybar-session.sh`, nothing else | `Sources/XrayBar/Resources/xraybar-session.sh` |
| As root | copies the config to `/var/run/xraybar`, starts xray, sets DNS, waits, stops xray, restores DNS; `--restore` cleans up after a session that died | same script |
| Network (app) | only on request: Xray downloads (the version tested with XrayBar is checked against a SHA-256 pinned in the source, others against their release's `.dgst`), the list of Xray releases (api.github.com), routing data (`.dat`, checked against its published SHA-256). Plus one request to `cp.cloudflare.com/generate_204` through the tunnel after connecting with an Xray version that has not carried traffic yet. Ephemeral session, no cookies or cache | `7-Assets.swift` |
| Files written | `~/Library/Application Support/XrayBar/` (library, generated config, stop file, `core/` with the downloaded Xray and `.dat`); `/var/run/xraybar/` (root: config copy while connected, pids; `/var/db/xraybar/dns.saved` survives reboots; log readable by admin users only, errors only unless Detailed Log is on) | `2-Store.swift`, script |
| Files read | the above; optionally v2rayN's database for one-time import (read-only); the clipboard or a screen area only when you choose an import command (QR decoded on-device by Vision) | `3-Import.swift`, `6-Menu.swift` |
| Processes | the admin prompt (`NSAppleScript`), `xray run -test` for validation; `ditto` to unzip and `xray version` after a download; Apple's `screencapture -i` when you choose *Scan QR Code on Screen…* (you select the area; the capture is deleted after decoding) | `5-Session.swift`, `6-Menu.swift`, `7-Assets.swift` |
| Secrets | profiles are stored as plain JSON (mode 600) in stage 1; Keychain is planned | `2-Store.swift` |

Nothing else: no telemetry, no crash reporting, no update checks, no analytics.

## Threat model

Protects against:
- The app doing something other than what its source says (build it yourself).
- Hidden network activity by the app (single place allowed to do network I/O, grep-able).
- Leftover state: orphaned root processes, leaked routes, DNS left pointing at the tunnel —
  including after a power loss or a killed root script (offered as "Restore" on next launch).
- Root running a config that writes arbitrary files: the script runs its own root-owned
  copy of the config and refuses configs that set log file paths.

Does not protect against (known limitations, stage 1):
- **Malware already running as your user.** It could replace the xray binary or the
  script in user-writable locations before you type your password. This is true of every
  "ask for password, then run a tool from my home folder" design, including v2rayN
  (which additionally pipes your sudo password through stdin). Stage 3 moves the
  privileged part into a root-owned LaunchDaemon, which closes this gap.
- A compromised Xray-core release upstream. The pinned hash proves you got exactly the
  release that was tested, not that it is benign. You can build Xray from source with Go
  and compare. Routing data is checked only against its same-origin checksum.
- Traffic analysis or anything outside Xray's own security properties.

## About the app bundle

`scripts/make-app.sh` signs the bundle ad hoc. `codesign --verify --strict XrayBar.app` then
tells you whether anything in it, including the root script, changed since it was built. An
ad-hoc signature carries no identity: whoever can modify the bundle can also re-sign it, so it
detects accidents and naive tampering, not a determined local attacker (stage 3 addresses that).
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

Open an issue, or for anything sensitive contact the maintainer privately first.
