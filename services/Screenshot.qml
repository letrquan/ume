pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Screenshots.
//   region / window: freeze the focused screen first (grim the whole output),
//     then show it in the overlay (screenshot/ShotWindow.qml) where you drag a
//     region or click a window; the picture is cut out of the frozen image,
//     so nothing that moves after the key press ends up in it.
//   screen: the whole focused screen at once, no overlay.
// Then: saved to Style.screenshotDir, copied to the clipboard, and a
// notification with the picture (scripts/shot-notify.sh: click opens it,
// Edit, Delete). With Edit switched on in the overlay, swappy opens instead.
//
// The same overlay picks what a screen recording takes (recordRegion():
// services/Recorder.qml gets the rectangle instead of a picture being cut),
// and where to read text from (text(): the piece goes through
// scripts/ocr.sh, the text is copied and a notification says how much).
//
// MINE_SHOT_DRYRUN=1, MINE_SHOT_DIR and MINE_SHOT_FREEZE are for testing:
// nothing is copied, notified or opened, only printed.
Singleton {
    id: root

    property bool active: false        // the overlay is up
    property bool busy: false          // freezing or saving
    property string mode: "region"     // region | window | screen
    property bool edit: false
    property bool forRecording: false  // picking for Recorder, not a picture
    property bool forText: false       // picking text to copy (OCR)

    // The focused output: { name, x, y, width, height, scale } (logical, mango).
    property var monitor: null
    // Windows visible on it: [{ x, y, width, height, title, appid }], in the
    // output's own coordinates.
    property var windows: []
    property string frozen: ""         // the frozen screen, a file path

    readonly property bool dryRun: Quickshell.env("MINE_SHOT_DRYRUN") === "1"
    readonly property string dir: Quickshell.env("MINE_SHOT_DIR") || Style.screenshotDir
    readonly property string freezePath: Quickshell.env("MINE_SHOT_FREEZE")
        || (Quickshell.env("XDG_RUNTIME_DIR") + "/mine-shot-frozen.png")

    // ---- Starting ------------------------------------------------------------------------
    function region() { forRecording = false; forText = false; start("region"); }
    function window() { forRecording = false; forText = false; start("window"); }
    function screen() { forRecording = false; forText = false; start("screen"); }
    // Pick what to record: the overlay comes up in region mode.
    function recordRegion() {
        if (active || busy)
            return;
        forRecording = true;
        forText = false;
        start("region");
    }
    // Copy the text in a region (drag one, or click a window).
    function text() {
        if (active || busy)
            return;
        forRecording = false;
        forText = true;
        start("region");
    }

    function start(m) {
        if (busy)
            return;
        if (active) {
            mode = m === "screen" ? mode : m;
            return;
        }
        mode = m;
        busy = true;
        monitors.running = true;        // → clients → grim
    }

    function close() {
        active = false;
        busy = false;
        forRecording = false;
        forText = false;
    }

    // ---- Capturing (from the overlay) -------------------------------------------------------
    // A rectangle in the output's logical coordinates.
    function captureRect(x, y, w, h) {
        if (!active || !monitor || w < 2 || h < 2)
            return;
        if (forRecording) {
            // wf-recorder wants global logical coordinates, inside the output.
            const rx = Math.max(0, x), ry = Math.max(0, y);
            const rw = Math.min(x + w, monitor.width) - rx, rh = Math.min(y + h, monitor.height) - ry;
            close();
            Recorder.recordRect(monitor.x + rx, monitor.y + ry, rw, rh);
            return;
        }
        const s = monitor.scale;
        const px = Math.max(0, Math.round(x * s));
        const py = Math.max(0, Math.round(y * s));
        const pw = Math.min(Math.round((x + w) * s), Math.round(monitor.width * s)) - px;
        const ph = Math.min(Math.round((y + h) * s), Math.round(monitor.height * s)) - py;
        if (forText) {
            readText(pw + "x" + ph + "+" + px + "+" + py);
            return;
        }
        const out = target();
        active = false;
        busy = true;
        crop.out = out;
        crop.command = ["magick", frozen, "-crop", pw + "x" + ph + "+" + px + "+" + py, "+repage", out];
        crop.running = true;
    }

    // The whole frozen screen.
    function captureAll() {
        if (!active)
            return;
        if (forRecording) {
            const name = monitor?.name ?? "";
            close();
            Recorder.recordOutput(name);
            return;
        }
        if (forText) {
            readText("");
            return;
        }
        const out = target();
        active = false;
        busy = true;
        crop.out = out;
        crop.command = ["cp", frozen, out];
        crop.running = true;
    }

    // ~/Pictures/Screenshots/screenshot_2026-10-15_03-58-12.png
    function target() {
        return dir + "/screenshot_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".png";
    }

    function finish(file) {
        busy = false;
        Sounds.screenshot();
        if (dryRun) {
            console.log("screenshot (dry run): saved", file, edit ? "→ swappy" : "→ copy + notify");
            if (!edit)
                Activities.screenshot(file);
            done(file);
            return;
        }
        // The live activity shows it; then the notification only goes to the
        // list (for its Open / Edit / Delete).
        const said = !edit && Activities.screenshot(file);
        Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", file]);
        if (edit)
            Quickshell.execDetached(["swappy", "-f", file]);
        else if (Style.screenshotNotify)
            Quickshell.execDetached(["sh", Quickshell.shellDir + "/scripts/shot-notify.sh", file, said ? "quiet" : ""]);
        done(file);
    }

    signal done(string file)

    // ---- Text (OCR) -------------------------------------------------------------------------
    // Style.ocrLanguages: "auto" (English, plus Vietnamese when installed) or
    // tesseract's own, e.g. "eng+vie".
    function readText(geometry) {
        active = false;
        busy = true;
        ocr.command = ["sh", Quickshell.shellDir + "/scripts/ocr.sh", frozen, geometry, Style.ocrLanguages || "auto"];
        ocr.running = true;
    }

    function gotText(raw) {
        busy = false;
        forText = false;
        // Lines joined back up, empty lines kept as paragraph breaks.
        const text = raw.replace(/\f/g, "").replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
        const words = text === "" ? 0 : text.split(/\s+/).length;
        const first = text.split("\n")[0].trim();
        const firstLine = first.length > 90 ? first.substring(0, 89) + "…" : first;
        // "--": the line read off the screen may start with "-" (any page can
        // show "--icon=..."); after it, it is only text.
        const note = words === 0
            ? ["notify-send", "-a", "Copy text", "-i", "edit-find", "Nothing found", "No text in that part of the screen"]
            : ["notify-send", "-a", "Copy text", "-i", "edit-copy", "--", "Copied " + words + (words === 1 ? " word" : " words"), firstLine];
        // The live activity says it, or (off, or a panel is open) the notification.
        const said = Activities.textRead(text, words);
        if (dryRun) {
            console.log("screenshot (dry run): text", JSON.stringify(text));
            if (words > 0)
                console.log("screenshot (dry run): wl-copy", words, "words");
            if (!said)
                console.log("screenshot (dry run):", JSON.stringify(note));
        } else {
            if (words > 0)
                Quickshell.execDetached(["wl-copy", "--", text]);
            if (!said)
                Quickshell.execDetached(note);
        }
        textRead(text);
    }

    signal textRead(string text)

    Process {
        id: ocr
        stdout: StdioCollector {
            onStreamFinished: root.gotText(text)
        }
        onExited: code => {
            if (code !== 0)
                console.warn("screenshot: reading text failed", code);
        }
    }

    // ---- Steps ---------------------------------------------------------------------------
    // 1) which output has focus
    Process {
        id: monitors
        command: ["mmsg", "get", "all-monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text).monitors ?? [];
                    const m = list.find(o => o.active) ?? list[0];
                    root.monitor = m ? { name: m.name, x: m.x, y: m.y, width: m.width, height: m.height, scale: m.scale } : null;
                } catch (e) {
                    root.monitor = null;
                }
                if (!root.monitor) {
                    console.warn("screenshot: no monitor from mmsg");
                    root.busy = false;
                    return;
                }
                if (root.mode === "screen") {
                    // No overlay: straight to the file.
                    const out = root.target();
                    crop.out = out;
                    crop.command = ["sh", "-c", 'mkdir -p "$(dirname "$2")" && grim -o "$1" "$2"', "sh", root.monitor.name, out];
                    crop.running = true;
                } else {
                    clients.running = true;
                }
            }
        }
    }

    // 2) the windows you can see on it
    Process {
        id: clients
        command: ["mmsg", "get", "all-clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try {
                    list = JSON.parse(text).clients ?? [];
                } catch (e) {}
                const m = root.monitor;
                root.windows = list.filter(c => c.is_visible && c.monitor === m.name && !c.is_minimized)
                    .map(c => ({
                        x: c.x - m.x, y: c.y - m.y, width: c.width, height: c.height,
                        title: c.title ?? "", appid: c.appid ?? "",
                        floating: c.is_floating, fullscreen: c.is_fullscreen
                    }))
                    // Floating and fullscreen ones sit on top: they win the hover.
                    .sort((a, b) => (b.floating || b.fullscreen) - (a.floating || a.fullscreen));
                freeze.running = true;
            }
        }
    }

    // 3) freeze: the whole output, at full resolution
    Process {
        id: freeze
        command: ["grim", "-o", root.monitor?.name ?? "", root.freezePath]
        onExited: code => {
            if (code !== 0) {
                console.warn("screenshot: grim failed", code);
                root.busy = false;
                return;
            }
            root.frozen = root.freezePath;
            root.busy = false;
            root.active = true;         // the overlay comes up now
        }
    }

    // 4) cut the picture out (or grim it straight for "screen")
    Process {
        id: crop
        property string out: ""
        onExited: code => {
            if (code === 0)
                root.finish(out);
            else {
                console.warn("screenshot: saving failed", code);
                root.busy = false;
            }
        }
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", dir])
}
