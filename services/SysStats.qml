pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// CPU, memory, temperature, network speed and disk use for the bar's stat
// items. Nothing is read until an item on the bar asks for it (hold), and
// then only what is shown: every Style.statsInterval ms, the disk every 30 s.
// All from /proc and /sys (tiny reads), the disk from `df`.
//
// While the System popup is open (SysmonState.open, click a stat) there's
// more: everything every Style.sysmonInterval ms, the clock speed and the
// busiest apps (`top`). It all stops again when the popup closes.
// Whenever the CPU is read, its last 40 values are kept for the popup's
// graph, so the graph is never empty when it opens.
Singleton {
    id: root

    // ---- Who wants what ------------------------------------------------------------
    // { cpu: 1, memory: 2, ... }: shown items per kind (one per screen).
    property var users: ({})

    function hold(kind) {
        const next = Object.assign({}, users);
        next[kind] = (next[kind] ?? 0) + 1;
        users = next;
    }
    function release(kind) {
        const next = Object.assign({}, users);
        next[kind] = Math.max(0, (next[kind] ?? 0) - 1);
        users = next;
    }

    // The System popup wants everything (and more, see "The popup" below).
    readonly property bool detailOn: SysmonState.open

    readonly property bool cpuOn: (users.cpu ?? 0) > 0 || detailOn
    readonly property bool memoryOn: (users.memory ?? 0) > 0 || detailOn
    readonly property bool tempOn: (users.temperature ?? 0) > 0 || detailOn
    readonly property bool netOn: (users.netspeed ?? 0) > 0 || detailOn
    readonly property bool diskOn: (users.disk ?? 0) > 0 || detailOn

    // ---- The numbers -------------------------------------------------------------------
    property real cpu: 0                // 0-1, all cores together
    property bool cpuReady: false       // needs two reads
    property string load: ""            // 1-minute load average
    property real memUsed: 0            // bytes
    property real memTotal: 0
    readonly property real memory: memTotal > 0 ? memUsed / memTotal : 0   // 0-1
    property real swapUsed: 0
    property real temp: 0               // °C
    property string tempSource: ""      // k10temp, coretemp, acpitz...
    property real down: 0               // bytes per second
    property real up: 0
    property bool netReady: false
    property real diskUsed: 0           // bytes, of /
    property real diskTotal: 0
    readonly property real disk: diskTotal > 0 ? diskUsed / diskTotal : 0  // 0-1

    // ---- More, for the popup (only while it's open) ---------------------------------
    property real mhz: 0                // average clock of all cores
    property real swapTotal: 0
    property int coreCount: 0           // threads (top's %CPU is of one)
    // The busiest apps (Style.sysmonProcessCount), by procSort, each
    // program's processes added up: [{ pids, user ("*" = several), name,
    // count, cpu (% of the whole CPU), mem (bytes) }]
    property var processes: []
    property bool processesReady: false
    // "cpu" or "memory"; starts as Style.sysmonSortBy each time it opens.
    property string procSort: Style.sysmonSortBy

    // The CPU's last 40 values (0-1), oldest first, kept whenever the CPU
    // is read (a stat on the bar, or the popup). It starts full, with the
    // first value (or the last one known, until a fresh one comes), so the
    // popup's graph never opens empty.
    readonly property int historyLength: 40
    property var cpuHistory: []
    property bool cpuHistoryGuessed: false

    function addCpu(value) {
        if (cpuHistory.length === 0 || cpuHistoryGuessed) {
            cpuHistory = Array(historyLength).fill(value);
            cpuHistoryGuessed = false;
        } else {
            const out = cpuHistory.slice(cpuHistory.length >= historyLength ? 1 : 0);
            out.push(value);
            cpuHistory = out;
        }
    }

    onDetailOnChanged: {
        if (detailOn) {
            forget.stop();
            procSort = Style.sysmonSortBy;
            cpuInfo.reload();
            if (cpuHistory.length === 0) {
                cpuHistory = Array(historyLength).fill(cpu);
                cpuHistoryGuessed = true;
            }
        } else {
            forget.restart();
        }
    }
    // Closed: let go of the apps once the popup has shrunk away (not while
    // it still shows).
    Timer {
        id: forget
        interval: Motion.morphOut + 300
        onTriggered: {
            root.processes = [];
            root.processesReady = false;
        }
    }

    // "1.2 MB/s", "640 KB/s": for the popup.
    function speed(bps) {
        if (bps >= 1e9)
            return (bps / 1e9).toFixed(1) + " GB/s";
        if (bps >= 1e6)
            return (bps / 1e6).toFixed(1) + " MB/s";
        if (bps >= 1e3)
            return Math.round(bps / 1e3) + " KB/s";
        return Math.round(bps) + " B/s";
    }
    // "6.1 GB", "512 MB" (in 1024s, like btop and df -h)
    readonly property real gb: 1024 * 1024 * 1024
    function size(b) {
        if (b >= gb * 1024)
            return (b / gb / 1024).toFixed(1) + " TB";
        if (b >= gb)
            return (b / gb).toFixed(1) + " GB";
        return Math.round(b / 1024 / 1024) + " MB";
    }
    // Shorter, for the popup's app list: "987M", "1.2G"
    function shortSize(b) {
        if (b >= gb)
            return (b / gb).toFixed(1) + "G";
        return Math.round(b / 1024 / 1024) + "M";
    }
    // Short, for the bar: "0K", "512K", "1.2M"
    function rate(bps) {
        if (bps >= 1e9)
            return (bps / 1e9).toFixed(1) + "G";
        if (bps >= 1e6)
            return (bps / 1e6).toFixed(bps >= 1e7 ? 0 : 1) + "M";
        return Math.round(bps / 1e3) + "K";
    }

    // ---- Click: a task manager -----------------------------------------------------
    // Style.statsClickCommand, or the first of btop / htop (in the terminal),
    // Resources, GNOME System Monitor that is installed.
    property string monitorCommand: ""
    Process {
        running: true
        command: ["sh", "-c", 't="${TERMINAL:-foot}"; '
            + 'if command -v btop >/dev/null; then echo "$t -e btop"; '
            + 'elif command -v htop >/dev/null; then echo "$t -e htop"; '
            + 'elif command -v resources >/dev/null; then echo resources; '
            + 'elif command -v gnome-system-monitor >/dev/null; then echo gnome-system-monitor; '
            + 'elif command -v missioncenter >/dev/null; then echo missioncenter; fi']
        stdout: StdioCollector {
            onStreamFinished: root.monitorCommand = text.trim()
        }
    }
    function openMonitor() {
        const cmd = Style.statsClickCommand !== "" ? Style.statsClickCommand : monitorCommand;
        if (cmd !== "")
            Quickshell.execDetached(["sh", "-c", cmd]);
    }

    // ---- Reading -----------------------------------------------------------------------
    // A file is only open while its kind is shown (an empty path reads
    // nothing); it's read once when it opens, then on every tick.
    Timer {
        running: root.cpuOn || root.memoryOn || root.tempOn || root.netOn
        interval: root.detailOn ? Math.max(250, Style.sysmonInterval) : Math.max(500, Style.statsInterval)
        repeat: true
        triggeredOnStart: true
        onTriggered: root.readAll()
    }
    function readAll() {
        if (cpuOn) {
            statFile.reload();
            loadFile.reload();
        }
        if (memoryOn)
            memFile.reload();
        if (tempOn && tempFile.path !== "")
            tempFile.reload();
        if (netOn)
            netFile.reload();
        if (detailOn)
            cpuInfo.reload();
    }
    // The first CPU and network numbers need a second read: soon after.
    Timer {
        id: second
        interval: 400
        onTriggered: {
            if (root.cpuOn)
                statFile.reload();
            if (root.netOn)
                netFile.reload();
        }
    }
    onCpuOnChanged: if (!cpuOn) { lastCpu = null; cpuReady = false; cpuHistory = []; }
    onNetOnChanged: if (!netOn) { lastNet = null; netReady = false; }

    // CPU: busy share of the time between two reads of the first line
    // (user nice system idle iowait irq softirq steal).
    property var lastCpu: null
    FileView {
        id: statFile
        path: root.cpuOn ? "/proc/stat" : ""
        printErrors: false
        onLoaded: {
            const lines = text().split("\n");
            if (root.coreCount === 0)
                root.coreCount = lines.filter(l => /^cpu\d/.test(l)).length;
            const f = lines[0].trim().split(/\s+/).slice(1, 9).map(Number);
            const idle = f[3] + f[4];
            const total = f.reduce((a, b) => a + b, 0);
            const prev = root.lastCpu;
            // Too soon after the last read (opening + first tick): wait.
            if (prev !== null && total - prev.total < 50)
                return;
            root.lastCpu = { idle: idle, total: total };
            if (prev === null) {
                second.restart();
                return;
            }
            if (total > prev.total) {
                root.cpu = Math.max(0, Math.min(1, 1 - (idle - prev.idle) / (total - prev.total)));
                root.cpuReady = true;
                root.addCpu(root.cpu);
            }
        }
    }
    FileView {
        id: loadFile
        path: root.cpuOn ? "/proc/loadavg" : ""
        printErrors: false
        onLoaded: root.load = text().split(" ")[0] ?? ""
    }
    // Clock speed (popup only).
    FileView {
        id: cpuInfo
        path: root.detailOn ? "/proc/cpuinfo" : ""
        printErrors: false
        onLoaded: {
            const t = text();
            const mhz = [];
            const re = /^cpu MHz\s*:\s*([\d.]+)/gm;     // (no matchAll in QML)
            for (let m = re.exec(t); m !== null; m = re.exec(t))
                mhz.push(Number(m[1]));
            if (mhz.length > 0)
                root.mhz = mhz.reduce((a, b) => a + b, 0) / mhz.length;
        }
    }

    // Memory: what apps can't get back right away (MemTotal - MemAvailable).
    FileView {
        id: memFile
        path: root.memoryOn ? "/proc/meminfo" : ""
        printErrors: false
        onLoaded: {
            const kb = {};
            for (const line of text().split("\n")) {
                const m = line.match(/^(\w+):\s+(\d+)/);
                if (m)
                    kb[m[1]] = Number(m[2]);
            }
            root.memTotal = (kb.MemTotal ?? 0) * 1024;
            root.memUsed = ((kb.MemTotal ?? 0) - (kb.MemAvailable ?? 0)) * 1024;
            root.swapUsed = ((kb.SwapTotal ?? 0) - (kb.SwapFree ?? 0)) * 1024;
            root.swapTotal = (kb.SwapTotal ?? 0) * 1024;
        }
    }

    // Temperature: the CPU's own sensor (k10temp / zenpower on AMD, coretemp
    // on Intel), else a thermal zone (this HP has only acpitz). Found once.
    Process {
        id: findTemp
        running: root.tempOn && tempFile.path === ""
        command: ["sh", "-c", 'for h in /sys/class/hwmon/hwmon*; do n=$(cat "$h/name" 2>/dev/null); '
            + 'case "$n" in k10temp|zenpower|coretemp|cpu_thermal) [ -e "$h/temp1_input" ] && { echo "$h/temp1_input $n"; exit; };; esac; done; '
            + 'for z in /sys/class/thermal/thermal_zone*; do [ "$(cat "$z/type" 2>/dev/null)" = x86_pkg_temp ] && { echo "$z/temp x86_pkg_temp"; exit; }; done; '
            + 'z=/sys/class/thermal/thermal_zone0; [ -e "$z/temp" ] && echo "$z/temp $(cat "$z/type")"']
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(" ");
                if (parts[0] === "")
                    return;
                root.tempSource = parts[1] ?? "";
                tempFile.path = parts[0];
            }
        }
    }
    FileView {
        id: tempFile
        path: ""
        printErrors: false
        onLoaded: {
            const milli = parseInt(text());
            if (!isNaN(milli))
                root.temp = milli / 1000;
        }
    }

    // Network: bytes in and out of the real interfaces (not lo, Docker,
    // Tailscale, VPN tunnels or VM bridges) between two reads.
    property var lastNet: null
    readonly property var virtualNet: /^(lo|docker|veth|br-|virbr|vnet|tailscale|tun|tap|wg|zt|vmnet|vboxnet)/
    FileView {
        id: netFile
        path: root.netOn ? "/proc/net/dev" : ""
        printErrors: false
        onLoaded: {
            let rx = 0, tx = 0;
            for (const line of text().split("\n").slice(2)) {
                const m = line.trim().match(/^([^:]+):\s*(.*)$/);
                if (!m || root.virtualNet.test(m[1]))
                    continue;
                const f = m[2].split(/\s+/).map(Number);
                rx += f[0];
                tx += f[8];
            }
            const now = Date.now();
            const prev = root.lastNet;
            if (prev !== null && now - prev.at < 200)
                return;
            root.lastNet = { rx: rx, tx: tx, at: now };
            if (prev === null) {
                second.restart();
                return;
            }
            const dt = (now - prev.at) / 1000;
            root.down = Math.max(0, (rx - prev.rx) / dt);
            root.up = Math.max(0, (tx - prev.tx) / dt);
            root.netReady = true;
        }
    }

    // Disk: how full / is (like df's Use%).
    Timer {
        running: root.diskOn
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: df.running = true
    }
    Process {
        id: df
        command: ["df", "-P", "-B1", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\n").pop().split(/\s+/);
                const used = Number(f[2]), avail = Number(f[3]);
                if (!isNaN(used) && !isNaN(avail) && used + avail > 0) {
                    root.diskUsed = used;
                    root.diskTotal = used + avail;
                }
            }
        }
    }

    // ---- The popup: the busiest apps ------------------------------------------------------
    // One `top` that keeps running while the popup is open (it measures the
    // time between its own frames, unlike ps' lifetime averages). awk adds
    // up each frame by program, so an app made of many processes (browsers,
    // Electron apps) is one row with its real total, and keeps the busiest
    // few. A quick top (0.4 s) goes first, so the list is there while the
    // popup is still opening; then the steady one. Each top's first frame
    // is since boot, so it's skipped (SKIP marks where the second starts).
    // top's %CPU is of one core: divided by the cores here, so it adds up
    // with the CPU number above it.
    // awk *is* the process (exec, top feeding it from <(...)): stopping it
    // ends awk right away, and top on its next frame (nothing reads it).
    readonly property int procDelay: Math.max(1, Math.round(Style.sysmonInterval * 2 / 1000))
    readonly property string procAwk: `
        function emit(   i, k, best, bv, v) {
            print "T\t" tasks
            for (i = 0; i < n; i++) {
                best = ""; bv = -1
                for (k in cnt) {
                    v = mode == "memory" ? res[k] : cpu[k] * 1e9 + res[k]
                    if (v > bv) { bv = v; best = k }
                }
                if (best == "") break
                print "P\t" pids[best] "\t" usr[best] "\t" res[best] "\t" cpu[best] "\t" cnt[best] "\t" best
                delete cnt[best]
            }
            print "E"; fflush()
        }
        /^SKIP$/ { skip = 1; next }
        /^top - / {
            f++; h = 0
            ignore = (f == 1 || skip); skip = 0
            split("", cpu); split("", res); split("", cnt); split("", pids); split("", usr); next
        }
        /^Tasks:/ { tasks = $2; next }
        /^ *PID / { h = 1; next }
        h && /^[ \t]*$/ { if (!ignore) emit(); h = 0; next }
        # Kernel threads use no memory of their own: not apps, left out.
        # Nor is this very top.
        h && $6 == 0 { next }
        h && $12 == "top" && $13 == "-b" && $14 == "-c" { next }
        h {
            # The program's file name (top -c: the command line), so helper
            # processes that rename themselves still count for their app;
            # kernel threads keep their [name].
            name = $12
            if (name ~ /^\\[/) {
                for (i = 13; i <= NF; i++) name = name " " $i
                gsub(/^\\[|\\]$/, "", name)
            } else
                sub(/^.*\\//, "", name)
            cpu[name] += $9; res[name] += $6; cnt[name]++
            pids[name] = pids[name] (pids[name] == "" ? "" : ",") $1
            if (!(name in usr)) usr[name] = $2; else if (usr[name] != $2) usr[name] = "*"
        }`
    readonly property var procCommand: ["bash", "-c",
        "exec awk -v n=" + Math.max(1, Math.round(Style.sysmonProcessCount) || 5) + " -v mode=" + (procSort === "memory" ? "memory" : "cpu") + " \"$0\" "
        + "< <(top -b -c -n 2 -d 0.4 -w 512 -e k; echo SKIP; exec top -b -c -d " + procDelay + " -w 512 -e k)", procAwk]
    // Another sort (or count): a new top. Off for a moment, then on again
    // (`running` stays a binding, so closing the popup always stops it).
    property bool procRestarting: false
    onProcCommandChanged: if (procs.running) { procRestarting = true; procRestart.restart(); }
    Timer {
        id: procRestart
        interval: 50
        onTriggered: root.procRestarting = false
    }

    property var procRows: []
    Process {
        id: procs
        running: root.detailOn && !root.procRestarting
        command: root.procCommand
        environment: ({ LC_ALL: "C" })
        stdout: SplitParser {
            onRead: line => {
                if (!root.detailOn)
                    return;     // a last frame after closing
                const f = line.split("\t");
                if (f[0] === "T") {
                    root.procRows = [];
                } else if (f[0] === "P" && f.length >= 7) {
                    root.procRows.push({
                        pids: f[1].split(",").map(Number),
                        user: f[2],                     // "*" = several users
                        mem: (Number(f[3]) || 0) * 1024,
                        cpu: (Number(f[4]) || 0) / Math.max(1, root.coreCount),
                        count: Number(f[5]) || 1,
                        name: f.slice(6).join("\t")
                    });
                } else if (f[0] === "E") {
                    root.processes = root.procRows;
                    root.procRows = [];
                    root.processesReady = true;
                }
            }
        }
    }

    // End an app: SIGTERM (like closing it) to each of its processes.
    // MINE_SYSMON_DRYRUN=1 (tests) only prints it.
    readonly property bool dryRun: Quickshell.env("MINE_SYSMON_DRYRUN") === "1"
    function endProcesses(pids) {
        const list = (pids ?? []).filter(p => p > 1).map(String);
        if (list.length === 0)
            return;
        if (dryRun)
            console.log("sysmon (dry run): kill -TERM", list.join(" "));
        else
            Quickshell.execDetached(["kill", "-TERM"].concat(list));
    }
}
