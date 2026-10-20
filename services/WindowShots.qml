pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Pictures of windows, for the overview and the dock's hover card.
// Quickshell's own ScreencopyView can't take one window on mango (it only
// knows Hyprland's way), but `grim -T <id>` can, also windows on another
// workspace. The id is the window's "foreign toplevel" id, which mango lists
// in `mmsg get all-clients`.
//
// Pictures stay in $XDG_RUNTIME_DIR/mine-shell/shots (memory, small) as
// <id>-<kind>.jpg between openings, so the overview shows the last ones at
// once and takes new ones in the background. A window's pictures go when
// the window does (prune). "kind" keeps the overview's big pictures apart
// from the dock's small ones.
//
// MINE_GRIM (tests): another command instead of grim (same arguments).
Singleton {
    id: root

    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/mine-shell/shots"
    readonly property string grim: Quickshell.env("MINE_GRIM") || "grim"

    // { "<id>-<kind>": n }: n goes up each time a new picture of it is in.
    // A picture byte for byte the same as the last (the window didn't
    // change) isn't new: nothing loads it again or fades it in.
    property var versions: ({})

    // A picture was taken: `key` "<id>-<kind>", `changed` false when it was
    // the same as the last one (the overview takes those less often).
    signal taken(string key, bool changed)

    // The picture ("" until there is one). The ?v= makes an Image load it
    // again when a new one comes in.
    function url(id, kind) {
        const key = id + "-" + kind;
        const v = versions[key];
        return validId(id) && v ? "file://" + dir + "/" + key + ".jpg?v=" + v : "";
    }

    function validId(id) {
        return typeof id === "string" && /^[0-9a-f]{8,64}$/i.test(id);
    }

    // ---- The pictures from before (also from before a restart) ------------------
    property bool scanned: false
    function use(delta) {
        if (!scanned && delta > 0) {
            scanned = true;
            scanner.running = true;
        }
    }
    Process {
        id: scanner
        command: ["sh", "-c", 'cd "$1" 2>/dev/null && ls *.jpg 2>/dev/null', "sh", root.dir]
        stdout: SplitParser {
            onRead: line => {
                const m = line.trim().match(/^([0-9a-f]+-[a-z]+)\.jpg$/i);
                if (m && !root.versions[m[1]]) {
                    const v = Object.assign({}, root.versions);
                    v[m[1]] = 1;
                    root.versions = v;
                }
            }
        }
    }

    // ---- Taking them -----------------------------------------------------------------------
    // [{ id, scale, kind }]: scale is of the window's own (logical) size, as
    // grim -s takes it; 1.25 = every pixel of this screen. Side by side, each
    // showing up as soon as it's in. While a batch is still going, the
    // newest request waits for it (one waiting per kind of request).
    property var waiting: []
    function capture(list) {
        const seen = new Set();
        const items = list.filter(i => validId(i.id) && /^[a-z]+$/.test(i.kind ?? "")
                                       && !seen.has(i.id + i.kind) && seen.add(i.id + i.kind));
        if (items.length === 0)
            return;
        if (batch.running) {
            // Newest wins for the same window and kind.
            const keep = waiting.filter(w => !items.some(i => i.id === w.id && i.kind === w.kind));
            waiting = keep.concat(items);
            return;
        }
        const args = ["sh", "-c",
            'mkdir -p "$1" && cd "$1" || exit 1; g=$2; shift 2\n'
            + 'while [ $# -gt 2 ]; do\n'
            + '  ( "$g" -T "$1" -s "$2" -t jpeg -q 88 "$1-$3.tmp.jpg" 2>/dev/null && if cmp -s "$1-$3.tmp.jpg" "$1-$3.jpg"; then rm -f "$1-$3.tmp.jpg"; echo "same $1-$3"; else mv -f "$1-$3.tmp.jpg" "$1-$3.jpg" && echo "ok $1-$3"; fi ) &\n'
            + '  shift 3\n'
            + 'done\n'
            + 'wait',
            "sh", dir, grim];
        for (const i of items)
            args.push(i.id, Math.max(0.05, Math.min(1.25, Number(i.scale) || 0.25)).toFixed(3), i.kind);
        batch.command = args;
        batch.running = true;
    }

    // Drop the pictures of `kind` still waiting to be taken.
    function cancel(kind) {
        waiting = waiting.filter(w => w.kind !== kind);
    }

    Process {
        id: batch
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/^(ok|same) ([0-9a-f]+-[a-z]+)$/i);
                if (!m)
                    return;
                if (m[1] === "ok") {
                    const v = Object.assign({}, root.versions);
                    v[m[2]] = (v[m[2]] ?? 0) + 1;
                    root.versions = v;
                }
                root.taken(m[2], m[1] === "ok");
            }
        }
        onExited: {
            const w = root.waiting;
            root.waiting = [];
            if (w.length > 0)
                root.capture(w);
        }
    }

    // Forget the pictures of windows that are gone: `alive` = the ids of
    // every window there is now.
    function prune(alive) {
        const keep = new Set(alive.filter(validId));
        const gone = Object.keys(versions).filter(k => !keep.has(k.replace(/-[a-z]+$/, "")));
        if (gone.length === 0)
            return;
        const v = Object.assign({}, versions);
        for (const k of gone)
            delete v[k];
        versions = v;
        Quickshell.execDetached(["sh", "-c", 'cd "$1" 2>/dev/null || exit 0; shift; for k; do rm -f "$k.jpg" "$k.tmp.jpg"; done', "sh", dir].concat(gone));
    }

    // ---- Which picture is which window (the dock's card) -------------------------------
    // The dock knows Wayland windows, not mango's: matched by app id + title
    // like the switcher. { "<key>": [{ id (mango), ftid, width, height }] }
    property var clients: ({})
    function lookup() {
        if (!clientReader.running)
            clientReader.running = true;
    }
    // { id, ftid, width, height } of a Wayland window, or null.
    function infoFor(toplevel) {
        if (!toplevel)
            return null;
        const key = SwitcherState.keyOf(toplevel.appId, toplevel.title);
        const list = clients[key] ?? [];
        // Two windows with the same app and title: in the order they're listed.
        const same = ToplevelManager.toplevels.values.filter(t => SwitcherState.keyOf(t.appId, t.title) === key);
        return list[Math.max(0, same.indexOf(toplevel))] ?? list[0] ?? null;
    }
    Process {
        id: clientReader
        command: ["mmsg", "get", "all-clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                const alive = [];
                try {
                    const data = JSON.parse(text);
                    const list = (Array.isArray(data) ? data : (data.clients ?? [])).slice().sort((a, b) => a.id - b.id);
                    for (const c of list) {
                        const key = SwitcherState.keyOf(c.appid, c.title);
                        (map[key] ?? (map[key] = [])).push({ id: c.id, ftid: c.foreign_toplevel_id ?? "",
                                                            width: Math.max(1, c.width ?? 1), height: Math.max(1, c.height ?? 1) });
                        alive.push(c.foreign_toplevel_id ?? "");
                    }
                } catch (e) {
                    return;
                }
                root.clients = map;
                root.prune(alive);
            }
        }
    }
}
