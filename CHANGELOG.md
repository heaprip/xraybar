# Changelog

Release notes, newest first. Each `## x.y.z` section becomes the GitHub release text.
Decisions behind the changes: [docs/DECISIONS.md](docs/DECISIONS.md) (D-numbers below).

## Unreleased

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
