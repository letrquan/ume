#!/bin/sh
# Find the QR codes and barcodes in a picture (or a part of it) and print
# what zbarimg says, as XML (services/qr.js reads it).
#   qr-scan.sh <picture.png> <geometry or "">
# geometry: WxH+X+Y in the picture's pixels ("" = all of it).
# Exit 0: found some; 4: none (zbarimg's own codes); else it failed.
# A small piece is scaled up first, square pixels kept sharp (zbar wants a
# few pixels per module).
picture="$1"
geometry="$2"

work="${XDG_RUNTIME_DIR:-/tmp}/mine-qr-$$.png"
trap 'rm -f "$work"' EXIT

# Read as PNG, under ../magick/policy.xml (see ocr.sh).
MAGICK_CONFIGURE_PATH=$(cd "$(dirname -- "$0")/.." && pwd)/magick
export MAGICK_CONFIGURE_PATH

crop=""
[ -n "$geometry" ] && crop="-crop $geometry +repage"
# shellcheck disable=SC2086
magick "png:$picture" $crop "png:$work" || exit 1

size=$(magick identify -format '%w %h' "png:$work")
w=${size% *}
h=${size#* }
if [ "$w" -lt 400 ] || [ "$h" -lt 400 ]; then
    magick "png:$work" -filter point -resize 300% "png:$work" || exit 1
fi

# --nodbus: zbar may also announce what it found on D-Bus; not wanted.
zbarimg --xml --nodbus -q "$work"
