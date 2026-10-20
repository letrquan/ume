#!/bin/sh
# Tell about a picked color, with a swatch of it: "Copy as rgb()" copies
# it that way instead of the hex.
#   color-notify.sh <#hex> <rgb(r, g, b)> [quiet]
# quiet: a live activity has shown it already; straight to the list.
# MINE_PICKER_DRYRUN=1 (tests): nothing is shown or copied, only printed.
hex="$1"
rgb="$2"
quiet=""
[ "$3" = quiet ] && quiet="boolean:x-mine-quiet:true"

if [ "$MINE_PICKER_DRYRUN" = 1 ]; then
    notify() { echo "color-notify (dry run): notify-send $*" >&2; echo "${ANSWER:-}"; }
    copy() { echo "color-notify (dry run): wl-copy $*"; }
else
    notify() { notify-send "$@"; }
    copy() { wl-copy -- "$1"; }
fi

# Kept (in the runtime dir, gone at logout) so the notification list can
# still show it.
swatch="${XDG_RUNTIME_DIR:-/tmp}/mine-color-${hex#\#}.png"
magick -size 96x96 "xc:$hex" "$swatch" 2>/dev/null
image=""
[ -s "$swatch" ] && image="string:image-path:$swatch"

action=$(notify -a "Color picker" -i color-select ${image:+-h "$image"} ${quiet:+-h "$quiet"} \
    -A rgb="Copy as rgb()" \
    "$hex" "Copied to the clipboard · $rgb")

[ "$action" = rgb ] && copy "$rgb"
exit 0
