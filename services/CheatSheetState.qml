pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "binds.js" as Binds

// The keyboard shortcut cheat sheet (Super+/): every mango bind, read from
// mango's config each time it opens (following its `source=` lines, so it
// also has binds.conf and shell.conf), grouped by the "# === Apps ==="
// headers, with the comment above a bind as its words (services/binds.js).
// Its window only exists while open (plus the fade out).
//
// MINE_BINDS_CONFIG (tests): another mango config.conf to read.
Singleton {
    id: root

    property bool open: false
    property bool mapped: false

    // [{ title, rows: [{ combos, desc, search }] }]; see binds.js.
    property var groups: []
    property bool loaded: false
    readonly property int count: groups.reduce((n, g) => n + g.rows.length, 0)

    // Only the rows with every word of `query` (in their words or keys).
    function filtered(query) {
        return Binds.filter(groups, query);
    }

    readonly property string configPath: Quickshell.env("MINE_BINDS_CONFIG")
        || (Quickshell.env("HOME") + "/.config/mango/config.conf")

    function toggle() {
        if (open)
            close();
        else
            show();
    }

    function show() {
        // They take the keyboard too.
        LauncherState.close();
        ClipboardState.close();
        NowPlayingState.close();
        reload();
        unmap.stop();
        mapped = true;
        open = true;
    }

    function close() {
        if (!open)
            return;
        open = false;
        unmap.restart();
    }

    // Read again each time: binds change while you tweak mango.
    function reload() {
        if (!reader.running)
            reader.running = true;
    }

    Process {
        id: reader
        command: ["sh", Quickshell.shellDir + "/scripts/mango-binds.sh", root.configPath]
        stdout: StdioCollector {
            onStreamFinished: {
                root.groups = Binds.parse(text);
                root.loaded = true;
            }
        }
    }

    Timer {
        id: unmap
        interval: Motion.normal + 200
        onTriggered: root.mapped = false
    }
}
