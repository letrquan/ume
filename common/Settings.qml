pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// What you changed in the Settings window: only those knobs, kept in
// ~/.local/state/mine-shell/settings.json (MINE_SETTINGS for tests), e.g.
//   { "islandOpacity": 0.7, "dockIconSize": 44 }
// Style.qml reads every knob as `Settings.values.<name> ?? <default>`, so the
// defaults stay in Style.qml, a change applies at once (no reload), and
// "reset" just removes the key. Editing the file by hand works too.
Singleton {
    id: root

    readonly property string path: Quickshell.env("MINE_SETTINGS")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/settings.json")
    property var values: ({})

    function set(name, value) {
        if (values[name] === value)
            return;
        const next = Object.assign({}, values);
        next[name] = value;
        values = next;
        saveTimer.restart();
    }

    function reset(name) {
        if (values[name] === undefined)
            return;
        const next = Object.assign({}, values);
        delete next[name];
        values = next;
        saveTimer.restart();
    }

    function resetAll() {
        values = {};
        saveTimer.restart();
    }

    function changed(name) {
        return values[name] !== undefined;
    }

    function read(text) {
        let parsed = {};
        try {
            parsed = text.trim() === "" ? {} : JSON.parse(text);
        } catch (e) {
            console.warn("settings: can't read", path, "- keeping the current values");
            return;
        }
        // Only take it when it really differs (our own saves come back here).
        if (JSON.stringify(parsed) !== JSON.stringify(values))
            values = parsed;
    }

    // Writes shortly after the last change (a slider sends many).
    Timer {
        id: saveTimer
        interval: 300
        onTriggered: file.setText(JSON.stringify(root.values, null, 1) + "\n")
    }

    // Read at once (before anything is drawn, so nothing jumps at start),
    // and again whenever the file changes.
    FileView {
        id: file
        path: root.path
        blockLoading: true
        watchChanges: true
        atomicWrites: true
        printErrors: false

        onLoaded: root.read(text())
        onFileChanged: reload()
    }

    Component.onCompleted: {
        // Right away, so the first frame already uses your values.
        read(file.text());
        const dir = path.substring(0, path.lastIndexOf("/"));
        Quickshell.execDetached(["mkdir", "-p", dir]);
    }
}
