pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The System popup (click a CPU / memory / temperature / network / disk
// item on the bar): whether it's open and which island it grows out of
// (the one that holds the clicked item). It shares that island with what
// else grows out of it (the control center on the right; the launcher, the
// clipboard and the calendar in the middle), so opening one closes the
// other. While it's open SysStats reads much more (see there), and the
// ports your programs listen on are read here (dev servers: open, copy the
// address, stop). It never comes back open after a reload or restart; its
// window only exists while open (plus the shrink-back).
Singleton {
    id: root

    property bool open: false
    property bool mapped: false
    property string island: "right"     // left | center | right

    readonly property var statKinds: ["cpu", "memory", "temperature", "netspeed", "disk"]

    // The island a bar item is on ("" if it's not on the bar).
    function islandOf(name) {
        if (Style.barLeft.includes(name))
            return "left";
        if (Style.barCenter.includes(name))
            return "center";
        if (Style.barRight.includes(name))
            return "right";
        return "";
    }
    // Without a clicked item (IPC, keys): the island with the first stat,
    // else the right one.
    function defaultIsland() {
        for (const k of statKinds) {
            const where = islandOf(k);
            if (where !== "")
                return where;
        }
        return "right";
    }

    function toggle(from) {
        if (open)
            close();
        else
            show(from);
    }

    function show(from) {
        const where = from || defaultIsland();
        // Still shrinking back into another island: start over from the new one.
        if (mapped && where !== island)
            mapped = false;
        island = where;
        if (island === "right")
            ControlState.close();
        if (island === "center") {
            LauncherState.close();
            ClipboardState.close();
            CalendarState.close();
            NowPlayingState.close();
            Notifs.putAwayPopups();     // the popup owns the middle island now
        }
        unmap.stop();
        // open first: the window is created the moment `mapped` turns on,
        // and must see the panel open already.
        open = true;
        mapped = true;
    }

    function close() {
        if (!open)
            return;
        open = false;
        unmap.restart();
    }

    // Something else growing out of our island: make room.
    Connections {
        target: ControlState
        function onOpenChanged() {
            if (ControlState.open && root.island === "right")
                root.close();
        }
    }
    Connections {
        target: LauncherState
        function onOpenChanged() {
            if (LauncherState.open && root.island === "center")
                root.close();
        }
    }
    Connections {
        target: ClipboardState
        function onOpenChanged() {
            if (ClipboardState.open && root.island === "center")
                root.close();
        }
    }
    Connections {
        target: CalendarState
        function onOpenChanged() {
            if (CalendarState.open && root.island === "center")
                root.close();
        }
    }
    Connections {
        target: NowPlayingState
        function onOpenChanged() {
            if (NowPlayingState.open && root.island === "center")
                root.close();
        }
    }

    // The window goes once the popup reports it's back in the island
    // (settled). This is only a safety net in case it never does.
    Timer {
        id: unmap
        interval: Motion.morphOut + 1500
        onTriggered: root.settled()
    }

    function settled() {
        if (open || !mapped)
            return;
        unmap.stop();
        // The window goes a moment later, not in the very frame the island
        // starts fading back in: letting go of a window stalls the shell
        // for ~50 ms, which made that fade stutter.
        release.restart();
    }

    Timer {
        id: release
        interval: Motion.contentIn + 80
        onTriggered: if (!root.open) root.mapped = false
    }

    // ---- What's listening (dev servers) ----------------------------------------------
    // TCP ports your own programs listen on, from `ss -ltnpH`: read when the
    // popup opens, then every 2 s or so while it's open, never otherwise.
    // ss only names the programs you may look into (your own), so a port
    // without a name (system services) isn't listed.
    //   [{ port, pids, name, scope: "all" | "local" | "other", address, url }]
    // scope: all = every network interface (0.0.0.0, [::], *): other
    // computers can reach it unless the firewall says no; local = this
    // computer only (127.x, [::1]); other = one address (a VPN's, say).
    property var listening: []
    property bool listeningReady: false

    // MINE_SYSMON_DRYRUN=1: nothing is opened, copied or stopped, only
    // printed; =links: only opening and copying are printed (tests).
    // MINE_SYSMON_SS=<file>: read that file instead of running ss (tests).
    readonly property string dryRun: Quickshell.env("MINE_SYSMON_DRYRUN") ?? ""
    readonly property string ssFile: Quickshell.env("MINE_SYSMON_SS") ?? ""

    // One line: State Recv-Q Send-Q Local:Port Peer:Port [users:((...))]
    // e.g. LISTEN 0 511 0.0.0.0:20128 0.0.0.0:* users:(("next-server (v1",pid=324564,fd=21))
    // A program's name can hold spaces, quotes and brackets; it ends at the
    // `",pid=N,fd=N)` after it. The same program on the same port over IPv4
    // and IPv6 is one row (the wider reach wins).
    function parseListening(text) {
        const out = [];
        const seen = {};
        const reach = { local: 0, other: 1, all: 2 };
        for (const line of String(text ?? "").split("\n")) {
            const m = line.match(/^\s*(\S+)\s+\d+\s+\d+\s+(\S+)\s+\S+\s*(.*)$/);
            if (!m || m[1] !== "LISTEN")
                continue;
            const local = m[2];
            const cut = local.lastIndexOf(":");
            const port = Number(local.slice(cut + 1));
            if (cut < 0 || !Number.isInteger(port) || port < 1 || port > 65535)
                continue;
            // 127.0.0.53%lo, [fd7a::1]%tailscale0, [::], *
            let address = local.slice(0, cut);
            const pct = address.lastIndexOf("%");
            if (pct >= 0)
                address = address.slice(0, pct);
            address = address.replace(/^\[/, "").replace(/\]$/, "");
            const scope = address === "0.0.0.0" || address === "::" || address === "*" ? "all"
                        : /^127\./.test(address) || address === "::1" || /^::ffff:127\./i.test(address) ? "local"
                        : "other";

            const procs = [];
            const who = /\("(.*?)",pid=(\d+),fd=\d+\)/g;
            let p;
            while ((p = who.exec(m[3])) !== null)
                procs.push({ name: p[1], pid: Number(p[2]) });
            if (procs.length === 0)
                continue;
            const pids = procs.map(x => x.pid).filter((pid, i, all) => all.indexOf(pid) === i).sort((x, y) => x - y);

            const key = port + ":" + pids.join(",");
            const have = seen[key];
            if (have) {
                if (reach[scope] > reach[have.scope]) {
                    have.scope = scope;
                    have.address = address;
                    have.url = urlFor(scope, address, port);
                }
                continue;
            }
            const row = { port: port, pids: pids, name: procs[0].name, scope: scope, address: address,
                          url: urlFor(scope, address, port) };
            seen[key] = row;
            out.push(row);
        }
        // Open to other computers first, then by port.
        out.sort((x, y) => (x.scope === "all" ? 0 : 1) - (y.scope === "all" ? 0 : 1) || x.port - y.port);
        return out;
    }

    // localhost reaches what listens everywhere or on 127.0.0.1 / ::1;
    // a port on one address only, through that address.
    function urlFor(scope, address, port) {
        const plain = scope === "all" || address === "127.0.0.1" || address === "::1"
                      || /^::ffff:127\.0\.0\.1$/i.test(address);
        const host = plain ? "localhost" : address.includes(":") ? "[" + address + "]" : address;
        return "http://" + host + ":" + port + "/";
    }

    function readListening() {
        if (!ss.running)
            ss.running = true;
    }

    Process {
        id: ss
        command: root.ssFile !== "" ? ["cat", "--", root.ssFile] : ["ss", "-ltnpH"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.open)
                    return;     // closed while it ran
                root.listening = root.parseListening(text);
                root.listeningReady = true;
            }
        }
    }
    Timer {
        running: root.open
        triggeredOnStart: true
        repeat: true
        interval: Math.max(2000, Style.sysmonInterval * 2)
        onTriggered: root.readListening()
    }
    // Closed: forget them once the popup has shrunk away.
    onOpenChanged: open ? forgetListening.stop() : forgetListening.restart()
    Timer {
        id: forgetListening
        interval: Motion.morphOut + 300
        onTriggered: {
            root.listening = [];
            root.listeningReady = false;
        }
    }

    function openListener(row) {
        links(["xdg-open", row.url]);
    }
    function copyListener(row) {
        links(["wl-copy", "--", row.url]);
    }
    function links(cmd) {
        if (dryRun !== "")
            console.log("sysmon (dry run):", JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    // Stop it: SIGTERM (like Ctrl+C in its terminal) to its processes. Right
    // before, each is checked again: a number above 1, yours (/proc/<pid>
    // owned by you), and still listening on that port (ss), so a pid that
    // went away and came back as something else is left alone. The port
    // and pids go in as separate arguments, never as part of the script.
    readonly property string stopScript: `port=$1; shift
        case $port in ""|*[!0-9]*) exit 1 ;; esac
        me=$(id -u)
        now=$(ss -ltnpH "sport = :$port" 2>/dev/null)
        for p; do
            case $p in ""|*[!0-9]*) continue ;; esac
            [ "$p" -gt 1 ] || continue
            [ "$(stat -c %u "/proc/$p" 2>/dev/null)" = "$me" ] || continue
            case $now in *"pid=$p,"*) ;; *) continue ;; esac
            kill -TERM "$p" && echo "stopped $p"
        done`

    function stopListener(row) {
        const pids = (row?.pids ?? []).filter(p => Number.isInteger(p) && p > 1).map(String);
        if (pids.length === 0 || !Number.isInteger(row.port))
            return;
        const cmd = ["sh", "-c", stopScript, "mine-stop", String(row.port)].concat(pids);
        if (dryRun === "1") {
            console.log("sysmon (dry run):", JSON.stringify(cmd.slice(3)));
            return;
        }
        Quickshell.execDetached(cmd);
        again.restart();
    }
    // Read again soon after a stop, so it goes from the list.
    Timer {
        id: again
        interval: 700
        onTriggered: if (root.open) root.readListening()
    }
}
