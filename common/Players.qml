pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Which music player the shell shows and controls. Everything with a song on
// it (the bar, the control center, the desktop card, the Now Playing card,
// lyrics, album-art colors, the media keys, the lock screen) asks here, so
// they all show the same one.
//   list     every player except playerctld: it only mirrors another player
//            (the same song a second time), and while nothing plays its
//            calls fail.
//   active   the one picked in the Now Playing card, until another player
//            starts playing; else, of those playing, the one that started
//            last; else the one that played last (so pausing doesn't make the
//            bar jump to another player); else the first one.
// In common/ rather than services/ because the lock screen and the greeter
// use it, and the greeter only gets common/ and lock/. So it must not use
// anything from services/.
Singleton {
    id: root

    function usable(p) {
        return p !== null && p !== undefined && !/(^|\.)playerctld$/.test(p.dbusName ?? "");
    }

    // A player's cover, to show: a local file (browsers save the page's
    // picture and pass the file) or an https address. Anything else
    // (http://, an address on your network, data:…) is no cover: the
    // address is the player's choice, and loading it is a request from the
    // shell itself, the lock screen included.
    function art(p) {
        const url = String(p?.trackArtUrl ?? "");
        return /^(file:\/\/\/|https:\/\/|\/)/i.test(url) ? url : "";
    }

    readonly property var list: Mpris.players.values.filter(p => root.usable(p))
    readonly property bool anyPlaying: list.some(p => p.isPlaying)

    // By D-Bus name: the one picked in the card, when each one last started
    // playing, and when each one last started or stopped (ms).
    property string picked: ""
    property var startedAt: ({})
    property var touchedAt: ({})

    readonly property var active: {
        const l = list;
        const chosen = picked !== "" ? l.find(p => p.dbusName === picked) : undefined;
        if (chosen)
            return chosen;
        const latest = (players, times) => players.reduce(
            (best, p) => (times[p.dbusName] ?? 0) > (times[best.dbusName] ?? 0) ? p : best, players[0]);
        const playing = l.filter(p => p.isPlaying);
        if (playing.length > 0)
            return latest(playing, startedAt);
        return l.length > 0 ? latest(l, touchedAt) : null;
    }

    // From the Now Playing card's player chips.
    function pick(p) {
        if (!usable(p))
            return;
        picked = p.dbusName;
        stamp(p, false);
    }

    function stamp(p, started) {
        if (!usable(p))
            return;
        const now = Date.now();
        const names = list.map(q => q.dbusName);
        // Only players still there (browsers come and go with a new name).
        const fresh = times => {
            const t = {};
            for (const n of names)
                if (times[n] !== undefined)
                    t[n] = times[n];
            return t;
        };
        const touched = fresh(touchedAt);
        touched[p.dbusName] = now;
        touchedAt = touched;
        if (started) {
            const s = fresh(startedAt);
            s[p.dbusName] = now;
            startedAt = s;
            if (picked !== p.dbusName)
                picked = "";
        }
    }

    Instantiator {
        model: Mpris.players
        delegate: Connections {
            required property var modelData
            target: modelData
            function onIsPlayingChanged() {
                root.stamp(modelData, modelData.isPlaying);
            }
        }
    }
}
