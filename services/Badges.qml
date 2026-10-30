pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Unread counts on the dock's icons (Discord, Telegram…), from two places
// (Style.dockBadgeSource "both", "apps" or "notifications"):
//
//   apps: the D-Bus signal com.canonical.Unity.LauncherEntry.Update, which
//     apps send for docks (Telegram, KDE apps, Chromium/Electron apps where
//     they do): the app ("application://org.telegram.desktop.desktop") and
//     the properties that changed (count + count-visible, urgent, progress
//     + progress-visible); what it doesn't send stays as it was. Heard with
//     `busctl --user monitor` (one line of JSON per signal), only while a
//     dock is there and badges are on. An app's badge goes when it leaves
//     the bus (it quit). If busctl stops by itself (the bus won't let it
//     listen), it isn't started again until badges or the dock are turned
//     off and on: the notifications still count.
//   notifications: the app's unread notifications in services/Notifs.qml
//     (unread until the notification center opens), matched by the app's
//     desktop-entry hint, else by its name, the way the center finds its
//     icon. A phone's (KDE Connect) never count: they're the phone's apps.
//
// An app that sends LauncherEntry wins over its notifications (even when
// it says there's nothing: count-visible false).
//
// API: of(item) → { count, urgent, progress (0–1, or -1: none) } for a
// DockState item; `docks` (Dock.qml counts itself in and out).
// Tests: MINE_BADGES_MONITOR (a program run instead of busctl, given the
// same arguments).
Singleton {
    id: root

    property int docks: 0
    readonly property bool wantApps: docks > 0 && Style.dockBadges && Style.dockBadgeSource !== "notifications"
    readonly property bool wantNotifs: Style.dockBadges && Style.dockBadgeSource !== "apps"
    readonly property string program: Quickshell.env("MINE_BADGES_MONITOR") || "busctl"

    // What apps said, by desktop id (lowercase):
    // { count, countVisible, urgent, progress, progressVisible, sender }
    property var entries: ({})
    // busctl stopped by itself: not started again until wantApps goes off.
    property bool failed: false

    readonly property var none: ({ count: 0, urgent: false, progress: -1 })

    function of(item) {
        if (!Style.dockBadges || !item)
            return none;
        const key = keyOf(item.entry?.id ?? item.appId ?? String(item.key ?? "").replace(/^app:/, ""));
        if (key === "")
            return none;
        const a = Style.dockBadgeSource !== "notifications" ? entries[key] : undefined;
        if (a)
            return { count: a.countVisible ? a.count : 0, urgent: a.urgent, progress: a.progressVisible ? a.progress : -1 };
        return { count: notifCounts[key] ?? 0, urgent: false, progress: -1 };
    }

    // "application://discord.desktop", "discord.desktop", "Discord" → the
    // desktop entry's id ("discord"), lowercase; as it is when there's none.
    // Looked up once per name (again when the app list changes; the cache
    // is a plain object, so filling it never re-runs a binding).
    readonly property var cache: ({ apps: -1, map: {} })
    function keyOf(id) {
        const raw = String(id ?? "").trim().replace(/^application:\/\//, "").replace(/\.desktop$/, "");
        if (raw === "" || raw.length > 255)
            return "";
        const apps = DesktopEntries.applications.values.length;
        if (cache.apps !== apps || Object.keys(cache.map).length > 300) {
            cache.apps = apps;
            cache.map = {};
        }
        if (cache.map[raw] !== undefined)
            return cache.map[raw];
        const entry = DesktopEntries.byId(raw) ?? DesktopEntries.heuristicLookup(raw);
        return cache.map[raw] = (entry?.id ?? raw).toLowerCase();
    }

    // ---- Notifications ----------------------------------------------------------------
    readonly property var notifCounts: {
        if (!wantNotifs)
            return ({});
        const out = {};
        for (const e of Notifs.list) {
            if (e.read || e.phone)
                continue;
            const hint = String(e.desktopEntry ?? "");
            const key = keyOf(hint !== "" ? hint : (e.appName ?? ""));
            if (key !== "")
                out[key] = (out[key] ?? 0) + Math.max(1, Math.round(Number(e.count) || 1));
        }
        return out;
    }

    // ---- Apps (LauncherEntry) ---------------------------------------------------------
    function take(line) {
        let m = null;
        try {
            m = JSON.parse(line);
        } catch (e) {
            return;
        }
        const data = m?.payload?.data;
        if (m?.type !== "signal" || !Array.isArray(data))
            return;
        // Someone left the bus: the badges it sent go with it.
        if (m.interface === "org.freedesktop.DBus" && m.member === "NameOwnerChanged") {
            if (data.length === 3 && typeof data[0] === "string" && data[0].startsWith(":") && data[2] === "")
                gone(data[0]);
            return;
        }
        if (m.interface !== "com.canonical.Unity.LauncherEntry" || m.member !== "Update" || m.payload.type !== "sa{sv}")
            return;
        const props = data[1];
        if (typeof data[0] !== "string" || !props || typeof props !== "object" || Array.isArray(props))
            return;
        const key = keyOf(data[0]);
        if (key === "" || (entries[key] === undefined && Object.keys(entries).length >= 64))
            return;
        const was = entries[key] ?? { count: 0, countVisible: false, urgent: false, progress: 0, progressVisible: false };
        const now = Object.assign({}, was, { sender: typeof m.sender === "string" ? m.sender : "" });
        const value = name => (props[name] && typeof props[name] === "object") ? props[name].data : undefined;
        const count = value("count");
        if (typeof count === "number" && Number.isInteger(count) && count >= 0)
            now.count = Math.min(count, 99999);
        const progress = value("progress");
        if (typeof progress === "number" && isFinite(progress))
            now.progress = Math.max(0, Math.min(1, progress));
        for (const [name, field] of [["count-visible", "countVisible"], ["urgent", "urgent"], ["progress-visible", "progressVisible"]]) {
            const b = value(name);
            if (typeof b === "boolean")
                now[field] = b;
        }
        const next = Object.assign({}, entries);
        next[key] = now;
        entries = next;
    }

    function gone(sender) {
        const left = Object.keys(entries).filter(k => entries[k].sender === sender);
        if (left.length === 0)
            return;
        const next = Object.assign({}, entries);
        for (const k of left)
            delete next[k];
        entries = next;
    }

    // Started and stopped by hand: a Process that exits by itself leaves
    // `running` false, which a binding wouldn't see.
    onWantAppsChanged: sync()
    Component.onCompleted: sync()
    function sync() {
        if (wantApps && !failed) {
            if (!monitor.running)
                monitor.running = true;
            return;
        }
        if (!wantApps)
            failed = false;
        if (monitor.running)
            monitor.running = false;
        entries = ({});
    }

    Process {
        id: monitor
        command: [root.program, "--user", "monitor", "--json=short",
            "--match=type='signal',interface='com.canonical.Unity.LauncherEntry',member='Update'",
            "--match=type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged'"]
        stdout: SplitParser {
            onRead: line => root.take(line)
        }
        stderr: StdioCollector {
            id: monitorErr
        }
        onExited: code => {
            if (!root.wantApps)
                return;
            root.failed = true;
            root.entries = ({});
            const why = monitorErr.text.trim().split("\n").pop() ?? "";
            console.warn("badges: busctl monitor stopped (exit " + code + ")" + (why !== "" ? ": " + why.substring(0, 200) : "")
                         + "; app badges are off, notifications still count");
        }
    }
}
