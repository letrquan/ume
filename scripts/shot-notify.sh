#!/bin/sh
# Tell about a new screenshot, with the picture, and act on the answer:
# clicking the notification opens it, Edit opens swappy, Delete removes it.
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

case "$action" in
    default) run xdg-open "$file" ;;
    edit) run swappy -f "$file" ;;
    delete) rm -f -- "$file" ;;
esac
