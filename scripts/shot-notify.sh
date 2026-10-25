#!/bin/sh
# Tell about a new screenshot, with the picture, and act on the answer:
# clicking the notification opens it, Edit marks it up in the shell (the
# screenshot overlay's markup, over IPC; swappy when the shell says no,
# Style.screenshotEditor "swappy" among others, or isn't there), Delete
# removes it.
#   shot-notify.sh <file> [quiet]
# quiet: a live activity has shown it already, so the notification goes
# straight to the list (x-mine-quiet), still with its buttons.
# MINE_SHOT_DRYRUN=1 (tests): only prints what it would open.
file="$1"
[ -f "$file" ] || exit 0
quiet=""
[ "$2" = quiet ] && quiet="boolean:x-mine-quiet:true"

action=$(notify-send -a "Screenshot" -i camera-photo \
    -h "string:image-path:$file" ${quiet:+-h "$quiet"} \
    -A default=Open -A edit=Edit -A delete=Delete \
    "Screenshot saved" "$(basename "$file") · copied to the clipboard")

run() {
    if [ "$MINE_SHOT_DRYRUN" = 1 ]; then
        echo "shot-notify (dry run): $*"
    else
        setsid -f "$@" >/dev/null 2>&1
    fi
}

# The shell this came from (scripts/ is in it).
shell=$(cd "$(dirname "$0")/.." && pwd)

edit() {
    if [ "$MINE_SHOT_DRYRUN" = 1 ]; then
        echo "shot-notify (dry run): qs ipc -p $shell call screenshot edit $file (swappy unless it prints ok)"
        return
    fi
    # Prints "ok" when the markup opens; anything else (no such function,
    # no shell running, busy, the swappy setting): swappy.
    [ "$(qs ipc -p "$shell" call screenshot edit "$file" 2>/dev/null)" = ok ] || run swappy -f "$file"
}

case "$action" in
    default) run xdg-open "$file" ;;
    edit) edit ;;
    delete) rm -f -- "$file" ;;
esac
