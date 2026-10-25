pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Reopens the apps that were open when you last logged out or shut down.
//
// Keeping the list: one entry per app id (its desktop entry, and the screen
// and workspace of its first window) in ~/.local/state/mine-shell/open-apps.json,
// written a few seconds after the windows last changed. Logging out closes
// the windows one by one, and a list written then would miss apps, so the
// wait is longer than that takes (the shell is gone by then), and once Log
// out, Restart or Shut down is picked in the power menu, or logind says the
// system is going down (shell.qml hears it from the Locker's listener), the
// list is written right then and kept as it is. Still running 90 s later:
// nothing happened (cancelled, refused), so it's kept up to date again.
//
// Reopening: once per login, never after a restart of the shell (`mine
// restart`, after a crash, a deploy). A login is a new mango: its pid (from
// MANGO_INSTANCE_SIGNATURE, $XDG_RUNTIME_DIR/mango-<pid>.sock) and start
// time. The mango last seen is noted in $XDG_RUNTIME_DIR/mine-shell/restored
// before anything starts; a mango that has been up for minutes already
// (the first start of this feature, or a start without a login) is only
// noted. A moment after the desktop is up, each app is started once, the way
// the dock starts it (a browser or Spotify brings back its own windows), one
// after another, and its first new window is sent to the workspace it was
// on (mango's tagsilent: you stay where you are). Not reopened: apps without
// a desktop entry, apps that start by themselves (mango's exec_once lines,
// ~/.config/autostart), the shell's own windows, Style.restoreAppsExclude.
// The screen is kept in the list but not used (one screen here).
//
// Tests: MINE_RESTORE_STATE (the list), MINE_RESTORE_DIR (instead of
// $XDG_RUNTIME_DIR/mine-shell), MINE_RESTORE_FRESH (seconds a mango counts
// as just started, 120), MINE_RESTORE_DRYRUN=1 (nothing started or moved,
// only printed). mango's config and autostart folders follow XDG_CONFIG_HOME.
Singleton {
    id: root

    readonly property bool enabled: Style.restoreApps
    readonly property bool dryRun: Quickshell.env("MINE_RESTORE_DRYRUN") === "1"
    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string statePath: Quickshell.env("MINE_RESTORE_STATE")
        || (home + "/.local/state/mine-shell/open-apps.json")
    // No runtime folder: no way to tell a login from a restart, so never reopen.
    readonly property string runDir: Quickshell.env("MINE_RESTORE_DIR")
        || (Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/mine-shell" : "")
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    readonly property int freshSeconds: Number(Quickshell.env("MINE_RESTORE_FRESH")) || 120
    readonly property string mangoPid: (Quickshell.env("MANGO_INSTANCE_SIGNATURE") ?? "").match(/mango-(\d+)\.sock$/)?.[1] ?? ""

    // How long after starting an app its first new window is still sent to
    // its workspace (a cold Spotify or Discord takes a while).
    readonly property int placeMs: 60000
    // Between two apps starting.
    readonly property int staggerMs: 500

    // What the file said at start (what a login reopens), then what was
    // last written: [{ appId, entry, name, monitor, tag, windows }].
    property var apps: []
    property bool fileRead: false
    property string lastText: ""

    // This mango ("<pid> <start time>"), once known.
    property string key: ""
    // "": not known yet; "new": a new login, reopen; "done": this mango had
    // its turn already (the shell restarted); "late": mango was up long
    // before the shell; "off": turned off at start; "none": can't tell which
    // mango this is.
    property string verdict: ""
    // The login's apps are being reopened (the list isn't written meanwhile).
    property bool restoring: false
    // Leaving (see the top): the list is kept as it is.
    property bool frozen: false

    readonly property bool entriesLoaded: DesktopEntries.applications.values.length > 0
    // Writing the list: on, the old one read first, the apps known (else
    // every app would look like one without a desktop entry), mango's list in.
    readonly property bool saving: enabled && fileRead && verdict !== "" && entriesLoaded
        && MangoClients.listed && !restoring && !frozen

    // For the Settings window: what the next login would reopen (apps that
    // start by themselves are only known then).
    readonly property string summary: {
        if (!enabled)
            return "";
        const names = apps.filter(a => a.entry && !Style.restoreAppsExclude.includes(a.appId)).map(a => a.name || a.appId);
        return names.length === 0 ? "No apps open" : names.join(", ");
    }

    // ---- Keeping the list --------------------------------------------------------------
    // The apps with windows now, in the order their first window opened.
    function current() {
        const out = [];
        const at = {};
        for (const c of MangoClients.clients) {
            // The shell's own (the Settings window).
            if (c.pid === Quickshell.processId)
                continue;
            if (at[c.appId] !== undefined) {
                out[at[c.appId]].windows++;
                continue;
            }
            const entry = entryFor(c.appId);
            at[c.appId] = out.length;
            out.push({ appId: c.appId, entry: entry?.id ?? "", name: entry?.name || c.appId,
                       monitor: c.monitor, tag: c.tag, windows: 1 });
        }
        return out;
    }

    function entryFor(appId) {
        if (!appId)
            return null;
        return DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId) ?? null;
    }

    function save() {
        if (saving)
            write(current());
    }

    function write(list) {
        apps = list;
        const text = JSON.stringify({ apps: list }, null, 1) + "\n";
        if (text === lastText)
            return;
        lastText = text;
        store.setText(text);
    }

    function readSaved(text) {
        if (fileRead)
            return;
        try {
            const list = text.trim() === "" ? [] : (JSON.parse(text).apps ?? []);
            apps = Array.isArray(list) ? list.filter(a => a && typeof a.appId === "string" && a.appId !== "") : [];
            lastText = text;
        } catch (e) {
            console.warn("restore: can't read", statePath);
        }
        fileRead = true;
    }

    onSavingChanged: if (saving) saveLater.restart()

    Connections {
        target: MangoClients
        function onClientsChanged() {
            if (root.saving)
                saveLater.restart();
            if (root.waiting.length > 0)
                root.place();
        }
    }

    // Long enough that windows closing one by one at logout never get written.
    Timer {
        id: saveLater
        interval: 5000
        onTriggered: root.save()
    }

    FileView {
        id: store
        path: root.statePath
        atomicWrites: true
        // Written before the power menu's logout goes ahead.
        blockWrites: true
        printErrors: false

        onLoaded: root.readSaved(text())
        onLoadFailed: root.readSaved("")
    }

    // ---- Leaving -----------------------------------------------------------------------
    // Log out / Restart / Shut down picked (SessionState), or logind says the
    // system is going down: write the windows as they are now, then keep it.
    function leave(why) {
        if (!enabled || frozen)
            return;
        if (saving) {
            saveLater.stop();
            write(current());
        }
        frozen = true;
        thaw.restart();
        markLeaving(true);
        console.log("restore: keeping the list of open apps (" + why + "):", apps.map(a => a.appId).join(", "));
    }

    // It didn't happen (logind: shutdown cancelled; or 90 s went by).
    function stay() {
        if (!frozen)
            return;
        frozen = false;
        thaw.stop();
        markLeaving(false);
        console.log("restore: keeping the list up to date again");
    }

    Timer {
        id: thaw
        interval: 90000
        onTriggered: root.stay()
    }

    // So a shell restarted in the middle of leaving keeps the list too.
    function markLeaving(on) {
        if (key === "" || runDir === "")
            return;
        Quickshell.execDetached(on
            ? ["sh", "-c", "mkdir -p \"$1\" && printf '%s\\n' \"$2\" > \"$1/leaving\"", "sh", runDir, key]
            : ["rm", "-f", runDir + "/leaving"]);
    }

    // ---- Which login is this -----------------------------------------------------------
    // One step, before anything starts: this mango's pid and start time
    // (/proc/<pid>/stat, field 22) against the one noted last, then the new
    // one noted. Prints "leaving" (see markLeaving), "key <pid> <start>",
    // then the verdict.
    readonly property string checkScript: [
        'pid=$1 dir=$2 fresh=$3 on=$4',
        'start=$(sed "s/.*) //" "/proc/$pid/stat" 2>/dev/null | cut -d" " -f20)',
        'case "$(cat "/proc/$pid/comm" 2>/dev/null)" in mango*) ;; *) start= ;; esac',
        '[ -n "$start" ] || { echo none; exit 0; }',
        'key="$pid $start"',
        '[ "$(cat "$dir/leaving" 2>/dev/null)" = "$key" ] && echo leaving',
        'echo "key $key"',
        '[ "$(cat "$dir/restored" 2>/dev/null)" = "$key" ] && { echo done; exit 0; }',
        'mkdir -p "$dir" && printf "%s\\n" "$key" > "$dir/restored.new" && mv -f "$dir/restored.new" "$dir/restored" || { echo none; exit 0; }',
        '[ "$on" = 1 ] || { echo off; exit 0; }',
        'up=$(awk -v s="$start" -v hz="$(getconf CLK_TCK)" \'{ printf "%d", $1 - s / hz }\' /proc/uptime)',
        'if [ "$up" -le "$fresh" ]; then echo new; else echo "late $up"; fi'
    ].join("\n")

    Process {
        id: check
        command: ["sh", "-c", root.checkScript, "sh", root.mangoPid, root.runDir, String(root.freshSeconds), root.enabled ? "1" : "0"]
        stdout: StdioCollector {
            onStreamFinished: root.decide(text)
        }
    }

    function decide(text) {
        const lines = text.trim().split("\n");
        for (const line of lines)
            if (line.startsWith("key "))
                key = line.substring(4);
        if (lines.includes("leaving")) {
            frozen = true;
            thaw.restart();
            console.log("restore: the shell restarted while leaving; keeping the list as it is");
        }
        const last = lines[lines.length - 1].split(" ");
        const said = ["new", "done", "late", "off", "none"].includes(last[0]) ? last[0] : "none";
        if (said === "new") {
            console.log("restore: a new login; reopening the apps soon");
            begin();
        } else if (said === "done") {
            console.log("restore: the shell restarted; the apps were reopened at login already");
        } else if (said === "late") {
            console.log("restore: mango has been up " + last[1] + " s; reopening only at login");
        }
        verdict = said;
    }

    // ---- Reopening ---------------------------------------------------------------------
    // Apps not to reopen (lower case names: app ids, desktop entry ids and
    // programs that mango or ~/.config/autostart start by themselves).
    property var autostarted: []
    property bool autostartRead: false
    property bool entriesLate: false
    property bool begun: false
    property var queue: []
    // Started, until their window is placed or time is up:
    // [{ appId, tag, since, before (window ids), placedId, shown }]
    property var waiting: []
    property var opened: []

    // The desktop is up: the list read, the apps known (or 10 s), mango's
    // windows in, the intro under way. Then a moment more.
    readonly property bool upAndReady: restoring && fileRead && autostartRead && MangoClients.listed
        && Intro.started && (entriesLoaded || entriesLate)
    onUpAndReadyChanged: {
        if (upAndReady && !begun) {
            begun = true;
            startLater.start();
        }
    }

    function begin() {
        restoring = true;
        autostart.running = true;
        entriesWait.start();
        giveUp.start();
    }

    function finish() {
        if (!restoring)
            return;
        restoring = false;
        giveUp.stop();
        console.log("restore: done");
    }

    Timer {
        id: entriesWait
        interval: 10000
        onTriggered: root.entriesLate = true
    }
    // mango never answered (or the list never came): don't hold the list back.
    Timer {
        id: giveUp
        interval: 30000
        onTriggered: {
            if (!root.begun) {
                console.warn("restore: the desktop didn't come up in time; not reopening");
                root.finish();
            }
        }
    }
    Timer {
        id: startLater
        interval: 2500
        onTriggered: root.reopen()
    }

    // What to start, in the order they were opened.
    function plan() {
        const skip = Style.restoreAppsExclude;
        const open = new Set(MangoClients.clients.map(c => c.appId));
        const entries = new Set();
        const out = [];
        for (const a of apps) {
            const entry = (a.entry ? DesktopEntries.byId(a.entry) : null) ?? entryFor(a.appId);
            let why = "";
            if (skip.includes(a.appId) || (entry && skip.includes(entry.id)))
                why = "in Never reopen";
            else if (!entry)
                why = "no desktop entry";
            else if (startsItself(a.appId, entry))
                why = "starts by itself";
            else if (open.has(a.appId))
                why = "already open";
            else if (entries.has(entry.id))
                why = "started for another window already";
            if (why !== "") {
                console.log("restore: not reopening", a.appId, "(" + why + ")");
                continue;
            }
            entries.add(entry.id);
            out.push({ appId: a.appId, entry: entry, tag: a.tag });
        }
        return out;
    }

    function reopen() {
        queue = plan();
        opened = [];
        if (queue.length === 0) {
            finish();
            return;
        }
        console.log("restore: reopening", queue.map(a => a.appId).join(", "));
        launchNext();
    }

    function launchNext() {
        const a = queue.shift();
        if (!a || !enabled) {
            queue = [];
            finish();
            return;
        }
        // Windows of it already there aren't the new one.
        waiting = waiting.concat([{ appId: a.appId, tag: a.tag, since: Date.now(), placedId: -1, shown: false,
                                    before: MangoClients.clients.filter(c => c.appId === a.appId).map(c => c.id) }]);
        opened.push(a.entry.name || a.appId);
        launch(a.entry);
        if (queue.length > 0) {
            stagger.restart();
        } else {
            notify(opened);
            place();
        }
    }

    Timer {
        id: stagger
        interval: root.staggerMs
        onTriggered: root.launchNext()
    }

    // The same way the dock starts an app (DockState.launch).
    function launch(entry) {
        console.log("restore: open", entry.id);
        if (dryRun)
            console.log("restore (dry run): launch", entry.id);
        else if (entry.runInTerminal)
            Quickshell.execDetached(["xdg-terminal-exec"].concat(entry.command));
        else
            entry.execute();
    }

    function notify(names) {
        const n = names.length;
        const cmd = ["notify-send", "-a", "Apps", "-i", "view-restore", "--",
                     "Reopened " + n + (n === 1 ? " app" : " apps"),
                     names.join(", ").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")];
        if (dryRun)
            console.log("restore (dry run):", JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    // Each started app's first new window goes to its workspace. If that
    // window goes away again (a splash screen), the next new one does.
    function place() {
        const list = MangoClients.clients;
        const now = Date.now();
        for (const a of waiting) {
            if (a.placedId >= 0 && list.some(c => c.id === a.placedId)) {
                // Its other windows (a browser's second one) stay where they open.
                for (const c of list)
                    if (c.appId === a.appId && !a.before.includes(c.id))
                        a.before.push(c.id);
                continue;
            }
            if (a.placedId >= 0) {
                a.before.push(a.placedId);
                a.placedId = -1;
            }
            const c = list.find(c => c.appId === a.appId && !a.before.includes(c.id));
            if (!c)
                continue;
            a.placedId = c.id;
            a.shown = true;
            moveTo(c, a);
        }
        waiting = waiting.filter(a => now - a.since < root.placeMs);
        if (restoring && begun && queue.length === 0 && waiting.every(a => a.shown))
            finish();
    }

    // mango's tagsilent: the window goes, you stay. Only a whole-number id
    // from mango's current list (mango uses the focused window for a wrong one).
    function moveTo(c, a) {
        if (!Number.isInteger(c.id) || c.id < 0 || !Number.isInteger(a.tag) || a.tag < 1 || c.tag === a.tag)
            return;
        const cmd = ["mmsg", "dispatch", "tagsilent," + a.tag, "client," + c.id];
        console.log("restore: move", a.appId, "(" + c.id + ") to workspace", a.tag);
        if (dryRun)
            console.log("restore (dry run):", JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    // Until every started app's time is up (no window changes meanwhile).
    Timer {
        interval: 2000
        repeat: true
        running: root.waiting.length > 0
        onTriggered: root.place()
    }

    // ---- Apps that start by themselves -------------------------------------------------
    // mango's exec_once (and exec) lines, and each ~/.config/autostart entry
    // that isn't hidden: its name, then its Exec line. Each line gives the
    // programs it starts, or only the app id it names (foot --app-id=dropdown
    // is a dropdown, not every foot window).
    readonly property string autostartScript: [
        'for f in "$1"/*.conf; do [ -f "$f" ] && sed -n "s/^[[:space:]]*exec\\(_once\\)\\{0,1\\}[[:space:]]*=[[:space:]]*//p" "$f"; done',
        'for f in "$2"/*.desktop; do',
        '    [ -f "$f" ] || continue',
        '    grep -qi "^Hidden[[:space:]]*=[[:space:]]*true" "$f" && continue',
        '    n=${f##*/}; echo "${n%.desktop}"',
        '    sed -n "s/^Exec[[:space:]]*=[[:space:]]*//p" "$f" | head -n 1',
        'done'
    ].join("\n")

    Process {
        id: autostart
        command: ["sh", "-c", root.autostartScript, "sh", root.configDir + "/mango", root.configDir + "/autostart"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = new Set();
                for (const line of text.split("\n")) {
                    const id = root.appIdIn(line);
                    for (const name of (id !== "" ? ["id:" + id] : root.programs(line)))
                        names.add(name);
                }
                root.autostarted = [...names];
                root.autostartRead = true;
            }
        }
        onExited: root.autostartRead = true
    }

    // Wrappers in front of the program that matters.
    readonly property var wrappers: ["env", "sh", "bash", "dash", "zsh", "fish", "exec", "setsid", "nohup", "sleep", "timeout",
        "nice", "ionice", "flatpak", "run", "uwsm", "uwsm-app", "app2unit", "systemd-run", "dbus-run-session", "gtk-launch",
        "dex", "python", "python3", "node"]

    // The programs a command line starts, lower case, without folders:
    //   env A=1 qs -c mine               → qs
    //   flatpak run com.spotify.Client   → com.spotify.client
    //   sh -c "sleep 6 && conky -c x"    → conky
    function programs(line) {
        const words = line.replace(/['"]/g, " ").replace(/&&|\|\||[;&|]/g, " ; ").split(/\s+/).filter(w => w !== "");
        const out = [];
        let starts = true;
        for (const w of words) {
            if (w === ";") {
                starts = true;
                continue;
            }
            if (!starts || /^[A-Za-z_][A-Za-z0-9_]*=/.test(w) || w.startsWith("-") || /^[\d.]+$/.test(w))
                continue;
            const name = w.split("/").pop().toLowerCase();
            if (root.wrappers.includes(name))
                continue;
            out.push(name);
            starts = false;
        }
        return out;
    }

    // "foot --app-id=dropdown", "app --class dropdown" → "dropdown"
    function appIdIn(line) {
        return (line.match(/--(?:app-id|class)[=\s]+['"]?([^\s'"]+)/)?.[1] ?? "").toLowerCase();
    }

    function startsItself(appId, entry) {
        const id = appId.toLowerCase();
        if (autostarted.includes("id:" + id))
            return true;
        const names = [id, entry.id.toLowerCase()].concat(programs((entry.command ?? []).join(" ")));
        return names.some(n => autostarted.includes(n));
    }

    // ---- Start -------------------------------------------------------------------------
    readonly property bool watching: enabled
    onWatchingChanged: MangoClients.keep(watching ? 1 : -1)

    Component.onCompleted: {
        if (watching)
            MangoClients.keep(1);
        const dir = statePath.substring(0, statePath.lastIndexOf("/"));
        if (dir !== "")
            Quickshell.execDetached(["mkdir", "-p", dir]);
        if (mangoPid === "" || runDir === "")
            verdict = "none";
        else
            check.running = true;
    }
}
