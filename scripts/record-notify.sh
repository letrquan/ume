#!/bin/sh
# Tell about a finished screen recording, with a frame from it, and act on
# the answer: clicking the notification opens the video, "Show in folder"
# opens the file manager on it.
#   record-notify.sh <file> <seconds> [why it stopped by itself]
# MINE_RECORD_DRYRUN=1 (tests): nothing is shown or opened, only printed.
file="$1"
secs="${2:-0}"
why="$3"

if [ "$MINE_RECORD_DRYRUN" = 1 ]; then
    notify() { echo "record-notify (dry run): notify-send $*" >&2; echo "${ANSWER:-}"; }
    run() { echo "record-notify (dry run): $*"; }
else
    notify() { notify-send "$@"; }
    run() { setsid -f "$@" >/dev/null 2>&1; }
fi

if [ ! -s "$file" ]; then
    rm -f -- "$file"
    # "--": the reason is wf-recorder's own line, which may start with "-".
    notify -a "Screen recording" -i dialog-error -- "Recording failed" "${why:-Nothing was saved}" >/dev/null
    exit 0
fi

# 1:05, 12:30, 1:02:03
h=$((secs / 3600)); m=$(((secs % 3600) / 60)); s=$((secs % 60))
if [ "$h" -gt 0 ]; then
    length=$(printf '%d:%02d:%02d' "$h" "$m" "$s")
else
    length=$(printf '%d:%02d' "$m" "$s")
fi

# A frame from half a second in (or the first one, for very short ones).
# Kept (in the runtime dir, gone at logout) so the notification list can
# still show it.
name=$(basename "$file")
thumb="${XDG_RUNTIME_DIR:-/tmp}/mine-record-${name%.*}.png"
ffmpeg -loglevel error -y -ss 0.5 -i "$file" -frames:v 1 -vf scale=480:-2 "$thumb" 2>/dev/null
[ -s "$thumb" ] || ffmpeg -loglevel error -y -i "$file" -frames:v 1 -vf scale=480:-2 "$thumb" 2>/dev/null
image=""
[ -s "$thumb" ] && image="string:image-path:$thumb"

action=$(notify -a "Screen recording" -i video-x-generic ${image:+-h "$image"} \
    -A default=Open -A folder="Show in folder" \
    "Recording saved" "$name · $length")

case "$action" in
    default) run xdg-open "$file" ;;
    folder)
        if command -v nautilus >/dev/null; then
            run nautilus --select "$file"
        else
            run xdg-open "$(dirname "$file")"
        fi ;;
esac
