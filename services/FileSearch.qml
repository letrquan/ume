pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The launcher's file search (type "/" or "~", then part of a name):
// `fd` under Style.fileSearchRoot, skipping hidden folders (unless the name
// starts with "."), what .gitignore hides, caches and node_modules. Several
// words match in order ("inv 2024" finds invoice-2024.pdf); a "/" searches
// the whole path ("~/proj/readme"). It waits until you stop typing for a
// moment, and a new search stops the one before.
Singleton {
    id: root

    // What the shown results are for.
    property string term: ""
    // [{ path, name, dir, isDir }]
    property var results: []
    readonly property bool busy: debounce.running || proc.running

    readonly property string home: Quickshell.env("HOME")
    readonly property string rootDir: Style.fileSearchRoot.replace(/^~(?=\/|$)/, home)

    property string pending: ""
    property string runTerm: ""
    property bool startAgain: false

    // "" stops searching and forgets the results.
    function search(t) {
        if (t === pending)
            return;
        pending = t;
        if (t === "") {
            debounce.stop();
            proc.running = false;
            results = [];
            term = "";
            return;
        }
        debounce.restart();
    }

    Timer {
        id: debounce
        interval: 300
        onTriggered: root.start()
    }

    function start() {
        if (proc.running) {
            // Starts once the old one is gone (see onRunningChanged).
            startAgain = true;
            proc.running = false;
            return;
        }
        if (pending === "")
            return;
        runTerm = pending;
        proc.command = command(pending);
        proc.running = true;
    }

    function command(t) {
        const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        const cmd = ["fd", "--ignore-case", "--absolute-path", "--color", "never", "--max-results", "300",
                     "--exclude", ".git", "--exclude", "node_modules", "--exclude", ".cache",
                     "--exclude", "__pycache__", "--exclude", ".local/share/Trash"];
        if (t.startsWith(".") || t.includes("/."))
            cmd.push("--hidden");
        if (t.includes("/"))
            cmd.push("--full-path");
        // "--": a pattern that starts with "-" is still a pattern, not an option.
        cmd.push("--", t.split(/\s+/).filter(w => w !== "").map(esc).join(".*"));
        cmd.push(rootDir);
        return cmd;
    }

    // Name matches first (exact, then the start, then anywhere), then the
    // shallower path; 50 at most.
    function sorted(lines, t) {
        const q = t.toLowerCase().split("/").pop().trim();
        const out = [];
        for (const line of lines) {
            if (line === "")
                continue;
            const isDir = line.endsWith("/");
            const path = isDir ? line.slice(0, -1) : line;
            const name = path.split("/").pop();
            const lower = name.toLowerCase();
            const rank = lower === q ? 0 : lower.startsWith(q) ? 1 : lower.includes(q) ? 2 : 3;
            out.push({ path: path, name: name, dir: path.slice(0, path.length - name.length - 1), isDir: isDir,
                       rank: rank, depth: path.split("/").length });
        }
        out.sort((a, b) => a.rank - b.rank || a.depth - b.depth || a.name.length - b.name.length);
        return out.slice(0, 50);
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                // A search that was stopped for a newer one: ignore it.
                if (root.runTerm !== root.pending)
                    return;
                root.results = root.sorted(this.text.split("\n"), root.runTerm);
                root.term = root.runTerm;
            }
        }
        onRunningChanged: {
            if (!running && root.startAgain) {
                root.startAgain = false;
                root.start();
            }
        }
    }
}
