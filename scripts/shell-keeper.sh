#!/usr/bin/env bash
# Keeps my shell running: runs qs in the foreground, waits on it, and starts
# it again when it crashes. `mine start` starts this, apart from the terminal
# or script it was called from (mango runs `mine start` at login,
# ~/.config/mango/shell-mine.conf). qs gets this script's environment (`mine
# start` adds the jemalloc settings, MALLOC_CONF).
#
# - It crashed (killed by a signal, or any exit but 0, like a config that
#   fails to load): what it left running is ended (`mine cleanup`: the list
#   `mine stop` uses, but only in this keeper's session, so only what its
#   shell started), then it starts again after 1, 2, 4, 8 s. The 5th crash
#   within 5 minutes: it gives up (a bad edit that crashes at every start);
#   `mine restart` once it's fixed.
# - Quickshell's own crash handler is off for the shell
#   (QS_DISABLE_CRASH_HANDLER): it restarts a shell that crashed after its
#   first 10 s inside the same process, where this can't see it, and leaves
#   the crashed one's helpers (gdbus, udevadm, wl-paste...) running next to
#   the new ones. A crash leaves a core dump instead (coredumpctl), not
#   Quickshell's report. qs-lock unsets it, so the lock screen the shell
#   starts keeps Quickshell's handler.
# - It quit with 0: stopped on purpose (`qs kill -c mine`), or another
#   instance was running already (qs -n). Not started again; this ends too.
# - `mine stop`, `mine restart` and deploy.sh end this first (TERM: the shell
#   is left as it is), then stop the shell, so nothing starts it again
#   meanwhile.
# - Logout: it never starts the shell without the compositor it began under
#   (the process listening on $WAYLAND_DISPLAY then; a later login's mango is
#   another one), and ends once that is gone.
# - Hung shell: every 30 s, from 60 s after a start, the shell must answer
#   `qs ipc -c mine call idle ping` (shell.qml) within 5 s. 3 misses in a
#   row: it's ended (TERM, then KILL) and counts as a crash. A shell stopped
#   on purpose (SIGSTOP, a debugger) isn't asked; after the laptop slept (a
#   wait that took far longer than asked) it counts from 0 again, from 60 s.
#
#   shell-keeper.sh     run (one at a time)
#
# What it did: $XDG_RUNTIME_DIR/mine-keeper/keeper.log
# Tests: MINE_CONFIG (the Quickshell config, mine), MINE_BIN (instead of
# ~/.local/bin/mine), MINE_KEEPER_PING (seconds between pings, 30; 0: no
# pings), MINE_KEEPER_GRACE (no pings this long after a start, 60).
set -u

config=${MINE_CONFIG:-mine}
mine=${MINE_BIN:-$HOME/.local/bin/mine}
every=${MINE_KEEPER_PING:-30}
grace=${MINE_KEEPER_GRACE:-60}
run=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
dir=$run/$config-keeper
mkdir -p "$dir"

log() {
    echo "$(date '+%F %T') $*" >>"$dir/keeper.log"
}

# One at a time. Nothing started from here may keep fd 9 (hence the 9>&-
# below): a crashed shell's leftover holding it would turn the next keeper
# away.
exec 9>"$dir/running"
flock -n 9 || exit 0
echo $$ >"$dir/pid"
trap 'rm -f "$dir/pid"' EXIT
# Not the caller's directory (a terminal's, deploy's): apps the shell
# launches start in it.
cd "$HOME" || cd /

# ---- The compositor ------------------------------------------------------------
case ${WAYLAND_DISPLAY:-wayland-0} in
/*) sock=$WAYLAND_DISPLAY ;;
*) sock=$run/${WAYLAND_DISPLAY:-wayland-0} ;;
esac
# The pid listening on the Wayland socket (none on a file left behind by a
# compositor that crashed).
listener() {
    ss -xlpn src "$sock" 2>/dev/null | grep -o 'pid=[0-9]*' | head -n 1 | cut -d= -f2
}
compositor=$(listener)
compositor_alive() {
    [ "$(listener)" = "$compositor" ]
}
if [ -z "$compositor" ]; then
    log "no compositor on $sock: not starting the shell"
    exit 1
fi

# Its session: the shell and everything it starts are in it (`mine start`
# runs this with setsid), so the cleanup after a crash finds only theirs.
sid=$(ps -o sid= -p $$ | tr -d ' ')

shell=""    # the shell's pid
helper=""   # a sleep or ping running in the background
quit() {
    if [ -n "$helper" ]; then
        kill "$helper" 2>/dev/null
    fi
    log "asked to stop; the shell is left to whoever asked"
    exit 0
}
trap quit TERM INT HUP

# ---- Hung shell ----------------------------------------------------------------
# R, S, T (stopped), Z (ended, not yet waited on)...
shell_state() {
    sed 's/.*) //' "/proc/$shell/stat" 2>/dev/null | cut -d' ' -f1
}

# watch: wait until the shell ends, pinging it meanwhile. Sets $status
# (128 + the signal when killed) and $hung.
watch() {
    local since=$EPOCHSECONDS misses=0 t which
    hung=0
    if [ "$every" -le 0 ]; then
        wait "$shell"
        status=$?
        return
    fi
    while :; do
        # Background + wait: a TERM ends the keeper right away, not after
        # the sleep.
        sleep "$every" 9>&- &
        helper=$!
        t=$EPOCHSECONDS
        which=""
        wait -n -p which "$shell" "$helper"
        status=$?
        if [ "$which" = "$shell" ]; then
            kill "$helper" 2>/dev/null
            helper=""
            return
        fi
        helper=""
        if [ $((EPOCHSECONDS - t)) -gt $((every * 2 + 10)) ]; then
            log "woke up after $((EPOCHSECONDS - t)) s (the laptop slept?): pings start over"
            misses=0
            since=$EPOCHSECONDS
            continue
        fi
        if [ $((EPOCHSECONDS - since)) -lt "$grace" ]; then
            continue
        fi
        case $(shell_state) in
        T | t)
            misses=0
            continue
            ;;
        esac
        timeout -k 1 5 qs ipc -c "$config" call idle ping >"$dir/pong" 2>/dev/null 9>&- &
        helper=$!
        wait "$helper"
        helper=""
        if [ "$(cat "$dir/pong" 2>/dev/null)" = pong ]; then
            misses=0
            continue
        fi
        # Ended meanwhile: the next wait has it.
        case $(shell_state) in
        Z | "") continue ;;
        esac
        misses=$((misses + 1))
        log "the shell didn't answer within 5 s ($misses of 3)"
        if [ "$misses" -lt 3 ]; then
            continue
        fi
        log "the shell hangs: ending it"
        hung=1
        kill "$shell" 2>/dev/null
        sleep 5 9>&- &
        helper=$!
        which=""
        wait -n -p which "$shell" "$helper"
        status=$?
        if [ "$which" = "$shell" ]; then
            kill "$helper" 2>/dev/null
        else
            kill -9 "$shell" 2>/dev/null
            wait "$shell"
            status=$?
        fi
        helper=""
        return
    done
}

# ---- Run, and again after a crash ----------------------------------------------
log "started (config $config, compositor pid $compositor, session $sid)"
crashes=()      # when the recent ones were (5 minutes)
while :; do
    if ! compositor_alive; then
        log "the compositor is gone (logout?): ending"
        exit 0
    fi
    QS_DISABLE_CRASH_HANDLER=1 qs -c "$config" -n </dev/null >/dev/null 2>&1 9>&- &
    shell=$!
    echo "$shell" >"$dir/shell"
    started=$EPOCHSECONDS
    log "the shell started (pid $shell)"
    watch
    ran=$((EPOCHSECONDS - started))
    if [ "$status" -eq 0 ]; then
        log "the shell quit (exit 0, after $ran s): stopped on purpose, or one was running already; not starting it again"
        exit 0
    fi
    core=""
    if [ "$status" -gt 128 ] && sig=$(kill -l "$status" 2>/dev/null); then
        how="killed by SIG$sig"
        case $sig in
        SEGV | ABRT | BUS | FPE | ILL | TRAP | SYS) core="; core dump: coredumpctl info $shell" ;;
        esac
    else
        how="exit $status"
    fi
    if [ "$hung" = 1 ]; then
        how="hung, $how"
    fi
    # Its leftovers, whatever ended it.
    "$mine" cleanup "$sid" 9>&- || log "cleanup failed ($mine cleanup $sid)"
    # The compositor quitting ends the shell too (exit 255).
    if ! compositor_alive; then
        log "the shell ended ($how) and the compositor is gone (logout?): ending"
        exit 0
    fi
    log "the shell crashed ($how, after $ran s; its log: qs log --pid $shell$core)"
    now=$EPOCHSECONDS
    recent=()
    for t in "${crashes[@]}"; do
        if [ $((now - t)) -lt 300 ]; then
            recent+=("$t")
        fi
    done
    crashes=("${recent[@]}" "$now")
    if [ "${#crashes[@]}" -ge 5 ]; then
        log "gave up: ${#crashes[@]} crashes within 5 minutes. Once it's fixed: mine restart"
        # The shell may have turned the screen off (services/Idle.qml) and
        # nothing would turn it on again: every screen back on.
        mmsg get all-monitors 2>/dev/null | jq -r '.monitors[].name' 2>/dev/null |
            while IFS= read -r out; do
                mmsg dispatch "wakeup_monitor,$out" >/dev/null 2>&1
            done
        exit 1
    fi
    delay=$((1 << (${#crashes[@]} - 1)))
    log "starting it again in $delay s"
    sleep "$delay" 9>&- &
    helper=$!
    wait "$helper"
    helper=""
done
