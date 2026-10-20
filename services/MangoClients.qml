pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Which apps are on which workspace, for the app icons in the bar's
// workspace slots (bar/Workspaces.qml counts itself in with use()), and
// the plain window list for reopening apps at login (services/AppRestore.qml
// counts itself in with keep(), whatever the bar shows).
// `mmsg watch all-clients` prints every window as one JSON line right away
// and again after every change; it only runs while a workspaces item with
// icons is on screen, or keep() is held.
//
// Window titles change a lot (a terminal's spinner, a browser tab), so a
// new line only counts when an app, a workspace or a monitor changed.
Singleton {
    id: root

    // Workspace items on screen right now.
    property int users: 0
    function use(delta) {
        users = Math.max(0, users + delta);
    }

    // Others that need the window list even without icons on the bar.
    property int keepers: 0
    function keep(delta) {
        keepers = Math.max(0, keepers + delta);
    }

    readonly property bool active: (Style.workspaceIcons && users > 0) || keepers > 0

    // { "<monitor>": { "<tag>": [{ appId, icon }, ...] } }: one entry per app,
    // in the order its first window was opened.
    property var apps: ({})
    // Every window: [{ id, pid, appId, monitor, tag }], in the order they
    // were opened (mango's ids); `tag` is its first workspace.
    property var clients: []
    // mango's list has come in at least once since the watcher started
    // (an empty `clients` before that means "not known yet", not "none").
    property bool listed: false
    property string lastKey: ""
    property string lastLine: ""

    // The apps on workspace `tag` (1-based) of `monitor`.
    function appsOn(monitor, tag) {
        return apps[monitor]?.[tag] ?? [];
    }

    // Icon for an app id: its desktop entry's icon (a theme name, or a file
    // path: Zen ships a .png), else the id itself.
    function iconFor(appId) {
        const entry = DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId);
        const icon = entry?.icon || appId;
        return icon.startsWith("/") ? "file://" + icon : Quickshell.iconPath(icon, "application-x-executable");
    }

    function read(line) {
        lastLine = line;
        let list;
        try {
            list = JSON.parse(line).clients ?? [];
        } catch (e) {
            console.warn("mango: can't read clients", line.substring(0, 80));
            return;
        }
        // Scratchpads and windows on every workspace (picture in picture)
        // don't belong to one workspace.
        list = list.filter(c => c.appid && !c.is_scratchpad && !c.is_namedscratchpad && !c.is_global)
                   .sort((a, b) => a.id - b.id);
        listed = true;
        const key = list.map(c => c.id + c.appid + c.monitor + c.tags.join(",")).join("|");
        if (key === lastKey)
            return;
        lastKey = key;
        clients = list.filter(c => (c.tags?.length ?? 0) > 0)
                      .map(c => ({ id: c.id, pid: c.pid ?? -1, appId: c.appid, monitor: c.monitor ?? "", tag: c.tags[0] }));

        const out = {};
        for (const c of list) {
            const mon = out[c.monitor] ?? (out[c.monitor] = {});
            for (const tag of c.tags) {
                const here = mon[tag] ?? (mon[tag] = []);
                if (!here.some(a => a.appId === c.appid))
                    here.push({ appId: c.appid, icon: iconFor(c.appid) });
            }
        }
        apps = out;
    }

    // Look the icons up again once the app list has loaded (the first line
    // can come before it).
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            root.lastKey = "";
            if (root.lastLine !== "")
                root.read(root.lastLine);
        }
    }

    Process {
        id: watcher
        command: ["mmsg", "watch", "all-clients"]

        stdout: SplitParser {
            onRead: line => root.read(line)
        }

        // mango restarted or mmsg died: try again in a moment.
        onExited: if (root.active) restart.start()
    }

    Timer {
        id: restart
        interval: 2000
        onTriggered: watcher.running = root.active
    }

    onActiveChanged: {
        watcher.running = active;
        if (!active) {
            apps = {};
            clients = [];
            listed = false;
            lastKey = "";
            lastLine = "";
        }
    }
}
