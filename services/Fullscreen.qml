pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Whether the focused window is fullscreen (a game, a film), for
// Style.dndFullscreen: new notifications then go quietly to the list.
// `mmsg watch focusing-client` prints the focused window as one JSON line
// right away and again after every change (also title changes, so a line
// is cheap: one small object). It only runs while the knob is on.
//
// MINE_FULLSCREEN_CMD (tests): a shell command printing such lines instead.
Singleton {
    id: root

    readonly property bool watching: Style.dndFullscreen
    property bool active: false
    property string appId: ""           // the fullscreen window's app

    readonly property string fakeCommand: Quickshell.env("MINE_FULLSCREEN_CMD") ?? ""

    function read(line) {
        let c;
        try {
            c = JSON.parse(line);
        } catch (e) {
            return;
        }
        // No window focused: {"id": null, …} or an empty object.
        const full = c?.id !== null && c?.id !== undefined && c.is_fullscreen === true;
        if (full !== active)
            console.log("fullscreen:", full ? (c.appid || "a window") + " is fullscreen, notifications go quietly to the list" : "back to normal");
        active = full;
        appId = full ? (c.appid ?? "") : "";
    }

    Process {
        id: watcher
        command: root.fakeCommand !== "" ? ["sh", "-c", root.fakeCommand] : ["mmsg", "watch", "focusing-client"]

        stdout: SplitParser {
            onRead: line => root.read(line)
        }

        // mango restarted or mmsg died: try again in a moment.
        onExited: {
            root.active = false;
            if (root.watching && root.fakeCommand === "")
                restart.start();
        }
    }

    Timer {
        id: restart
        interval: 2000
        onTriggered: watcher.running = root.watching
    }

    // Not a binding on `running`: the restart above sets it by hand.
    onWatchingChanged: {
        watcher.running = watching;
        if (!watching)
            active = false;
    }
    Component.onCompleted: watcher.running = watching
}
