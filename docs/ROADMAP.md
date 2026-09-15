# Roadmap

## Stage 0 — feasibility (done, 2026-09-21)
- Xray native TUN on macOS validated with a standalone PoC on real traffic (see D1–D3).

## Stage 1 — Connect from the menu (in progress)
- Menu: status, Connect/Disconnect, profile picker, routing set picker, log, Quit.
- Profiles: VLESS (Reality/TLS, raw). Import `vless://` from the clipboard.
- One-time read-only import of profiles and routing sets from v2rayN.
- Config generator ported from v2rayN, covered by tests.
- Privileged session script: start xray, set/restore DNS, stop on disconnect/app exit.

## Stage 2 — configurations done properly
- QR: show a profile as QR; import from an image or the clipboard (Vision).
- Edit/duplicate/delete profiles; routing rules editor (SwiftUI window).
- Own copy of Xray and `.dat` files, downloaded on request, checksum-verified.
- Route exclusions (CIDR subtraction, from v2rayN).
- More transports if needed (xhttp, ws, grpc), other protocols only on demand.

## Stage 3 — solid
- Privileged LaunchDaemon helper instead of an admin prompt per connect.
- Credentials in Keychain.
- Sleep/wake, network switch, IPv6 verified.
- `.app` bundle script, ad-hoc signing; Developer ID/notarization only if distributed.
