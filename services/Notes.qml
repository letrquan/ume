pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Notes and to-dos (the notes panel, notes/NotesWindow.qml; the desktop's
// notes card, desktop/NotesCard.qml; the control center's Notes tile):
//   text  a title and free text
//   list  a checklist: tick, add, delete, drag to reorder; ticked ones go
//         to the bottom, folded away (Style.notesCollapseDone)
//   ink   a page to write or sketch on with the pen (ink/InkCanvas.qml,
//         the same drawing as the screen's ink), kept as strokes
// One of them shows on the desktop card (`desktopId`; none picked: the
// newest). Typing happens in the panel: it takes the keyboard, the
// shell's on-screen keyboard types into it, and an input method's word
// still being composed (bamboo's preedit) is kept when the panel closes or
// loses the keyboard (notes/Composing.qml). The desktop card only shows,
// ticks and opens the panel.
// Kept in ~/.local/state/mine-shell/notes.json (MINE_NOTES_STATE for
// tests), saved a moment after a change through services/StateStore.qml
// (a private file moved into place: never half written, never through a
// link left at its name).
// qs -c mine ipc call notes toggle | open | close | add text|list|ink
Singleton {
    id: root

    readonly property string statePath: Quickshell.env("MINE_NOTES_STATE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/notes.json")

    // [{ id, kind: "text" | "list" | "ink", title, updated (ms),
    //    text (text), items: [{ id, text, done }] (list),
    //    strokes: [ink/ink.js strokes, points only], w, h (ink) }]
    property var notes: []
    property string desktopId: ""
    readonly property var desktopNote: notes.find(n => n.id === desktopId) ?? newest
    readonly property var newest: notes.length === 0 ? null : notes.reduce((a, b) => (b.updated > a.updated ? b : a))
    // Goes up on every change (cards re-read what they show).
    property int revision: 0

    // ---- The panel ----------------------------------------------------------------------
    property bool open: false
    property bool mapped: false             // its window exists (open, or fading out)
    property string current: ""             // the note open in it ("": the list)
    property string screen: ""              // where it opens ("": the focused one)

    // Open on a note (or the list), on a screen (by name; none: the focused one).
    function show(id, screenName) {
        if (id !== undefined && id !== null)
            current = notes.some(n => n.id === id) ? id : "";
        unmap.stop();
        if (mapped || screenName) {
            if (!mapped)
                screen = screenName;
            open = true;
            mapped = true;
            return;
        }
        // Which screen has the focus (mango), then up.
        focused.running = true;
    }
    Process {
        id: focused
        command: ["mmsg", "get", "all-monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                let name = "";
                try {
                    name = (JSON.parse(text).monitors ?? []).find(o => o.active)?.name ?? "";
                } catch (e) {}
                root.screen = Quickshell.screens.some(s => s.name === name) ? name : (Quickshell.screens[0]?.name ?? "");
                root.open = true;
                root.mapped = true;
            }
        }
    }
    function close() {
        if (!open)
            return;
        // The panel puts any word still being composed in first (it listens),
        // and what's waiting is written now, not a moment later.
        closing();
        Qt.callLater(store.flush);
        open = false;
        unmap.restart();
    }
    function toggle() {
        if (open)
            close();
        else
            show();
    }
    signal closing()
    Timer {
        id: unmap
        interval: Motion.normal + 120
        onTriggered: if (!root.open) root.mapped = false
    }

    // ---- Notes ----------------------------------------------------------------------------
    property int counter: 0
    function newId(prefix) {
        counter++;
        return prefix + Date.now().toString(36) + counter;
    }
    function find(id) {
        return notes.find(n => n.id === id) ?? null;
    }

    // A new note at the top: its id.
    function add(kind) {
        const k = ["text", "list", "ink"].includes(kind) ? kind : "text";
        const n = { id: newId("n"), kind: k, title: "", updated: Date.now() };
        if (k === "text")
            n.text = "";
        else if (k === "list")
            n.items = [];
        else {
            n.strokes = [];
            n.w = 0;
            n.h = 0;
        }
        notes = [n].concat(notes);
        changed();
        return n.id;
    }

    // Fields of a note changed (title, text, items, strokes, w, h); the
    // same values again change nothing (not even its time).
    function update(id, fields) {
        const n = find(id);
        if (!n)
            return;
        const same = Object.keys(fields).every(k => typeof fields[k] === "object" && fields[k] !== null
            ? JSON.stringify(fields[k]) === JSON.stringify(n[k]) : fields[k] === n[k]);
        if (same)
            return;
        notes = notes.map(x => x.id === id ? Object.assign({}, x, fields, { updated: Date.now() }) : x);
        changed();
    }

    function remove(id) {
        notes = notes.filter(n => n.id !== id);
        if (desktopId === id)
            desktopId = "";
        if (current === id)
            current = "";
        changed();
    }

    // On the desktop card ("" = the newest).
    function pin(id) {
        desktopId = desktopId === id ? "" : id;
        changed();
    }

    // ---- Checklist items ----
    function setItems(id, items) {
        update(id, { items: items.map(i => ({ id: i.id || newId("i"), text: String(i.text ?? ""), done: i.done === true })) });
    }
    function addItem(id, text) {
        const n = find(id);
        if (!n || n.kind !== "list")
            return "";
        const item = { id: newId("i"), text: String(text ?? ""), done: false };
        // After the last one not done (ticked ones stay at the bottom).
        const items = n.items.slice();
        const at = items.findIndex(i => i.done);
        items.splice(at < 0 ? items.length : at, 0, item);
        update(id, { items: items });
        return item.id;
    }
    // Ticked: to the top of the ticked ones; unticked: back after the rest.
    function toggleItem(id, itemId) {
        const n = find(id);
        const it = n?.items?.find(i => i.id === itemId);
        if (!it)
            return;
        const rest = n.items.filter(i => i.id !== itemId);
        const moved = Object.assign({}, it, { done: !it.done });
        const firstDone = rest.findIndex(i => i.done);
        rest.splice(firstDone < 0 ? rest.length : firstDone, 0, moved);
        update(id, { items: rest });
    }
    function removeItem(id, itemId) {
        const n = find(id);
        if (n?.items)
            update(id, { items: n.items.filter(i => i.id !== itemId) });
    }
    function moveItem(id, from, to) {
        const n = find(id);
        if (!n?.items || from < 0 || from >= n.items.length || to < 0 || to >= n.items.length || from === to)
            return;
        const items = n.items.slice();
        items.splice(to, 0, items.splice(from, 1)[0]);
        update(id, { items: items });
    }

    // What a note is called in lists: its title, else its first words.
    function label(n) {
        if (!n)
            return "";
        if (n.title.trim() !== "")
            return n.title.trim();
        if (n.kind === "text" && n.text.trim() !== "")
            return n.text.trim().split("\n")[0].slice(0, 60);
        if (n.kind === "list" && n.items.length > 0)
            return n.items[0].text.slice(0, 60) || "Checklist";
        return n.kind === "list" ? "Checklist" : n.kind === "ink" ? "Drawing" : "Note";
    }
    // "now", "5m", "2h", "Mon", "14 Oct".
    function ago(time) {
        const minutes = Math.floor((Date.now() - time) / 60000);
        if (minutes < 1)
            return "now";
        if (minutes < 60)
            return minutes + "m";
        if (minutes < 24 * 60)
            return Math.floor(minutes / 60) + "h";
        const locale = Style.clockLocale !== "" ? Qt.locale(Style.clockLocale) : Qt.locale();
        return locale.toString(new Date(time), minutes < 7 * 24 * 60 ? "ddd" : "d MMM");
    }
    function iconOf(n) {
        return n?.kind === "list" ? "checklist" : n?.kind === "ink" ? "draw" : "notes";
    }

    // ---- Kept ------------------------------------------------------------------------------
    property bool loaded: false

    function changed() {
        revision++;
        if (loaded)
            store.save(JSON.stringify({ version: 1, desktop: desktopId, notes: notes }) + "\n");
    }

    function read(text) {
        let d = {};
        try {
            d = text.trim() === "" ? {} : JSON.parse(text);
        } catch (e) {
            console.warn("notes: can't read", statePath, "- starting empty (the file is left as it is until a change)");
        }
        const str = v => typeof v === "string" ? v : "";
        const num = v => typeof v === "number" && isFinite(v) ? v : 0;
        notes = (Array.isArray(d.notes) ? d.notes : [])
            .filter(n => n && typeof n.id === "string" && ["text", "list", "ink"].includes(n.kind))
            .map(n => {
                const out = { id: n.id, kind: n.kind, title: str(n.title), updated: num(n.updated) };
                if (n.kind === "text")
                    out.text = str(n.text);
                else if (n.kind === "list")
                    out.items = (Array.isArray(n.items) ? n.items : []).filter(i => i && typeof i.id === "string")
                        .map(i => ({ id: i.id, text: str(i.text), done: i.done === true }));
                else {
                    out.strokes = (Array.isArray(n.strokes) ? n.strokes : []).filter(s => s && Array.isArray(s.points));
                    out.w = num(n.w);
                    out.h = num(n.h);
                }
                return out;
            });
        desktopId = str(d.desktop);
        loaded = true;
        revision++;
    }

    signal saved(bool ok)
    StateStore {
        id: store
        path: root.statePath
        onLoaded: text => root.read(text)
        onSaved: ok => root.saved(ok)
    }
    Component.onCompleted: store.load()

    // Write what's waiting now (the tests; saved() says when it's done).
    function flush() {
        store.flush();
    }
    // Read the file again, as a restart would (the tests).
    function reload() {
        store.load();
    }
}
