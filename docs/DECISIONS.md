# Decisions

Short records of decisions and the evidence behind them. Newest last.
Format: context → decision → consequences.

## D1. Xray native TUN, no sing-box or tun2socks (2026-09-15)

v2rayN ≤ 7.23 on macOS always ran TUN through sing-box and piped traffic over a local
SOCKS hop into xray (`ConfigHandler.GetPreSocksItem` forced "legacy protect" on non-Windows).
Measured on the author's machine: GUI 280 MB + xray 85 MB + root sing-box 69 MB, plus a
leaked orphan xray. v2rayN ≥ 7.24 can use Xray's own `tun` inbound; a standalone PoC with
Xray 26.5.9 confirmed on real traffic: utun creation, `autoSystemRoutingTable` routes,
geosite/geoip routing, UDP/QUIC, DNS hijack on port 53.

→ Xray-core is the only data plane. The `tun` inbound installs the routes itself.

## D2. No `process` routing rules (2026-09-15)

Xray 26.5.9 on darwin logs `process lookup is not supported on this platform` for every
connection that reaches a `process` rule; the rule never matches. Loop prevention is done
by `autoOutboundsInterface: "auto"` (outbounds bind to the physical interface).
Xray 26.9.9 appears to add darwin support; revisit when needed.

→ The generator emits no `process` rules.

## D3. System DNS is set explicitly while connected (2026-09-15)

The `dns` field of the `tun` inbound has no effect on macOS: the system resolver stays on
the LAN router (192.168.1.1), which is reached via the more specific LAN route, so DNS
bypasses the tunnel. Same behaviour observed in v2rayN.

→ On connect, the privileged session sets the active network service's DNS to servers
that route into the tunnel (hijacked to Xray's DNS module); on disconnect it restores the
previous value.

## D4. Root via an admin prompt per connect, for now (2026-09-15)

Creating a utun needs root. Options: password on every connect (`osascript … with
administrator privileges`), a sudoers rule, or a LaunchDaemon helper.

→ Stage 1–2: one admin prompt per Connect, running a single auditable script
(`xraybar-session.sh`) that owns the whole root lifetime. It stops Xray and restores DNS
when the app asks, when the app process dies, or when Xray exits, so Disconnect needs no
second prompt and nothing is left orphaned.
→ Stage 3: replace with a LaunchDaemon helper.

## D5. PIDs are never found by pattern (2026-09-15)

The PoC stop script matched `xray run -c` and killed v2rayN's xray instead of its own,
leaving its routes in place and breaking v2rayN ("failed to add system route … file exists").

→ Only the PID of the process the session script itself started is ever signalled.

## D6. Routing rules use v2rayN's rule shape (2026-09-15)

`RulesItem` (domain, ip, port, network, protocol, outboundTag, enabled, remarks) is simple,
and keeping it lets existing v2rayN routing sets and runetfreedom templates import as-is.
One UI rule expands into separate Xray rules for domain and ip (v2rayN `GenRoutingUserRule`).

## D7. Language and size (2026-09-15)

Swift + AppKit (`NSStatusItem`/`NSMenu`), SwiftUI only for editor windows, Swift Package
Manager, Command Line Tools only (no Xcode). macOS 14+. Tests with Swift Testing.
Source is a few numbered files read in order; budget enforced by `scripts/audit.sh`.

## D8. Stage-1 assets come from an existing Xray install (2026-09-15)

Until XrayBar ships its own verified copy, the xray binary and `.dat` files are taken
from a configurable directory (default: v2rayN's `bin`). Known limitation: that directory
is user-writable, see `docs/SECURITY.md`.

## D9. MIT license; v2rayN is a behaviour reference, not a code source (2026-09-15)

The author wants a permissive license (MIT/Apache). v2rayN is GPL-3.0, so translating its
code would make XrayBar a derivative work. What XrayBar needs from v2rayN is behaviour
(which Xray config shape works in TUN mode, how a rule with domains and IPs is split) and
formats (routing-set JSON, share links), which can be implemented independently.

→ XrayBar is MIT. v2rayN's source is read to understand behaviour; the Swift is written from
Xray's documentation and observed configs, never translated line by line (CLAUDE.md).
Stage-1 code was reviewed against this rule and its "ported from" wording removed.
Not legal advice; if the project gains contributors, keep this rule in review.

## D10. Docs: English primary, Russian mirror (2026-09-15)

→ `README.md` + `docs/*.md` in English; `README.ru.md` + `docs/ru/*.md` in Russian for README,
PRINCIPLES, SECURITY, AUDIT and ROADMAP, linked by a language line at the top of each file
(the common GitHub convention; the wiki is not versioned with the code, so it is not used).
DECISIONS stays English only. Both languages change in the same commit.

## D11. Root session log is admin-readable only (2026-09-15)

The Xray log lists every host visited. → `/var/run/xraybar/xray.log` is `root:admin 0640`.

## D12. The root script is parsed whole before it runs (2026-09-15)

bash reads a script file incrementally while executing it. Rebuilding the app during a
session replaces the file under a running root shell, which would then continue at its old
byte offset in the new file. → The script body is a single `{ … }` block ending in `exit`.

## D13. Errors-only log by default; root PATH pinned (2026-09-16)

With the access log on, a few minutes of browsing produced ~300 lines, one per connection.
→ Default `loglevel: error`, `access: none`. A **Detailed Log** menu toggle restores
warnings and the access log for diagnosing routing; it applies on the next Connect.
The root script accepts only empty or `"none"` log paths.
→ The root script sets `PATH=/usr/bin:/bin:/usr/sbin:/sbin` so it only ever runs system tools.
→ Tests run through `scripts/test.sh`: CLT's SwiftPM builds the test target's emit-module job
without the Swift Testing macro plugin; the script passes the plugin path explicitly.

## D14. Clean up after sessions that died (2026-09-16)

`/var/run` is emptied at boot, so a DNS backup kept there is lost on power loss while
connected, leaving the Wi-Fi DNS overridden with nothing to restore it from. A root script
killed while xray keeps running blocked the next Connect ("already running") and made
Disconnect wait forever.

→ The saved DNS lives in `/var/db/xraybar/dns.saved`. The session records its own PID
(`session.pid`); xray alive without its session is "stale". Every Connect cleans up stale
state first, and `xraybar-session.sh --restore` does only that. The app detects leftovers at
launch and offers **Restore** (one password prompt); the menu shows **Restore Network
Settings…** while leftovers exist. A stale xray is stopped only if its PID, recorded by the
session, still runs `xray run -c /var/run/xraybar/config.json` (PIDs can be reused).
→ The root-owned config copy (it holds credentials) is deleted when a session ends.

## D15. XrayBar's own Xray and routing data, verified, on request (2026-09-16)

Depending on v2rayN's `bin` ties XrayBar to another app's update cycle (v2rayN 7.24.9 broke
TUN) and to files nobody verified.

→ *Update Xray and Routing Data* downloads the latest Xray release zip for this CPU and
`geoip.dat`/`geosite.dat` from the chosen source (runetfreedom by default, or Loyalsoldier),
into `~/Library/Application Support/XrayBar/core` (v2rayN's layout). Each file is checked
against the SHA-256 published in the same release (`.dgst` `SHA2-256=` line for Xray,
`*.sha256sum` for the data) in a staging directory; nothing replaces the current copy unless
every file passes. Ephemeral URLSession. This file (`7-Assets.swift`) is the only network code.
→ No automatic updates or update checks (PRINCIPLES: quiet). Same-origin checksums prove
integrity in transit, not upstream honesty (SECURITY).
→ Until the first download, v2rayN's copy is used, as before (D8).

## D16. QR codes with system frameworks only (2026-09-16)

→ Share: `Import.link(for:)` writes the standard `vless://` link; CoreImage's QR generator
draws it inside a plain `NSAlert` with *Copy Link*. Import: *Import from Clipboard* accepts a
link or a copied image; *Import QR Code from Image…* takes a file. Decoding is Vision's
`VNDetectBarcodesRequest`, on-device. No screen scanning (it would need the Screen Recording
permission); a screenshot copied to the clipboard covers that case.

## D17. Long menu sections, removal, no editors (2026-09-17)

The author decided editor windows are not needed. Imported lists grow (4 servers, 9 routing
sets after a v2rayN import), and duplicate names were indistinguishable.

→ A section shows up to four choices inline; with more, the selected one stays inline and the
rest move to an "Other …" submenu (the Wi-Fi menu pattern; NSMenu has no collapsible sections).
→ A name used more than once is shown with the server address or the rule count.
→ Holding Option turns each choice into "Remove “…”…" with a confirmation (NSMenu alternates).
→ Downloads retry twice on HTTP 5xx or network errors (GitHub returned 504 in testing).
→ Until XrayBar is a bundled .app, alerts use an SF Symbol as the app icon.

## D18. QR import by scanning the screen with Apple's screencapture (2026-09-17)

Saving a screenshot to a file to import a QR code is the most common annoyance in clients.
→ *Scan QR Code on Screen…* runs `/usr/sbin/screencapture -i -x <temp file>`: the system
crosshair, the user selects the code, Vision decodes it, the file is deleted. XrayBar does not
capture the screen itself and asks for no Screen Recording permission of its own. It replaces
*Import QR Code from Image…* (open the image in Preview and scan it instead).

## D19. Tunnel exclusions by subtracting from the TUN routes (2026-09-17)

Some networks must not enter Xray at all (a work network behind another VPN, an unusual LAN).
A `direct` rule is not enough: that traffic still passes through the tunnel and Xray.

→ *Exclude from Tunnel…* takes IPv4 addresses/CIDRs (validated, stored in settings). The
generator sets `autoSystemRoutingTable` to 0.0.0.0/0 minus those networks: a network that
partly overlaps an exclusion is halved until each half is fully in or out, which yields the
minimal list (one excluded address → 32 routes). Excluded networks keep their normal system
route. Same idea as v2rayN's RouteExcludeAddress; written independently (`CIDR` in 4-Config).
IPv6 exclusions wait for IPv6 routing (stage 3).

## D20. App bundle now; bundle ID is a placeholder (2026-09-17)

Without a bundle, alerts showed a generic icon, macOS attributes permissions (e.g. screen
capture for QR scanning) to the terminal that launched the binary, and login items are
impossible.

→ `scripts/make-app.sh` builds `build/XrayBar.app` (LSUIElement, resource bundle in
Contents/Resources where SwiftPM's accessor looks) and signs it ad hoc. Menu gains
*Open at Login* via `SMAppService.mainApp`, shown only when running from a bundle.
→ `io.github.xraybar.XrayBar` is a placeholder identifier; change it to a domain the project
controls before any public release.

## D21. Keychain waits for stage 3; generated config deleted once running (2026-09-17)

Keychain items are bound to the app's code signature. With an ad-hoc signature every rebuild
is a "different app", so macOS would ask for Keychain access after each build, and the
generated config would still hold the same credentials in plain text while connecting.
→ Keychain moves with the signed helper in stage 3. Meanwhile the user-side `config.json` is
deleted as soon as the root session runs (it uses its own root-only copy, itself deleted when
the session ends); `library.json` stays mode 0600.

## D22. Pin the tested Xray release and its hash; refuse Xray too old for TUN (2026-09-18)

Since 26.5 every Xray release is marked *pre*release on GitHub, so `releases/latest` served
26.3.27 (March). That version has no `autoSystemRoutingTable`/`autoOutboundsInterface`; Xray
ignores unknown fields, so it brought up a utun no traffic entered, while the session had
already pointed DNS at the tunnel: no connectivity (reported by the author).

→ `7-Assets.swift` pins v26.9.9 and the SHA-256 of its zip per CPU. The hash was cross-checked
three ways: the release's `.dgst`, an independent download, and the unpacked binary is
byte-identical to the xray in v2rayN 7.25.2. A pinned hash in audited source is stronger than
a same-origin checksum; newer Xray ships with a new XrayBar version after testing.
→ Connect refuses Xray older than 26.5.9 with an explanation (`Assets.minimumXray`).
→ The root session no longer changes DNS if Xray installed no routes within 10 s; it fails.
→ Alerts set their icon explicitly (bundled apps otherwise show the empty bundle icon).
→ Scanning the screen from the bundled app triggers macOS's one-time Screen Recording prompt
for XrayBar (screencapture runs on its behalf). Alternative with no permission: ⌘⇧⌃4 copies
a selection to the clipboard, then *Import from Clipboard*.

## D23. User-chosen Xray versions with a trial and a way back (2026-09-18)

The author preferred choosing newer Xray releases over getting only versions blessed by
XrayBar, and wanted to try one safely and return to a working one (something v2rayN lacks).

→ Versions live side by side in `core/xray/<tag>/xray`; *Xray Version ›* lists them (and
v2rayN's), with a checkmark on the one in use and "works"/"not yet tested". *Download v26.9.9
(tested with XrayBar)* keeps the pinned-hash path (D22); *Check for Newer Versions…* lists
GitHub releases ≥ 26.5.9 (all prereleases) via api.github.com and verifies the chosen one
against its release `.dgst`.
→ Trial: after connecting with an xray that has not carried traffic yet, one request to
`https://cp.cloudflare.com/generate_204` goes through the tunnel (3 tries). 204 marks that
xray as the known-good one; otherwise an alert offers *Switch Back* (select the last good
xray, disconnect, connect again). Already-proven versions trigger no request, keeping the
app quiet (PRINCIPLES 3). A failure can also be the server's; the alert says what was tested.
→ Routing data is updated separately (*Update Routing Data*); xray path and data directory
are independent settings.
→ Size budget raised from 1200 to 1400 Swift lines for this feature (1264 now).

## D24. Screen QR via the system content picker; menu regrouped; tunnel conflict check (2026-09-18)

`screencapture` run by the bundled app made macOS ask for Screen Recording on every scan:
TCC binds the grant to the app's designated requirement, which for an ad-hoc signature is the
build's cdhash, so each rebuild is a new app (and a new grant needs a relaunch). A standing
permission to record the screen is also a poor look for a VPN app under audit.
→ *Scan QR Code on Screen…* presents ScreenCaptureKit's `SCContentSharingPicker`: the user
clicks the window or display showing the code, which is consent for that single
`SCScreenshotManager` capture. No Screen Recording permission is requested or kept.
(Replaces D18's screencapture approach. An old XrayBar entry in Privacy & Security › Screen
Recording can be removed.)

The menu had grown a five-line Xray block with "not yet tested" on every version.
→ Main menu: status, servers, routing, import/share, then *Xray v… ›* (versions with "works",
routing data, source, exclusions) and *Diagnostics ›* (log, detailed log, data folder).

Connecting while v2rayN's TUN was on failed deep in the root session with a raw
"failed to add system route … file exists".
→ Before asking for the password, Connect checks which interface carries 1.1.1.1; if it is a
utun that is not ours, it says another VPN/TUN is active and to turn it off.

## D25. App icon drawn from source at build time (2026-09-18)

Without an .icns the bundle showed a blank placeholder in Spotlight and Finder. A committed
.icns would be an opaque binary in a repository meant to be read.
→ `scripts/make-icon.swift` draws the icon (white `shield.fill` on a blue rounded square on
Apple's icon grid) into an .iconset; `make-app.sh` runs it and `iconutil` builds AppIcon.icns.
→ Imports now name what was recognized, including servers that were already in the list, so a
QR scan of an existing server visibly succeeds.

## D26. Correction to D24: the picker works, but macOS still shows its prompt (2026-09-18)

Observed on macOS 26 (system log, replayd/tccd): presenting `SCContentSharingPicker` from an
app without the standing permission makes TCC show its "would like to record this computer's
screen" notice and report a picker start failure, yet the picker stays up and the capture of
the chosen window is allowed through the picker filter (`TCC Allow … contentPickerFilter`,
screenshot created). XrayBar treated the start failure as the end of the scan and dropped the
capture, so scans silently did nothing.

→ Only a selection or a cancel ends a scan; the start-failure callback is ignored. A failed
capture now says so and points to ⌘⇧⌃4 + Import from Clipboard.
→ The prompt can be dismissed with *Deny*; the permission is not needed and should stay off.
D24's "no prompt" statement was wrong.

## D27. No screen capture in XrayBar at all (2026-09-19)

Even with the system picker (D24, D26), macOS 26 showed two system prompts per scan ("would
like to record…", "requesting to bypass the system private window picker…"), and the capture
failed unless the standing permission was granted, which a VPN app should not hold.
→ Screen scanning is removed; ScreenCaptureKit is no longer linked. QR import goes through the
clipboard: ⌘⇧⌃4 (Apple's screenshot tool, run by the user) puts the selection on the
clipboard, and *Import Link or QR Code from Clipboard* accepts that image or a vless:// link.
The menu title and the "nothing to import" message say both work. `audit.sh` expects no
screen-capture APIs.

## D28. Stage 3: a root-owned LaunchDaemon helper, Touch ID per Connect (2026-09-19)

Stage 1–2 run the session script from the app bundle through an admin prompt that accepts
only a password, and user-level malware could alter that script before it runs as root.

→ **Install once** (*Set Up Touch ID…*, one admin prompt via the old path) runs
`xraybar-install.sh` as root, which only: copies `XrayBarHelper` and `xraybar-session.sh` into
`/Library/Application Support/XrayBar/` (root:wheel), writes
`/Library/LaunchDaemons/io.github.xraybar.helper.plist` (socket-activated, `AbandonProcessGroup`
so a session outlives the helper), adds the authorization right `io.github.xraybar.connect`
(admin, not shared, timeout 0: every Connect authenticates), and loads the daemon.
`--uninstall` removes exactly those four things.
→ **Connect**: the app sends the helper, over `/var/run/xraybar-helper.sock`, an
`AuthorizationExternalForm` (no rights) and the session arguments. The helper asks for the
right with interaction allowed, so macOS shows its own dialog (Touch ID or password) in the
user's session: the check happens in root code, not in the app. Then it starts the root-owned
session script. The app PID argument is replaced with the socket peer's PID. *Restore* needs
no authorization (it only cleans up). Disconnect stays the stop file.
→ The helper is ~150 lines of Swift with its own size budget; all root logic stays in the one
session script. The app compares the SHA-256 of its bundled helper and script with the
installed copies and offers *Update Helper…* when they differ. Without the helper everything
works as before (admin prompt per Connect).
→ Still from user space: the xray binary and the config (validated by the script as before).

## D29. A panel instead of a menu (2026-09-19)

An NSMenu closes after every click; the author wanted to pick a server and a routing set in
one go, closing only by clicking outside or on the icon, like the Wi-Fi and Control Center
panels.
→ The UI is a `MenuBarExtra` with `.menuBarExtraStyle(.window)` (App.swift, 8-Panel.swift):
header with a Connect switch and status; Server and Routing choices with checkmarks (up to four
inline, the rest in an "Other …" pop-up; right-click to remove); a footer with the Xray version
and a "⋯" menu for everything else (import, share, Xray versions and data, exclusions,
diagnostics, helper, Open at Login, Quit). The old menu controller became `AppModel`
(6-Actions.swift), observable, with the same actions.
→ Changing server/routing while connected shows "Changes apply after reconnecting — Reconnect"
in the panel instead of an alert.
→ No `@State`: in the macOS 27 SDK it is a macro whose plugin the Command Line Tools lack, so
the App holds the model as a constant and row hover lives in the model.
→ App size budget 1400 → 1500 (1443 now).

## D30. Panel styled after the system's Wi-Fi/Bluetooth modules; a knowing HIG deviation (2026-09-20)

The HIG (The menu bar › Menu bar extras) says: "Display a menu — not a popover — when people
click your menu bar extra. Unless the app functionality you want to expose is too complex for a
menu, avoid presenting it in a popover." XrayBar deviates on purpose (D29: the author wants to
pick a server and routing set without the menu closing each time), so the panel copies the
closest system precedent, the Wi-Fi and Bluetooth modules, instead of inventing a look:
→ title with a switch; rows with a 26 pt round icon, blue for the one in use (no checkmarks),
the connection state under the selected server; "Other …" rows with a chevron that expand in
place below the list; a plain "XrayBar Options" row at the bottom (the "Wi-Fi Settings…"
position) opening the menu with everything else.
→ Background: `NSVisualEffectView` with the `.menu` material, blending behind the window and
kept active; MenuBarExtra's own background follows window activity and looked opaque.
→ Reference for visuals: Apple Design Resources (macOS UI kit). If a future macOS restyles its
modules, follow it; the HIG's own preference, a plain menu, remains the fallback.

## D31. Libraries allowed; Control Center look from MacControlCenterUI's measurements (2026-09-20)

The author clarified that "minimal" means the app itself, not zero dependencies (PRINCIPLES 2
and CLAUDE.md updated). The obvious library for a Control Center–style panel is
orchetect/MacControlCenterUI (MIT, maintained, ~2,400 lines + MenuBarExtraAccess), but it does
not build with the Command Line Tools: it uses `@State` (a macro on the macOS 27 SDK) and
`#Preview`, whose plugins ship only with Xcode (checked with SDK 27 and 26.5).
→ The panel stays our own (~200 lines) with the library's macOS 26 measurements, attributed in
8-Panel.swift and the README: width 310; content inset 14; highlight inset 6 with 10 pt
continuous corners; row padding 4; round icons 26; section titles 13 pt semibold at 60 % white
(dark) / 70 % black (light); hover white 0.3 @ 40 % (dark) / white 0.9 @ 20 % (light); the
glass comes from `backgroundStyle(.ultraThinMaterial)` on 26 and `.regularMaterial` on 27,
drawn by the system (replaces D30's NSVisualEffectView workaround).
→ If the project ever requires Xcode, switching to the package itself is a small change.
→ App size budget 1500 → 1600 (1513 now): the Control Center panel and its measurements.

## D32. Panel rows are not Buttons; make-app always recompiles (2026-09-20)

Live on macOS 26 the rows were squeezed to ~19 pt (icons overlapping) although the same view
laid out at 30 pt in an NSHostingView: inside a MenuBarExtra window macOS restyles `Button`s,
and our ButtonStyle's padding was lost. MacControlCenterUI builds its rows without Button.
→ Rows are content with a fixed height (icon row 30, section row 20 + 4) plus `onTapGesture`
and `onHover` (the `row(height:highlighted:action:)` modifier), like the library.
→ SwiftPM under the CLT sometimes skipped a just-edited file ("Build complete (0.15 sec)"),
so a release could contain old code. `make-app.sh` touches the sources before building.

## D33. Closer to Wi-Fi: gray circles, hover-only disclosure, icons in the menu (2026-09-21)

Compared side by side with the live Wi-Fi panel once rows had their real height (D32):
→ Rows not in use sit on a gray circle (Wi-Fi's other networks), the one in use on a blue one.
→ "Other …" is shaded only under the pointer, not while expanded.
→ "XrayBar Options" items carry SF Symbols, as macOS 26 menus do (Karabiner, Battery).

## D34. Back to a standard menu (HIG); connect at launch (2026-09-21)

After D29–D33 the panel came close to Wi-Fi but stayed hand-made. Karabiner-Elements, which the
author found indistinguishable from the system, is a default-style `MenuBarExtra`: SwiftUI
buttons with `Label(…, systemImage:)`, rendered by the system as an NSMenu. The author chose
the HIG over a menu that stays open: once connected, people rarely open it.
→ UI is `AppMenu` (8-Menu.swift): status, Connect/Disconnect, Server and Routing sections with
system checkmarks (up to four inline, the rest in "Other …" submenus), import/share, a
*Remove ›* submenu (menus have no right-click), *Xray v… ›*, *Diagnostics ›*, helper, toggles,
Quit. The panel code (metrics, rows, hover, blur) is gone.
→ *Connect at Launch* (setting, on by default): at startup XrayBar connects to the last used
server unless a restore is pending, no server exists, or another VPN owns the routes. It still
authorizes (Touch ID with the helper, else the password): an unauthenticated connect would let
any process of the user make root run an xray binary from a user-writable folder. With
*Open at Login* the user needs no click, only the one authentication.

## D35. Option alternates back; macOS 15 minimum (2026-09-21)

The author missed the Option-to-remove items of the NSMenu era (D17); D34's *Remove ›* submenu
was a detour because it was not checked whether SwiftUI menus support alternates. They do:
`modifierKeyAlternate(.option)`, macOS 15+.
→ Minimum macOS 14 → 15 (no reason for 14 was ever recorded; the author runs 26).
→ With Option held: servers and routing sets turn into "Remove “…”…"; the status line shows
technical details (tunnel interface, Xray version, DNS, Touch ID or password), as the system
Wi-Fi menu does; *Share Server…* becomes *Copy Server Link*. The Remove submenu is gone.

## D36. Published as heaprip/xraybar; final identifiers (2026-09-21)

→ Public repository github.com/heaprip/xraybar. Bundle ID `io.github.heaprip.xraybar`
(replaces the D20 placeholder), helper label `io.github.heaprip.xraybar.helper`, authorization
right `io.github.heaprip.xraybar.connect`. The install script also removes the pre-release
`io.github.xraybar.*` helper, plist and right. Open at Login must be enabled again (login
items are bound to the bundle ID). Version 0.2.0.
→ Before publishing, history was scanned for personal data: a real server IP used in a CIDR
test was replaced with 203.0.113.7 (RFC 5737 documentation range) in every commit.

## D37. No roadmap file; no emoji in docs (2026-09-21)

→ The author removed docs/ROADMAP.md: the history and DECISIONS already tell what was done, and a
roadmap with checkmark emoji added noise. What is not done yet is one line in the README status.

## D38. Root runs only a root-owned xray; root writes the log section (2026-09-21)

An outside review found two holes in the root model. (1) The session ran the xray path it was
given, and every candidate lived in the user's folders (`core/xray/<tag>/xray`, v2rayN's
`bin/xray`). Malware running as the user could replace that file and have it started as root
at the next Connect, which with Connect at Launch and Touch ID is a routine, reflexive
approval; the root-owned helper did not help. (2) The session rejected log paths with a grep
over the config, which `"access"` (valid JSON for `"access"`) passed: root could still be
made to write a file.

→ Xray versions live in `/Library/Application Support/XrayBar/xray/<tag>/xray`, root:wheel 755.
`xraybar-install.sh --xray <tag> <binary> <sha256>` puts one there: root copies the binary
first, then checks the copy against the SHA-256 the app took, so a file changed in between is
refused. This runs through the administrator prompt (password, with its own prompt text),
also when the helper is installed: installing a binary is a distinct consent from the daily
Touch ID for Connect. Downloads are staged in `~/…/XrayBar/download` and removed after.
→ The session script accepts only `<store>/<tag>/xray`, a root-owned 755 regular file, and
refuses anything else. The helper is unchanged: it passes arguments to the script, which now
checks them. An old installed script still accepts the new paths; *Update Helper…* appears
because the bundled script differs.
→ v2rayN's xray is no longer run where it is: *Copy Xray from v2rayN…* installs a copy under
the tag `v2rayN`. With nothing installed, Connect explains how to get Xray; the chosen version
falls back to the newest installed one. Older downloads in `core/xray` (user-owned) are ignored
and deleted after the first root install; older `xrayBinary`/`goodXray` paths simply no longer match.
→ The session replaces the config's `log` section with `plutil -replace log -json …`, keeping
only a validated `loglevel` and `access` "none" or "" (stdout). plutil parses and re-serializes
the whole file, so escapes and duplicate keys are resolved before xray sees it; invalid JSON
stops the session. A unit test checks that the rest of the config comes through unchanged.
→ `--uninstall` of the helper keeps the xray store (connecting without the helper needs it).
→ Still from user space, documented in SECURITY.md: the config's servers and routes, and the
`.dat` files. Root-script budget 220 → 250 lines.

## D39. Connect off the main thread; the menu reads cached state (2026-09-21)

The same review: Connect ran `xray run -test` (seconds, it loads geosite.dat) and waited for
the helper's Touch ID dialog on the main thread, so the menu bar app hung meanwhile; the menu
body hashed the helper files and listed directories on every redraw, with a `tick` counter
to make SwiftUI notice.
→ Connect shows *Connecting…* at once; validation and the helper request run in detached
tasks. A Disconnect chosen meanwhile wins (the start is skipped). The 15 s start timeout
counts from the privileged start, not from the click.
→ `AppModel` keeps what the menu shows from disk (installed versions, helper state, restore
needed, login item) and refreshes it after each state change or action; `tick` is gone.
→ The 1 s status timer has 0.5 s tolerance, so macOS can coalesce its wakeups.

## D40. IPv6 enters the tunnel when the Mac has a global IPv6 address (2026-09-21)

The TUN routes were IPv4 only (`0.0.0.0/0`). On a network with global IPv6 (many mobile
hotspots and ISPs) IPv6 followed the system's default route around Xray: a leak, for example
from a browser with its own DNS-over-HTTPS resolver getting AAAA answers (the system DNS
already returns none, `queryStrategy: UseIPv4`).
→ At Connect, if an interface that is up, not loopback and not a utun holds an address in
2000::/3, `autoSystemRoutingTable` gets `::/0` as well. Without one there is nothing to leak,
and IPv6 sent into the tunnel could not get out, so it is left out. This is v2rayN's current
behaviour (read in `.ref`, written from scratch): no IPv6 address on the TUN, only the route.
IPv6 destinations are then routed by the same rules (proxy, direct or block).
→ Route exclusions stay IPv4. The decision is taken at Connect; a network change later is
covered by reconnecting (network switches are not handled yet, README).
→ Not verified on a real IPv6 network yet: the author's home network has only ULA addresses,
where nothing changes. To test: connect via a hotspot with IPv6, then
`curl -6 https://ifconfig.co` should show the server's address (or fail), not the ISP's.

## D41. The DNS override follows a network switch (2026-09-21)

The session set DNS on the service that was primary at Connect (D3). After a switch, say from
Wi-Fi to Ethernet or to a hotspot on another service, the new primary service kept its own DNS
servers, usually the router's: on the local network and therefore routed outside the tunnel,
so every name lookup leaked to the local network and ISP.
→ The session's wait loop compares the default route's interface every second (one `route`
call; `networksetup` only when it changed). When another interface with a network service
takes over, it restores the old service's DNS and overrides the new one's, recording it in
`dns.saved` as before, so restore after a crash still knows which service to fix. With no
default route (network down) nothing changes until one appears.
→ Considered: a non-persistent override through `scutil` (`State:/Network/Service/…/DNS`),
which is what VPN clients usually do and which a reboot clears by itself. It changes how DNS
is set and restored everywhere, so it waits for a session that can be tested live; this change
reuses the existing, tested set/restore functions.
→ Not verified live yet (README: network switches). Root-script budget is at its 250 limit.

## D42. Events instead of polling; sleep and wake (2026-09-21)

The root session checked xray, the app and the stop file once a second (`sleep 1`), and D41
added a `route` call to that loop; the app read the pid file once a second as well. The author
expected an event-driven design, as macOS provides one, and asked for sleep/wake handling too.

What happens across sleep, wake and network switches, from Xray v26.9.9's source
(`proxy/tun/tun_darwin.go`): with `autoOutboundsInterface`, Xray listens on a routing socket
and picks the physical interface again on every route change, so its own traffic follows a
new network and the link coming back after wake. Its routes stay on the utun. What XrayBar
itself must do is move the DNS override (D41) and notice when a session ends.

→ `XrayBarHelper --watch <stop-file> <pid>...`: the helper binary gets a second mode that only
observes and prints one line per event: `network` (SCDynamicStore notification on
`State:/Network/Global/IPv4`, which configd rewrites when the primary service changes),
`stop` (a vnode watch on the stop file's folder), `exit <pid>` (kqueue `NOTE_EXIT` for xray,
the app and the session script itself). The session script reads these lines and keeps every
action (DNS, stopping xray) in bash. If the watcher dies, the session ends and cleans up.
→ The script runs the watcher next to itself: the root-owned copy in `/Library/Application
Support/XrayBar` when the helper started the session, else the one in the app bundle (the
same trust as the bundled script). The watcher therefore runs as root in every session.
→ The app: while connected, disconnected or failed nothing runs; kqueue reports when xray or
the session ends (watching a root process needs no rights over it and sends it nothing,
checked on this Mac). Only the short connecting/disconnecting states are checked every 0.5 s.
A session found without its script while connected now offers Restore (it only did so while
disconnecting). Exits during sleep are delivered on wake.
→ Sleep and wake need nothing of their own. If the link drops during sleep, configd removes
and later republishes the primary service, the watcher reports `network` and the log records
it (`network: en0 -> none`, `none -> en0`). Checked live the same day: toggling Wi-Fi logged
both lines and traffic resumed by itself; a sleep on AC power (`TCPKeepAlive=active` in
`pmset -g log`) kept Wi-Fi associated, so no event came and none was needed: traffic went
through the tunnel during DarkWake and right after the full wake, without reconnecting.
A sleep that drops the link (on battery, longer) is not checked yet.
→ Known gap: a session started outside this app instance while it shows Not Connected is
noticed at the next launch, not at once (before: within a second).
→ Budgets: helper 150 → 180 lines, root scripts 250 → 270.
→ The behaviour across sleep/wake and network switches still needs a live check (README).
