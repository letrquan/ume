#!/bin/sh
# Started by greetd (as the `greeter` user, see /etc/greetd/config.toml):
# cage, a compositor that shows one window full screen, running the login
# screen. When you log in, the login screen quits, cage ends with it, and
# greetd starts your session.
# What it printed last time: /var/cache/mine-greeter/greeter.log (only the
# greeter user can read it: `sudo cat` it).
export XDG_CACHE_HOME=/var/cache/mine-greeter/cache
export XCURSOR_THEME=Bibata-Modern-Classic
export XCURSOR_SIZE=24
# Same size as your desktop (mango's scale 1.25); cage has no scaling.
export QT_SCALE_FACTOR=1.25
export QT_QPA_PLATFORM=wayland
# cage draws no window frames, so Qt would draw its own (a title bar with
# an X): none, the login screen is the whole screen.
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# What the login screen writes stays the greeter's: new files only it can
# read (umask; your session doesn't inherit it, greetd starts that), its
# folder closed to others, and the log made anew (an old one would keep
# its old 0644). greetd's debug lines (who logs in, the session's command)
# aren't logged; the password never is (Quickshell writes <CENSORED>).
umask 077
cache=/var/cache/mine-greeter
chmod 700 "$cache" 2>/dev/null
rm -f "$cache/greeter.log"
cage -s -m last -- /usr/bin/qs --log-rules 'quickshell.service.greetd.debug=false' \
    -p /etc/greetd/mine-greeter/greeter.qml > "$cache/greeter.log" 2>&1
status=$?
# 0: you logged in (the login screen quits once greetd has the session).
[ "$status" = 0 ] && exit 0

# Anything else: it didn't load, or crashed (cage passes on its exit code,
# 128 + the signal for a crash). Quitting would have greetd start it again
# and again until systemd gives up: a black screen at boot. A text login
# on the same screen instead, so there's always a way in; it starts mango.
# After you log out, the real login screen gets another try.
printf '\033[H\033[2J'
echo "The login screen didn't start (exit $status). Log in here to start mango."
echo "What went wrong: sudo cat $cache/greeter.log"
echo
exec /usr/bin/agreety --cmd "env XDG_SESSION_DESKTOP=mango XDG_CURRENT_DESKTOP=mango systemd-cat --identifier=mango-session -- mango"
