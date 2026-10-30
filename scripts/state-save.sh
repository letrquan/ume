#!/bin/sh
# Save one of the shell's state files the safe way (services/StateStore.qml:
# the notes, the timers). The new content comes on stdin and goes into a
# new file next to the old one (mktemp: a fresh name, readable only by you,
# never opened through a link), then is moved over it. A move replaces a
# link someone left at that name instead of writing through it, and a
# reader never sees half a file. Nothing arrived (empty input): the old
# file stays as it was.
#   state-save.sh <file>        (the content on stdin)
# Exit 0: saved; 1: not saved (the old file is untouched).
f=$1
case "$f" in
    /*) ;;
    *) echo "state-save: not a full path: $f" >&2; exit 1 ;;
esac
d=$(dirname -- "$f")
mkdir -p -- "$d" || exit 1
tmp=$(mktemp -- "$d/.$(basename -- "$f").XXXXXX") || exit 1
# -T: the name itself is replaced, even when a link to a folder sits there.
if cat > "$tmp" && [ -s "$tmp" ] && mv -fT -- "$tmp" "$f"; then
    exit 0
fi
rm -f -- "$tmp"
exit 1
