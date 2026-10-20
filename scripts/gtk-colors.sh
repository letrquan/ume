#!/bin/sh
# Puts the shell's GTK colors where GTK apps read them, or takes them away.
#   gtk-colors.sh install <state dir> <config home>
#       <state dir>/gtk3.css -> <config home>/gtk-3.0/gtk.css (same for 4)
#   gtk-colors.sh remove <config home>
#
# Only files with the marker "GTK colors generated with Matugen" are ever
# replaced or removed: end-4's (Hyprland) carry it too, and GNOME's login
# runs ~/.config/hypr/custom/scripts/gtk-colors.sh off, which removes
# exactly those, so GNOME never sees these colors. A hand-written gtk.css
# (no marker) is left alone. Copies are atomic (temp file + mv).
# Exit 3: a state file is missing (the caller makes the colors first).
marker="GTK colors generated with Matugen"

ours() {
    [ ! -e "$1" ] || grep -q "$marker" "$1"
}

case "$1" in
install)
    state=$2 cfg=$3
    for v in 3 4; do
        [ -s "$state/gtk$v.css" ] || exit 3
    done
    for v in 3 4; do
        dst="$cfg/gtk-$v.0/gtk.css"
        if ! ours "$dst"; then
            echo "gtk-colors: $dst is not generated, left alone" >&2
            continue
        fi
        mkdir -p "$cfg/gtk-$v.0" &&
            cp "$state/gtk$v.css" "$dst.mine-tmp" &&
            mv -f "$dst.mine-tmp" "$dst"
    done
    ;;
remove)
    cfg=$2
    for v in 3 4; do
        dst="$cfg/gtk-$v.0/gtk.css"
        [ -e "$dst" ] && ours "$dst" && rm -f "$dst"
    done
    exit 0
    ;;
*)
    echo "usage: gtk-colors.sh install <state dir> <config home> | remove <config home>" >&2
    exit 2
    ;;
esac
