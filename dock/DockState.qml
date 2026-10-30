pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.services

// What the dock shows and does: pinned apps first, then apps with open
// windows that aren't pinned. Pins are kept in
// ~/.local/state/mine-shell/dock.json (Style.dockPinned until you change them).
//
// Item: { key, entry (DesktopEntry or null), appId, toplevels: [Toplevel], pinned }
Singleton {
    id: root

    // MINE_DOCK_DRYRUN=1 / MINE_DOCK_STATE are for testing: nothing is
    // launched, focused or closed, only printed.
    readonly property bool dryRun: Quickshell.env("MINE_DOCK_DRYRUN") === "1"
    readonly property string statePath: Quickshell.env("MINE_DOCK_STATE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/dock.json")

    property var pinned: Style.dockPinned.slice()
    // The open windows (previews can swap in a list of their own).
    property var toplevelList: ToplevelManager.toplevels.values

    // Desktop entry for a window's app id, if there is one.
    function entryFor(appId) {
        if (!appId)
            return null;
        return DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId) ?? null;
    }

    readonly property var items: {
        // Look the entries up again once the app list has loaded.
        DesktopEntries.applications.values.length;
        const out = [];
        const byKey = {};
        for (const id of pinned) {
            const item = { key: id, entry: DesktopEntries.byId(id), appId: id, toplevels: [], pinned: true };
            out.push(item);
            byKey[id] = item;
        }
        for (const t of toplevelList) {
            const entry = entryFor(t.appId);
            const key = entry ? entry.id : "app:" + t.appId;
            let item = byKey[key];
            if (!item) {
                item = { key: key, entry: entry, appId: t.appId, toplevels: [], pinned: false };
                out.push(item);
                byKey[key] = item;
            }
            item.toplevels.push(t);
        }
        return out;
    }

    // Keys in dock order, with "|" where the running-only apps start.
    readonly property var keys: {
        const out = [];
        for (const item of items) {
            if (!item.pinned && out.length > 0 && !out.includes("|"))
                out.push("|");
            out.push(item.key);
        }
        return out;
    }

    function item(key) {
        return items.find(i => i.key === key) ?? null;
    }

    function iconFor(item) {
        const icon = item?.entry?.icon ?? item?.appId ?? "";
        if (icon.startsWith("/"))
            return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }

    function title(item) {
        return item?.entry?.name ?? item?.toplevels[0]?.title ?? item?.appId ?? "";
    }

    // ---- Actions -------------------------------------------------------------------

    // Click: bring its window forward (again: the next one), or start it.
    function open(item) {
        if (!item)
            return false;
        const list = item.toplevels;
        if (list.length === 0) {
            launch(item);
            return true;
        }
        const now = list.findIndex(t => t.activated);
        const next = list[(now + 1) % list.length];
        if (dryRun)
            console.log("dock (dry run): activate", item.key, (now + 1) % list.length);
        else
            next.activate();
        return false;
    }

    function launch(item) {
        const entry = item?.entry;
        if (!entry)
            return;
        if (dryRun)
            console.log("dock (dry run): launch", entry.id);
        else if (entry.runInTerminal)
            Quickshell.execDetached(["xdg-terminal-exec"].concat(entry.command));
        else
            entry.execute();
    }

    // One of the app's own actions (Apps.actionsOf: "New Private Window"…).
    function launchAction(item, action) {
        const entry = item?.entry;
        if (!entry || !action)
            return;
        if (dryRun)
            console.log("dock (dry run): action", entry.id, action.id);
        else if (entry.runInTerminal)
            Quickshell.execDetached(["xdg-terminal-exec"].concat(action.command));
        else
            action.execute();
    }

    function closeAll(item) {
        for (const t of item?.toplevels ?? []) {
            if (dryRun)
                console.log("dock (dry run): close", item.key);
            else
                t.close();
        }
    }

    // One window, from the preview card. mango's focusid also changes
    // workspace; the window is found by app id + title, the same way as the
    // Alt+Tab switcher. The Wayland way when mango can't tell which it is.
    property var focusPending: null
    function focusWindow(t) {
        if (!t)
            return;
        if (dryRun) {
            console.log("dock (dry run): focus window", t.appId, "|", t.title);
            return;
        }
        focusPending = t;
        clients.running = true;
    }

    function closeWindow(t) {
        if (!t)
            return;
        if (dryRun)
            console.log("dock (dry run): close window", t.appId, "|", t.title);
        else
            t.close();
    }

    Process {
        id: clients
        command: ["mmsg", "get", "all-clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = root.focusPending;
                root.focusPending = null;
                if (!t)
                    return;
                const want = SwitcherState.keyOf(t.appId, t.title);
                let id = -1, matches = 0;
                try {
                    const data = JSON.parse(text);
                    for (const c of (Array.isArray(data) ? data : (data.clients ?? []))) {
                        if (SwitcherState.keyOf(c.appid, c.title) === want) {
                            id = c.id ?? -1;
                            matches++;
                        }
                    }
                } catch (e) {}
                // Only a whole-number id mango just listed (it uses the
                // focused window for a wrong one).
                if (Number.isInteger(id) && id >= 0 && matches === 1)
                    Quickshell.execDetached(["mmsg", "dispatch", "focusid", "client," + id]);
                else
                    t.activate();
            }
        }
    }

    function isPinned(key) {
        return pinned.includes(key);
    }

    function togglePin(key) {
        pinned = isPinned(key) ? pinned.filter(k => k !== key) : pinned.concat([key]);
        saveTimer.restart();
    }

    // ---- Saving the pins ------------------------------------------------------------
    Timer {
        id: saveTimer
        interval: 300
        onTriggered: store.setText(JSON.stringify({ pinned: root.pinned }, null, 1))
    }

    FileView {
        id: store
        path: root.statePath
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                const saved = JSON.parse(text()).pinned;
                if (Array.isArray(saved))
                    root.pinned = saved;
            } catch (e) {
                console.warn("dock: can't read", root.statePath);
            }
        }
    }
}
