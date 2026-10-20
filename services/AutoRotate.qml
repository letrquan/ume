pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Turns the built-in screen with the tablet. Style.rotateScreen: "off" (the
// default: nothing here runs), "tablet" (only while folded back,
// TabletMode), "always". Back to normal when it stops (folded back to a
// laptop, or turned off). lock() holds the screen as it is (the control
// center's Auto-rotate tile, `qs -c mine ipc call rotate lock`); not kept
// after a restart.
//
// The sensor: `monitor-sensor --accel` (iio-sensor-proxy) runs only while
// turning is on and not held. It claims the accelerometer, so the proxy
// reads it only then, and stopping it lets go. A way up must last 0.5 s
// before the screen follows; "undefined" (lying flat) keeps the screen as
// it is.
//
// The turn: mango has no rotate command, so this adds a monitor_rule with
// `mmsg dispatch setoption,monitor_rule,...`: mango's own rule for that
// screen, read from its config (following source=), with only rr changed,
// so the scale and the rest stay (no rule: name and the scale mango reports).
// mango then re-applies its settings, like a reload without reading the
// files. Touch follows by itself: mango maps the touchscreen to the screen
// and wlroots turns touch points with that screen. The pen only does with a
// `device_rule=type:tablet,monitor:eDP-1` line in mango's config.
// A mango reload (the wallpaper's colors do one) puts the screen back the
// way its config says; the screen's orientation changing tells, and it's
// turned again. Never while the screen is off (screenOff, from Idle through
// shell.qml): mango wakes a sleeping screen when it applies a monitor_rule.
// It catches up when the screen comes back.
//
// MINE_ROTATE_SENSOR (tests): a command run with sh -c instead of
// monitor-sensor (same output). MINE_BINDS_CONFIG: another mango config, as
// the cheat sheet. MINE_ROTATE_OUTPUT: the screen to turn instead of eDP-*.
// MINE_ROTATE_DEBUG=1 logs every step.
Singleton {
    id: root

    readonly property string mode: Style.rotateScreen
    readonly property bool enabled: mode === "tablet" || mode === "always"
    readonly property bool active: mode === "always" || (mode === "tablet" && TabletMode.tablet)
    property bool locked: false
    readonly property bool listening: active && !locked

    readonly property bool debug: Quickshell.env("MINE_ROTATE_DEBUG") === "1"
    readonly property string sensorCommand: Quickshell.env("MINE_ROTATE_SENSOR") ?? ""
    readonly property string configPath: Quickshell.env("MINE_BINDS_CONFIG")
        || (Quickshell.env("HOME") + "/.config/mango/config.conf")

    // The sensor's last word: "normal", "left-up", "right-up", "bottom-up",
    // "undefined", or "" (not running / nothing yet).
    property string orientation: ""
    // false once it said there's no accelerometer.
    property bool sensorFound: true

    // Way up -> mango's rr (wl_output transform; 1 = 90°, 3 = 270°). With
    // wlroots' 90°, the top of the picture is along the panel's left edge (it
    // maps a touch at the panel's x, y to 1 - y, x), so left-up is 1.
    // If the screen turns the wrong way on a machine, swap 1 and 3.
    readonly property var transforms: ({ "normal": 0, "left-up": 1, "bottom-up": 2, "right-up": 3 })

    // The screen to turn: only the built-in one (eDP-*). None (docked with
    // the lid shut): nothing is turned. MINE_ROTATE_OUTPUT: another (tests).
    readonly property string outputName: Quickshell.env("MINE_ROTATE_OUTPUT") ?? ""
    readonly property var screen: Quickshell.screens.find(s => root.outputName !== "" ? s.name === root.outputName : s.name.startsWith("eDP")) ?? null
    readonly property string output: screen?.name ?? (outputName || "eDP")

    // How it's turned now, from the screen's orientation as Qt sees it (for a
    // screen that's wider than tall when normal); -1 = no such screen.
    readonly property int actual: !screen ? -1
        : screen.orientation === Qt.PortraitOrientation ? 1
        : screen.orientation === Qt.InvertedLandscapeOrientation ? 2
        : screen.orientation === Qt.InvertedPortraitOrientation ? 3 : 0

    // Idle has put the screen to sleep (shell.qml keeps this in step).
    property bool screenOff: false
    onScreenOffChanged: check.restart()

    // How it should be: -1 = not ours (left as it is).
    property int wanted: -1
    property int tries: 0
    property bool busy: false

    function log(...args) {
        if (debug)
            console.log("rotate:", ...args);
    }

    function lock() {
        locked = true;
    }
    function unlock() {
        locked = false;
    }
    function toggleLock() {
        locked = !locked;
    }

    // For `qs -c mine ipc call rotate status`.
    function status() {
        return JSON.stringify({
            mode: mode, active: active, locked: locked, listening: sensor.running,
            orientation: orientation, sensorFound: sensorFound, output: output,
            actual: actual, wanted: wanted, busy: busy
        });
    }

    // One line for Settings.
    readonly property string summary: !enabled ? ""
        : !sensorFound ? "No accelerometer found (iio-sensor-proxy)"
        : locked ? "Held as it is (control center → Auto-rotate)"
        : !active ? "Waits for tablet mode"
        : ["Now: normal", "Now: left edge up", "Now: upside down", "Now: right edge up"][Math.max(0, actual)]

    // ---- The sensor ----------------------------------------------------------------

    onListeningChanged: {
        log("listening", listening);
        orientation = "";
        hold.stop();
    }

    // Stopped: back to normal if it was turned, then left alone.
    onActiveChanged: {
        log("active", active);
        if (active)
            return;
        if (wanted > 0)
            turn(0);
        else
            wanted = -1;
    }

    Process {
        id: sensor
        running: root.listening
        command: root.sensorCommand !== "" ? ["sh", "-c", root.sensorCommand] : ["monitor-sensor", "--accel"]
        stdout: SplitParser {
            onRead: line => root.heard(line)
        }
        onExited: (code, status) => {
            // Not started again here (only when turning goes off and on).
            if (root.listening)
                console.warn("rotate: monitor-sensor stopped (exit " + code + "); is iio-sensor-proxy running?");
        }
    }

    // "=== Has accelerometer (orientation: normal, tilt: vertical)",
    // "    Accelerometer orientation changed: left-up", "=== No accelerometer".
    function heard(line) {
        const m = /orientation(?: changed)?: ([a-z-]+)/.exec(line);
        if (m) {
            sensorFound = true;
            orientation = m[1];
        } else if (/No accelerometer|Accelerometer disappeared/.test(line)) {
            sensorFound = false;
            orientation = "";
        } else if (/Accelerometer appeared/.test(line)) {
            sensorFound = true;
        }
    }

    onOrientationChanged: {
        if (orientation !== "")
            log("sensor", orientation);
        if (transforms[orientation] !== undefined)
            hold.restart();
        else
            hold.stop();
    }

    // It must stay that way up for a moment.
    Timer {
        id: hold
        interval: 500
        onTriggered: {
            if (root.listening && root.transforms[root.orientation] !== undefined)
                root.turn(root.transforms[root.orientation]);
        }
    }

    // ---- Turning -------------------------------------------------------------------

    function turn(rr) {
        log("turn to", rr, "now", actual);
        wanted = rr;
        tries = 0;
        settle();
    }

    // The screen is as wanted, or ask mango (a few tries at most, so a
    // screen that doesn't follow isn't asked forever).
    function settle() {
        if (busy || wanted < 0)
            return;
        if (actual === wanted) {
            tries = 0;
            // Back to normal after turning stopped: not ours any more.
            if (!active)
                wanted = -1;
            return;
        }
        if (screenOff || actual < 0) {
            log("screen", output, "is off or not there; later");
            return;
        }
        if (tries >= 3) {
            console.warn("rotate:", output, "stays at", actual, "after 3 tries for", wanted);
            return;
        }
        tries++;
        busy = true;
        query.running = true;
    }

    // Something turned it (a mango reload), or it came back on: look again
    // once things have settled.
    onActualChanged: {
        log("screen now", actual);
        check.restart();
    }

    Timer {
        id: check
        interval: 400
        onTriggered: root.settle()
    }

    // mango's monitors (scale) and its monitor_rule lines.
    Process {
        id: query
        command: ["sh", "-c", "mmsg get all-monitors | tr -d '\\n'; echo; sh \"$1\" \"$2\" 2>/dev/null | grep -E '^[[:space:]]*monitor_rule[[:space:]]*='",
            "sh", Quickshell.shellDir + "/scripts/mango-binds.sh", root.configPath]
        stdout: StdioCollector {
            onStreamFinished: root.send(text)
        }
    }

    function send(text) {
        const lines = text.split("\n");
        let mon = null;
        try {
            mon = (JSON.parse(lines[0]).monitors ?? []).find(m => m.name === output) ?? null;
        } catch (e) {}
        if (!mon) {
            console.warn("rotate: mango doesn't list", output);
            busy = false;
            return;
        }
        const rule = ruleFor(lines.slice(1), mon, wanted);
        log("setoption monitor_rule", rule);
        dispatch.command = ["mmsg", "dispatch", "setoption,monitor_rule," + rule];
        dispatch.running = true;
    }

    // mango's own rule for this screen with only rr changed: the last one
    // whose name matches, as mango picks when it re-applies them. None: the
    // name, and the scale and vrr / hdr mango reports.
    function ruleFor(lines, mon, rr) {
        let found = "";
        for (const l of lines) {
            const value = l.slice(l.indexOf("=") + 1).trim();
            const name = /(?:^|,)\s*name\s*:\s*([^,]*)/.exec(value);
            if (!name)
                continue;
            try {
                if (new RegExp(name[1].trim()).test(output))
                    found = value;
            } catch (e) {}
        }
        let fields = found !== ""
            ? found.split(",").map(f => f.trim()).filter(f => f !== "" && !/^rr\s*:/.test(f))
            : ["name:" + output, "scale:" + mon.scale].concat(mon.is_vrr ? ["vrr:1"] : [], mon.is_hdr ? ["hdr:1"] : []);
        return fields.concat(["rr:" + rr]).join(",");
    }

    Process {
        id: dispatch
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.indexOf("success") < 0)
                    console.warn("rotate: mango said", text.trim());
            }
        }
        onExited: {
            root.busy = false;
            check.restart();
        }
    }

    // A restart while turned (or turning switched off while the shell was
    // away): back to normal once tablet mode is known, if it isn't on now.
    Connections {
        target: TabletMode
        function onKnownChanged() {
            if (TabletMode.known && root.enabled && !root.active && root.actual > 0) {
                root.log("turned at start; back to normal");
                root.turn(0);
            }
        }
    }
}
