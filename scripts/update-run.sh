#!/bin/sh
# The updates panel's install (services/UpdateRun.qml): the repo packages
# (pacman -Syu through pkexec, so the shell's own password dialog asks),
# then your Flatpaks (as you, never through pkexec). AUR packages are never
# built here (the panel's "Build in terminal").
#
# The shell starts this detached: replacing Qt's or Quickshell's libraries
# in the middle of the transaction can crash the shell (shell-keeper then
# starts it again), and that must never stop pacman. So everything the
# shell needs to pick it back up is written down here:
#   <state>  JSON, written whole each time (tmp + mv):
#            id, pid (this script), log, started (s), logStart (pacman.log's
#            size before pacman ran), repo (1 = pacman -Syu was asked),
#            flatpakStep (how many Flatpak updates were waiting, 0 = none),
#            pacman (pkexec's exit: -1 = not yet or not asked; 126 / 127 =
#            the password was dismissed or not given), logEnd (pacman.log's
#            size after), flatpak (-1 = not yet or skipped), modulesGone
#            (1 = the running kernel's modules are no longer installed),
#            finished (s, 0 = still running)
#   <log>    pacman's and flatpak's output, opened HERE, before pkexec, so
#            the file is yours
# Progress itself comes from pacman.log (the shell tails it from logStart).
# At the end the shell is told over IPC (`updates done`), like after the
# terminal; a shell that's down then reads <state> when it starts.
#
#   update-run.sh <id> <state> <log> <pacman.log> <modules dir> <repo 0|1> <flatpak count> <shell dir>
#
# While it runs, sleep and shutdown wait (systemd-inhibit "mine updates",
# held by a helper that ends with this script, however it ends; closing the
# lid still suspends).
id=$1 state=$2 log=$3 plog=$4 modules=$5 repo=$6 flatpak=$7 shelldir=$8

case $id in "" | *[!0-9]*) echo "update-run: bad id" >&2; exit 2 ;; esac
case $repo in 0 | 1) ;; *) echo "update-run: bad repo step" >&2; exit 2 ;; esac
case $flatpak in "" | *[!0-9]*) echo "update-run: bad flatpak count" >&2; exit 2 ;; esac
[ -n "$state" ] && [ -n "$log" ] && [ -n "$plog" ] || { echo "update-run: missing paths" >&2; exit 2; }

umask 077
mkdir -p "$(dirname "$state")" "$(dirname "$log")"
# The log: new for this run, and yours (pkexec only gets the open file).
: > "$log" || exit 1
exec >> "$log" 2>&1 < /dev/null
# Never stopped by a hangup (it has no terminal anyway) or a stray Ctrl+C.
trap '' HUP INT

size() {
    stat -c %s -- "$plog" 2>/dev/null || echo 0
}
esc() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
started=$(date +%s)
logstart=$(size)
pcode=-1 logend=-1 fcode=-1 gone=0 finished=0
put() {
    printf '{"id":"%s","pid":%s,"log":"%s","started":%s,"logStart":%s,"repo":%s,"flatpakStep":%s,"pacman":%s,"logEnd":%s,"flatpak":%s,"modulesGone":%s,"finished":%s}\n' \
        "$id" "$$" "$(esc "$log")" "$started" "$logstart" "$repo" "$flatpak" \
        "$pcode" "$logend" "$fcode" "$gone" "$finished" > "$state.tmp" \
        && mv -f -- "$state.tmp" "$state"
}
put

# Sleep and shutdown wait while this runs. The helper (tail --pid) ends
# with this script, even if it's killed, so the lock never outlives it.
if command -v systemd-inhibit > /dev/null; then
    systemd-inhibit --what=shutdown:sleep --who="mine updates" --why="Installing updates" --mode=block \
        tail --pid=$$ -f /dev/null > /dev/null &
fi

if [ "$repo" = 1 ]; then
    echo "$ pacman -Syu"
    # The C locale: the shell reads "Packages (N)" and "error:" in English.
    # (pkexec keeps LC_ALL.)
    # Full paths: never a pkexec found first in a folder of yours on PATH
    # (MINE_UPDATES_PKEXEC: the tests' fake one). The password dialog
    # compares this command with UpdateRun.rootCommand.
    LC_ALL=C.UTF-8 "${MINE_UPDATES_PKEXEC:-/usr/bin/pkexec}" /usr/bin/pacman -Syu --noconfirm --noprogressbar
    pcode=$?
    logend=$(size)
    put
fi

# Flatpak only after pacman went through (or wasn't asked): a dismissed
# password or a failed upgrade stops here.
if [ "$flatpak" -gt 0 ] && { [ "$repo" = 0 ] || [ "$pcode" = 0 ]; }; then
    echo
    echo "$ flatpak update"
    flatpak update --user -y --noninteractive
    fcode=$?
fi

# A new kernel replaced the running one's modules: say "restart soon".
[ -d "$modules/$(uname -r)" ] || gone=1
finished=$(date +%s)
put
echo
echo "Done."

# Tell the shell (it reads <state> again). A shell that isn't running reads
# it when it starts; a hung one must not keep this around.
timeout 5 qs ipc -p "$shelldir" call updates done > /dev/null 2>&1
exit 0
