#!/bin/sh
# "Switch to GNOME" in the power menu: leaves a note for the login screen
# (/var/lib/mine-greeter/next-session.json: the session and when), then logs
# out of mango. The login screen picks that session once: only while the
# note is newer than the last login it remembers (greeter/Greeter.qml). You
# still type your password there.
#   switch-session.sh <session>   a file name in /usr/share/wayland-sessions
#
# No login screen folder (GDM, or not installed): only the log out.
# MINE_GREETER_ASSETS: another folder; MINE_SESSION_DRYRUN=1: no log out (tests).
set -eu

session=${1:?which session}
[ -f "/usr/share/wayland-sessions/$session.desktop" ] || { echo "no session $session" >&2; exit 1; }

dir=${MINE_GREETER_ASSETS:-/var/lib/mine-greeter}
if [ -d "$dir" ] && [ -w "$dir" ]; then
    printf '{ "session": "%s", "at": %s }\n' "$session" "$(date +%s%3N)" > "$dir/.next-session.json"
    chmod 644 "$dir/.next-session.json"
    mv -f "$dir/.next-session.json" "$dir/next-session.json"
fi

[ "${MINE_SESSION_DRYRUN:-}" = 1 ] && { echo "switch-session (dry run): would log out to $session"; exit 0; }

# mango's names, so a user manager still up when the next session starts
# (a quick password) doesn't hand them to it.
systemctl --user unset-environment XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP WAYLAND_DISPLAY DISPLAY 2>/dev/null || true
exec mmsg dispatch quit
