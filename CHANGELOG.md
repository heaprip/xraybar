# Changelog

Release notes, newest first. Each `## x.y.z` section becomes the GitHub release text.
Decisions behind the changes: [docs/DECISIONS.md](docs/DECISIONS.md) (D-numbers below).

## Unreleased

- Xray tested with XrayBar: v26.10.21 (checksums pinned; D56).
- *Check for Newer Versions…* offers the newest release with two buttons; the version list in
  its alert did not open on macOS 27 (D56).
- New mark: a four-petal star, white on black for the app icon. In the menu bar it is faint
  when not connected, a petal runs round while connecting, filled when connected; a dot means
  the helper needs an update (D53).
- After an update, XrayBar explains macOS's keychain prompt before it appears: what its one
  item holds, that nothing else is read, and to choose Always Allow (D55).
- *Diagnostics › Reset XrayBar…* (hold Option): removes everything XrayBar keeps (servers,
  settings, routing data, Xray versions, the helper, the keychain item, the login item, and the
  cache macOS keeps for the app) with one password, then quits (D52).
- README: why XrayBar exists, "Don't trust, verify" near the top, how to give feedback;
  positioned as a client built on Xray-core rather than a client for its TUN.

## 0.4.0

Hysteria 2 servers, and fixes for macOS 27.

**New**
- Hysteria 2 servers, through Xray itself: `hysteria2://` and `hy2://` links and QR codes,
  salamander obfuscation, port hopping (a port list or range, or `mport=`), certificate pin
  (`pinSHA256`); also imported from v2rayN and shared back as a link. The certificate is
  always checked (D51).
- README: what *Import from v2rayN…* brings over and what not; routing data vs routing rules.

**Fixes**
- macOS 27: the administrator prompt took no password, with a spinning cursor, while
  XrayBar's menu stayed open behind it (D49).
- The menu showed Connected, and a new Xray counted as working, before Xray had routed any
  traffic into the tunnel (D49).
- "The helper is not responding" at the first Connect after installing or updating it.
- A server given by name (not an address) is resolved with the direct DNS resolver; through
  the proxy it could not be reached (D51).
- REALITY configs use Xray's current `realitySettings.password` for the server's key; share
  links keep `pbk` (D50).

**Other**
- Releases are published as Latest (they did not show in GitHub's sidebar as prereleases).
- README: a shorter "How it was built"; Russian docs name menu items as the Russian UI does;
  AUDIT covers the install script, the helper, the keychain item and release builds;
  vulnerabilities are reported privately on the Security tab.

## 0.3.0

The first release with downloadable builds: a `.pkg` and a `.zip`, built by CI from this tag
for Apple silicon and Intel, with a provenance attestation. Signed ad hoc, not notarized:
see *Install* in the README for the one-time *Open Anyway*.

**Security**
- Root runs only an Xray installed into a root-owned folder, checked against its SHA-256;
  a file in your user folders can no longer be swapped and run as root (D38). Existing
  downloads are not reused: choose *Xray › Download* once more.
- Root writes the config's log section itself, so no config can make it write files (D38).
- IPv6 goes through the tunnel when the Mac has a global IPv6 address (D40).
- The DNS override follows a switch to another network service (D41).
- Server credentials (VLESS ids) live in the login keychain; one item, so an update asks once (D45).

**Behaviour**
- No polling: the session and the app react to events (network changes, process exits, the
  stop file); a network change or wake is written to the log (D42).
- An outdated root helper is shown loudly and Connect offers to update it first (D43).
- Touch ID once per app run (per login) instead of at every Connect (D44).
- The menu stays responsive while connecting (D39).

**Mac conventions**
- About XrayBar, VoiceOver label for the menu bar icon, one instance only, unified logging (D46).
- Russian interface; it follows the system language (D47).

After installing: *Update Helper (Required)* if you use Touch ID, then *Xray › Download*.

## 0.2.0

First public version: menu-bar app for Xray-core's native TUN, VLESS + Reality, geosite/geoip
routing sets in v2rayN's format, QR import and sharing, Touch ID helper. Source only.
