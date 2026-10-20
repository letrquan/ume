pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.common

// The Now Playing card (click the song in the middle island): whether it's
// open, and which player it shows. It shares the middle island with the
// launcher, the clipboard and the calendar, so opening one closes the
// others. It never comes back open after a reload or restart; its window
// only exists while open (plus the shrink-back).
//
// MINE_NOWPLAYING_DRYRUN=1 (tests): "Show the window" only logs what it
// would have done.
Singleton {
    id: root

    property bool open: false
    property bool mapped: false

    readonly property bool dryRun: Quickshell.env("MINE_NOWPLAYING_DRYRUN") === "1"

    // The player shown: the one picked in the card (by its D-Bus name), else
    // the bar's (the first playing, else the first one at all).
    property string chosen: ""
    readonly property var players: Mpris.players.values
    readonly property var player: players.find(p => p.dbusName === chosen)
        ?? players.find(p => p.isPlaying) ?? players[0] ?? null

    function choose(p) {
        chosen = p?.dbusName ?? "";
    }

    function toggle() {
        if (open)
            close();
        else
            show();
    }

    function show() {
        if (!Style.nowPlayingEnabled || player === null)
            return;
        LauncherState.close();          // they share the middle island
        ClipboardState.close();
        CalendarState.close();
        if (Wallpaper.pickerOpen)
            Wallpaper.setPicker(false);
        chosen = "";                    // opens on what the bar shows
        unmap.stop();
        // open first: the window is created the moment `mapped` turns on,
        // and must see the card open already.
        open = true;
        mapped = true;
    }

    function close() {
        if (!open)
            return;
        open = false;
        unmap.restart();
    }

    // The last player went away: nothing left to show.
    onPlayerChanged: if (open && player === null) close()

    // The window goes once the card reports it's back in the island
    // (settled). This is only a safety net in case it never does.
    Timer {
        id: unmap
        interval: Motion.morphOut + 1500
        onTriggered: root.mapped = false
    }

    function settled() {
        if (open || !mapped)
            return;
        unmap.stop();
        // The window goes a moment later, not in the very frame the island
        // starts fading back in (letting go of a window stalls the shell for
        // ~50 ms, which made that fade stutter).
        release.restart();
    }

    Timer {
        id: release
        interval: Motion.contentIn + 80
        onTriggered: if (!root.open) root.mapped = false
    }

    // ---- Show the player's window -------------------------------------------------------
    // mango's focusid (it also changes workspace) for the window of the
    // player's app: its desktop entry (or name) against the windows' app
    // ids (brave-browser also finds brave-browser-nightly); with several (a
    // browser), the one whose title has the song in it.
    // Without a match, the player's own Raise (if it has one).
    property var raising: null
    function raise(p) {
        if (!p)
            return;
        const entry = (p.desktopEntry ?? "").toLowerCase().replace(/\.desktop$/, "");
        raising = {
            player: p,
            names: [entry, entry.split(".").pop(), (p.identity ?? "").toLowerCase()].filter(s => s !== ""),
            title: p.trackTitle ?? ""
        };
        clients.running = true;
    }

    Process {
        id: clients
        command: ["mmsg", "get", "all-clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.raising;
                root.raising = null;
                if (!r)
                    return;
                let list = [];
                try {
                    list = JSON.parse(text).clients ?? [];
                } catch (e) {}
                const fits = c => {
                    const app = String(c.appid ?? "").toLowerCase();
                    return app !== "" && r.names.some(n => app === n || app.endsWith("." + n) || n.endsWith("." + app) || app.startsWith(n + "-"));
                };
                const found = list.filter(fits);
                const c = found.find(x => r.title !== "" && String(x.title ?? "").includes(r.title)) ?? found[0] ?? null;
                const id = c?.id ?? -1;
                // Only a whole-number id mango just listed (it uses the
                // focused window for a wrong one).
                if (Number.isInteger(id) && id >= 0) {
                    if (root.dryRun)
                        console.log("nowplaying: would focus client", id, c.appid);
                    else
                        Quickshell.execDetached(["mmsg", "dispatch", "focusid", "client," + id]);
                } else if (r.player.canRaise) {
                    if (root.dryRun)
                        console.log("nowplaying: would ask", r.player.identity, "to raise");
                    else
                        r.player.raise();
                } else {
                    console.log("nowplaying: no window found for", r.names.join("/"));
                }
            }
        }
    }
}
