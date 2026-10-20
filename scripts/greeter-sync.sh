#!/bin/sh
# Copies what the login screen shows to /var/lib/mine-greeter: the
# wallpaper (scaled to the screen), the colors, your picture (~/.face) and
# a few settings (24-hour clock, the time's font...). The login screen runs
# as the `greeter` user, which can't read your home folder; this folder is
# yours and readable by everyone. Does nothing until the login screen is
# installed (greeter-install.sh makes the folder). Run by
# services/Wallpaper.qml after each color change and at start.
#
# MINE_GREETER_ASSETS: another folder (tests).
set -eu

dir=${MINE_GREETER_ASSETS:-/var/lib/mine-greeter}
[ -d "$dir" ] && [ -w "$dir" ] || exit 0

state=${XDG_STATE_HOME:-$HOME/.local/state}/mine-shell
colors=$state/colors.json
settings=$state/settings.json
[ -f "$colors" ] || exit 0
command -v jq >/dev/null || exit 0

# The wallpaper, only when it changed (path + time), at the screen's size.
# Decoded as its ending says, under ../magick/policy.xml (as in
# wallpaper-thumbs.sh: a ".jpg" that is really PostScript is refused); any
# other kind of file isn't copied, and the login screen keeps the last one.
wall=$(jq -r '.wallpaper // empty' "$colors")
case $(printf %s "${wall##*.}" | tr '[:upper:]' '[:lower:]') in
    jpg | jpeg) coder=jpeg ;;
    png) coder=png ;;
    webp) coder=webp ;;
    *) coder="" ;;
esac
MAGICK_CONFIGURE_PATH=$(cd "$(dirname -- "$0")/.." && pwd)/magick
export MAGICK_CONFIGURE_PATH
if [ -n "$wall" ] && [ -n "$coder" ] && [ -f "$wall" ]; then
    stamp="$wall $(stat -c %Y "$wall")"
    if [ "$(cat "$dir/.wallpaper-source" 2>/dev/null)" != "$stamp" ] || [ ! -f "$dir/wallpaper.jpg" ]; then
        if command -v magick >/dev/null; then
            magick "$coder:$wall[0]" -auto-orient -resize '2560x1600>' -quality 90 \
                "jpeg:$dir/.wallpaper.jpg" || rm -f "$dir/.wallpaper.jpg"
        else
            cp -f "$wall" "$dir/.wallpaper.jpg"
        fi
        if [ -s "$dir/.wallpaper.jpg" ]; then
            chmod 644 "$dir/.wallpaper.jpg"
            mv -f "$dir/.wallpaper.jpg" "$dir/wallpaper.jpg"
            printf '%s' "$stamp" > "$dir/.wallpaper-source"
        fi
    fi
fi

# The colors, pointing at that copy.
jq --arg w "$dir/wallpaper.jpg" '.wallpaper = $w' "$colors" > "$dir/.colors.json"
chmod 644 "$dir/.colors.json"
mv -f "$dir/.colors.json" "$dir/colors.json"

# Your picture, by your name (the login screen shows face-<user>).
if [ -f "$HOME/.face" ]; then
    me=$(id -un)
    cp -f "$HOME/.face" "$dir/.face.tmp"
    chmod 644 "$dir/.face.tmp"
    mv -f "$dir/.face.tmp" "$dir/face-$me"
fi

# The settings the login screen uses (the rest stay at their defaults).
if [ -f "$settings" ]; then
    jq '{clock24h, clockLocale, lockClockFont, lockHideAfter, font, iconFont}
        | with_entries(select(.value != null))' "$settings" > "$dir/.settings.json"
else
    echo '{}' > "$dir/.settings.json"
fi
chmod 644 "$dir/.settings.json"
mv -f "$dir/.settings.json" "$dir/settings.json"
