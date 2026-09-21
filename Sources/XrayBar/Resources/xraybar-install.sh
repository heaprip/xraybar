#!/bin/bash
# Installs or removes XrayBar's privileged helper (docs/DECISIONS.md D28). Runs as root, once,
# through the administrator prompt. Installing touches exactly four things:
#   /Library/Application Support/XrayBar/        XrayBarHelper + xraybar-session.sh (root-owned)
#   /Library/LaunchDaemons/io.github.heaprip.xraybar.helper.plist
#   the authorization right io.github.heaprip.xraybar.connect (security authorizationdb)
#   the loaded launchd job io.github.heaprip.xraybar.helper
# --uninstall removes the same four.
#
# Usage: xraybar-install.sh <XrayBarHelper> <xraybar-session.sh>
#        xraybar-install.sh --uninstall

# One { } block: parsed completely before running (see xraybar-session.sh).
{
set -eu
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ $(id -u) == 0 ]] || { echo "must run as root" >&2; exit 1; }

DIR="/Library/Application Support/XrayBar"
LABEL=io.github.heaprip.xraybar.helper
PLIST=/Library/LaunchDaemons/$LABEL.plist
RIGHT=io.github.heaprip.xraybar.connect

launchctl bootout "system/$LABEL" 2>/dev/null || true
# Builds before the bundle ID was final (D36) used io.github.xraybar.*: remove those too.
launchctl bootout system/io.github.xraybar.helper 2>/dev/null || true
rm -f /Library/LaunchDaemons/io.github.xraybar.helper.plist
security authorizationdb remove io.github.xraybar.connect >/dev/null 2>&1 || true

if [[ ${1:-} == --uninstall ]]; then
    rm -f "$PLIST"
    rm -rf "$DIR"
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

# Every Connect authenticates (timeout 0, not shared); any admin user of this Mac may connect.
security authorizationdb write "$RIGHT" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>class</key><string>user</string>
    <key>group</key><string>admin</string>
    <key>shared</key><false/>
    <key>timeout</key><integer>0</integer>
    <key>allow-root</key><false/>
    <key>comment</key><string>Connect XrayBar: start Xray with a TUN interface as root.</string>
</dict>
</plist>
EOF

launchctl bootstrap system "$PLIST"
echo "XrayBar helper installed"
exit 0
}
