#!/bin/sh
# wallpaper-thumbs.sh <thumb-dir> <image>...
# Makes a small 16:10 thumbnail of each image for the wallpaper picker (once,
# and again when the image is newer than its thumbnail), and prints
# "image<TAB>thumbnail" for each one as soon as it is ready.
#
# Other apps can drop files in the wallpaper folder (a browser's "Save image
# as"), so ImageMagick is held tight: the decoder is the one the file's
# ending names, never guessed from its first bytes (a ".jpg" that is really
# PostScript would reach Ghostscript), any other file is skipped, and
# ../magick/policy.xml allows only JPEG, PNG and WebP.
MAGICK_CONFIGURE_PATH=$(cd "$(dirname -- "$0")/.." && pwd)/magick
export MAGICK_CONFIGURE_PATH
dir=$1
shift
mkdir -p "$dir" || exit 1
for f in "$@"; do
    case $(printf %s "${f##*.}" | tr '[:upper:]' '[:lower:]') in
        jpg | jpeg) coder=jpeg ;;
        png) coder=png ;;
        webp) coder=webp ;;
        *) continue ;;
    esac
    t="$dir/$(printf %s "$f" | md5sum | cut -c1-32).jpg"
    if [ ! -s "$t" ] || [ "$f" -nt "$t" ]; then
        # jpeg:size lets the decoder shrink big photos while reading them.
        nice -n 10 magick -define jpeg:size=704x440 "$coder:$f[0]" -auto-orient \
            -thumbnail 352x220^ -gravity center -extent 352x220 \
            -strip -quality 82 "jpeg:$t" 2>/dev/null || continue
    fi
    printf '%s\t%s\n' "$f" "$t"
done
