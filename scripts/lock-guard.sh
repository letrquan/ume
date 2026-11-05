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
#   lock it started: that stays up. It looks at the process itself, so the
#   lookup failing later on means nothing.
# - No such process found (the socket doesn't answer yet at login, no python):
#   unlike the shell's keeper it guards anyway and says so in its log, and looks
#   again each time until it finds it. One left over after a logout is better
#   than none at all.
# - One at a time, for this user, as qs-lock and its marker are: two guards
#   locking at once could each take the other's lock for its own. The next one
#   compares its compositor with the one the guard holding the lock is for
#   (mine-lock-guard/holder):
#   - The same: it leaves it to that guard (after 2 s, in case that one is
#     ending). No pids to compare: the same login counts as the same.
#   - One that's gone: that guard does nothing any more and is about to end, so
#     this one guards at once, and takes the lock when it's free.
#   - Another that's still there (a second login on another VT): it waits, and
#     guards once it has the lock, or that compositor has gone. So until then a
#     second login has no guard of its own, as it never had.
#   - It can't tell (that guard knows no compositor, in another login): it
#     guards. So it does when the lock itself doesn't work.
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
# A positive number: read would spin on 0, and fail on anything else.
if ! [[ $every =~ ^[0-9]*\.?[0-9]+$ && $every =~ [1-9] ]]; then
    every=5
fi
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
# read_stat <pid>: sets $state and $began from /proc/<pid>/stat (what follows
# the name, which can hold anything; the start time tells it from a later
# process with the same pid). Fails if it can't be read.
read_stat() {
    local line=""
    # All of it (read says it failed, finding no NUL): a name can hold newlines.
    { IFS= read -r -d '' line <"/proc/$1/stat"; } 2>/dev/null
    if [ -z "$line" ]; then
        return 1
    fi
    # shellcheck disable=SC2086
    set -- ${line##*) }
    state=${1:-}
    began=${20:-}
}
# is_up <pid> <start time>: only a true "gone" ends a guard, so anything unclear
# counts as there.
is_up() {
    if ! read_stat "$1"; then
        kill -0 "$1" 2>/dev/null
        return
    fi
    case $state in
    Z | X) return 1 ;;  # ended, its parent hasn't noticed yet
    esac
    [ -z "$began" ] || [ -z "$2" ] || [ "$began" = "$2" ]
}
compositor=""
compositor_began=""
compositor_alive() {
    [ -z "$compositor" ] || is_up "$compositor" "$compositor_began"
}
# find_compositor: what's listening on the Wayland socket, from the socket itself
# (nothing on a file left behind by a compositor that crashed). Not from `ss` like
# the shell's keeper: that lists a child the compositor has just forked, which
# holds the socket for a moment, and a sandboxed process with a socket of the same
# path in its own mount namespace, which could then end this guard by exiting.
find_compositor() {
    local p
    p=$(timeout 2 python3 -I -c '
import socket, struct, sys
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
print(struct.unpack("3i", s.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))[0])
' "$sock" 2>/dev/null)
    case $p in
    "" | 0 | *[!0-9]*) return ;;
    esac
    if read_stat "$p" && [ -n "$began" ]; then
        compositor=$p
        compositor_began=$began
    fi
}
find_compositor

# ---- One at a time -------------------------------------------------------------
# Nothing started from here may keep fd 9 (hence the 9>&- below, and 8<&- for
# what gdbus says): a leftover holding it would turn the next guard away.
exec 9>"$dir/lock"
locked=""
# take_lock <flock's options>: fails if another guard holds it. flock's 1 is just
# that; anything else is a lock that doesn't work, and no reason not to guard.
take_lock() {
    flock "$@" 9
    local got=$?
    case $got in
    0) note_holder ;;
    1) return 1 ;;
    *) log "couldn't take the lock (flock said $got): guarding anyway" ;;
    esac
    locked=1
}
# What the next guard compares with. Whole or not at all: it can read it any time.
note_holder() {
    printf '%s %s %s\n' "${compositor:--}" "${compositor_began:--}" "${XDG_SESSION_ID:--}" >"$dir/holder.new" &&
        mv -f "$dir/holder.new" "$dir/holder"
}
# judge_holder: sets $verdict, about the guard holding the lock: same (it's for
# this compositor, or this login), other (for another compositor that's still
# there), over (its compositor has gone), unknown (can't tell).
judge_holder() {
    local c="" b="" login=""
    { read -r c b login <"$dir/holder"; } 2>/dev/null
    case $c in
    "" | *[!0-9]*) c="" ;;
    esac
    case $b in
    "" | *[!0-9]*) b="" ;;
    esac
    if [ -n "$c" ] && ! is_up "$c" "$b"; then
        verdict=over
    elif [ -n "${XDG_SESSION_ID:-}" ] && [ "$login" = "$XDG_SESSION_ID" ] && { [ -z "$c" ] || [ -z "$compositor" ]; }; then
        verdict=same
    elif [ -z "$c" ]; then
        verdict=unknown
    elif [ -z "$compositor" ]; then
        verdict=other
    elif [ "$c" = "$compositor" ] && [ "$b" = "$compositor_began" ]; then
        verdict=same
    else
        verdict=other
    fi
}
if ! take_lock -n; then
    judge_holder
    if [ "$verdict" = same ] && ! take_lock -w 2; then
        log "another guard runs for this compositor: leaving it to that one"
        exit 0
    fi
    if [ "$verdict" = other ]; then
        log "another login's guard holds the lock: this one waits (compositor: ${compositor:-not found})"
    fi
    while [ "$verdict" = other ] && ! take_lock -w "$every"; do
        if ! compositor_alive; then
            log "the compositor (pid $compositor) is gone (logout?), and this one never started: ending"
            exit 0
        fi
        if [ -z "$compositor" ]; then
            find_compositor
        fi
        judge_holder
        if [ "$verdict" = same ]; then
            log "another guard runs for this compositor: leaving it to that one"
            exit 0
        fi
    done
fi

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
helper=""   # the wait before listening again
stop() {
    trap '' TERM INT HUP
    release
    for p in "$listening" "$helper" "$idler"; do
        if [ -n "$p" ]; then
            kill "$p" 2>/dev/null
        fi
    done
    exit 0
}
trap stop TERM INT HUP
# Its files (hypridle.conf, holder, the logs) stay: the next login's guard is
# using them.
gone() {
    log "the compositor (pid $compositor) is gone (logout?): ending"
    stop
}
# look: what it couldn't settle at the start, each time the wait below is over.
look() {
    if [ -z "$compositor" ]; then
        find_compositor
        if [ -n "$compositor" ]; then
            log "found the compositor (pid $compositor): watching it now"
            if [ -n "$locked" ]; then
                note_holder
            fi
        fi
    fi
    if [ -z "$locked" ] && ! take_lock -n; then
        judge_holder
        if [ "$verdict" = same ]; then
            log "another guard runs for this compositor: leaving it to that one"
            stop
        fi
    fi
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
    # socket name: without the check it would start again and join that one (one
    # found later isn't known here: stop ends this then, at the next look). In
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
    log "no compositor found on $sock: guarding without watching for it, and looking again every $every s"
fi
watching=${compositor:+compositor pid $compositor}
if [ -n "$idler" ]; then
    log "started (${watching:-no compositor found}); idle: locks after $((after + ${MINE_GUARD_IDLE_EXTRA:-60})) s if the shell doesn't answer"
else
    log "started (${watching:-no compositor found}); idle: off (lockAfter is $after)"
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
            look
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
    # Saying nothing more doesn't have to mean it ended.
    kill "$listening" 2>/dev/null
    exec 8<&-
    listening=""
    if [ -n "${MINE_GUARD_MONITOR:-}" ]; then
        stop
    fi
    # logind restarted or gdbus ended: listen again. Background + wait: a TERM
    # ends the guard right away, not after the sleep.
    sleep 2 9>&- &
    helper=$!
    wait "$helper"
    helper=""
    look
done
gone
