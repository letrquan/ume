#!/bin/sh
# tablet-keyboard.sh on | off | status
# Whether the laptop's own keyboard and touchpad keep working when the
# screen is folded back into a tablet (Settings → On-screen keyboard →
# Tablet, Style.tabletKeepKeyboard).
#
# libinput turns the internal keyboard and the touchpad off while a
# tablet-mode switch is on, unless a quirk says ModelTabletModeNoSuspend.
# libinput's own 50-system-hp.quirks has that for the sibling HP OmniBook
# Ultra Flip 14 (board 8CDE: it says tablet mode just before 180° and the
# hardware cuts the inputs just after, so they work laid flat). This puts
# the same two sections for this laptop (HP OmniBook X Flip 14, board 8EA1)
# in /etc/libinput/local-overrides.quirks, between two marker lines, or
# takes them out again; anything else in the file stays.
#
#   on, off  as root: sudo sh tablet-keyboard.sh on
#   status   prints "on" or "off" (no root needed)
#
# libinput reads quirks when a device appears: it counts after logging out
# and in (mango starts libinput again). If libinput-tools is installed, `on`
# checks the new file with `libinput quirks validate` before putting it in
# place (a file libinput can't read would lose every quirk).
#
# MINE_LIBINPUT_QUIRKS (tests): another file. MINE_LIBINPUT_QUIRKS_TOOL:
# another libinput-quirks; MINE_LIBINPUT_DATA: libinput's own quirks dir.
set -eu

file=${MINE_LIBINPUT_QUIRKS:-/etc/libinput/local-overrides.quirks}
tool=${MINE_LIBINPUT_QUIRKS_TOOL:-/usr/lib/libinput/libinput-quirks}
data=${MINE_LIBINPUT_DATA:-/usr/share/libinput}
begin="# >>> mine shell: tablet keyboard (scripts/tablet-keyboard.sh) >>>"
end="# <<< mine shell: tablet keyboard <<<"

section() {
    cat <<EOF
$begin
# HP OmniBook X Flip 14 (board 8EA1): libinput doesn't turn the keyboard and
# touchpad off in tablet mode, like the Ultra Flip 14 in 50-system-hp.quirks.
# Take it out with: sudo sh tablet-keyboard.sh off (the mine shell's scripts/)
[mine shell: HP OmniBook X Flip Laptop 14 Keyboard]
MatchBus=ps2
MatchUdevType=keyboard
MatchDMIModalias=dmi:*:svnHP:*:rn8EA1:*
ModelTabletModeNoSuspend=1

[mine shell: HP OmniBook X Flip Laptop 14 Touchpad]
MatchBus=i2c
MatchUdevType=touchpad
MatchDMIModalias=dmi:*:svnHP:*:rn8EA1:*
ModelTabletModeNoSuspend=1
$end
EOF
}

has() {
    [ -f "$file" ] && grep -qxF "$begin" "$file"
}

# The file without our section (refuses if its end marker is gone, so a
# hand-edited file is never cut short).
without() {
    awk -v b="$begin" -v e="$end" '
        $0 == b { skip = 1; found = 1; next }
        skip && $0 == e { skip = 0; next }
        !skip { print }
        END { if (skip) exit 3 }
    ' "$file"
}

# Writes stdin to the file through a temporary file next to it.
put() {
    tmp=$(mktemp "$file.XXXXXX")
    cat >"$tmp"
    chmod 644 "$tmp"
    mv -f "$tmp" "$file"
}

writable() {
    dir=$(dirname "$file")
    if [ -e "$dir" ] && [ ! -w "$dir" ]; then
        echo "tablet-keyboard: can't write $file: run it with sudo" >&2
        exit 1
    fi
    mkdir -p "$dir" 2>/dev/null || { echo "tablet-keyboard: can't make $dir: run it with sudo" >&2; exit 1; }
}

case "${1:-}" in
    status)
        if has; then echo on; else echo off; fi
        ;;
    on)
        if has; then
            echo "on (already in $file)"
            exit 0
        fi
        writable
        board=$(cat /sys/class/dmi/id/board_name 2>/dev/null || true)
        [ "$board" = 8EA1 ] || echo "tablet-keyboard: this isn't board 8EA1 (it's ${board:-unknown}); the quirk won't match it" >&2
        new=$(mktemp)
        trap 'rm -f "$new"; rm -rf "${check:-}"' EXIT
        {
            if [ -s "$file" ]; then
                cat "$file"
                # The old content ends with a line break.
                [ -z "$(tail -c 1 "$file")" ] || echo
            fi
            section
        } >"$new"
        if [ -x "$tool" ]; then
            check=$(mktemp -d)
            cp "$data"/*.quirks "$check"/ 2>/dev/null || true
            cp "$new" "$check/99-local-overrides.quirks"
            if ! "$tool" validate --data-dir "$check"; then
                echo "tablet-keyboard: libinput can't read the new file; $file is unchanged" >&2
                exit 1
            fi
        else
            echo "tablet-keyboard: not checked (no $tool: libinput-tools isn't installed)" >&2
        fi
        put <"$new"
        echo "on: log out and in for it to count"
        ;;
    off)
        if ! has; then
            echo "off (not in $file)"
            exit 0
        fi
        writable
        rest=$(mktemp)
        trap 'rm -f "$rest"' EXIT
        if ! without >"$rest"; then
            echo "tablet-keyboard: $file has the start marker but not the end one; fix it by hand" >&2
            exit 1
        fi
        if grep -q '[^[:space:]]' "$rest"; then
            put <"$rest"
        else
            # Only ours was in it.
            rm -f "$file"
        fi
        echo "off: log out and in for it to count"
        ;;
    *)
        echo "usage: tablet-keyboard.sh on | off | status" >&2
        exit 2
        ;;
esac
