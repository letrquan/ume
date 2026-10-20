#!/usr/bin/env bash
# The lock's backup, for when my shell can't lock (it crashed, hangs, or
# isn't running): before the laptop sleeps, and after a long idle. mango
# starts it apart from the shell (~/.config/mango/shell-mine.conf), so it
# keeps working when the shell doesn't.
#
# - Before sleep (lid closed, suspend): like the shell's own
#   (services/Locker.qml), a "delay" sleep inhibitor is held; when logind
#   says sleep is coming, qs-lock runs (it does nothing when already
#   locked, so this and the shell never lock twice) and the inhibitor is let
#   go once the lock is up (4.5 s at most; logind waits up to 5 s).
#   Settings' lockBeforeSleep off: it doesn't lock.
# - Idle: hypridle, 60 s after Settings' lockAfter (videos and Keep awake
#   hold it off, as they do the shell's). Then it locks only if the shell
#   doesn't answer (`qs ipc -c mine call idle ping`): a shell that answers
#   has locked already, or chose not to.
# - `loginctl lock-session`: hypridle runs qs-lock too (the shell does as
#   well; one lock).
#
#   lock-guard.sh         run (one at a time; mango starts it at login)
#   lock-guard.sh idle    hypridle's idle step (above)
#
# What it did: $XDG_RUNTIME_DIR/mine-lock-guard/guard.log
# Tests: MINE_GUARD_MONITOR (a command printing gdbus-monitor-style lines;
# it stops when that ends), MINE_LOCK_CMD (instead of qs-lock),
# MINE_SETTINGS, MINE_GUARD_IDLE_EXTRA (seconds after lockAfter, 60).
set -u

self=$(readlink -f "$0")
lockcmd=${MINE_LOCK_CMD:-$HOME/.local/bin/qs-lock}
settings=${MINE_SETTINGS:-$HOME/.local/state/mine-shell/settings.json}
run=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
dir=$run/mine-lock-guard
marker=$run/qs-lock.secure      # lock.qml: the compositor confirmed the lock
mkdir -p "$dir"

log() {
    echo "$(date '+%F %T') $*" >>"$dir/guard.log"
}

# setting <key> <default>: from the shell's settings (true/false lowercase).
setting() {
    python3 -I -c '
import json, sys
try:
    v = json.load(open(sys.argv[1])).get(sys.argv[2])
except Exception:
    v = None
print(sys.argv[3] if v is None else (str(v).lower() if isinstance(v, bool) else v))
' "$settings" "$1" "$2"
}

if [ "${1:-}" = idle ]; then
    if [ "$(timeout 2 qs ipc -c mine call idle ping 2>/dev/null)" = pong ]; then
        exit 0
    fi
    log "idle: the shell doesn't answer, locking"
    exec "$lockcmd"
fi

# One at a time.
exec 9>"$dir/running"
flock -n 9 || exit 0

# ---- Before sleep --------------------------------------------------------------
# The inhibitor lives as long as its `sleep`: ending that lets go of it.
holder=""
hold() {
    if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
        return
    fi
    systemd-inhibit --what=sleep --mode=delay --who="mine lock guard" \
        --why="Backup lock when the shell can't" sleep infinity 2>/dev/null &
    holder=$!
}
release() {
    if [ -n "$holder" ]; then
        pkill -P "$holder" 2>/dev/null
        wait "$holder" 2>/dev/null
        holder=""
    fi
}

lock_now() {
    if [ "$(setting lockBeforeSleep true)" = false ]; then
        return
    fi
    "$lockcmd" >/dev/null 2>&1 &
    local p=$! i
    for i in $(seq 45); do
        if [ -e "$marker" ]; then
            log "sleep: locked"
            return
        fi
        if ! kill -0 "$p" 2>/dev/null; then
            log "sleep: qs-lock ended (it was locked already)"
            return
        fi
        sleep 0.1
    done
    log "sleep: the lock didn't confirm within 4.5 s, letting it sleep anyway"
}

# Not the argument order of the shell's own `gdbus monitor --system --dest
# org.freedesktop.login1`: `mine stop` ends that one by its command line.
monitor() {
    if [ -n "${MINE_GUARD_MONITOR:-}" ]; then
        sh -c "$MINE_GUARD_MONITOR"
    else
        gdbus monitor --dest org.freedesktop.login1 --system
    fi
}

# ---- Idle ----------------------------------------------------------------------
idler=""
after=$(setting lockAfter 600)
if [[ "$after" =~ ^[0-9]+$ ]] && [ "$after" -gt 0 ]; then
    cat >"$dir/hypridle.conf" <<EOF
general {
    lock_cmd = $lockcmd
    inhibit_sleep = 0
    ignore_dbus_inhibit = true
}
listener {
    timeout = $((after + ${MINE_GUARD_IDLE_EXTRA:-60}))
    on-timeout = $self idle
}
EOF
    (
        while :; do
            hypridle -q -c "$dir/hypridle.conf" >>"$dir/hypridle.log" 2>&1
            sleep 5
        done
    ) &
    idler=$!
fi

stop() {
    release
    if [ -n "$idler" ]; then
        pkill -P "$idler" 2>/dev/null
        kill "$idler" 2>/dev/null
    fi
    exit 0
}
trap stop TERM INT HUP

if [ -n "$idler" ]; then
    log "started; idle: locks after $((after + ${MINE_GUARD_IDLE_EXTRA:-60})) s if the shell doesn't answer"
else
    log "started; idle: off (lockAfter is $after)"
fi
hold
while :; do
    while IFS= read -r line; do
        case $line in
        *"PrepareForSleep (true"*)
            lock_now
            release
            ;;
        *"PrepareForSleep (false"*)
            hold
            ;;
        esac
    done < <(monitor)
    if [ -n "${MINE_GUARD_MONITOR:-}" ]; then
        stop
    fi
    # logind restarted or gdbus ended: listen again.
    sleep 2
    hold
done
