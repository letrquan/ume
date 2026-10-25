#!/bin/sh
# Tell what a scanned QR code or barcode holds (services/Screenshot.qml's
# QR scan), and act on the answer:
#   qr-notify.sh url <link> <kind>          Open (the browser) or Copy
#   qr-notify.sh wifi <name> <password> <security> <kind>
#                                           Copy password / Copy name
#   qr-notify.sh text <text> <kind>         copied already; shown
#   qr-notify.sh several <summary> <text>   copied already (no Wi-Fi
#                                           password); shown
#   qr-notify.sh none | failed              nothing found / it went wrong
# kind: "QR code", "EAN-13 barcode", …; text to show comes cut short
# already (the full text is what was copied).
# Open only takes http(s) links (checked again here). A Wi-Fi password is
# never kept: the notification is transient (not in the history) and the
# copy is marked sensitive (cliphist leaves it out).
# MINE_SHOT_DRYRUN=1 (tests): nothing is shown, opened or copied, only
# printed; MINE_SHOT_ANSWER is the button "clicked".
what="$1"

if [ "$MINE_SHOT_DRYRUN" = 1 ]; then
    notify() { echo "qr-notify (dry run): notify-send $*" >&2; echo "${MINE_SHOT_ANSWER:-}"; }
    open() { echo "qr-notify (dry run): xdg-open $1"; }
    copy() { echo "qr-notify (dry run): wl-copy $*"; }
else
    notify() { notify-send "$@"; }
    open() { setsid -f xdg-open "$1" >/dev/null 2>&1; }
    copy() { wl-copy "$@"; }
fi

# The body may hold markup (the notification spec): what came from the
# code is only text.
escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

case "$what" in
    url)
        link="$2"
        kind="${3:-QR code}"
        action=$(notify -a "QR code" -i insert-link -A default=Open -A open=Open -A copy="Copy link" \
            -- "Link in the $kind" "$(escape "$link")")
        case "$action" in
            default | open)
                case "$link" in
                    http://* | https://* | HTTP://* | HTTPS://*) open "$link" ;;
                esac ;;
            copy) copy -- "$link" ;;
        esac ;;
    wifi)
        ssid="$2"
        password="$3"
        security="$4"
        kind="${5:-QR code}"
        if [ -n "$password" ]; then
            body="Password: $(escape "$password")"
            [ -n "$security" ] && body="$body · $(escape "$security")"
            action=$(notify -e -a "QR code" -i network-wireless -A copy="Copy password" -A ssid="Copy name" \
                -- "Wi-Fi: $ssid" "$body")
        else
            action=$(notify -e -a "QR code" -i network-wireless -A ssid="Copy name" \
                -- "Wi-Fi: $ssid" "Open network, no password")
        fi
        case "$action" in
            copy) copy --sensitive -- "$password" ;;
            ssid) copy -- "$ssid" ;;
        esac ;;
    text)
        kind="${3:-QR code}"
        notify -a "QR code" -i edit-copy -- "Copied the $kind's text" "$(escape "$2")" ;;
    several)
        notify -a "QR code" -i edit-copy -- "$2" "$(escape "$3")" ;;
    none)
        notify -a "QR code" -i edit-find -- "No QR code found" "No QR code or barcode in that part of the screen" ;;
    failed)
        notify -a "QR code" -i dialog-error -- "Couldn't scan" "Reading that part of the screen failed" ;;
esac
exit 0
