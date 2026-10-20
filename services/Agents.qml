pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common

// Claude Code sessions in terminals: a notification when one is done or
// waits for you while you're in another window, and the counts for the
// bar (bar/AgentsItem.qml).
//
// Claude Code puts its state in front of the terminal's title: ◐ / ◑ (they
// take turns about once a second, or sit still) while it works, ✳ once it
// stops. A permission prompt or a question stops it too, so ✳ means "done
// or needs you"; the title can't tell which. The window titles reach the
// shell anyway, so this costs nothing extra:
//   - ◐/◑ then ✳ that stays ✳ for Style.agentsHold seconds: the session
//     waits for you (shorter stops, between steps, don't count). Unless
//     you're in that window, or were while it held: then you saw it.
//   - It stops waiting once you go to that window, or it works again.
//   - A window already showing ✳ when first seen (the shell just started,
//     or Claude was idle when it opened) is left alone.
// Under tmux / screen Claude Code keeps ✳ all the time, so those aren't
// seen. Codex sets its titles differently (and can be told how): not here.
//
// "Show" (or a click on the notification, or on the bar item) goes to the
// window: mango's focusid, which also changes workspace, found by app +
// title the way the dock does; Toplevel.activate() only when mango can't
// tell which window it is (it did nothing in a test with mango 0.18).
Singleton {
    id: root

    // Items on the bar that show the counts.
    property int users: 0
    function use(on) {
        users = Math.max(0, users + (on ? 1 : -1));
    }

    readonly property bool watching: Style.agentsNotify || users > 0

    // Sessions seen right now (Claude Code's glyph in the title): each one
    // { modelData (its Toplevel), status ("working" | "idle"), name (the
    // title without the glyph), waiting, since (ms, when it began waiting) }.
    property var sessions: []
    readonly property var workingList: sessions.filter(s => s.status === "working")
    // Longest waiting first.
    readonly property var waitingList: sessions.filter(s => s.waiting).sort((a, b) => a.since - b.since)
    readonly property int workingCount: workingList.length
    readonly property int waitingCount: waitingList.length

    // "working", "idle" or "" (not Claude Code): only the first character
    // and a space after it, so the title's own text never counts.
    function statusOf(title) {
        if (/^[◐◑](\s|$)/.test(title))
            return "working";
        if (/^✳(\s|$)/.test(title))
            return "idle";
        return "";
    }
    function nameOf(title) {
        return (title ?? "").replace(/^[◐◑✳]\s*/, "");
    }

    // A session's title glyph changed (◐ and ◑ count as one, so the ticking
    // while it works doesn't come here).
    function changed(s) {
        if (s.status === "working") {
            s.hold.stop();
            if (!s.armed)
                s.workingSince = Date.now();
            s.armed = true;
            s.waiting = false;
        } else if (s.status === "idle" && s.armed) {
            // You're in that window: you see it stop.
            if (s.activated)
                s.armed = false;
            else
                s.hold.restart();
        } else {
            // Seen for the first time already idle, or Claude Code is gone.
            s.hold.stop();
            s.armed = false;
            s.waiting = false;
        }
        refresh();
    }

    // ✳ held for Style.agentsHold seconds.
    function settled(s) {
        if (s.status !== "idle" || !s.armed)
            return;
        s.armed = false;    // one notification per stop
        if (s.activated)
            return;
        s.waiting = true;
        s.since = Date.now();
        refresh();
        if (Style.agentsNotify)
            notify(s);
    }

    // You went to the window: it's seen. While its ✳ is still holding,
    // that stop is seen too.
    function focused(s) {
        if (s.hold.running) {
            s.hold.stop();
            s.armed = false;
        }
        if (s.waiting) {
            s.waiting = false;
            refresh();
        }
    }

    function refresh() {
        const list = [];
        for (let i = 0; i < watcher.count; i++) {
            const s = watcher.objectAt(i);
            if (s && s.status !== "")
                list.push(s);
        }
        sessions = list;
    }

    Instantiator {
        id: watcher
        model: root.watching ? ToplevelManager.toplevels : null

        delegate: QtObject {
            id: session

            required property Toplevel modelData
            readonly property string status: root.statusOf(modelData?.title ?? "")
            readonly property string name: root.nameOf(modelData?.title ?? "")
            readonly property bool activated: modelData?.activated ?? false
            // It was working: a ✳ that holds counts.
            property bool armed: false
            property real workingSince: 0
            property bool waiting: false
            property real since: 0

            property Timer hold: Timer {
                interval: Math.max(1, Style.agentsHold) * 1000
                onTriggered: root.settled(session)
            }

            onStatusChanged: root.changed(session)
            onActivatedChanged: if (activated) root.focused(session)
            Component.onCompleted: root.changed(session)
        }

        onObjectAdded: Qt.callLater(root.refresh)
        onObjectRemoved: Qt.callLater(root.refresh)
    }

    // ---- Notification ---------------------------------------------------------------

    function notify(s) {
        const t = s.modelData;
        const entry = DesktopEntries.heuristicLookup(t?.appId ?? "");
        const minutes = Math.round((Date.now() - s.workingSince) / 60000);
        const worked = minutes < 1 ? "under a minute" : minutes + " min";
        // Plain text: the title is in the summary (shown as text); the body
        // is our own. The sound is ours too (below), not the usual one. The
        // time makes each stop's text its own: the same text again would be
        // counted on the earlier card ("×2", no popup; services/Notifs.qml).
        const at = Qt.formatTime(new Date(), "HH:mm");
        const cmd = ["notify-send", "-a", "Claude Code", "-i", entry?.icon || "utilities-terminal",
                     "-h", "boolean:suppress-sound:true", "-A", "default=Show", "-A", "show=Show",
                     "--", s.name || "Claude Code", "Done or waiting for you at " + at + " (worked " + worked + ")"];
        console.log("agents: done or waiting:", t?.appId ?? "", "|", s.name);
        notice.createObject(root, { session: s }).exec(cmd);
        if (Style.agentsSound && !Notifs.dnd && !Notifs.fullscreenQuiet)
            Sounds.play("agentDone", 1000);
    }

    // notify-send waits while the notification is around and prints the
    // button pressed; one of these per notification.
    Component {
        id: notice

        Process {
            property QtObject session

            stdout: SplitParser {
                onRead: line => {
                    if (line === "default" || line === "show")
                        root.show(session);
                }
            }
            onExited: destroy()
        }
    }

    // ---- Going to a session ----------------------------------------------------------

    // The bar item's click: the one waiting longest; with none waiting, the
    // next working one.
    function showNext() {
        if (waitingList.length > 0) {
            show(waitingList[0]);
            return;
        }
        const list = workingList;
        if (list.length === 0)
            return;
        const at = list.findIndex(s => s.activated);
        show(list[(at + 1) % list.length]);
    }

    property var focusPending: null
    function show(s) {
        const t = s?.modelData;
        if (!t)
            return;
        focusPending = t;
        clients.running = true;
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
                const want = root.nameOf(t.title);
                const same = (appId, title) => appId === t.appId && root.nameOf(title) === want;
                let found = [];
                try {
                    found = (JSON.parse(text).clients ?? []).filter(c => same(c.appid, c.title)).sort((a, b) => a.id - b.id);
                } catch (e) {}
                // Two with the same app and title (two new sessions, both
                // still "Claude Code"): mango's ids and the shell's window
                // list both go in the order the windows opened.
                const ours = ToplevelManager.toplevels.values.filter(x => same(x.appId, x.title));
                const c = found.length === 1 ? found[0] : found.length === ours.length ? found[ours.indexOf(t)] : null;
                const id = c?.id ?? -1;
                // Only a whole-number id mango just listed (it uses the
                // focused window for a wrong one).
                if (Number.isInteger(id) && id >= 0)
                    Quickshell.execDetached(["mmsg", "dispatch", "focusid", "client," + id]);
                else
                    t.activate();
            }
        }
    }
}
