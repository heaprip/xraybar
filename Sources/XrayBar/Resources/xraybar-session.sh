#!/bin/bash
# XrayBar privileged session. This is ALL the code XrayBar runs as root.
#
# Started once per Connect through the macOS administrator prompt (docs/DECISIONS.md D4).
# Lifetime: copy config -> start xray -> set DNS -> wait -> stop xray -> restore DNS.
# It ends when the stop file appears, when the XrayBar app exits, or when xray exits,
# so nothing is ever left running or half-configured.
#
# Root writes only /var/run/xraybar (session files, gone at reboot), /var/db/xraybar (the
# saved DNS, which must survive a power loss) and the DNS setting of the active network
# service. The stop file is only tested for existence (the app creates and removes it).
#
# Usage: xraybar-session.sh <xray> <assets-dir> <config> <stop-file> <app-pid> <dns-server>...
#        xraybar-session.sh --restore     clean up after a session that died (e.g. power loss)

# The whole body is one { } block: bash parses it completely before running anything, so
# replacing this file on disk (e.g. rebuilding the app) cannot change a running session.
{
set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin   # system tools only, whatever the caller had
[[ $(id -u) == 0 ]] || { echo "must run as root" >&2; exit 1; }

RUN=/var/run/xraybar           # root-owned; the app only reads xray.pid and the log from here
LOG=$RUN/xray.log
PIDFILE=$RUN/xray.pid          # xray started by the current session
SESSION_PIDFILE=$RUN/session.pid
STATE=/var/db/xraybar
DNS_SAVED=$STATE/dns.saved     # "service<TAB>previous servers" while DNS is overridden

install -d -o root -g wheel -m 755 "$RUN" "$STATE"
log() { echo "xraybar-session: $*" >>"$LOG"; }
fail() { log "$*"; echo "$*" >&2; exit 1; }
alive() { [[ -f $1 ]] && kill -0 "$(cat "$1")" 2>/dev/null; }

# --- DNS -----------------------------------------------------------------------------
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
    log "DNS of $service restored to: $previous"
}

set_dns() {
    local service previous
    service=$(active_service)
    [[ -n $service ]] || { log "no active network service, DNS unchanged"; return; }
    previous=$(networksetup -getdnsservers "$service")
    [[ $previous == *"any DNS Servers"* ]] && previous=empty
    printf '%s\t%s\n' "$service" "$(echo $previous)" >"$DNS_SAVED"
    networksetup -setdnsservers "$service" "${DNS[@]}"
    log "DNS of $service set to: ${DNS[*]}"
}

# --- Processes -----------------------------------------------------------------------
# Stop a PID this script recorded earlier, and only if it still is our xray (the PID
# could have been reused after a reboot or a long time).
stop_xray() {
    local pid=$1
    ps -o command= -p "$pid" 2>/dev/null | grep -q " run -c $RUN/config.json" || return 0
    kill -TERM "$pid"
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || return 0; sleep 0.5; done
    kill -KILL "$pid"
}

# A session whose script died (killed, crashed) but whose xray kept running.
clean_stale() {
    if alive "$PIDFILE" && ! alive "$SESSION_PIDFILE"; then
        log "stopping xray left by a dead session (pid $(cat "$PIDFILE"))"
        stop_xray "$(cat "$PIDFILE")"
    fi
    alive "$SESSION_PIDFILE" || { restore_dns; rm -f "$PIDFILE" "$SESSION_PIDFILE" "$RUN/config.json"; }
}

if [[ ${1:-} == --restore ]]; then
    alive "$SESSION_PIDFILE" && fail "a session is running; disconnect instead"
    clean_stale
    exit 0
fi

# --- Session -------------------------------------------------------------------------
[[ $# -ge 6 ]] || { echo "usage: $0 <xray> <assets> <config> <stop-file> <app-pid> <dns>..." >&2; exit 2; }
XRAY=$1 ASSETS=$2 CONFIG=$3 STOP=$4 APP_PID=$5
shift 5
DNS=("$@")

alive "$SESSION_PIDFILE" && { echo "a session is already running" >&2; exit 1; }
# The log lists visited hosts: readable by admins (you), not by other local users.
: >"$LOG"; chown root:admin "$LOG"; chmod 640 "$LOG"
clean_stale
echo $$ >"$SESSION_PIDFILE"

# Validate inputs: fixed shapes only, nothing is ever evaluated.
[[ -x $XRAY && -f $XRAY ]] || fail "xray binary not found: $XRAY"
[[ -d $ASSETS ]]           || fail "assets directory not found: $ASSETS"
[[ -f $CONFIG ]]           || fail "config not found: $CONFIG"
[[ $APP_PID =~ ^[0-9]+$ ]] || fail "bad app pid"
for d in "${DNS[@]}"; do [[ $d =~ ^[0-9A-Fa-f:.]+$ ]] || fail "bad DNS server: $d"; done

# Work on a root-owned copy from here on, so the file cannot change after it is checked.
install -o root -g wheel -m 600 "$CONFIG" "$RUN/config.json"
# Root must not be steered into writing files: log paths may only be empty or "none".
grep -Eo '"(access|error)"[[:space:]]*:[[:space:]]*"[^"]+"' "$RUN/config.json" | grep -qv '"none"$' \
    && fail "config sets log files"

XPID=
cleanup() {
    [[ -n $XPID ]] && stop_xray "$XPID"
    restore_dns
    rm -f "$PIDFILE" "$SESSION_PIDFILE" "$RUN/config.json"   # the config holds credentials
    log "stopped"
}
trap cleanup EXIT
trap 'exit 0' TERM INT HUP

XRAY_LOCATION_ASSET=$ASSETS "$XRAY" run -c "$RUN/config.json" >>"$LOG" 2>&1 &
XPID=$!
echo "$XPID" >"$PIDFILE"; chmod 644 "$PIDFILE"

# Wait until Xray has installed its routes (the tunnel is up) before touching DNS. Without
# them no traffic enters the tunnel; pointing DNS at it then would only break name lookups.
routed=
for _ in $(seq 1 20); do
    kill -0 "$XPID" 2>/dev/null || fail "xray exited during startup"
    route -n get 1.1.1.1 2>/dev/null | grep -q 'interface: utun' && { routed=1; break; }
    sleep 0.5
done
[[ -n $routed ]] || fail "xray started but installed no routes (too old for native TUN on macOS?)"
set_dns

while kill -0 "$XPID" 2>/dev/null && kill -0 "$APP_PID" 2>/dev/null && [[ ! -e $STOP ]]; do
    sleep 1
done
exit 0
}
