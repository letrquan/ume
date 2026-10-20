pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common

// The Alt+Tab window switcher's state: windows in most-recently-used order
// (the one you were in just before comes second, so a quick Alt+Tab flips
// back), which one is picked, and switching / closing.
//
// mango runs `mine switcher next` on Alt+Tab (and `previous` on
// Alt+Shift+Tab), also while the switcher is open: mango handles those keys
// itself even when the switcher has the keyboard. Letting go of Alt (seen by
// the switcher window) switches. If Alt was already up before the window got
// the keyboard (a very fast tap), it switches after Style.switcherIdleCommit
// with nothing pressed.
//
// MINE_SWITCHER_DRYRUN=1 (tests): switching and closing only print.
Singleton {
    id: root

    property bool open: false
    property bool mapped: false
    property int selected: 0

    readonly property bool dryRun: Quickshell.env("MINE_SWITCHER_DRYRUN") === "1"

    // The open windows (previews can swap in a list of their own).
    property var toplevelList: ToplevelManager.toplevels.values
    // Most recently used first; windows we haven't seen active go last.
    property var recent: []

    readonly property var windows: {
        const alive = toplevelList;
        const out = recent.filter(t => alive.includes(t));
        for (const t of alive)
            if (!out.includes(t))
                out.push(t);
        return out;
    }

    // mango's workspace (tag) and client id of each window, looked up when
    // opening: { keyOf(appId, title): { tag, id } } (id -1 when two windows
    // share the app id and title).
    property var tags: ({})

    function noteActive(t) {
        if (!t)
            return;
        recent = [t].concat(recent.filter(x => x !== t && toplevelList.includes(x)));
    }

    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            root.noteActive(ToplevelManager.activeToplevel);
        }
    }
    Component.onCompleted: noteActive(ToplevelManager.activeToplevel)

    // ---- Opening and moving --------------------------------------------------------

    // A second Alt+Tab while open means Alt is still held, and by then the
    // switcher has the keyboard and will see Alt let go: no need to switch
    // on its own after the short quick-tap wait (only a long safety one).
    property bool altHeld: false

    function show(start) {
        if (windows.length === 0)
            return;
        // open first: the window is created the moment `mapped` turns on.
        unmap.stop();
        altHeld = false;
        selected = Math.max(0, Math.min(windows.length - 1, start));
        open = true;
        mapped = true;
        idle.restart();
        clients.running = true;
    }

    function next() {
        if (!open) {
            show(windows.length > 1 ? 1 : 0);
        } else {
            altHeld = true;
            move(1);
        }
    }

    function previous() {
        if (!open) {
            show(windows.length - 1);
        } else {
            altHeld = true;
            move(-1);
        }
    }

    function move(by) {
        if (!open || windows.length === 0)
            return;
        selected = (selected + by + windows.length) % windows.length;
        idle.restart();
    }

    function pick(index) {
        selected = index;
        commit("click");
    }

    // Switch to the picked window. The switcher gives the keyboard back
    // first; mango hands it to the window you were in, so switching at the
    // same moment would be undone. Then mango's focusid (it also changes
    // workspace), or the Wayland way when mango's id isn't known.
    property var pending: null
    function commit(why) {
        if (!open)
            return;
        pending = windows[selected] ?? null;
        hide();
        if (!pending)
            return;
        console.log("switcher: to", pending.appId, "(" + (why ?? "key") + ")");
        focusLater.restart();
    }
    Timer {
        id: focusLater
        interval: 60
        onTriggered: {
            const t = root.pending;
            root.pending = null;
            if (!t)
                return;
            const id = root.tags[root.keyOf(t.appId, t.title)]?.id ?? -1;
            if (root.dryRun) {
                console.log("switcher (dry run): focus", t.appId, "|", t.title, "| mango id", id);
                return;
            }
            if (id >= 0)
                Quickshell.execDetached(["mmsg", "dispatch", "focusid", "client," + id]);
            else
                t.activate();
        }
    }

    // Close without switching.
    function cancel() {
        hide();
    }

    // Close the picked window (Q / W); the switcher stays open.
    function closeSelected() {
        const t = windows[selected];
        if (!t)
            return;
        idle.restart();
        if (dryRun)
            console.log("switcher (dry run): close", t.appId, "|", t.title);
        else
            t.close();
    }

    function hide() {
        idle.stop();
        if (!open)
            return;
        open = false;
        unmap.restart();
    }

    // Keep the list sane while open: closed windows drop out.
    onWindowsChanged: {
        if (!open)
            return;
        if (windows.length === 0)
            hide();
        else if (selected >= windows.length)
            selected = windows.length - 1;
    }

    // Nothing pressed for a while: switch (covers an Alt let go before the
    // switcher had the keyboard). Every key or click starts it over.
    Timer {
        id: idle
        interval: root.altHeld ? 4000 : Style.switcherIdleCommit
        onTriggered: root.commit("nothing pressed")
    }

    // Long enough for the fade out; the window only exists while needed.
    Timer {
        id: unmap
        interval: Motion.fast
        onTriggered: root.mapped = false
    }

    // Titles can start with a symbol that keeps changing (a terminal's
    // spinner, e.g. "✳ " / "◑ " / "⠋ "), so that part is left out of the match
    // (symbols, arrows, shapes, dingbats, braille: U+2000-2BFF).
    function keyOf(appId, title) {
        return (appId ?? "") + "\n" + (title ?? "").replace(/^[\u2000-\u2bff\s]+/, "");
    }

    function tagOf(t) {
        return tags[keyOf(t?.appId, t?.title)]?.tag ?? 0;
    }

    // Which workspace each window is on (mango knows, the Wayland side
    // doesn't): matched by app id + title.
    Process {
        id: clients
        command: ["mmsg", "get", "all-clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                try {
                    const data = JSON.parse(text);
                    const list = Array.isArray(data) ? data : (data.clients ?? []);
                    for (const c of list) {
                        const key = root.keyOf(c.appid, c.title);
                        map[key] = { tag: c.tags?.[0] ?? 0, id: map[key] ? -1 : (c.id ?? -1) };
                    }
                } catch (e) {}
                root.tags = map;
            }
        }
    }
}
