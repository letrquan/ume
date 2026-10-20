pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "binds.js" as Binds

// mango's keys by what they do, for the bar's tips: keys("mine:session")
// -> "Super+X" (binds.js shortcuts()). Read from mango's config, its
// source= files too, when a tip first shows (refresh()), and again on a
// later tip a minute or more after: binds change while you tweak mango.
//
// MINE_BINDS_CONFIG (tests): another mango config.conf to read.
Singleton {
    id: root

    property var map: ({})
    property real readAt: 0

    readonly property string configPath: Quickshell.env("MINE_BINDS_CONFIG")
        || (Quickshell.env("HOME") + "/.config/mango/config.conf")

    function keys(id) {
        return id ? (map[id] ?? "") : "";
    }

    function refresh() {
        const now = Date.now();
        if (reader.running || now - readAt < 60000)
            return;
        readAt = now;
        reader.running = true;
    }

    Process {
        id: reader
        command: ["sh", Quickshell.shellDir + "/scripts/mango-binds.sh", root.configPath]
        stdout: StdioCollector {
            onStreamFinished: root.map = Binds.shortcuts(text)
        }
    }
}
