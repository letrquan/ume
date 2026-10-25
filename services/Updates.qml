pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.common

// Updates waiting, for the bar's "updates" item. Nothing is installed here:
//  - repos: `checkupdates` (pacman-contrib) syncs its OWN copy of the
//    package lists in /tmp/checkup-db-<uid> (no root, pacman's own lists are
//    never touched), then compares with what's installed;
//  - AUR: `paru -Qua` (asks aur.archlinux.org);
//  - Flatpak: `flatpak remote-ls --updates` (Style.updatesFlatpak).
//
// When: Style.updatesFirstDelay minutes after something starts using it (the
// bar item: use()), then every Style.updatesInterval hours, counted on the
// wall clock so a night asleep counts too; only while online (Wi-Fi or a cable
// connected; otherwise it waits for one). The last answer is saved
// (~/.local/state/mine-shell/updates.json), so after a restart the badge is
// back at once and the next check keeps its time.
//
// After you update elsewhere (a terminal, pamac, …): pacman writes to
// /var/log/pacman.log on every run. A FileView watches it (inotify only; the
// file is never read) and, 4 s after it goes quiet, one `pacman -Q <names>`
// (the local database, no network, a few ms) drops what is now installed at
// another version than the one we saw. Finding NEW updates is the next real
// check's job. While the updates panel installs (services/UpdateRun.qml)
// this waits: pacman.log changes all the time then, and the list must stay
// as it was until the install says it's done.
//
// Installing: the updates panel (Update: services/UpdateRun.qml), or the
// update command in a terminal (run(): the panel's "In terminal", or the
// click with Style.updatesClick "terminal"; buildAur(): the AUR group's
// "Build in terminal"). Either one tells the shell when it's done (IPC
// `updates done`), which checks again for real.
//
// Tests: MINE_UPDATES_DRYRUN=1 (commands are logged, not run; a launched
// update "finishes" 2 s later), MINE_UPDATES_FAKE=<json file> (what the
// commands print instead of running them: { repo, aur, flatpak, installed }
// as text, optional { repoCode, aurCode, flatpakCode } exit codes),
// MINE_UPDATES_STATE (where the answer is saved), MINE_UPDATES_LOG (the file
// watched instead of pacman.log).
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("MINE_UPDATES_DRYRUN") === "1"
    readonly property string fakePath: Quickshell.env("MINE_UPDATES_FAKE") ?? ""
    readonly property bool fake: fakePath !== ""
    readonly property string statePath: Quickshell.env("MINE_UPDATES_STATE")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/updates.json")
    readonly property string logPath: Quickshell.env("MINE_UPDATES_LOG") || "/var/log/pacman.log"

    // ---- What the bar shows ---------------------------------------------------------
    // Each a list of { name, from, to } (Flatpak: from is "", name is the
    // app or runtime id, `branch` too).
    property var repo: []
    property var aur: []
    property var flatpak: []
    readonly property int count: repo.length + aur.length + flatpak.length
    property double checkedAt: 0          // ms, 0 = never
    property bool checking: false
    property string failed: ""            // why the last check didn't work, "" = it did
    property bool updating: false         // the update command is open in a terminal

    // "78 repo · 2 AUR · 5 Flatpak" (only the kinds that have some).
    readonly property string summary: [
        repo.length > 0 ? repo.length + " repo" : "",
        aur.length > 0 ? aur.length + " AUR" : "",
        flatpak.length > 0 ? flatpak.length + " Flatpak" : ""
    ].filter(s => s !== "").join(" · ")

    // Packages worth a look before updating (Style.updatesHeadsUp, globs):
    // the shell leans on Quickshell's quirks, the kernel and firmware are
    // pinned on this laptop. Just names, it doesn't stop anything.
    readonly property var headsUpPatterns: Style.updatesHeadsUp.map(glob => new RegExp(
        "^" + glob.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".") + "$"))
    readonly property var headsUp: repo.concat(aur)
        .map(u => u.name)
        .filter(name => headsUpPatterns.some(re => re.test(name)))

    // ---- Who uses it ----------------------------------------------------------------
    property int users: 0
    property double usedSince: 0
    function use(on) {
        users = Math.max(0, users + (on ? 1 : -1));
        if (users > 0 && usedSince === 0) {
            usedSince = Date.now();
            schedule();
        }
    }
    readonly property bool active: users > 0 && loaded && Style.updatesInterval > 0

    readonly property bool online: Networking.devices.values.some(d =>
        (d.type === DeviceType.Wifi || d.type === DeviceType.Wired) && d.connected)

    // ---- When ------------------------------------------------------------------------
    property double due: 0
    property bool waitingOnline: false

    function schedule() {
        if (!active) {
            tick.stop();
            return;
        }
        const firstAt = usedSince + Style.updatesFirstDelay * 60000;
        due = checkedAt === 0 ? firstAt
            : Math.max(checkedAt + Style.updatesInterval * 3600000, firstAt);
        // The last try failed: not again before the retry time.
        if (failed !== "")
            due = Math.max(due, lastTry + Style.updatesRetry * 60000);
        armTick();
    }
    // The timer never waits more than 10 minutes in one go: Qt's timers don't
    // count time asleep, the wall clock (due) does.
    function armTick() {
        tick.interval = Math.max(1000, Math.min(due - Date.now(), 600000));
        tick.restart();
    }
    Timer {
        id: tick
        onTriggered: {
            if (!root.active)
                return;
            if (Date.now() < root.due) {
                root.armTick();
                return;
            }
            if (!root.online) {
                root.waitingOnline = true;     // onOnlineChanged takes it from here
                return;
            }
            root.check("timer");
        }
    }
    onOnlineChanged: {
        if (online && waitingOnline) {
            waitingOnline = false;
            due = Date.now() + 30000;          // let the connection settle
            armTick();
        }
    }
    onActiveChanged: schedule()
    Connections {
        target: Style
        function onUpdatesIntervalChanged() { root.schedule(); }
        function onUpdatesFirstDelayChanged() { root.schedule(); }
        function onUpdatesFlatpakChanged() {
            if (!Style.updatesFlatpak && root.flatpak.length > 0) {
                root.flatpak = [];
                root.save();
            }
        }
    }

    // ---- Checking -------------------------------------------------------------------
    property double lastTry: 0
    property int pending: 0
    // Fresh answers of the check in progress (null = that one failed: the
    // old list stays).
    property var gotRepo: null
    property var gotAur: null
    property var gotFlatpak: null
    property var fakeData: ({})

    // A real check (network). `why` only goes to the log.
    function check(why) {
        if (checking)
            return;
        checking = true;
        lastTry = Date.now();
        gotRepo = gotAur = gotFlatpak = null;
        const jobs = [repoJob, aurJob].concat(Style.updatesFlatpak ? [flatpakJob] : []);
        console.log("updates: checking (" + why + ")");
        if (fake) {
            fakeData = readFake();
            for (const job of jobs)
                fakeRun(job.kind);
            finish();
            return;
        }
        if (dryRun) {
            for (const job of jobs)
                console.log("updates (dry run):", JSON.stringify(job.command));
            checking = false;
            return;
        }
        pending = jobs.length;
        for (const job of jobs)
            job.running = true;
    }

    function jobDone() {
        pending--;
        if (pending <= 0)
            finish();
    }

    function finish() {
        checking = false;
        const okRepo = gotRepo !== null;
        if (okRepo)
            repo = gotRepo;
        if (gotAur !== null)
            aur = gotAur;
        if (!Style.updatesFlatpak)
            flatpak = [];
        else if (gotFlatpak !== null)
            flatpak = gotFlatpak;
        const broken = [okRepo ? "" : "repos", gotAur !== null ? "" : "AUR",
                        !Style.updatesFlatpak || gotFlatpak !== null ? "" : "Flatpak"].filter(s => s !== "");
        failed = broken.length === 0 ? "" : "Couldn't check " + broken.join(", ") + (online ? "" : " (offline)");
        // The repos are what counts: if they failed, try again sooner.
        if (okRepo)
            checkedAt = Date.now();
        console.log("updates:", count, "(" + (summary || "none") + ")" + (failed !== "" ? " — " + failed : ""));
        save();
        ArchNews.refresh();
        if (okRepo)
            schedule();
        else {
            due = Date.now() + Style.updatesRetry * 60000;
            armTick();
        }
    }

    // "name 1.0-1 -> 1.1-1" lines (checkupdates, paru -Qua; colours and
    // " [ignored]" taken off).
    function parseArrows(text) {
        const out = [];
        for (let line of (text ?? "").split("\n")) {
            line = line.replace(/\x1b\[[0-9;]*m/g, "").trim();
            if (line === "" || /\[ignored\]$/.test(line))
                continue;
            const m = /^(\S+)\s+(\S+)\s+->\s+(\S+)/.exec(line);
            if (m)
                out.push({ name: m[1], from: m[2], to: m[3] });
        }
        return out;
    }
    // flatpak remote-ls --updates --columns=application,branch,version
    function parseFlatpak(text) {
        const out = [];
        for (const line of (text ?? "").split("\n")) {
            const cols = line.split("\t").map(c => c.trim());
            if (cols[0] === "" || cols[0] === undefined)
                continue;
            out.push({ name: cols[0], branch: cols[1] ?? "", from: "", to: cols[2] ?? "" });
        }
        return out;
    }

    function readFake() {
        try {
            return JSON.parse(fakeFile.text() || "{}");
        } catch (e) {
            console.log("updates: bad MINE_UPDATES_FAKE file:", e);
            return {};
        }
    }
    FileView {
        id: fakeFile
        path: root.fakePath
        blockLoading: true
        printErrors: false
        // A test may change it between checks.
        watchChanges: true
        onFileChanged: reload()
    }

    // One answer in: the fresh list, or null when that one failed (its old
    // list stays).
    //  checkupdates: 0 = some, 2 = none, 1 = couldn't sync (offline, mirror down);
    //  paru -Qua: 0 = some, 1 with nothing on stderr = none, else an error
    //  ("error: …" when the AUR can't be reached);
    //  127 (from the sh wrapper) = not installed = none.
    function take(kind, code, out, err) {
        if (kind === "repo")
            gotRepo = code === 0 ? parseArrows(out) : code === 2 ? [] : null;
        else if (kind === "aur")
            gotAur = code === 0 ? parseArrows(out) : (code === 1 && err.trim() === "") || code === 127 ? [] : null;
        else
            gotFlatpak = code === 0 ? parseFlatpak(out) : code === 127 ? [] : null;
        if (code !== 0 && !(kind === "repo" && code === 2) && err.trim() !== "")
            console.log("updates:", kind, "said:", err.trim().split("\n").slice(-1)[0]);
    }
    function fakeRun(kind) {
        const out = fakeData[kind] ?? "";
        const code = fakeData[kind + "Code"]
            ?? (out.trim() !== "" ? 0 : kind === "repo" ? 2 : kind === "aur" ? 1 : 0);
        take(kind, code, out, fakeData[kind + "Err"] ?? "");
    }

    // A check command: its answer counts once it has exited AND both its
    // outputs were read (they can come in either order).
    component Job: Process {
        id: job
        property string kind
        property int code: -1
        property int parts: 0
        signal result(string kind, int code, string out, string err)
        function part() {
            if (++parts === 3)
                result(kind, code, outText.text, errText.text);
        }
        onRunningChanged: if (running) parts = 0
        stdout: StdioCollector {
            id: outText
            onStreamFinished: job.part()
        }
        stderr: StdioCollector {
            id: errText
            onStreamFinished: job.part()
        }
        onExited: c => {
            code = c;
            part();
        }
    }
    // (Through sh: a missing paru or flatpak is exit 127, not a failed start.)
    Job {
        id: repoJob
        kind: "repo"
        command: ["sh", "-c", "command -v checkupdates >/dev/null || exit 127; exec checkupdates --nocolor"]
        onResult: (kind, code, out, err) => { root.take(kind, code, out, err); root.jobDone(); }
    }
    Job {
        id: aurJob
        kind: "aur"
        command: ["sh", "-c", "command -v paru >/dev/null || exit 127; exec paru -Qua --color never"]
        onResult: (kind, code, out, err) => { root.take(kind, code, out, err); root.jobDone(); }
    }
    Job {
        id: flatpakJob
        kind: "flatpak"
        command: ["sh", "-c", "command -v flatpak >/dev/null || exit 127; exec flatpak remote-ls --updates --columns=application,branch,version"]
        onResult: (kind, code, out, err) => { root.take(kind, code, out, err); root.jobDone(); }
    }

    // ---- After pacman ran ------------------------------------------------------------
    FileView {
        path: root.users > 0 && root.loaded ? root.logPath : ""
        preload: false          // only watched, never read
        watchChanges: true
        printErrors: false
        onFileChanged: settle.restart()
    }
    Timer {
        id: settle
        interval: 4000
        onTriggered: root.recount()
    }

    // Drops what is now installed at another version (updated, or removed).
    // Not while the panel installs: its end checks again for real (done()).
    function recount() {
        const listed = repo.concat(aur);
        if (listed.length === 0 || checking || UpdateRun.busy)
            return;
        if (fake) {
            applyInstalled(fakeData.installed ?? readFake().installed ?? "");
            return;
        }
        if (dryRun) {
            console.log("updates (dry run): pacman -Q --", listed.length, "names");
            return;
        }
        if (installed.running)
            return;
        installed.command = ["pacman", "-Q", "--"].concat(listed.map(u => u.name));
        installed.running = true;
    }
    function applyInstalled(text) {
        const now = {};
        for (const line of (text ?? "").split("\n")) {
            const m = /^(\S+)\s+(\S+)/.exec(line.trim());
            if (m)
                now[m[1]] = m[2];
        }
        // Nothing at all: pacman didn't answer, not "all removed".
        if (Object.keys(now).length === 0)
            return;
        const keep = u => now[u.name] === u.from;
        const before = repo.length + aur.length;
        repo = repo.filter(keep);
        aur = aur.filter(keep);
        const gone = before - repo.length - aur.length;
        if (gone > 0) {
            console.log("updates: pacman ran,", gone, "fewer now:", count);
            save();
        }
    }
    Process {
        id: installed
        // (Exit 1 when a name is no longer installed: what it did print counts.)
        stdout: StdioCollector {
            onStreamFinished: root.applyInstalled(text)
        }
    }

    // ---- Updating in a terminal -------------------------------------------------------
    // The update command (Style.updatesCommand, yours: run as shell text) in a
    // terminal, then `flatpak update` when there are Flatpak ones. The
    // terminal is started detached: restarting the shell must never kill a
    // running pacman. When it ends (or is closed) it tells the shell over IPC.
    function run() {
        terminal(Style.updatesCommand, Style.updatesFlatpak && flatpak.length > 0);
    }
    // The AUR ones only (the panel never builds them itself, nor through
    // pkexec): paru builds as you and asks for sudo when it installs.
    function buildAur() {
        terminal("paru -Sua", false);
    }
    function terminal(command, withFlatpak) {
        // Ctrl+C stops the command but keeps the terminal (you read what
        // happened, then Enter); closing the window still says done.
        const script = 'trap \'qs ipc -p "$3" call updates done >/dev/null 2>&1\' EXIT\n'
            + 'trap "exit 1" HUP TERM\n'
            + 'trap ":" INT\n'
            + 'echo "$ $1"\n'
            + 'eval "$1"\n'
            + 'if [ "$2" = 1 ]; then echo; echo "$ flatpak update"; flatpak update; fi\n'
            + 'printf "\\nDone. Press Enter to close. "\n'
            + 'read -r _\n';
        const cmd = ["xdg-terminal-exec", "--title=Updates", "--",
                     "sh", "-c", script, "mine-updates", command, withFlatpak ? "1" : "0", Quickshell.shellDir];
        updating = true;
        doneSafety.restart();
        if (dryRun || fake) {
            console.log("updates (dry run):", JSON.stringify(cmd));
            fakeDone.restart();
            return;
        }
        Quickshell.execDetached(cmd);
    }
    Timer {
        id: fakeDone
        interval: 2000
        onTriggered: root.done()
    }
    // If the terminal never says it's done (killed): forget it after 2 h.
    Timer {
        id: doneSafety
        interval: 2 * 3600000
        onTriggered: root.updating = false
    }
    // The terminal closed, or the panel's install ended (scripts/update-run.sh
    // says so too): check again for real (Flatpak too).
    function done() {
        updating = false;
        doneSafety.stop();
        settle.stop();
        UpdateRun.poke();
        if (online || fake)
            again.restart();
        else
            recount();
    }
    Timer {
        id: again
        interval: 3000
        onTriggered: root.check("after updating")
    }

    // ---- Saved answer ---------------------------------------------------------------
    property bool loaded: false

    function save() {
        if (!loaded)
            return;
        stateFile.setText(JSON.stringify({
            checkedAt: checkedAt, repo: repo, aur: aur, flatpak: flatpak
        }));
    }
    FileView {
        id: stateFile
        path: root.statePath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            const saved = text();
            Qt.callLater(() => root.restore(saved));
        }
        onLoadFailed: Qt.callLater(() => root.restore(""))
    }
    function restore(text) {
        let s = {};
        try {
            s = JSON.parse(text || "{}");
        } catch (e) {}
        repo = s.repo ?? [];
        aur = s.aur ?? [];
        flatpak = Style.updatesFlatpak ? (s.flatpak ?? []) : [];
        checkedAt = s.checkedAt ?? 0;
        loaded = true;
        schedule();
        // Updated while the shell wasn't running?
        if (repo.length + aur.length > 0)
            Qt.callLater(recount);
    }

    // "12 min ago", "3 h ago", "yesterday"…
    function ago(ms) {
        if (ms <= 0)
            return "never";
        const min = Math.max(0, Math.round((Date.now() - ms) / 60000));
        if (min < 1)
            return "just now";
        if (min < 60)
            return min + " min ago";
        if (min < 24 * 60)
            return Math.round(min / 60) + " h ago";
        const days = Math.round(min / (24 * 60));
        return days === 1 ? "yesterday" : days + " days ago";
    }
}
