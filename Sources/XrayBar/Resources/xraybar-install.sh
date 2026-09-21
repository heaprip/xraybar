#!/bin/bash
# Installs or removes XrayBar's privileged helper (docs/DECISIONS.md D28). Runs as root, once,
# through the administrator prompt. Installing touches exactly four things:
#   /Library/Application Support/XrayBar/        XrayBarHelper + xraybar-session.sh (root-owned)
#   /Library/LaunchDaemons/io.github.heaprip.xraybar.helper.plist
#   the authorization right io.github.heaprip.xraybar.connect (security authorizationdb)
#   the loaded launchd job io.github.heaprip.xraybar.helper
# --uninstall removes the same four (Xray versions stay: connecting without the helper uses them).
#
# --xray installs one Xray version where the session accepts it (D38):
#   /Library/Application Support/XrayBar/xray/<tag>/xray   root-owned, checked against <sha256>
# so a binary in the user's folders is never run as root. Nothing else is touched.
#
# Usage: xraybar-install.sh <XrayBarHelper> <xraybar-session.sh>
#        xraybar-install.sh --uninstall
#        xraybar-install.sh --xray <tag> <xray binary> <sha256>

# One { } block: parsed completely before running (see xraybar-session.sh).
{
set -eu
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ $(id -u) == 0 ]] || { echo "must run as root" >&2; exit 1; }

DIR="/Library/Application Support/XrayBar"
LABEL=io.github.heaprip.xraybar.helper
PLIST=/Library/LaunchDaemons/$LABEL.plist
RIGHT=io.github.heaprip.xraybar.connect

if [[ ${1:-} == --xray ]]; then
    [[ $# -eq 4 && $2 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && -f $3 && $4 =~ ^[0-9a-f]{64}$ ]] \
        || { echo "usage: $0 --xray <tag> <xray binary> <sha256>" >&2; exit 2; }
    install -d -o root -g wheel -m 755 "$DIR" "$DIR/xray" "$DIR/xray/$2"
    # Copy first, then check the copy: the source is in the user's folders and could change.
    new=$(mktemp "$DIR/xray/$2/.new.XXXXXX")
    trap 'rm -f "$new"' EXIT
    cp "$3" "$new"
    [[ $(shasum -a 256 "$new" | cut -d ' ' -f 1) == "$4" ]] || { echo "checksum mismatch: $3" >&2; exit 1; }
    chown root:wheel "$new"
    chmod 755 "$new"
    mv -f "$new" "$DIR/xray/$2/xray"
    echo "Xray $2 installed"
    exit 0
fi

launchctl bootout "system/$LABEL" 2>/dev/null || true
# Builds before the bundle ID was final (D36) used io.github.xraybar.*: remove those too.
launchctl bootout system/io.github.xraybar.helper 2>/dev/null || true
rm -f /Library/LaunchDaemons/io.github.xraybar.helper.plist
security authorizationdb remove io.github.xraybar.connect >/dev/null 2>&1 || true

if [[ ${1:-} == --uninstall ]]; then
    rm -f "$PLIST" "$DIR/XrayBarHelper" "$DIR/xraybar-session.sh"
    security authorizationdb remove "$RIGHT" >/dev/null 2>&1 || true
    echo "XrayBar helper removed"
    exit 0
fi

[[ $# -eq 2 && -f $1 && -f $2 ]] || { echo "usage: $0 <XrayBarHelper> <xraybar-session.sh>" >&2; exit 2; }
install -d -o root -g wheel -m 755 "$DIR"
install -o root -g wheel -m 755 "$1" "$DIR/XrayBarHelper"
install -o root -g wheel -m 644 "$2" "$DIR/xraybar-session.sh"

cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$DIR/XrayBarHelper</string></array>
    <key>Sockets</key>
    <dict>
        <key>Listener</key>
        <dict>
            <key>SockPathName</key><string>/var/run/xraybar-helper.sock</string>
            <key>SockPathMode</key><integer>438</integer>
        </dict>
    </dict>
    <key>AbandonProcessGroup</key><true/>
</dict>
</plist>
EOF
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

# Any admin user of this Mac may connect. Not shared: the credential stays in the one
# authorization XrayBar keeps while it runs, so Touch ID is asked once per app run, i.e. per
# login, and no other right or process can use it. No timeout: valid for that run (D44).
security authorizationdb write "$RIGHT" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>class</key><string>user</string>
    <key>group</key><string>admin</string>
    <key>shared</key><false/>
    <key>allow-root</key><false/>
    <key>comment</key><string>Connect XrayBar: start Xray with a TUN interface as root.</string>
</dict>
</plist>
EOF

launchctl bootstrap system "$PLIST"
echo "XrayBar helper installed"
exit 0
}
