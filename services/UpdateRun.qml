pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The updates panel's Update (updates/UpdatesPanel.qml): installs the repo
// packages and your Flatpaks right there, with progress, without a
// terminal. AUR packages are never built here (the panel's "Build in
// terminal" opens paru in a terminal, like Updates.run()).
//
// scripts/update-run.sh does the work, started DETACHED: Qt and Quickshell
// are among the updates, and replacing their libraries mid-transaction can
// crash the shell (shell-keeper starts it again). The script writes what's
// going on to ~/.local/state/mine-shell/update-run.json (its pid, its log,
// where pacman.log was when it began, and at the end the exit codes), so a
// shell that starts in the middle of a run (or after it) reads that file
// and picks it back up. shell.qml reads `loaded` to start this at startup.
//
// Progress comes from /var/log/pacman.log, never pacman's own output: its
// "[ALPM] upgraded / installed / removed …", "transaction started /
// completed", "running '….hook'" and "warning: … installed as ….pacnew"
// lines are stable. The file is tailed from the byte where the run began
// (never read whole, it's big). Only the total comes from pacman's output
// (its "Packages (N)" line, "Package (N)" atop VerbosePkgLists' table), in
// the run's own log, which is also the
// panel's "Details".
//
// It doesn't start while pacman's database is locked (another pacman, paru,
// a crashed one) or while the update is open in a terminal (Updates.updating).
// pacman runs with --noconfirm: a question whose answer is no (a conflict,
// "Remove X? [y/N]") stops it with nothing changed; that's "Needs you:
// finish in the terminal", not a failure. A dismissed password (pkexec 126 /
// 127, also when the shell died while asking) is "Cancelled".
//
// Tests: MINE_UPDATES_RUN (the state file; the log is next to it, .log),
// MINE_UPDATES_DBLOCK (instead of /var/lib/pacman/db.lck),
// MINE_UPDATES_MODULES (instead of /usr/lib/modules), and with
// MINE_UPDATES_FAKE the script runs only when MINE_UPDATES_TESTBIN names a
// directory of fakes (pkexec, flatpak, …), put first on its PATH (pkexec is
// run by its full path, so the fake one is named in MINE_UPDATES_PKEXEC); without
// it, or with MINE_UPDATES_DRYRUN=1, the command is only printed. The
// terminal, `mine restart`, notifications and links are only printed in
// both cases.
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("MINE_UPDATES_DRYRUN") === "1"
    readonly property bool fake: (Quickshell.env("MINE_UPDATES_FAKE") ?? "") !== ""
    readonly property string testBin: Quickshell.env("MINE_UPDATES_TESTBIN") ?? ""
    readonly property string statePath: Quickshell.env("MINE_UPDATES_RUN")
        || (Quickshell.env("HOME") + "/.local/state/mine-shell/update-run.json")
    readonly property string logPath: statePath.replace(/\.json$/, "") + ".log"
    readonly property string lockPath: Quickshell.env("MINE_UPDATES_DBLOCK") || "/var/lib/pacman/db.lck"
    readonly property string modulesDir: Quickshell.env("MINE_UPDATES_MODULES") || "/usr/lib/modules"
    readonly property string script: Quickshell.shellDir + "/scripts/update-run.sh"

    // ---- Where it is ------------------------------------------------------------------
    // "" nothing; "starting": launched, the script hasn't written yet;
    // "running"; "done" (what it did stays until you've seen it).
    property string stage: ""
    readonly property bool busy: stage === "starting" || stage === "running"
    // The script ended without writing its end (killed): "stopped".
    property bool stopped: false
    // When done: ok | failed | needsYou | cancelled | stopped.
    readonly property string result: stage !== "done" ? "" : stopped ? "stopped" : classify(run, question)
    // The bar item stays for a run, and for what it did until seen (a
    // dismissed password needs no news of its own).
    readonly property bool showing: busy || (stage === "done" && result !== "cancelled")
    // Why the last Update didn't start ("" = it did, or wasn't asked).
    property string refused: ""
    property bool loaded: false

    // The state file, as the script wrote it (see scripts/update-run.sh).
    property var run: ({})
    property string expectId: ""

    // ---- Progress (pacman.log) ----------------------------------------------------------
    property int total: 0                 // "Packages (N)" in pacman's output
    property int count: 0                 // packages changed so far
    property string current: ""           // the last one
    property string alpmPhase: ""         // syncing | downloading | preparing | installing | hooks
    property string hook: ""              // the hook running now
    property bool txStarted: false
    property bool txDone: false
    property var changed: []              // names upgraded, installed, removed…
    property var pacnew: []               // "/etc/pacman.conf.pacnew", …
    // ---- From the run's own log -----------------------------------------------------------
    property var lines: []                // its last 200 lines (the panel's Details)
    property string errorLine: ""         // the last "error: …"
    property string question: ""          // a question answered no ("… [y/N]")
    property string clash: ""             // "pkg: /path exists in filesystem" (the first)
    property bool nothingToDo: false
    property int flatpakDone: 0
    property string flatpakCurrent: ""

    readonly property bool repoStep: run.repo === 1
    // How many Flatpak updates waited when it started (0 = no Flatpak step).
    readonly property int flatpakTotal: run.flatpakStep ?? 0
    readonly property bool flatpakStep: flatpakTotal > 0
    readonly property bool pacmanDone: !repoStep || (run.pacman ?? -1) >= 0

    // What scripts/update-run.sh runs through pkexec: the password dialog says
    // "From Updates" only for exactly this, while it's asked for
    // (polkit/PolkitWindow.qml).
    readonly property string rootCommand: "/usr/bin/pacman -Syu --noconfirm --noprogressbar"
    // ("starting": pkexec asks within moments of the launch, often before
    // the script's first state is read.)
    readonly property bool askingPassword: stage === "starting" || phase === "password"

    // password | syncing | downloading | preparing | installing | hooks | flatpak | finishing
    readonly property string phase: {
        if (stage === "starting")
            return "starting";
        if (stage !== "running")
            return "";
        if (!pacmanDone)
            return alpmPhase !== "" ? alpmPhase : "password";
        if (flatpakStep && (run.flatpak ?? -1) < 0 && (run.pacman ?? 0) === 0)
            return "flatpak";
        return "finishing";
    }
    // 0…1 for the bar; -1 while there's no way to tell (an indeterminate one).
    readonly property real fraction: {
        if (phase === "installing")
            return total > 0 ? Math.min(1, count / total) : -1;
        if (phase === "hooks" || phase === "finishing")
            return 1;
        if (phase === "flatpak")
            return flatpakTotal > 0 ? Math.min(1, Math.max(0, flatpakDone - 1) / flatpakTotal) : -1;
        return -1;
    }
    // "Installing 12 of 68 · mesa"
    readonly property string progressText: {
        switch (phase) {
        case "starting":
            return "Starting…";
        case "password":
            return "Waiting for your password";
        case "syncing":
            return "Syncing package lists";
        case "downloading":
            return total > 0 ? "Downloading " + total + (total === 1 ? " package" : " packages") : "Downloading";
        case "preparing":
            return "Getting ready" + (hook !== "" ? " · " + hook : "");
        case "installing":
            // (pacman.log names a package once it's in: N and the name agree.)
            return (total > 0 ? "Installing " + Math.max(1, Math.min(count, total)) + " of " + total : "Installing")
                + (current !== "" ? " · " + current : "");
        case "hooks":
            return "Running hooks" + (hook !== "" ? " · " + hook : "");
        case "flatpak":
            return "Flatpak" + (flatpakTotal > 0 ? " " + Math.max(1, Math.min(flatpakDone, flatpakTotal)) + " of " + flatpakTotal : "")
                + (flatpakCurrent !== "" ? " · " + flatpakCurrent : "");
        case "finishing":
            return "Finishing";
        }
        return "";
    }
    // For the bar: "42%", or "…" while it can't tell.
    readonly property string percentText: fraction < 0 ? "…" : Math.round(fraction * 100) + "%"

    // ---- After it ----------------------------------------------------------------------
    // These need a restart to take effect (the kernel, its firmware, the
    // microcode, systemd, glibc, mesa).
    readonly property var restartFor: changed.filter(n => /^linux/.test(n) || /firmware/.test(n)
        || ["amd-ucode", "systemd", "glibc", "mesa"].includes(n))
    // The running kernel's modules were replaced: drivers that aren't loaded
    // yet (a USB stick, sound after sleep…) won't load until a restart.
    readonly property bool modulesGone: run.modulesGone === 1
    // Quickshell or Qt changed: the running shell still has the old ones.
    readonly property var shellFor: changed.filter(n => /^quickshell/.test(n) || /^qt6-/.test(n))
    readonly property int flatpakCount: flatpakStep && run.flatpak === 0 ? flatpakTotal : 0

    function classify(s, asked) {
        if (s.repo === 1 && (s.pacman === 126 || s.pacman === 127))
            return "cancelled";
        if (s.repo === 1 && s.pacman !== 0)
            return asked !== "" ? "needsYou" : "failed";
        if ((s.flatpakStep ?? 0) > 0 && s.flatpak > 0)
            return "failed";
        return "ok";
    }

    // "Updated 68 packages and 3 Flatpaks"
    readonly property string summary: {
        if (stage !== "done")
            return "";
        switch (result) {
        case "ok": {
            const parts = [];
            if (count > 0)
                parts.push(count + (count === 1 ? " package" : " packages"));
            if (flatpakCount > 0)
                parts.push(flatpakCount + (flatpakCount === 1 ? " Flatpak" : " Flatpaks"));
            return parts.length > 0 ? "Updated " + parts.join(" and ") : "Already up to date";
        }
        case "failed":
            if (repoStep && run.pacman !== 0)
                return "Couldn't update";
            // pacman went through, Flatpak didn't.
            return count > 0 ? "Updated " + count + (count === 1 ? " package" : " packages") + ", but Flatpak failed"
                             : "Flatpak couldn't update";
        case "needsYou":
            return "Needs you: finish in the terminal";
        case "cancelled":
            return "Cancelled";
        case "stopped":
            return "The update stopped";
        }
        return "";
    }

    // ---- Starting --------------------------------------------------------------------
    function start() {
        refused = "";
        if (busy)
            return;
        if (Updates.updating) {
            refused = "The update is open in a terminal";
            return;
        }
        const repo = Updates.repo.length > 0;
        const flatpak = Style.updatesFlatpak && Updates.flatpak.length > 0;
        if (!repo && !flatpak) {
            refused = Updates.aur.length > 0 ? "Only AUR updates: build them in the terminal" : "Nothing to install";
            return;
        }
        if (!repo) {
            launch(false, flatpak);
            return;
        }
        // pacman's lock first: another pacman (or paru, or one that crashed).
        lockCheck.wantFlatpak = flatpak;
        lockCheck.running = true;
    }
    Process {
        id: lockCheck
        property bool wantFlatpak: false
        command: ["test", "-e", root.lockPath]
        onExited: code => {
            if (code === 0)
                root.refused = "pacman's database is locked: another update is running (or one crashed and left "
                    + root.lockPath + "). Finish in the terminal";
            else
                root.launch(true, wantFlatpak);
        }
    }

    function launch(repo, flatpak) {
        const id = String(Date.now());
        const flatpaks = flatpak ? Updates.flatpak.length : 0;
        let cmd = ["sh", script, id, statePath, logPath, Updates.logPath, modulesDir,
                   repo ? "1" : "0", String(flatpaks), Quickshell.shellDir];
        if (dryRun || (fake && testBin === "")) {
            console.log("updates (dry run):", JSON.stringify(cmd));
            return;
        }
        if (fake)
            cmd = ["env", "PATH=" + testBin + ":/usr/bin", "MINE_UPDATES_PKEXEC=" + testBin + "/pkexec"].concat(cmd);
        reset();
        expectId = id;
        stage = "starting";
        console.log("updates: installing (" + [repo ? Updates.repo.length + " repo" : "", flatpak ? flatpaks + " Flatpak" : ""]
            .filter(s => s !== "").join(", ") + ")");
        Quickshell.execDetached(cmd);
        starting.restart();
    }
    // The script writes its state at once; nothing after 20 s: it didn't start.
    Timer {
        id: starting
        interval: 20000
        onTriggered: {
            if (root.stage !== "starting")
                return;
            console.log("updates: the install never started");
            root.stage = "";
            root.refused = "Couldn't start the update";
        }
    }

    function reset() {
        run = {};
        expectId = "";
        stopped = false;
        notified = false;
        resetAlpm();
        lines = [];
        errorLine = "";
        clash = "";
        question = "";
        nothingToDo = false;
        total = 0;
        flatpakDone = 0;
        flatpakCurrent = "";
    }

    // ---- The state file ----------------------------------------------------------------
    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const t = text();
            Qt.callLater(() => root.take(t));
        }
        onLoadFailed: Qt.callLater(() => root.take(""))
    }
    // While it runs: read it again every 2 s too (a rename can slip past
    // the watch; the IPC can't reach a shell that's restarting), and see
    // that the script is still there.
    Timer {
        running: root.busy
        interval: 2000
        repeat: true
        onTriggered: {
            stateFile.reload();
            if (root.stage === "running" && !alive.running)
                alive.running = true;
        }
    }
    // `updates done` over IPC (Updates.done()): read it now.
    function poke() {
        stateFile.reload();
    }

    function take(text) {
        let s = null;
        try {
            s = text.trim() === "" ? null : JSON.parse(text);
        } catch (e) {
            s = null;     // half-written: the next read gets it
            if (!loaded) {
                loaded = true;
                console.log("updates: can't read", statePath);
            }
            return;
        }
        const first = !loaded;
        loaded = true;
        if (!s || !s.id || s.dismissed) {
            if (stage === "done" || (stage === "running" && first))
                clear();
            return;
        }
        // Waiting for our own run: an older file doesn't count.
        if (stage === "starting" && s.id !== expectId)
            return;
        const same = s.id === run.id;
        if (!same) {
            // Another run than the one shown (a new one, or the one going on
            // when the shell started).
            if (stage !== "starting")
                reset();
            expectId = s.id;
            if (first)
                console.log("updates: picking up the install of", new Date(s.started * 1000).toString(),
                            s.finished > 0 ? "(finished)" : "(still running)");
        }
        // Over is over: a read of the file queued before the script was
        // found gone never brings the run back.
        if (same && stage === "done" && !(s.finished > 0))
            return;
        // Found gone, then its real end turns up after all: that wins.
        const late = same && stopped && s.finished > 0;
        if (late)
            stopped = false;
        const before = run;
        run = s;
        starting.stop();
        if (s.finished > 0) {
            const wasRunning = stage !== "done";
            stage = "done";
            if (!same || late || before.logEnd !== s.logEnd)
                readAlpm();
            runLog.reload();
            if (wasRunning)
                finished(first);
        } else {
            stage = "running";
            if (!same) {
                readAlpm();
                alive.running = true;
            } else if (before.pacman !== s.pacman) {
                readAlpm();          // pacman's part is over: its exact slice
            }
            runLog.reload();
        }
    }

    function clear() {
        stage = "";
        reset();
    }

    // Is the script still there? (pid, and the right program: pids come back.)
    Process {
        id: alive
        command: ["sh", "-c", 'kill -0 "$1" 2>/dev/null && tr "\\0" " " < "/proc/$1/cmdline" | grep -q update-run',
                  "sh", String(root.run.pid ?? 0)]
        onExited: code => {
            if (code === 0 || root.stage !== "running" || gone.running)
                return;
            // Gone: maybe it has just written its end. Read the file once
            // more and give that a moment.
            stateFile.reload();
            gone.start();
        }
    }
    Timer {
        id: gone
        interval: 2500
        onTriggered: {
            if (root.stage !== "running")
                return;
            console.log("updates: the install stopped without finishing (pid", root.run.pid + ")");
            root.stopped = true;
            root.stage = "done";
            root.readAlpm();
            runLog.reload();
            root.finished(false);
        }
    }

    // ---- pacman.log, from where the run began ------------------------------------------------
    function resetAlpm() {
        count = 0;
        current = "";
        alpmPhase = "";
        hook = "";
        txStarted = false;
        txDone = false;
        changed = [];
        pacnew = [];
        pending.changed = [];
        pending.pacnew = [];
    }

    // pacman still running: follow the file. Its part over (or reading it
    // again after a restart): exactly the bytes pacman wrote. Each read is
    // a reader of its own; an older one still finishing is ignored (gen).
    property int gen: 0
    property var follower: null
    function readAlpm() {
        gen++;
        if (follower) {
            follower.running = false;
            follower = null;
        }
        resetAlpm();
        if (!repoStep)
            return;
        const from = Number(run.logStart ?? 0) + 1;        // tail -c +N is 1-based
        let cmd;
        if ((run.pacman ?? -1) >= 0 && (run.logEnd ?? -1) >= 0)
            cmd = ["sh", "-c", 'tail -c +"$1" -- "$3" 2>/dev/null | head -c "$2"',
                   "sh", String(from), String(Math.max(0, run.logEnd - run.logStart)), Updates.logPath];
        else if (stage === "running")
            // --pid: it ends with the shell, so a crash leaves no tail behind.
            cmd = ["sh", "-c", 'exec tail --pid="$PPID" -c +"$1" -F -- "$2" 2>/dev/null',
                   "sh", String(from), Updates.logPath];
        else
            // Stopped before pacman's end was written: what's there now.
            cmd = ["sh", "-c", 'tail -c +"$1" -- "$2" 2>/dev/null', "sh", String(from), Updates.logPath];
        const p = reader.createObject(root, { gen: gen, command: cmd });
        if (cmd[2].startsWith("exec tail"))
            follower = p;
        p.running = true;
    }
    Component {
        id: reader
        Process {
            property int gen: 0
            stdout: SplitParser {
                onRead: line => {
                    if (gen === root.gen)
                        root.takeAlpm(line);
                }
            }
            onExited: {
                if (gen === root.gen)
                    flush.restart();
                destroy();
            }
        }
    }

    // Lists grow in a plain object and are handed over in one go (a
    // binding per line would redo the panel's lists hundreds of times).
    QtObject {
        id: pending
        property var changed: []
        property var pacnew: []
    }
    Timer {
        id: flush
        interval: 250
        onTriggered: root.flushAlpm()
    }
    function flushAlpm() {
        changed = pending.changed.slice();
        pacnew = pending.pacnew.slice();
    }

    function takeAlpm(line) {
        const m = /^\[[^\]]*\] \[(ALPM|PACMAN)\] (.*)$/.exec(line);
        if (!m)
            return;
        const what = m[2];
        let p;
        if (m[1] === "PACMAN") {
            if (/^synchronizing package lists/.test(what))
                alpmPhase = "syncing";
            else if (/^starting full system upgrade/.test(what))
                alpmPhase = "downloading";
            else if (/^Running '/.test(what) && alpmPhase === "")
                alpmPhase = "syncing";
            return;
        }
        if ((p = /^(upgraded|installed|removed|downgraded|reinstalled) (\S+) \(/.exec(what)) !== null) {
            count++;
            current = p[2];
            pending.changed.push(p[2]);
            alpmPhase = "installing";
            if (!flush.running)
                flush.start();
        } else if ((p = /^warning: (.+) installed as (.+\.pacnew)$/.exec(what)) !== null) {
            pending.pacnew.push(p[2]);
            if (!flush.running)
                flush.start();
        } else if ((p = /^running '(.+)'\.\.\.$/.exec(what)) !== null) {
            hook = p[1].replace(/\.hook$/, "").replace(/^\d+-/, "");
            alpmPhase = txStarted && !txDone ? "installing" : txDone ? "hooks" : "preparing";
        } else if (/^transaction started/.test(what)) {
            txStarted = true;
            alpmPhase = "installing";
            hook = "";
        } else if (/^transaction (completed|failed|interrupted)/.test(what)) {
            txDone = true;
            alpmPhase = "hooks";
            hook = "";
        }
    }

    // ---- The run's own log (pacman's and flatpak's output) ------------------------------------
    FileView {
        id: runLog
        path: root.stage !== "" ? (root.run.log || root.logPath) : ""
        watchChanges: root.busy
        printErrors: false
        // Lines come fast: read again at most 3 times a second.
        onFileChanged: if (!again.running) again.start()
        onLoaded: root.takeLog(text())
    }
    Timer {
        id: again
        interval: 330
        onTriggered: runLog.reload()
    }

    function takeLog(text) {
        const all = [];
        for (let line of String(text ?? "").split("\n")) {
            // Colours and a progress line's earlier versions off.
            line = line.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "");
            const cr = line.lastIndexOf("\r");
            if (cr >= 0)
                line = line.slice(cr + 1);
            all.push(line);
        }
        if (all.length > 0 && all[all.length - 1] === "")
            all.pop();
        let tot = 0, err = "", asked = "", nothing = false, fpAt = -1, clashed = "";
        for (let i = 0; i < all.length; i++) {
            const line = all[i];
            let m;
            // "Packages (68) a-1 b-2 …", or with VerbosePkgLists (on here)
            // the table's header: "Package (68)   Old Version   New Version …".
            if ((m = /^\s*Packages? \((\d+)\)/.exec(line)) !== null)
                tot = Number(m[1]);
            else if (/^error: /.test(line))
                err = line;
            else if (/\[y\/N\]/.test(line))
                asked = line.trim().replace(/^::\s*/, "");
            else if (/^\s*there is nothing to do/.test(line))
                nothing = true;
            else if (clashed === "" && /^\S+: \/.* exists in filesystem/.test(line))
                clashed = line.trim();
            else if (line === "$ flatpak update")
                fpAt = i;
        }
        let fpDone = 0, fpNow = "";
        if (fpAt >= 0) {
            for (let i = fpAt + 1; i < all.length; i++) {
                const m = /^(Updating|Installing) (\S+)/.exec(all[i]);
                if (!m || /^(appstream|summary|metadata)/.test(m[2]))
                    continue;
                fpDone++;
                // app/com.spotify.Client/x86_64/stable → com.spotify.Client
                const parts = m[2].split("/");
                fpNow = parts.length >= 2 ? parts[1] : m[2];
            }
        }
        total = tot;
        errorLine = err;
        clash = clashed;
        question = asked;
        nothingToDo = nothing;
        flatpakDone = fpDone;
        flatpakCurrent = fpNow;
        lines = all.slice(-200);
    }

    // ---- When it's over ---------------------------------------------------------------
    property bool notified: false
    property string handled: ""

    function finished(atStart) {
        console.log("updates: install finished:", result, "| pacman", run.pacman, "flatpak", run.flatpak,
                    "| changed", count, "| pacnew", pacnew.length);
        // Check again for real (once per run; the IPC asks too). A result
        // found at start: only when it's fresh (not at every restart).
        const recent = Date.now() - (run.finished ?? 0) * 1000 < 3600000;
        if (handled !== run.id && (!atStart || recent)) {
            handled = run.id;
            Updates.done();
        }
        // Tell about it unless you're looking at it (or it's old news).
        if (!run.notified && !(atStart && !recent))
            tellLater.restart();
    }
    // A moment later: the log and pacman.log's last lines are in by then.
    Timer {
        id: tellLater
        interval: 1500
        onTriggered: root.tell()
    }
    function tell() {
        if (stage !== "done" || run.notified || notified)
            return;
        notified = true;
        mark({ notified: true });
        if (UpdatesState.open || result === "cancelled")
            return;
        const restart = restartFor.length > 0 ? (modulesGone ? " · Restart soon" : " · Restart to finish") : "";
        const body = result === "ok" ? summary + restart + (pacnew.length > 0 ? " · " + pacnew.length + " .pacnew" : "")
                   : result === "needsYou" ? (question || "pacman asked something; finish in the terminal")
                   : result === "stopped" ? "It ended before finishing; finish in the terminal"
                   : errorLine || "Finish in the terminal";
        const cmd = ["notify-send", "-a", "Updates", "-i", result === "ok" ? "system-software-update" : "dialog-warning",
                     "-A", "default=Show", "--", result === "ok" ? "Updates installed" : summary, body];
        if (dryRun || fake) {
            console.log("updates (dry run):", JSON.stringify(cmd));
            return;
        }
        notice.createObject(root, { command: cmd }).running = true;
    }
    // notify-send waits while the notification is around and prints the
    // button pressed: Show opens the panel.
    Component {
        id: notice
        Process {
            stdout: SplitParser {
                onRead: line => {
                    if (line === "default")
                        UpdatesState.request();
                }
            }
            onExited: destroy()
        }
    }

    // A few fields added to the finished run's file (the script is done
    // with it): told, dismissed.
    function mark(fields) {
        if (stage !== "done" || !run.id)
            return;
        run = Object.assign({}, run, fields);
        stateFile.setText(JSON.stringify(run) + "\n");
    }

    // Seen: the list again (and the bar item hides when nothing waits).
    function dismiss() {
        if (stage !== "done")
            return;
        mark({ dismissed: true });
        clear();
    }

    // Quickshell or Qt changed: `mine restart` (detached, it stops this shell).
    function restartShell() {
        dismiss();
        const cmd = [Quickshell.env("HOME") + "/.local/bin/mine", "restart"];
        if (dryRun || fake)
            console.log("updates (dry run):", JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    // "updates status" (IPC).
    function describe() {
        if (stage === "")
            return refused !== "" ? "not started: " + refused : "";
        if (busy)
            return "installing: " + progressText;
        return "done: " + result + (summary !== "" ? " (" + summary + ")" : "")
            + (errorLine !== "" && result !== "ok" ? "; " + errorLine : "")
            + (restartFor.length > 0 ? "; restart for " + restartFor.join(" ") : "")
            + (pacnew.length > 0 ? "; pacnew " + pacnew.join(" ") : "");
    }
}
