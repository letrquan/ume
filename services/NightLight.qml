pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Night light: warmer screen colors, done by wlsunset
// (sudo pacman -S wlsunset). Style.nightLightMode:
//   "off"
//   "on"        warm all the time
//   "schedule"  warm at night: sunset to sunrise at the weather place
//               (Style.nightLightUseLocation), or from Style.nightLightFrom
//               to Style.nightLightTo; it fades in and out
// wlsunset runs as the shell's child only while it's needed. The normal
// colors come back when it stops (also when the shell stops).
//
// The control center tile turns it off and on (back to the last mode);
// right-click switches between "all the time" and "at night".
// MINE_NIGHT_DRYRUN=1 (tests): prints the command instead of running it.
Singleton {
    id: root

    readonly property string mode: Style.nightLightMode
    readonly property bool isOn: mode !== "off"
    readonly property bool dryRun: Quickshell.env("MINE_NIGHT_DRYRUN") === "1"
    // wlsunset is installed (looked up at start and when you turn it on).
    property bool available: false

    // For the tile.
    readonly property string detail: !available ? "Install wlsunset"
        : mode === "on" ? "On"
        : mode === "schedule" ? (Style.nightLightUseLocation ? "Sunset to sunrise" : Style.nightLightFrom + " – " + Style.nightLightTo)
        : "Off"

    // The last mode that wasn't "off", for turning it back on.
    property string lastOn: mode !== "off" ? mode : "on"
    onModeChanged: if (mode !== "off") lastOn = mode

    function setMode(m) {
        if (m === "off" || m === "on" || m === "schedule")
            Settings.set("nightLightMode", m);
    }
    function toggle() {
        if (!available) {
            check.running = true;
            return;
        }
        setMode(isOn ? "off" : lastOn);
    }
    // Right-click on the tile: all the time <-> at night (and on).
    function cycle() {
        if (!available) {
            check.running = true;
            return;
        }
        setMode(mode === "on" ? "schedule" : "on");
    }

    // wlsunset -t <night temp> -T <day temp> and when.
    readonly property var command: {
        const t = Math.round(Style.nightLightTemp);
        const where = ["-l", String(Style.weatherLatitude), "-L", String(Style.weatherLongitude)];
        if (mode === "on")
            // Day and night (almost) the same warm color = warm all the time.
            return ["wlsunset", "-t", String(t), "-T", String(t + 1)].concat(where);
        if (Style.nightLightUseLocation)
            return ["wlsunset", "-t", String(t), "-T", "6500"].concat(where);
        return ["wlsunset", "-t", String(t), "-T", "6500",
                "-s", root.clockTime(Style.nightLightFrom, "20:00"),
                "-S", root.clockTime(Style.nightLightTo, "07:00")];
    }
    readonly property bool wanted: isOn && available

    // "7:5" / "07:05" -> "07:05"; anything else -> the fallback.
    function clockTime(text, fallback) {
        const m = /^\s*(\d{1,2})[:.h](\d{2})\s*$/.exec(text ?? "");
        if (!m || +m[1] > 23 || +m[2] > 59)
            return fallback;
        return (m[1].length === 1 ? "0" : "") + m[1] + ":" + m[2];
    }

    // Any change: stop wlsunset, start it again with the new command a
    // moment later (a slider sends many changes).
    property bool restarting: false
    onCommandChanged: apply.restart()
    onWantedChanged: {
        crashes = 0;
        apply.restart();
    }

    Timer {
        id: apply
        interval: 400
        onTriggered: {
            if (root.dryRun) {
                console.log("nightlight (dry run):", root.wanted ? JSON.stringify(root.command) : "off");
                return;
            }
            if (sunset.running) {
                // Started again (if still wanted) once it has really gone.
                root.restarting = true;
                sunset.running = false;
                return;
            }
            if (root.wanted) {
                sunset.command = root.command;
                sunset.running = true;
            }
        }
    }

    Process {
        id: sunset
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn("nightlight: wlsunset:", text.trim())
        }
        onExited: (code, status) => {
            if (root.restarting) {
                root.restarting = false;
                apply.restart();      // stopped for a change: start the new one
            } else if (root.wanted) {
                // Died by itself (e.g. a screen came and went): start it
                // again, a few times at most, each wait longer.
                root.crashes++;
                console.warn("nightlight: wlsunset stopped by itself (exit", code + ")",
                             root.crashes <= 5 ? "- starting it again" : "- giving up");
                if (root.crashes <= 5) {
                    revive.interval = 2000 * root.crashes;
                    revive.restart();
                }
            }
        }
    }
    property int crashes: 0
    Timer {
        id: revive
        onTriggered: if (root.wanted && !sunset.running) apply.restart()
    }

    // Is wlsunset there?
    Process {
        id: check
        running: true
        command: ["sh", "-c", "command -v wlsunset"]
        onExited: code => root.available = code === 0
    }
}
