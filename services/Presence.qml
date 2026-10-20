pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The camera module's presence sensor (Settings → Power & locking →
// Presence sensor; off by default). Only reads: what to do with the answers
// is services/Idle.qml's business, which also says when to read (`watching`:
// no input for a while, and not locked).
//
// The sensor is an IIO device named "prox" (HP 5MP camera module; the
// laptop has two: the one whose attention means something is used):
//   in_proximity0_raw   > 0 = someone is there
//   in_attention_input  > 0 = and looking at the screen (if the file exists)
// What the numbers really mean is not verified yet (seen: 1 and 25500 while
// sitting there). Every read wakes the camera's USB device for ~2 s, so
// nothing is read while you type or while locked, and only one read at a
// time (the next is asked for when the last one is back).
//
// MINE_PRESENCE_DIR (tests): another folder instead of /sys/bus/iio/devices.
Singleton {
    id: root

    readonly property bool enabled: Style.presenceLock
    readonly property string base: Quickshell.env("MINE_PRESENCE_DIR") || "/sys/bus/iio/devices"
    // The sensor's folder, found by its name when this turns on.
    property string device: ""
    property bool searched: false

    // Set by Idle: read every Style.presenceEvery seconds while true.
    property bool watching: false
    // Set by Idle: also read in_attention_input with every read.
    property bool wantAttention: false

    // Nobody there for Style.presenceAwayFor seconds in a row (while watching).
    signal away()
    // The answer to ask(); known is false when the read failed.
    signal answered(bool looking, bool known)
    // After every read (also ask()'s), for whoever waits on someone looking.
    signal reading(bool present, bool looking, bool known)

    // Files read so far (Settings shows it: the cost).
    property int reads: 0

    // ---- Finding the sensor --------------------------------------------------------
    // By the name of each device. This laptop has two "prox" ones that see
    // you come and go alike, but only one's attention means anything (0 or
    // 100: looking or not; the other's stays at 25500, checked 2026-10-16),
    // so the one whose attention reads 0-100 is taken (one read each, when
    // this turns on), else the first.
    Process {
        id: finder
        command: ["sh", "-c", "first=; for d in \"$1\"/*; do [ -e \"$d/in_proximity0_raw\" ] || continue; "
            + "read -r n < \"$d/name\" 2>/dev/null || continue; [ \"$n\" = prox ] || continue; "
            + "[ -n \"$first\" ] || first=$d; read -r a < \"$d/in_attention_input\" 2>/dev/null || continue; "
            + "case $a in ''|*[!0-9]*) continue ;; esac; [ \"$a\" -le 100 ] && { echo \"$d\"; exit 0; }; done; "
            + "[ -n \"$first\" ] && echo \"$first\"",
            "sh", root.base]
        stdout: StdioCollector {
            onStreamFinished: {
                root.device = text.trim().split("\n")[0];
                root.searched = true;
                console.log("presence:", root.device !== "" ? "sensor " + root.device : "no presence sensor (IIO device named prox) found");
                if (root.watching && !root.busy)
                    root.read(root.wantAttention);
            }
        }
    }
    function find() {
        if (!finder.running) {
            searched = false;
            finder.running = true;
        }
    }
    onEnabledChanged: if (enabled) find()
    Component.onCompleted: if (enabled) find()

    // ---- Reading -------------------------------------------------------------------
    // One read = in_proximity0_raw, then (when wanted) in_attention_input.
    // A FileView reads as soon as it gets a path, so the paths are set for
    // one read and cleared again; with Presence off they stay empty.
    property bool busy: false
    property bool withAttention: false
    property bool asking: false
    property bool tryAgain: true        // find the device again once if it vanished

    function read(attention) {
        if (!enabled || device === "" || busy)
            return false;
        busy = true;
        withAttention = attention;
        load(proxFile, device + "/in_proximity0_raw");
        return true;
    }
    function load(view, path) {
        reads++;
        if (view.path === path)
            view.reload();
        else
            view.path = path;
    }

    // One read now, answered with answered().
    function ask() {
        asking = true;
        if (!busy && !read(true)) {
            asking = false;
            answered(false, false);
        }
        // else: a read is out; its answer is taken (with attention if it
        // wasn't, by reading that file after it).
    }

    property real lastRead: 0

    function finish(present, looking, known) {
        busy = false;
        lastRead = Date.now();
        // Not from inside the FileView's own signal; and not if a new read
        // has started by then.
        Qt.callLater(() => {
            if (!root.busy) {
                proxFile.path = "";
                attFile.path = "";
            }
        });
        if (!known && tryAgain && enabled) {
            // The camera may have come back under another number.
            tryAgain = false;
            device = "";
            find();
        }
        reading(present, looking, known);
        if (asking) {
            asking = false;
            answered(looking, known);
        }
        if (watching) {
            track(present, known);
            next.restart();
        }
    }

    function number(text) {
        const v = parseInt(text);
        return isNaN(v) ? -1 : v;
    }

    FileView {
        id: proxFile
        printErrors: false
        onLoaded: {
            const v = root.number(text());
            if (v < 0) {
                root.finish(false, false, false);
            } else if (v > 0 && (root.withAttention || root.asking)) {
                root.load(attFile, root.device + "/in_attention_input");
            } else {
                root.finish(v > 0, false, true);
            }
        }
        onLoadFailed: if (path !== "") root.finish(false, false, false)
    }
    FileView {
        id: attFile
        printErrors: false
        onLoaded: {
            const v = root.number(text());
            root.finish(true, v > 0, true);
        }
        // No attention file: being there counts as looking.
        onLoadFailed: if (path !== "") root.finish(true, true, true)
    }

    // ---- Every few seconds while watching -----------------------------------------
    property real awaySince: -1
    property bool told: false

    function track(present, known) {
        if (!known || present) {
            awaySince = -1;
            return;
        }
        const now = Date.now();
        if (awaySince < 0)
            awaySince = now;
        else if (!told && now - awaySince >= Style.presenceAwayFor * 1000) {
            told = true;
            away();
        }
    }

    onWatchingChanged: {
        awaySince = -1;
        told = false;
        tryAgain = true;
        if (!watching)
            next.stop();
        else if (Date.now() - lastRead < Style.presenceEvery * 1000)
            next.restart();     // just read (the dim-time ask)
        else
            read(wantAttention);
    }

    // The next read, counted from when the last one came back.
    Timer {
        id: next
        interval: Math.max(1, Style.presenceEvery) * 1000
        onTriggered: if (root.watching) root.read(root.wantAttention)
    }
}
