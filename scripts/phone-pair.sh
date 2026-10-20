#!/bin/sh
# Pairing with a KDE Connect device, for services/Phone.qml:
#   phone-pair.sh request <id>        ask it to pair (a key then shows on both screens)
#   phone-pair.sh cancel  <id>        take that back
#   phone-pair.sh accept  <id> <key>  say yes to its request, with the key you compared
#   phone-pair.sh reject  <id>        say no to its request
# Each step only goes through if the device is still where the Phone page
# showed it, checked right before: kdeconnectd's acceptPairing trusts a
# device whatever it was doing (even one that never asked), requestPairing
# quietly accepts if the other side asked in the meantime, and every new
# request comes with a new key.
# Exit: 0 done, 1 kdeconnectd didn't answer, 2 bad arguments, 3 it changed
# meanwhile (nothing done). Never starts kdeconnectd (auto-start off).
set -u

bus() {
    busctl --user --auto-start=no "$@"
}

action=${1:-}
id=${2:-}
key=${3:-}

# Object paths only take letters, digits and _.
case "$id" in '' | *[!A-Za-z0-9_]*) exit 2 ;; esac
path="/modules/kdeconnect/devices/$id"

# The pair state it must be in (0 not paired, 1 we asked, 2 it asked,
# 3 paired), and what to call.
case "$action" in
request) want=0 method=requestPairing ;;
cancel) want=1 method=cancelPairing ;;
accept) want=2 method=acceptPairing ;;
reject) want=2 method=cancelPairing ;;
*) exit 2 ;;
esac
if [ "$action" = accept ]; then
    case "$key" in [0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]) ;; *) exit 2 ;; esac
fi

# No answer: the device is gone (it changed) or kdeconnectd is.
if ! now=$(bus --json=short get-property org.kde.kdeconnect "$path" org.kde.kdeconnect.device \
    pairState verificationKey 2>/dev/null); then
    bus call org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon selfId >/dev/null 2>&1 && exit 3
    exit 1
fi
state=$(printf '%s\n' "$now" | jq -s -r '.[0].data // empty')
[ "$state" = "$want" ] || exit 3
if [ "$action" = accept ]; then
    [ "$(printf '%s\n' "$now" | jq -s -r '.[1].data // empty')" = "$key" ] || exit 3
fi

exec busctl --user --auto-start=no call org.kde.kdeconnect "$path" org.kde.kdeconnect.device "$method"
