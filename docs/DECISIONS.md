# Decisions

Short records of decisions and the evidence behind them. Newest last.
Format: context → decision → consequences.

## D1. Xray native TUN, no sing-box or tun2socks (2026-09-21)

v2rayN ≤ 7.23 on macOS always ran TUN through sing-box and piped traffic over a local
SOCKS hop into xray (`ConfigHandler.GetPreSocksItem` forced "legacy protect" on non-Windows).
Measured on the author's machine: GUI 280 MB + xray 85 MB + root sing-box 69 MB, plus a
leaked orphan xray. v2rayN ≥ 7.24 can use Xray's own `tun` inbound; a standalone PoC with
Xray 26.5.9 confirmed on real traffic: utun creation, `autoSystemRoutingTable` routes,
geosite/geoip routing, UDP/QUIC, DNS hijack on port 53.

→ Xray-core is the only data plane. The `tun` inbound installs the routes itself.

## D2. No `process` routing rules (2026-09-21)

Xray 26.5.9 on darwin logs `process lookup is not supported on this platform` for every
connection that reaches a `process` rule; the rule never matches. Loop prevention is done
by `autoOutboundsInterface: "auto"` (outbounds bind to the physical interface).
Xray 26.9.9 appears to add darwin support; revisit when needed.

→ The generator emits no `process` rules.

## D3. System DNS is set explicitly while connected (2026-09-21)

The `dns` field of the `tun` inbound has no effect on macOS: the system resolver stays on
the LAN router (192.168.1.1), which is reached via the more specific LAN route, so DNS
bypasses the tunnel. Same behaviour observed in v2rayN.

→ On connect, the privileged session sets the active network service's DNS to servers
that route into the tunnel (hijacked to Xray's DNS module); on disconnect it restores the
previous value.

## D4. Root via an admin prompt per connect, for now (2026-09-21)

Creating a utun needs root. Options: password on every connect (`osascript … with
administrator privileges`), a sudoers rule, or a LaunchDaemon helper.

→ Stage 1–2: one admin prompt per Connect, running a single auditable script
(`xraybar-session.sh`) that owns the whole root lifetime. It stops Xray and restores DNS
when the app asks, when the app process dies, or when Xray exits, so Disconnect needs no
second prompt and nothing is left orphaned.
→ Stage 3: replace with a LaunchDaemon helper.

## D5. PIDs are never found by pattern (2026-09-21)

The PoC stop script matched `xray run -c` and killed v2rayN's xray instead of its own,
leaving its routes in place and breaking v2rayN ("failed to add system route … file exists").

→ Only the PID of the process the session script itself started is ever signalled.

## D6. Routing rules use v2rayN's rule shape (2026-09-21)

`RulesItem` (domain, ip, port, network, protocol, outboundTag, enabled, remarks) is simple,
and keeping it lets existing v2rayN routing sets and runetfreedom templates import as-is.
One UI rule expands into separate Xray rules for domain and ip (v2rayN `GenRoutingUserRule`).

## D7. Language and size (2026-09-21)

Swift + AppKit (`NSStatusItem`/`NSMenu`), SwiftUI only for editor windows, Swift Package
Manager, Command Line Tools only (no Xcode). macOS 14+. Tests with Swift Testing.
Source is a few numbered files read in order; budget enforced by `scripts/audit.sh`.

## D8. Stage-1 assets come from an existing Xray install (2026-09-21)

Until XrayBar ships its own verified copy, the xray binary and `.dat` files are taken
from a configurable directory (default: v2rayN's `bin`). Known limitation: that directory
is user-writable, see `docs/SECURITY.md`.

## D9. MIT license; v2rayN is a behaviour reference, not a code source (2026-09-21)

The author wants a permissive license (MIT/Apache). v2rayN is GPL-3.0, so translating its
code would make XrayBar a derivative work. What XrayBar needs from v2rayN is behaviour
(which Xray config shape works in TUN mode, how a rule with domains and IPs is split) and
formats (routing-set JSON, share links), which can be implemented independently.

→ XrayBar is MIT. v2rayN's source is read to understand behaviour; the Swift is written from
Xray's documentation and observed configs, never translated line by line (CLAUDE.md).
Stage-1 code was reviewed against this rule and its "ported from" wording removed.
Not legal advice; if the project gains contributors, keep this rule in review.

## D10. Docs: English primary, Russian mirror (2026-09-21)

→ `README.md` + `docs/*.md` in English; `README.ru.md` + `docs/ru/*.md` in Russian for README,
PRINCIPLES, SECURITY, AUDIT and ROADMAP, linked by a language line at the top of each file
(the common GitHub convention; the wiki is not versioned with the code, so it is not used).
DECISIONS stays English only. Both languages change in the same commit.

## D11. Root session log is admin-readable only (2026-09-21)

The Xray log lists every host visited. → `/var/run/xraybar/xray.log` is `root:admin 0640`.

## D12. The root script is parsed whole before it runs (2026-09-21)

bash reads a script file incrementally while executing it. Rebuilding the app during a
session replaces the file under a running root shell, which would then continue at its old
byte offset in the new file. → The script body is a single `{ … }` block ending in `exit`.

## D13. Errors-only log by default; root PATH pinned (2026-09-21)

With the access log on, a few minutes of browsing produced ~300 lines, one per connection.
→ Default `loglevel: error`, `access: none`. A **Detailed Log** menu toggle restores
warnings and the access log for diagnosing routing; it applies on the next Connect.
The root script accepts only empty or `"none"` log paths.
→ The root script sets `PATH=/usr/bin:/bin:/usr/sbin:/sbin` so it only ever runs system tools.
→ Tests run through `scripts/test.sh`: CLT's SwiftPM builds the test target's emit-module job
without the Swift Testing macro plugin; the script passes the plugin path explicitly.
