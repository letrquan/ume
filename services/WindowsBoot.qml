pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// "Restart to Windows" in the power menu. The laptop starts Linux by itself
// (GRUB is hidden); the firmware also has a "Windows Boot Manager" entry.
//  - Finding it: `efibootmgr` with no flags only lists the entries (no root
//    needed). Read once with the shell and again each time the power menu
//    opens; `entry` is its number ("0001"), "" when there's none.
//  - Restarting: `pkexec efibootmgr -n <entry>` sets BootNext (the entry the
//    firmware starts ONCE, next time; after that it's back to Linux). pkexec
//    asks for the password through the shell's own polkit agent (polkit/).
//    Only when efibootmgr answers with "BootNext: <entry>" (its own listing
//    after the change, or a plain listing read right after) does it restart,
//    the same way the power menu's Restart does (SessionState.run("reboot")).
//    The password dialog closed (pkexec 126 / 127) or efibootmgr failing:
//    nothing happens but a short notification. It never restarts without
//    BootNext set.
//
// Tests: MINE_WINBOOT_DRYRUN=1 (pkexec and the restart are only logged, not
// run; the listing still is); MINE_WINBOOT_LIST (a file read instead of
// running `efibootmgr`, for a listing to parse).
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("MINE_WINBOOT_DRYRUN") === "1"
    readonly property string listFile: Quickshell.env("MINE_WINBOOT_LIST") ?? ""

    // The Windows Boot Manager entry ("0001"), "" = none (or not read yet).
    property string entry: ""
    // What the firmware will start next time, from the last listing ("" = the usual).
    property string bootNext: ""
    property bool known: false            // read at least once
    property bool busy: false             // pkexec / efibootmgr running
    // What pkexec runs (full paths: never a program found first in a folder
    // of yours on PATH); the password dialog says "From Restart to Windows"
    // only for exactly this (polkit/PolkitWindow.qml).
    readonly property string rootCommand: "/usr/bin/efibootmgr -n " + asked
    property string lastError: ""

    // A listing's Windows entry: "Boot0001* Windows Boot Manager\tHD(...)".
    // (The * means active; an inactive one can still be started with BootNext.)
    function parse(text) {
        const win = String(text).match(/^Boot([0-9A-Fa-f]{4})\*?\s+Windows Boot Manager\b/m);
        const next = String(text).match(/^BootNext:\s*([0-9A-Fa-f]{4})\s*$/m);
        return { entry: win ? win[1].toUpperCase() : "", bootNext: next ? next[1].toUpperCase() : "" };
    }

    // Already reading: once more after it (a BootNext just set must be seen).
    property bool listAgain: false
    function check() {
        if (lister.running) {
            listAgain = true;
            return;
        }
        lister.exec(root.listFile !== "" ? ["cat", root.listFile] : root.wrap(["efibootmgr"]));
    }

    // Through sh: a missing program is exit 127 with a message, not a failed start.
    function wrap(cmd) {
        return ["sh", "-c", "command -v \"$1\" >/dev/null || { echo \"$1: not installed\" >&2; exit 127; }; exec \"$@\"", "sh"].concat(cmd);
    }

    Job {
        id: lister
        onResult: (code, out, err) => {
            if (root.listAgain) {
                root.listAgain = false;
                root.check();
                return;
            }
            root.known = true;
            if (code !== 0) {
                console.log("winboot: efibootmgr failed (" + code + "):", err.trim());
                return;
            }
            const r = root.parse(out);
            root.entry = r.entry;
            root.bootNext = r.bootNext;
            if (root.pendingVerify) {
                root.pendingVerify = false;
                root.verified(r.bootNext === root.asked);
            }
        }
    }
    Component.onCompleted: check()

    // ---- Restart into Windows ---------------------------------------------------------
    property string asked: ""
    property bool pendingVerify: false

    function restart() {
        if (busy)
            return;
        if (entry === "") {
            tell("No Windows to restart into", "The firmware has no Windows Boot Manager entry.");
            return;
        }
        // Updates installing hold the restart back (their block lock), but
        // BootNext would stay set: the next restart, whenever, lands in
        // Windows. So not now at all.
        if (UpdateRun.busy) {
            tell("Updates are installing", "Restart to Windows once they're done.");
            return;
        }
        asked = entry;
        lastError = "";
        const cmd = ["/usr/bin/pkexec", "/usr/bin/efibootmgr", "-n", asked];
        if (dryRun) {
            console.log("winboot (dry run):", JSON.stringify(cmd), "then the power menu's restart");
            return;
        }
        busy = true;
        console.log("winboot: asking to set BootNext", asked);
        setter.exec(wrap(cmd));
    }

    Job {
        id: setter
        onResult: (code, out, err) => {
            if (code === 0) {
                // efibootmgr lists the entries after the change: BootNext
                // should be ours. If it didn't say, read the list once more.
                if (root.parse(out).bootNext === root.asked) {
                    root.verified(true);
                } else {
                    root.pendingVerify = true;
                    root.check();
                }
                return;
            }
            root.busy = false;
            if (code === 126 || code === 127) {
                // pkexec: 126 = the dialog was dismissed, 127 = not
                // authorized (or the password was wrong too often).
                root.lastError = "cancelled";
                console.log("winboot: pkexec", code, "-", (err.trim() || "no password"));
                root.tell("Not restarting", "No password was given, so Windows isn't set to start next.");
            } else {
                root.lastError = root.lastLine(err) || root.lastLine(out) || ("exit " + code);
                console.log("winboot: efibootmgr -n failed (" + code + "):", root.lastError);
                root.tell("Not restarting", "Windows couldn't be set to start next: " + root.lastError);
            }
        }
    }

    function verified(ok) {
        busy = false;
        if (!ok) {
            lastError = "BootNext not confirmed";
            console.log("winboot: BootNext isn't", asked, "after efibootmgr; not restarting");
            tell("Not restarting", "The firmware didn't confirm Windows as the next start.");
            return;
        }
        bootNext = asked;
        console.log("winboot: BootNext is", asked, "- restarting");
        SessionState.run("reboot");
    }

    function lastLine(text) {
        const lines = String(text).split("\n").map(l => l.trim()).filter(l => l !== "");
        return lines.length > 0 ? lines[lines.length - 1] : "";
    }

    function tell(summary, body) {
        const cmd = ["notify-send", "-a", "Power", "-i", "system-reboot", "--", summary, body];
        if (dryRun)
            console.log("winboot (dry run):", JSON.stringify(cmd));
        else
            Quickshell.execDetached(cmd);
    }

    // For IPC and tests.
    function status() {
        return JSON.stringify({ entry: entry, bootNext: bootNext, known: known, busy: busy, listed: Style.sessionWindows && entry !== "", lastError: lastError });
    }

    // A command whose answer counts once it has exited AND both its outputs
    // were read (they can come in either order).
    component Job: Process {
        id: job
        property int code: -1
        property int parts: 0
        signal result(int code, string out, string err)
        function part() {
            if (++parts === 3)
                result(code, outText.text, errText.text);
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
}
