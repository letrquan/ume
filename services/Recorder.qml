pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.common

// Screen recording with wf-recorder.
//   screen: the focused screen, right away
//   region: pick it in the screenshot overlay first (drag a region, click a
//           window, or the whole screen), then it starts
// Stop: the red dot in the bar, the Record tile, or the same key again.
// Saved to Style.recordDir as Recording_2026-10-15_06-12-30.mp4, then a
// notification (scripts/record-notify.sh: click opens it; Show in folder).
// Style.recordAudio adds what you hear (the speaker's monitor), and
// Style.recordHardware encodes on the GPU (VA-API) instead of the CPU.
//
// MINE_RECORD_DRYRUN=1 (tests): wf-recorder isn't run, the command is
// printed, and a stand-in process "records" until stop() interrupts it.
// MINE_RECORD_DIR: another folder instead of Style.recordDir.
Singleton {
    id: root

    readonly property bool recording: proc.running
    property bool starting: false       // between the key and wf-recorder running
    property string file: ""
    property real startedAt: 0
    property int elapsed: 0             // seconds
    // "0:42", "12:05", "1:02:33"
    readonly property string elapsedText: {
        const h = Math.floor(elapsed / 3600);
        const m = Math.floor((elapsed % 3600) / 60);
        const s = elapsed % 60;
        const ss = (s < 10 ? "0" : "") + s;
        return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss;
    }

    readonly property bool dryRun: Quickshell.env("MINE_RECORD_DRYRUN") === "1"
    // (A "~/..." typed in the Settings window counts from home.)
    readonly property string dir: (Quickshell.env("MINE_RECORD_DIR") || Style.recordDir)
        .replace(/^~(?=\/|$)/, Quickshell.env("HOME"))
    readonly property string gpu: "/dev/dri/renderD128"

    // ---- Starting and stopping ---------------------------------------------------------------
    function toggle() {
        if (recording)
            stop();
        else
            start("screen");
    }

    // "screen" or "region". While recording, either one stops it (so the
    // same key starts and stops).
    function start(kind) {
        if (recording) {
            stop();
            return;
        }
        if (starting)
            return;
        if (kind === "region") {
            Screenshot.recordRegion();  // → recordRect() once picked
            return;
        }
        starting = true;
        monitors.running = true;        // → begin(["-o", <focused screen>])
    }

    // From a panel that closes first (the control center): once it's gone,
    // so it isn't in the recording or in the way of the region picker.
    function startSoon(kind) {
        soon.kind = kind;
        soon.restart();
    }
    Timer {
        id: soon
        property string kind: "screen"
        interval: Motion.morphOut + 150
        onTriggered: root.start(kind)
    }

    // From the screenshot overlay: a rectangle in global logical coordinates
    // (the overlay closes first, so it isn't in the first frames).
    function recordRect(x, y, w, h) {
        if (recording || starting)
            return;
        starting = true;
        afterOverlay.where = ["-g", Math.round(x) + "," + Math.round(y) + " " + Math.round(w) + "x" + Math.round(h)];
        afterOverlay.restart();
    }
    function recordOutput(name) {
        if (recording || starting)
            return;
        starting = true;
        afterOverlay.where = name !== "" ? ["-o", name] : [];
        afterOverlay.restart();
    }

    function stop() {
        if (!recording)
            return;
        stopping = true;
        proc.signal(2);                 // SIGINT: wf-recorder finishes the file
    }

    // ---- The wf-recorder command ---------------------------------------------------------------
    property bool stopping: false
    property bool hardware: false       // the GPU's render node exists
    property string lastError: ""

    function commandFor(where, out) {
        let cmd = ["wf-recorder", "-y", "-f", out].concat(where);
        if (Style.recordHardware && hardware)
            cmd = cmd.concat(["-c", "h264_vaapi", "-d", gpu]);
        else
            // Light on the CPU, and yuv420p plays everywhere (browsers, chats).
            cmd = cmd.concat(["-c", "libx264", "-p", "preset=veryfast", "-p", "crf=23", "-x", "yuv420p"]);
        if (Style.recordAudio) {
            const sink = Pipewire.defaultAudioSink?.name ?? "";
            cmd.push("--audio=" + (sink !== "" ? sink + ".monitor" : "@DEFAULT_MONITOR@"));
        }
        return cmd;
    }

    function begin(where) {
        const out = dir + "/Recording_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".mp4";
        const cmd = commandFor(where, out);
        file = out;
        elapsed = 0;
        lastError = "";
        stopping = false;
        startedAt = Date.now();
        if (dryRun) {
            console.log("record (dry run):", JSON.stringify(cmd));
            // A stand-in that runs until SIGINT, like wf-recorder.
            proc.command = ["sh", "-c", "trap 'exit 0' INT; while :; do sleep 0.1; done"];
        } else {
            // mkdir first; exec keeps the same process, so SIGINT reaches wf-recorder.
            proc.command = ["sh", "-c", 'mkdir -p "$1" && shift && exec "$@"', "sh", dir].concat(cmd);
        }
        proc.running = true;
        starting = false;
        Sounds.recording(true);
    }

    function finished(code) {
        const seconds = Math.round((Date.now() - startedAt) / 1000);
        const asked = stopping;
        const out = file;
        stopping = false;
        Sounds.recording(false);
        if (!asked && code !== 0)
            console.warn("record: wf-recorder stopped by itself (" + code + "):", lastError);
        if (dryRun)
            console.log("record (dry run): saved", out, "after", seconds, "s, exit", code, asked ? "(stopped)" : "(by itself)");
        else
            Quickshell.execDetached(["sh", Quickshell.shellDir + "/scripts/record-notify.sh", out, String(seconds), asked ? "" : lastError]);
        // Once `recording` is false too.
        Qt.callLater(() => root.done(out));
    }

    signal done(string file)

    Process {
        id: proc
        stderr: SplitParser {
            // Only the last line matters (why it stopped, if it did).
            onRead: line => {
                if (line.trim() !== "")
                    root.lastError = line.trim();
            }
        }
        onExited: code => root.finished(code)
    }

    Timer {
        interval: 500
        repeat: true
        running: root.recording
        onTriggered: root.elapsed = Math.floor((Date.now() - root.startedAt) / 1000)
    }

    // The overlay's last frame should be gone before the first one is taken.
    Timer {
        id: afterOverlay
        property var where: []
        interval: 250
        onTriggered: root.begin(where)
    }

    // Which screen has focus (mango).
    Process {
        id: monitors
        command: ["mmsg", "get", "all-monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                let name = "";
                try {
                    const list = JSON.parse(text).monitors ?? [];
                    name = (list.find(o => o.active) ?? list[0])?.name ?? "";
                } catch (e) {}
                // wf-recorder asks on the terminal when there are several
                // screens and no -o: never let it.
                if (name === "")
                    name = Quickshell.screens[0]?.name ?? "";
                root.begin(name !== "" ? ["-o", name] : []);
            }
        }
    }

    // Is VA-API there (for Style.recordHardware)?
    Process {
        running: true
        command: ["test", "-e", root.gpu]
        onExited: code => root.hardware = code === 0
    }
}
