#!/bin/sh
# Read the text in a picture (or a part of it) and print it.
#   ocr.sh <picture.png> <geometry or ""> <languages>
# geometry: WxH+X+Y in the picture's pixels ("" = all of it).
# languages: tesseract's, e.g. "eng+vie"; "auto" = English, plus
# Vietnamese if its data is installed (tesseract-data-vie).
# Small pieces are scaled up first (tesseract reads ~30 px letters best),
# and everything goes grey with a bit more contrast.
picture="$1"
geometry="$2"
langs="${3:-auto}"

work="${XDG_RUNTIME_DIR:-/tmp}/mine-ocr-$$.png"
trap 'rm -f "$work"' EXIT

# The picture is a PNG (the screenshot's frozen screen): read as PNG, never
# as whatever its first bytes say, under ../magick/policy.xml (only JPEG,
# PNG and WebP; see wallpaper-thumbs.sh).
MAGICK_CONFIGURE_PATH=$(cd "$(dirname -- "$0")/.." && pwd)/magick
export MAGICK_CONFIGURE_PATH

if [ "$langs" = auto ]; then
    have=$(tesseract --list-langs 2>/dev/null)
    langs=eng
    printf '%s\n' "$have" | grep -qx vie && langs="eng+vie"
fi

crop=""
[ -n "$geometry" ] && crop="-crop $geometry +repage"
# shellcheck disable=SC2086
magick "png:$picture" $crop -colorspace Gray "png:$work" || exit 1

# Under ~1000 px wide or ~300 px tall: twice the size.
size=$(magick identify -format '%w %h' "png:$work")
w=${size% *}
h=${size#* }
if [ "$w" -lt 1000 ] || [ "$h" -lt 300 ]; then
    magick "png:$work" -resize 200% -level 10%,90% "png:$work" || exit 1
fi

# --psm 6 would force one block; the default (3) finds the layout itself.
tesseract "$work" - -l "$langs" 2>/dev/null
