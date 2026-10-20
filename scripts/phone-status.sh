#!/bin/sh
# What KDE Connect knows about your phones, as one JSON line for
# services/Phone.qml:
#   {"installed":true,"running":true,"devices":[{"id","name","type",
#    "reachable","paired","pairRequested","pairRequestedByPeer","key",
#    "charge","charging"}]}
# charge is -1 when the phone doesn't send its battery (not connected, or
# its battery plugin is off). key is the pairing key (8 hex digits, the same
# on both screens) while one side asks to pair, else "". Read-only: it asks kdeconnectd over D-Bus and
# never starts it (auto-start off), so nothing runs that you didn't start.
set -u

if ! command -v kdeconnect-cli >/dev/null 2>&1 && ! command -v kdeconnectd >/dev/null 2>&1; then
    echo '{"installed":false,"running":false,"devices":[]}'
    exit 0
fi

bus() {
    busctl --user --auto-start=no --json=short "$@" 2>/dev/null
}

# Not running (or not answering): nothing more to ask.
if ! bus call org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon selfId >/dev/null; then
    echo '{"installed":true,"running":false,"devices":[]}'
    exit 0
fi

# Every device it knows (paired or seen on the network).
ids=$(bus call org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon devices bb false false \
    | jq -r '.data[0][]?')

devices="[]"
for id in $ids; do
    # Object paths only take letters, digits and _: skip anything else.
    case "$id" in *[!A-Za-z0-9_]*) continue ;; esac
    path="/modules/kdeconnect/devices/$id"
    props=$(bus get-property org.kde.kdeconnect "$path" org.kde.kdeconnect.device \
        name type isReachable isPaired isPairRequested isPairRequestedByPeer | jq -s -c '[.[].data]')
    [ -n "$props" ] && [ "$props" != "[]" ] || continue
    # The key only while a pairing is going on: kdeconnectd makes it from
    # both certificates and the time of the request, so at any other moment
    # it means nothing (not even for a paired phone).
    key=""
    if printf '%s' "$props" | jq -e '.[4] == true or .[5] == true' >/dev/null; then
        key=$(bus get-property org.kde.kdeconnect "$path" org.kde.kdeconnect.device verificationKey | jq -r '.data // ""')
    fi
    battery=$(bus get-property org.kde.kdeconnect "$path/battery" org.kde.kdeconnect.device.battery \
        charge isCharging | jq -s -c '[.[].data]')
    [ -n "$battery" ] || battery="[]"
    devices=$(jq -c -n --argjson list "$devices" --arg id "$id" --argjson p "$props" --argjson b "$battery" --arg k "$key" \
        '$list + [{
            id: $id, name: ($p[0] // ""), type: ($p[1] // ""),
            reachable: ($p[2] // false), paired: ($p[3] // false),
            pairRequested: ($p[4] // false), pairRequestedByPeer: ($p[5] // false),
            key: (if $k | test("^[0-9A-F]{8}$") then $k else "" end),
            charge: (if ($b | length) == 2 then $b[0] else -1 end),
            charging: (if ($b | length) == 2 then $b[1] else false end)
        }]')
done

jq -c -n --argjson d "$devices" '{installed: true, running: true, devices: $d}'
