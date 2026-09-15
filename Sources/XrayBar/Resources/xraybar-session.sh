#!/bin/bash
# XrayBar privileged session. This is ALL the code XrayBar runs as root.
#
# Started once per Connect through the macOS administrator prompt (docs/DECISIONS.md D4).
# Lifetime: copy config -> start xray -> set DNS -> wait -> stop xray -> restore DNS.
# Root never writes or deletes anything outside /var/run/xraybar except the DNS setting;
# the stop file is only tested for existence (the app creates and removes it).
# It ends when the stop file appears, when the XrayBar app exits, or when xray exits,
# so nothing is ever left running or half-configured.
#
# Usage: xraybar-session.sh <xray> <assets-dir> <config> <stop-file> <app-pid> <dns-server>...

set -u
[[ $(id -u) == 0 ]] || { echo "must run as root" >&2; exit 1; }
[[ $# -ge 6 ]] || { echo "usage: $0 <xray> <assets> <config> <stop-file> <app-pid> <dns>..." >&2; exit 2; }

XRAY=$1 ASSETS=$2 CONFIG=$3 STOP=$4 APP_PID=$5
shift 5
DNS=("$@")

RUN=/var/run/xraybar           # root-owned; the app only reads the pid and log from here
LOG=$RUN/xray.log
PIDFILE=$RUN/xray.pid
DNS_SAVED=$RUN/dns.saved       # "service<TAB>previous servers" while DNS is overridden

fail() { echo "xraybar-session: $*" >>"$LOG"; echo "$*" >&2; exit 1; }

install -d -o root -g wheel -m 755 "$RUN"
if [[ -f $PIDFILE ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "a session is already running (pid $(cat "$PIDFILE"))" >&2; exit 1
fi
: >"$LOG"; chmod 644 "$LOG"

# --- Validate inputs: fixed shapes only, nothing is ever evaluated -------------------
[[ -x $XRAY && -f $XRAY ]] || fail "xray binary not found: $XRAY"
[[ -d $ASSETS ]]           || fail "assets directory not found: $ASSETS"
[[ -f $CONFIG ]]           || fail "config not found: $CONFIG"
[[ $APP_PID =~ ^[0-9]+$ ]] || fail "bad app pid"
for d in "${DNS[@]}"; do [[ $d =~ ^[0-9A-Fa-f:.]+$ ]] || fail "bad DNS server: $d"; done

# Work on a root-owned copy from here on, so the file cannot change after it is checked.
install -o root -g wheel -m 600 "$CONFIG" "$RUN/config.json"
# Root must not be steered into writing files: reject configs that set log file paths.
grep -Eq '"(access|error|dnsLog)"[[:space:]]*:[[:space:]]*"[^"]' "$RUN/config.json" && fail "config sets log files"


# --- DNS helpers ---------------------------------------------------------------------
# The network service (e.g. "Wi-Fi") that owns the default route's interface.
active_service() {
    local dev
    dev=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
    networksetup -listnetworkserviceorder | awk -v dev="$dev" '
        /^\([0-9*]+\) / { sub(/^\([0-9*]+\) /, ""); name = $0 }
        index($0, "Device: " dev ")") { print name; exit }'
}

restore_dns() {
    [[ -f $DNS_SAVED ]] || return 0
    local service previous
    IFS=$'\t' read -r service previous <"$DNS_SAVED"
    # shellcheck disable=SC2086  # previous is a space-separated list or "empty"
    networksetup -setdnsservers "$service" $previous
    rm -f "$DNS_SAVED"
    echo "xraybar-session: DNS of $service restored to: $previous" >>"$LOG"
}

set_dns() {
    local service previous
    service=$(active_service)
    [[ -n $service ]] || { echo "xraybar-session: no active network service, DNS unchanged" >>"$LOG"; return; }
    previous=$(networksetup -getdnsservers "$service")
    [[ $previous == *"any DNS Servers"* ]] && previous=empty
    printf '%s\t%s\n' "$service" "$(echo $previous)" >"$DNS_SAVED"
    networksetup -setdnsservers "$service" "${DNS[@]}"
    echo "xraybar-session: DNS of $service set to: ${DNS[*]}" >>"$LOG"
}

# A previous session that died hard (power loss) may have left DNS overridden.
restore_dns

# --- Run -----------------------------------------------------------------------------
XPID=
cleanup() {
    if [[ -n $XPID ]] && kill -0 "$XPID" 2>/dev/null; then
        kill -TERM "$XPID"
        for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$XPID" 2>/dev/null || break; sleep 0.5; done
        kill -0 "$XPID" 2>/dev/null && kill -KILL "$XPID"
    fi
    restore_dns
    rm -f "$PIDFILE"
    echo "xraybar-session: stopped" >>"$LOG"
}
trap cleanup EXIT
trap 'exit 0' TERM INT HUP

XRAY_LOCATION_ASSET=$ASSETS "$XRAY" run -c "$RUN/config.json" >>"$LOG" 2>&1 &
XPID=$!
echo "$XPID" >"$PIDFILE"; chmod 644 "$PIDFILE"

# Wait until Xray has installed its routes (the tunnel is up) before touching DNS.
for _ in $(seq 1 20); do
    kill -0 "$XPID" 2>/dev/null || fail "xray exited during startup"
    route -n get 1.1.1.1 2>/dev/null | grep -q 'interface: utun' && break
    sleep 0.5
done
set_dns

while kill -0 "$XPID" 2>/dev/null && kill -0 "$APP_PID" 2>/dev/null && [[ ! -e $STOP ]]; do
    sleep 1
done
exit 0
