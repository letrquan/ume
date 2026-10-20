pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import "tiling.js" as Tiling

// The overview (Super+O, the hot corner, 4 fingers up): every workspace as
// a small copy of the screen in a grid, its windows where they really are.
// Click a window to go to it, a workspace to go there, drag a window onto
// another workspace (or "+") to move it there, middle-click a window to
// close it, type to find a window.
//
// Where the windows are and which workspace they're on comes from mango:
// `mmsg watch all-clients` (a JSON line now and after every change) runs
// only while the overview is open. The live pictures need the matching
// Wayland window (Toplevel), found by app id + title like the switcher.
//
// mango tiles only the workspace you're on: moving a window to another
// one (the drag), mango keeps reporting the old places there until you go
// there, so the overview shows where it will tile them (see shape(),
// tiling.js).
//
// Pictures of the windows: services/WindowShots.qml (grim; Quickshell's
// own capture can't take single windows on mango).
//
// Every mango command names the window by its id, and only an id that is a
// whole number from mango's current list: mango doesn't refuse a wrong one
// ("client,abc"), it uses the focused window instead.
//
// MINE_OVERVIEW_DRYRUN=1 (tests): going, moving and closing only print
// (moving also moves the window in the overview's own list).
Singleton {
    id: root

    property bool open: false
    property bool mapped: false
    // What you typed: windows on any workspace whose title or app has it.
    property string query: ""
    // The workspace the overview zooms into as it closes (the one you
    // picked, or the one you're on).
    property int closeTag: 0
    // mango's window list and screens have come in since it opened: until
    // then the overview draws nothing (else the first frames show your
    // workspace without its windows, or the wrong workspace).
    property bool clientsIn: false
    property bool monitorsIn: false
    readonly property bool fresh: clientsIn && monitorsIn

    readonly property bool dryRun: Quickshell.env("MINE_OVERVIEW_DRYRUN") === "1"

    // [{ id, ftid, appId, title, monitor, tag, x, y, width, height, focused,
    //    floating, fullscreen, maximized, toplevel }] (ftid: for grim -T)
    property var clients: []
    // The same as mango has it (clients: with the places guessed where
    // mango hasn't tiled yet, see shape()).
    property var raw: []
    // The same by mango id (the overview's tiles are keyed by id, so a
    // title changing doesn't make a new tile and a new live picture).
    readonly property var byId: {
        const map = {};
        for (const c of clients)
            map[c.id] = c;
        return map;
    }
    // { "<name>": { x, y, width, height, activeTag, tagCount, layouts: { tag: "DW" } } }
    property var monitors: ({})

    // A window moved: mango's list has it on its new workspace (`id`, `tag`).
    signal moved(int id, int tag)

    function toggle() {
        if (open)
            close();
        else
            show();
    }

    function show() {
        // They take the keyboard too.
        LauncherState.close();
        ClipboardState.close();
        NowPlayingState.close();
        CheatSheetState.close();
        SwitcherState.cancel();
        // Still up (opened again while flying back): the list is current.
        clientsIn = mapped;
        monitorsIn = false;
        if (!mapped)
            seed();
        unmap.stop();
        query = "";
        closeTag = 0;
        WindowShots.use(1);
        // open first: the window is created the moment `mapped` turns on.
        open = true;
        mapped = true;
        monitorReader.running = true;
    }

    // tag: the workspace to zoom into (0: the one you're on).
    function close(tag) {
        if (!open)
            return;
        closeTag = tag > 0 ? tag : 0;
        open = false;
        unmap.restart();
    }

    // The overview has flown back into the workspace (OverviewWindow): gone
    // at once, so no still picture covers your windows any longer.
    function closed() {
        if (open || !mapped)
            return;
        unmap.stop();
        mapped = false;
        forget();
    }
    function forget() {
        clients = [];
        raw = [];
        moving = {};
    }

    // ---- What's on screen -----------------------------------------------------------
    function onMonitor(name) {
        return clients.filter(c => c.monitor === name);
    }
    function onTag(name, tag) {
        return clients.filter(c => c.monitor === name && c.tag === tag);
    }
    function activeTag(name) {
        return monitors[name]?.activeTag ?? 1;
    }
    // The workspaces worth a card: the ones with windows and the one you're
    // on, in order.
    function tagsOf(name) {
        const set = new Set(onMonitor(name).map(c => c.tag));
        set.add(activeTag(name));
        return [...set].filter(t => t > 0).sort((a, b) => a - b);
    }
    // The first workspace with no windows (the "+" card), 0 if none is free.
    function freeTag(name) {
        const used = new Set(onMonitor(name).map(c => c.tag));
        const count = monitors[name]?.tagCount ?? 9;
        for (let t = 1; t <= count; t++)
            if (!used.has(t) && t !== activeTag(name))
                return t;
        return 0;
    }
    // Windows that match what you typed, from every workspace.
    function matching(text) {
        const words = text.toLowerCase().split(/\s+/).filter(w => w !== "");
        return clients.filter(c => {
            const hay = (c.title + " " + c.appId).toLowerCase();
            return words.every(w => hay.includes(w));
        });
    }

    // ---- Doing things -----------------------------------------------------------------
    // A window mango knows right now (see the top).
    function known(c) {
        return !!c && Number.isInteger(c.id) && c.id >= 0 && clients.some(x => x.id === c.id);
    }

    function run(what, cmd) {
        if (dryRun)
            console.log("overview (dry run):", what, JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    // Go to a window: the overview gives the keyboard back first (mango
    // hands it to the window you were in, which would undo a switch made at
    // the same moment), then mango's focusid, which also changes workspace.
    property var pending: null
    function focus(c) {
        if (!known(c) && !c?.toplevel)
            return;
        pending = known(c) ? c : Object.assign({}, c, { id: -1 });
        close(c.tag);
        focusLater.restart();
    }
    Timer {
        id: focusLater
        interval: 60
        onTriggered: {
            const c = root.pending;
            root.pending = null;
            if (!c)
                return;
            // The list was cleared on the way out: c is from just before.
            if (Number.isInteger(c.id) && c.id >= 0)
                root.run("focus " + c.appId, ["mmsg", "dispatch", "focusid", "client," + c.id]);
            else
                c.toplevel?.activate();
        }
    }

    // Go to a workspace.
    function view(tag) {
        close(tag);
        if (tag > 0)
            run("view " + tag, ["mmsg", "dispatch", "view," + tag]);
    }

    // Move a window to another workspace without following it (mango's
    // tagsilent on that one window); the overview stays open. False: not
    // moved.
    function moveTo(c, tag) {
        if (!c || !Number.isInteger(tag) || tag <= 0 || tag === c.tag)
            return false;
        if (!known(c)) {
            console.warn("overview: not moving", c.appId, "(" + c.id + "): mango doesn't list that window");
            return false;
        }
        console.log("overview: move", c.appId, "(" + c.id + ") to", tag);
        run("move " + c.appId + " to " + tag, ["mmsg", "dispatch", "tagsilent," + tag, "client," + c.id]);
        // The places mango last gave the windows on both workspaces, before
        // it changes (see shape()).
        remember(c.monitor, c.tag);
        remember(c.monitor, tag);
        // Right away here; mango's next list confirms it (read()).
        moving[c.id] = { tag: tag, since: Date.now() };
        raw = raw.map(x => x.id === c.id ? Object.assign({}, x, { tag: tag }, landingSpot(x, tag)) : x);
        clients = shape(raw);
        if (dryRun)
            moved(c.id, tag);
        return true;
    }

    // ---- Where mango will tile them ---------------------------------------------------
    // mango tiles only the workspace you're on (dwindle: halves of halves).
    // Moved onto another one, a window keeps the place it had where it was,
    // on top of (or under) the ones there, and leaves a hole; mango tiles
    // them when you go there. Until then the overview shows where it will
    // (tiling.js: from where it last tiled them, the windows gone taken
    // out, the new ones split in).
    //
    // "<monitor>/<tag>" → { base: [{ id, x, y, width, height }] }: such a
    // workspace and where mango last tiled its windows. Kept across
    // openings, until mango tiles it again (you went there).
    property var untiled: ({})
    // Moving: { id: { tag, since } }, until mango's list has it there.
    property var moving: ({})

    function tiled(c) {
        return !c.floating && !c.fullscreen && !c.maximized;
    }
    function layoutOf(mon, tag) {
        return monitors[mon]?.layouts?.[tag] ?? "";
    }
    function shownTag(mon, tag) {
        return monitors[mon]?.activeTag === tag;
    }
    function remember(mon, tag) {
        const key = mon + "/" + tag;
        if (untiled[key] || shownTag(mon, tag) || layoutOf(mon, tag) !== "DW")
            return;
        untiled[key] = {
            base: raw.filter(x => x.monitor === mon && x.tag === tag && tiled(x))
                .map(x => ({ id: x.id, x: x.x, y: x.y, width: x.width, height: x.height }))
        };
    }
    // The screen's room for windows: the workspace you're on (it's tiled),
    // or a window alone on its workspace (it fills it).
    function areaOf(mon, list) {
        const byTag = {};
        for (const c of list)
            if (c.monitor === mon && tiled(c) && !untiled[mon + "/" + c.tag])
                (byTag[c.tag] ?? (byTag[c.tag] = [])).push(c);
        const here = byTag[monitors[mon]?.activeTag];
        if (here && layoutOf(mon, monitors[mon].activeTag) === "DW")
            return Tiling.bounds(here);
        for (const t in byTag)
            if (byTag[t].length === 1 && layoutOf(mon, Number(t)) === "DW")
                return Tiling.bounds(byTag[t]);
        return null;
    }
    // (mango's own default when no two windows show it.)
    function gapOf(list) {
        return Tiling.innerGap(list.filter(c => tiled(c) && !untiled[c.monitor + "/" + c.tag]), 5);
    }
    // Onto the workspace you're on: mango tiles it at once (its list comes
    // a moment later); until then, the place it will likely get (the
    // dragged copy flies there).
    function landingSpot(c, tag) {
        if (!shownTag(c.monitor, tag) || layoutOf(c.monitor, tag) !== "DW" || !tiled(c))
            return {};
        const there = raw.filter(x => x.monitor === c.monitor && x.tag === tag && tiled(x) && x.id !== c.id);
        const list = Tiling.insert(there.map(x => ({ id: x.id, x: x.x, y: x.y, width: x.width, height: x.height })),
                                   c.id, areaOf(c.monitor, raw), gapOf(raw), there.find(x => x.focused)?.id ?? -1);
        const r = list?.find(x => x.id === c.id);
        return r ? { x: r.x, y: r.y, width: r.width, height: r.height } : {};
    }
    // mango's list with the places it will give the windows where it
    // hasn't tiled yet.
    function shape(list) {
        const keys = Object.keys(untiled);
        if (keys.length === 0)
            return list;
        const place = {};
        const areas = {};
        const gap = gapOf(list);
        for (const key of keys) {
            const cut = key.lastIndexOf("/");
            const mon = key.substring(0, cut);
            const tag = Number(key.substring(cut + 1));
            const base = untiled[key].base;
            const here = list.filter(c => c.monitor === mon && c.tag === tag && tiled(c));
            // Shown now, or tiled again since (a window that stayed there
            // has a new place): mango's places are right again.
            const again = here.some(c => {
                const b = base.find(r => r.id === c.id);
                return b && (b.x !== c.x || b.y !== c.y || b.width !== c.width || b.height !== c.height);
            });
            const layout = layoutOf(mon, tag);
            if (shownTag(mon, tag) || again || (layout !== "" && layout !== "DW")) {
                delete untiled[key];
                continue;
            }
            if (layout === "")
                continue;
            if (!(mon in areas))
                areas[mon] = areaOf(mon, list);
            Object.assign(place, Tiling.dwindle(base, here.map(c => c.id), areas[mon], gap));
        }
        return list.map(c => place[c.id] ? Object.assign({}, c, place[c.id]) : c);
    }

    // Close a window (the app may ask first).
    function closeWindow(c) {
        if (!c)
            return;
        if (!c.toplevel && !known(c)) {
            console.warn("overview: not closing", c.appId, "(" + c.id + "): mango doesn't list that window");
            return;
        }
        if (dryRun)
            console.log("overview (dry run): close", c.appId, "|", c.title);
        else if (c.toplevel)
            c.toplevel.close();
        else if (known(c))
            Quickshell.execDetached(["mmsg", "dispatch", "killclient", "client," + c.id]);
    }

    // ---- Reading mango ----------------------------------------------------------------
    // Same matching as the switcher: a title can start with a symbol that
    // keeps changing (a terminal's spinner), so that part is left out.
    function keyOf(appId, title) {
        return SwitcherState.keyOf(appId, title);
    }

    // Each mango window gets its Wayland window (for the live picture and
    // closing). Two windows with the same app and title share in order.
    function attach(list) {
        const pool = {};
        for (const t of ToplevelManager.toplevels.values) {
            const k = keyOf(t.appId, t.title);
            (pool[k] ?? (pool[k] = [])).push(t);
        }
        return list.map(c => {
            const k = keyOf(c.appId, c.title);
            c.toplevel = pool[k]?.shift() ?? null;
            return c;
        });
    }

    function read(line) {
        let list;
        try {
            const data = JSON.parse(line);
            list = Array.isArray(data) ? data : (data.clients ?? []);
        } catch (e) {
            console.warn("overview: can't read clients", line.substring(0, 80));
            return;
        }
        // Scratchpads and windows on every workspace (picture in picture)
        // don't belong to one workspace.
        const out = list.filter(c => !c.is_scratchpad && !c.is_namedscratchpad && !c.is_global && (c.tags?.length ?? 0) > 0)
            .sort((a, b) => a.id - b.id)
            .map(c => ({
                id: Number.isInteger(c.id) ? c.id : -1,
                ftid: c.foreign_toplevel_id ?? "",
                appId: c.appid ?? "",
                title: c.title ?? "",
                monitor: c.monitor ?? "",
                tag: c.tags[0],
                x: c.x ?? 0,
                y: c.y ?? 0,
                width: Math.max(1, c.width ?? 1),
                height: Math.max(1, c.height ?? 1),
                focused: c.is_focused ?? false,
                floating: c.is_floating ?? false,
                fullscreen: c.is_fullscreen ?? false,
                maximized: c.is_maximized ?? false,
                toplevel: null
            }));
        // Just moved: mango's list may be from just before; it stays where
        // it went until mango's has it there (or 1.5 s: then mango's word).
        const done = [];
        const now = Date.now();
        for (const c of out) {
            const m = moving[c.id];
            if (!m)
                continue;
            if (c.tag === m.tag) {
                delete moving[c.id];
                done.push(c);
            } else if (now - m.since < 1500) {
                c.tag = m.tag;
            } else {
                delete moving[c.id];
                console.warn("overview: mango didn't move", c.appId, "(" + c.id + ") to", m.tag);
            }
        }
        raw = attach(out);
        clients = shape(raw);
        clientsIn = true;
        for (const c of done)
            moved(c.id, c.tag);
        // Pictures of windows that are gone go too.
        WindowShots.prune(list.map(c => c.foreign_toplevel_id ?? ""));
    }

    // While open: the windows, live.
    Process {
        id: watcher
        command: ["mmsg", "watch", "all-clients"]
        running: root.mapped
        stdout: SplitParser {
            onRead: line => root.read(line)
        }
    }
    function monitorEntry(m) {
        const active = (m.tags ?? []).find(t => t.is_active)?.index ?? m.active_tags?.[0] ?? 1;
        const layouts = {};
        for (const t of (m.tags ?? []))
            layouts[t.index] = t.layout ?? "";
        return { x: m.x ?? 0, y: m.y ?? 0, width: m.width ?? 0, height: m.height ?? 0,
                 activeTag: active, tagCount: m.tag_num ?? 9, layouts: layouts };
    }

    // Start from what the bar's watchers already know (`mmsg watch`: as of
    // the last change), so the overview can show at once instead of waiting
    // ~30 ms for its own readers; they still come in and refresh it.
    function seed() {
        // (The screens first: which workspaces are shown, for shape().)
        const map = {};
        let all = Quickshell.screens.length > 0;
        for (const s of Quickshell.screens) {
            const m = Monitors.byScreen[s.name]?.latest;
            if (m)
                map[s.name] = monitorEntry(m);
            else
                all = false;
        }
        if (all) {
            monitors = map;
            monitorsIn = true;
        }
        if (MangoClients.lastLine !== "")
            read(MangoClients.lastLine);
    }

    // Once per opening: the screens and the workspace each one shows.
    Process {
        id: monitorReader
        command: ["mmsg", "get", "all-monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                try {
                    const data = JSON.parse(text);
                    for (const m of (data.monitors ?? []))
                        map[m.name] = root.monitorEntry(m);
                } catch (e) {}
                root.monitors = map;
                root.monitorsIn = true;
                if (root.raw.length > 0)
                    root.clients = root.shape(root.raw);
            }
        }
    }

    // A window opened or closed while the overview is up: match again.
    Connections {
        target: ToplevelManager.toplevels
        enabled: root.mapped
        function onValuesChanged() {
            root.raw = root.attach(root.raw.map(c => Object.assign({}, c)));
            root.clients = root.shape(root.raw);
        }
    }

    // The wallpaper, decoded once and kept (about 6 MB per screen): every
    // workspace in the overview shows it at once (same file, same size: Qt's
    // picture cache hands this one out) instead of decoding the big file
    // again on each opening, which held up the windows' pictures (and so
    // the zoom) by ~80 ms.
    Variants {
        model: Quickshell.screens

        Image {
            required property var modelData
            source: Colors.wallpaper !== "" ? "file://" + Colors.wallpaper : ""
            sourceSize: Qt.size(modelData.width, modelData.height)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: false
        }
    }

    // In case closed() never comes (it normally does, when the windows have
    // flown back); the window only exists while needed (and nothing is
    // captured once it's gone).
    Timer {
        id: unmap
        interval: Style.overviewCloseMs + 400
        onTriggered: {
            root.mapped = false;
            root.forget();
        }
    }
}
