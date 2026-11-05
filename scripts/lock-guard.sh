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
# - Logout: it belongs to the compositor it began under (the process listening
#   on $WAYLAND_DISPLAY then; a later login's mango is another one, even on the
#   same socket name), looks every 5 s, and ends once that process is gone,
#   with everything it started: the idle loop and hypridle (never started again
#   without that compositor), the inhibitor and its `sleep`, the gdbus. Not a
#   lock it started: that stays up. It looks at the process itself, so `ss`
#   failing later on means nothing.
# - No such process found at the start (no `ss`, too early at login): unlike
#   the shell's keeper it guards anyway, without the above, and says so in its
#   log. One left over after a logout is better than none at all.
# - One at a time, for each compositor (each login, when none was found): the
#   next login's guard has a lock of its own, so it starts at once, even with
#   the last one still ending. One asked to start next to a guard that's ending
#   waits 2 s for it; next to one that stays, it leaves it to that one. Whatever
#   else goes wrong with the lock, it guards.
#
#   lock-guard.sh         run (mango starts it at login)
#   lock-guard.sh idle    hypridle's idle step (above)
#
# What it did: $XDG_RUNTIME_DIR/mine-lock-guard/guard.log
# Tests: MINE_GUARD_MONITOR (a command printing gdbus-monitor-style lines;
# it stops when that ends), MINE_LOCK_CMD (instead of qs-lock),
# MINE_SETTINGS, MINE_GUARD_IDLE_EXTRA (seconds after lockAfter, 60),
# MINE_GUARD_WATCH (seconds between looks at the compositor, 5).
set -u

self=$(readlink -f "$0")
lockcmd=${MINE_LOCK_CMD:-$HOME/.local/bin/qs-lock}
settings=${MINE_SETTINGS:-$HOME/.local/state/mine-shell/settings.json}
run=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
dir=$run/mine-lock-guard
marker=$run/qs-lock.secure      # lock.qml: the compositor confirmed the lock
every=${MINE_GUARD_WATCH:-5}
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

# ---- The compositor ------------------------------------------------------------
case ${WAYLAND_DISPLAY:-wayland-0} in
/*) sock=$WAYLAND_DISPLAY ;;
*) sock=$run/${WAYLAND_DISPLAY:-wayland-0} ;;
esac
# The pid listening on the Wayland socket (none on a file left behind by a
# compositor that crashed).
listener() {
    timeout 2 ss -xlpn src "$sock" 2>/dev/null | grep -o 'pid=[0-9]*' | head -n 1 | cut -d= -f2
}
# read_stat <pid>: sets $state and $began from /proc/<pid>/stat (what follows
# the name, which can hold anything; the start time tells it from a later
# process with the same pid). Fails if it can't be read.
read_stat() {
    local line
    { IFS= read -r line <"/proc/$1/stat"; } 2>/dev/null || return 1
    # shellcheck disable=SC2086
    set -- ${line##*) }
    state=${1:-}
    began=${20:-}
}
# Only true "gone" ends a guard, so anything unclear counts as alive.
compositor_alive() {
    if [ -z "$compositor" ]; then
        return 0
    fi
    if ! read_stat "$compositor"; then
        kill -0 "$compositor" 2>/dev/null
        return
    fi
    case $state in
    Z | X) return 1 ;;  # ended, its parent hasn't noticed yet
    esac
    [ -z "$began" ] || [ -z "$compositor_began" ] || [ "$began" = "$compositor_began" ]
}
compositor=""
compositor_began=""
for _ in 1 2 3 4; do
    compositor=$(listener)
    if [ -n "$compositor" ]; then
        break
    fi
    sleep 0.5
done
if [ -n "$compositor" ] && read_stat "$compositor"; then
    compositor_began=$began
fi
guards=${compositor:+compositor pid $compositor}

# One at a time, for each compositor. Nothing started from here may keep fd 9
# (hence the 9>&- below, and 8<&- for what gdbus says): a leftover holding it
# would turn the next guard away. The start time is in the name for a later
# process with the same pid: that one's guard isn't this compositor's. flock's 1
# is the wait running out, so another guard is there; anything else is a lock
# that doesn't work, and no reason not to guard.
key=${compositor:+$compositor-$compositor_began}
lockfile=$dir/running.${key:-session-${XDG_SESSION_ID:-$$}}
exec 9>"$lockfile"
flock -w 2 9
got=$?
case $got in
0) ;;
1)
    log "another guard runs for ${guards:-this login}: leaving it to that one"
    exit 0
    ;;
*)
    log "couldn't take the lock (flock said $got): guarding anyway"
    ;;
esac

# ---- Before sleep --------------------------------------------------------------
# The inhibitor lives as long as its `sleep`: ending that lets go of it.
holder=""
hold() {
    if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
        return
    fi
    systemd-inhibit --what=sleep --mode=delay --who="mine lock guard" \
        --why="Backup lock when the shell can't" sleep infinity 2>/dev/null 9>&- 8<&- &
    holder=$!
}
release() {
    if [ -n "$holder" ]; then
        # Its `sleep` may not be running yet, if it has only just started.
        local i
        for i in $(seq 20); do
            pkill -P "$holder" 2>/dev/null
            if ! kill -0 "$holder" 2>/dev/null; then
                break
            fi
            if [ "$i" = 20 ]; then
                kill -9 "$holder" 2>/dev/null
            fi
            sleep 0.05
        done
        wait "$holder" 2>/dev/null
        holder=""
    fi
}

lock_now() {
    if [ "$(setting lockBeforeSleep true)" = false ]; then
        return
    fi
    "$lockcmd" >/dev/null 2>&1 9>&- 8<&- &
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
# exec: its pid is the one to end, as nothing else tells it to go until it next
# has something to say.
monitor() {
    if [ -n "${MINE_GUARD_MONITOR:-}" ]; then
        exec sh -c "$MINE_GUARD_MONITOR"
    else
        exec gdbus monitor --dest org.freedesktop.login1 --system
    fi
}

# ---- Ending --------------------------------------------------------------------
idler=""
listening=""
stop() {
    trap '' TERM INT HUP
    release
    if [ -n "$listening" ]; then
        kill "$listening" 2>/dev/null
    fi
    if [ -n "$idler" ]; then
        kill "$idler" 2>/dev/null
    fi
    exit 0
}
trap stop TERM INT HUP
# The lock file only ever meant this compositor. The rest (hypridle.conf, the
# logs) stays: the next login's guard is using them.
gone() {
    log "the compositor (pid $compositor) is gone (logout?): ending"
    rm -f "$lockfile"
    stop
}

# ---- Idle ----------------------------------------------------------------------
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
    # hypridle dies with the compositor, and the next login's can have the same
    # socket name: without the check it would start again and join that one. In
    # the background, so a TERM ends this right away, and what's running with it.
    (
        trap 'kill "${!:-}" 2>/dev/null; exit 0' TERM
        while compositor_alive; do
            hypridle -q -c "$dir/hypridle.conf" >>"$dir/hypridle.log" 2>&1 &
            wait "$!"
            sleep 5 &
            wait "$!"
        done
    ) 9>&- &
    idler=$!
fi

if [ -z "$compositor" ]; then
    log "no compositor found on $sock: guarding without watching for it, so this one won't end at logout"
fi
if [ -n "$idler" ]; then
    log "started (${guards:-no compositor to watch}); idle: locks after $((after + ${MINE_GUARD_IDLE_EXTRA:-60})) s if the shell doesn't answer"
else
    log "started (${guards:-no compositor to watch}); idle: off (lockAfter is $after)"
fi
while compositor_alive; do
    hold
    exec 8< <(monitor 9>&-)
    listening=$!
    part=""
    while :; do
        # Not waiting for ever, to look at the compositor; a line wakes it at
        # once. Timed out (above 128): what came so far is the start of a line.
        IFS= read -r -t "$every" -u 8 line
        got=$?
        if ! compositor_alive; then
            gone
        fi
        if [ "$got" -gt 128 ]; then
            part+=$line
            continue
        fi
        if [ "$got" -ne 0 ]; then
            break
        fi
        line=$part$line
        part=""
        case $line in
        *"PrepareForSleep (true"*)
            lock_now
            release
            ;;
        *"PrepareForSleep (false"*)
            hold
            ;;
        esac
    done
    exec 8<&-
    listening=""
    if [ -n "${MINE_GUARD_MONITOR:-}" ]; then
        stop
    fi
    # logind restarted or gdbus ended: listen again.
    sleep 2
done
gone
