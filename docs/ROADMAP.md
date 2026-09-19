# Roadmap

**English** · [Русский](ru/ROADMAP.md)

## Stage 0 — feasibility (done, 2026-09-21)
- Xray native TUN on macOS validated with a standalone PoC on real traffic (see D1–D3).

## Stage 1 — Connect from the menu (done, 2026-09-21)
- Menu: status, Connect/Disconnect, profile picker, routing set picker, log, Quit.
- Profiles: VLESS (Reality/TLS, raw). Import `vless://` from the clipboard.
- One-time read-only import of profiles and routing sets from v2rayN.
- Config generator matching v2rayN's TUN-mode behaviour, covered by tests.
- Privileged session script: start xray, set/restore DNS, stop on disconnect/app exit.
- Verified by the author on real traffic: import from v2rayN, connect, DNS through the tunnel.

## Stage 2 — configurations done properly
- ✅ QR: show a server as QR (Share Server…); import a link or a QR screenshot (⌘⇧⌃4) from the clipboard (Vision).
- ✅ Remove servers and routing sets (hold Option in the menu). No editor windows (decided: not needed).
- ✅ Own copy of Xray and `.dat` files, downloaded on request, checksum-verified (runetfreedom or Loyalsoldier data).
- ✅ Several Xray versions side by side; newer releases on request; the first connection with a new
  version is a trial with one-click switch back to the last working one.
- ✅ Tunnel exclusions: IPv4 networks routed by the system outside the tunnel (Exclude from Tunnel…).
- More transports if needed (xhttp, ws, grpc), other protocols only on demand.

## Stage 3 — solid
- ✅ Privileged LaunchDaemon helper (optional): Touch ID or password per Connect via the system dialog (D28).
- Credentials in Keychain.
- Sleep/wake, network switch, IPv6 verified.
- ✅ `.app` bundle script with ad-hoc signing, Open at Login (done early, independent of the helper).
- Developer ID/notarization only if distributed.
