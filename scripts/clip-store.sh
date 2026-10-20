#!/bin/sh
# What the clipboard watcher runs for every text you copy (services/Clipboard.qml:
# `wl-paste --type text --watch sh clip-store.sh`, the copy on stdin). It stores
# the copy in cliphist, unless it is a secret:
#  - the whole copy (give or take spaces and newlines around it) is an API key,
#    a token or a private key: the list is in secret() below;
#  - it is a 6-digit code that a notification of the last 2 minutes shows (a
#    code your phone got, through KDE Connect). Other 6-digit numbers, like a
#    price, are kept.
# What a password manager marks as secret (wl-copy --sensitive) never gets
# here: cliphist leaves it out itself.
#
# Per copy: this sh becomes one gawk, which hands the copy unchanged (byte for
# byte) to `cliphist store`. A copy that is exactly 6 digits is decided in the
# background instead (one sh, one or two jq): wl-paste waits for this script
# before it reads the next copy, and the code check may wait a second.
#
# MINE_NOTIF_HISTORY: the shell's notifications file (same as services/Notifs.qml).

notifs=${MINE_NOTIF_HISTORY:-$HOME/.local/state/mine-shell/notifications.json}

# clip-store.sh --code (in the background, CLIP_CODE / CLIP_TEXT set below):
# stored unless a notification of the last 2 minutes shows the code, as a
# number of its own (or split, "123 456" / "123-456"). Asked once more a
# second later: the shell writes a new notification to the file within one.
if [ "$1" = --code ]; then
    shown() {
        jq -e --arg code "$CLIP_CODE" '
            ("(^|[^0-9])" + $code[0:3] + "[ -]?" + $code[3:] + "([^0-9]|$)") as $re
            | ((now - 120) * 1000) as $since
            | any(.list[]?; (.time // 0) >= $since
                  and ((.summary // "") + " " + (.body // "") | test($re)))
        ' "$notifs" >/dev/null 2>&1
    }
    shown || { sleep 1; shown; } || printf '%s' "$CLIP_TEXT" | cliphist store
    exit
fi

# Not a plain copy (nothing there, or marked secret): cliphist knows what to
# do. Without gawk, keep everything, as before.
[ "${CLIPBOARD_STATE:-data}" = data ] || exec cliphist store
command -v gawk >/dev/null || exec cliphist store

export LC_ALL=C CLIP_STORE="$0"
exec gawk '
# The secrets, matched against the whole copy. Narrow on purpose: a match
# means the copy is not kept, so a word or a sentence must never match.
function secret(t) {
    return t ~ /^sk-[0-9A-Za-z_-]{32,}$/ ||                     # OpenAI, Anthropic (sk-ant-...), OpenRouter
           t ~ /^gh[pousr]_[0-9A-Za-z]{36,}$/ ||                 # GitHub (ghr_: its refresh tokens)
           t ~ /^github_pat_[0-9A-Za-z_]{22,}$/ ||               # GitHub fine-grained
           t ~ /^A(KIA|SIA)[0-9A-Z]{16}$/ ||                     # AWS key id (ASIA: its temporary keys)
           t ~ /^eyJ[0-9A-Za-z_-]+\.eyJ[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+$/ ||    # JWT
           t ~ /^-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY( BLOCK)?-----\r?\n./ ||  # private key, header then more
           t ~ /^xox[abpr]-[0-9A-Za-z-]{10,}$/ ||                # Slack
           t ~ /^AIza[0-9A-Za-z_-]{35}$/ ||                      # Google API key
           t ~ /^glpat-[0-9A-Za-z_.-]{20,}$/                     # GitLab
}
BEGIN { RS = "^$" }    # the whole copy is one record
{ text = $0 }
END {
    t = text
    sub(/^[ \t\r\n]+/, "", t)
    sub(/[ \t\r\n]+$/, "", t)
    if (secret(t))
        exit
    # Maybe a code from the phone: decided in the background (see --code).
    # Only digits and spaces, so it travels in the environment as it is.
    if (t ~ /^[0-9]{6}$/) {
        ENVIRON["CLIP_CODE"] = t
        ENVIRON["CLIP_TEXT"] = text
        system("sh \"$CLIP_STORE\" --code </dev/null >/dev/null 2>&1 &")
        exit
    }
    printf "%s", text | "exec cliphist store"
}'
