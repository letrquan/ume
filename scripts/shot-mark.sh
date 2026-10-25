#!/bin/sh
# A marked-up screenshot (services/Screenshot.qml): the cut, its blurred
# rectangles turned to blocks, the drawn marks laid on top; saved or copied.
#   shot-mark.sh <picture> <cut> <marks.png|-> <out|-> <block> [blur...]
# <cut>       WxH+X+Y: the part of <picture> that is kept (all of it: its
#             size +0+0). Cut exactly like the plain screenshot.
# <blur>      WxH+X+Y in the kept part: made blocks of <block> px, each the
#             average of its pixels (-scale down, -sample back up), so the
#             detail is gone, not hidden. The overlay snaps them to whole
#             blocks and shows the same blocks.
# <marks.png> lines, arrows, boxes and text, transparent elsewhere, at any
#             size (Qt draws it devicePixelRatio times bigger): scaled to the
#             kept part. Pixels without a mark stay exactly the plain cut.
#             Removed afterwards.
# <out>       the file, or - for the clipboard only (nothing kept). The
#             picture is made in the private runtime folder and then moved
#             to <out>: never left half written, and a link someone left at
#             that name (Chrome's Flatpak can write to ~/Pictures) is
#             replaced, never written through.
# MINE_SHOT_DRYRUN=1 (tests): the clipboard copy is only printed.
pic=$1 cut=$2 marks=$3 out=$4 block=$5
[ $# -ge 5 ] || { echo "usage: shot-mark.sh <picture> <cut> <marks.png|-> <out|-> <block> [blur...]" >&2; exit 2; }
shift 5

# The pictures are ours or a screenshot the notification named; still,
# ImageMagick reads them under the shell's rules (magick/policy.xml).
export MAGICK_CONFIGURE_PATH="$(dirname "$0")/../magick"

tmp="${XDG_RUNTIME_DIR:-/tmp}/mine-shot-$$.png"
cleanup() {
    [ "$marks" = - ] || rm -f -- "$marks"
    # A failed write leaves nothing behind.
    rm -f -- "$tmp"
}
trap cleanup EXIT

geometry() {
    case $1 in
        *[!0-9x+]* | "" | *x*x* | *+*+*+* ) return 1 ;;
        [0-9]*x[0-9]*+[0-9]*+[0-9]*) return 0 ;;
    esac
    return 1
}
geometry "$cut" || { echo "shot-mark: bad cut $cut" >&2; exit 2; }
case $block in *[!0-9]* | "" | 0 | 1) echo "shot-mark: bad block $block" >&2; exit 2 ;; esac
blurs=$*
for r in $blurs; do
    geometry "$r" || { echo "shot-mark: bad blur $r" >&2; exit 2; }
done

set -- "png:$pic" -crop "$cut" +repage
for r in $blurs; do
    size=${r%%+*} at=${r#*+}
    w=${size%x*} h=${size#*x}
    x=${at%+*} y=${at#*+}
    bw=$(( (w + block - 1) / block )) bh=$(( (h + block - 1) / block ))
    set -- "$@" "(" +clone -crop "$r" +repage -scale "${bw}x${bh}!" -sample "${w}x${h}!" ")" \
        -geometry "+$x+$y" -composite
done
if [ "$marks" != - ]; then
    set -- "$@" "(" "png:$marks" -scale "${cut%%+*}!" ")" -geometry +0+0 -composite
fi

if [ "$MINE_SHOT_DRYRUN" = 1 ] && [ "$marks" != - ]; then
    echo "shot-mark (dry run): marks $(magick identify -format '%wx%h' "png:$marks") scaled to ${cut%%+*}"
fi
magick "$@" "png:$tmp" || exit 1

if [ "$out" != - ]; then
    mkdir -p "$(dirname "$out")" && mv -f -- "$tmp" "$out" || exit 1
elif [ "$MINE_SHOT_DRYRUN" = 1 ]; then
    echo "shot-mark (dry run): wl-copy $(magick identify -format '%wx%h' "png:$tmp") picture"
else
    wl-copy --type image/png < "$tmp"
fi
