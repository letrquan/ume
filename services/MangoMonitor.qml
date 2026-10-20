import QtQuick
import Quickshell
import Quickshell.Io

// Live workspaces (mango calls them tags) of one monitor.
// `mmsg watch monitor <name>` prints the whole monitor state as one JSON line
// right away and again after every change; we keep the latest one.
// (Quickshell's own WindowManager module sees 0 workspaces on mango 0.18,
// and it can't tell which tags have windows anyway.)
Scope {
    id: root

    required property string monitor

    // [{ index: 1-based, active, urgent, clients: number of windows }]
    property var tags: []
    property int activeTag: 1
    property string layout: ""     // tiling layout symbol, e.g. "DW" (services/Tiling.qml)
    // Tell the OSD when you change the layout (the bar's monitor only, so
    // the dock's doesn't do it twice).
    property bool reportTiling: false
    property bool started: false
    // The latest line as is (the overview starts from it).
    property var latest: null

    function view(tag: int) {
        Quickshell.execDetached(["mmsg", "dispatch", "view," + tag]);
    }
    function viewLeft() {
        Quickshell.execDetached(["mmsg", "dispatch", "viewtoleft"]);
    }
    function viewRight() {
        Quickshell.execDetached(["mmsg", "dispatch", "viewtoright"]);
    }

    Process {
        id: watcher
        command: ["mmsg", "watch", "monitor", root.monitor]
        running: true

        stdout: SplitParser {
            onRead: line => {
                let state;
                try {
                    state = JSON.parse(line);
                } catch (e) {
                    console.warn("mango: can't read", line);
                    return;
                }
                root.latest = state;
                root.tags = (state.tags ?? []).map(t => ({
                    index: t.index,
                    active: t.is_active,
                    urgent: t.is_urgent,
                    clients: t.client_count
                }));
                const tag = state.active_tags?.[0] ?? root.activeTag;
                const layout = state.layout_symbol ?? "";
                // Every tag has its own layout: only a change on the same tag
                // is you switching layouts (not the first line, not a tag change).
                const switched = root.started && tag === root.activeTag && layout !== root.layout && layout !== "";
                root.activeTag = tag;
                root.layout = layout;
                root.started = true;
                if (switched && root.reportTiling)
                    OsdState.noteTiling(layout);
                // Keyboard layout (e.g. "English (US)"): the OSD shows it when it changes.
                OsdState.noteLayout(state.keyboardlayout ?? "");
            }
        }

        // mango restarted or mmsg died: try again in a moment.
        onExited: restart.start()
    }

    Timer {
        id: restart
        interval: 2000
        onTriggered: watcher.running = true
    }
}
