pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The music visualizer's levels: cava listens to what the speakers play and
// gives Style.visualizerBars numbers (0-1) Style.visualizerFps times a
// second (20; the bar draws again for each, so this is most of its cost).
// cava only runs while something is playing AND a visualizer is on screen
// (bar/MusicBars.qml counts itself in with use()); otherwise it isn't
// running at all, so it costs nothing when the music stops.
//
// Its settings go to $XDG_RUNTIME_DIR/mine-shell/cava.conf (written fresh
// each start, so changing the number of bars or the frame rate just
// restarts it).
//
// MINE_VISUALIZER_CMD (tests): a shell command that prints cava-like lines
// ("12;40;99;...;", 0-100) instead of running cava; it gets the frame rate
// as $1.
Singleton {
    id: root

    // Visualizers on screen right now.
    property int users: 0
    function use(delta) {
        users = Math.max(0, users + delta);
    }

    readonly property bool playing: Players.anyPlaying
    readonly property bool active: Style.showVisualizer && playing && users > 0
    readonly property int bars: Math.max(2, Math.min(24, Style.visualizerBars))
    readonly property int fps: Math.max(5, Math.min(60, Style.visualizerFps))
    // cava smooths per frame, so fewer frames make the bars lazier (at 20
    // fps they rose and fell about a quarter slower than at 30): its noise
    // reduction (77 by default) is scaled so they move as fast, in seconds,
    // as they did at 30 (20 fps: 68, 15 fps: 59).
    readonly property int smoothing: Math.round(100 * Math.pow(0.77, 30 / fps))

    // One number per bar, 0-1. All zero while not running.
    property var levels: []
    function clear() {
        levels = new Array(bars).fill(0);
    }

    readonly property string testCmd: Quickshell.env("MINE_VISUALIZER_CMD") ?? ""
    readonly property string confDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/mine-shell"
    // ascii output 0-100, ';' between bars, one line per frame; mono so the
    // bars go low to high once instead of mirrored.
    readonly property string conf: [
        "[general]",
        "bars = " + bars,
        "framerate = " + fps,
        "autosens = 1",
        "[smoothing]",
        "noise_reduction = " + smoothing,
        "[input]",
        "method = pipewire",
        "source = auto",
        "[output]",
        "method = raw",
        "raw_target = /dev/stdout",
        "data_format = ascii",
        "ascii_max_range = 100",
        "bar_delimiter = 59",
        "frame_delimiter = 10",
        "channels = mono",
        "mono_option = average",
        ""
    ].join("\n")

    // Restart quietly when the bar count or frame rate changes while running.
    onConfChanged: if (cava.running) {
        cava.running = false;
        Qt.callLater(() => cava.running = root.active);
    }
    onActiveChanged: {
        failures = 0;
        cava.running = active;
        if (!active)
            clear();
    }
    onBarsChanged: clear()
    Component.onCompleted: clear()

    // cava missing or broken: give up after a few quick tries (until the
    // music starts again).
    property int failures: 0

    Process {
        id: cava
        command: root.testCmd !== ""
            ? ["sh", "-c", root.testCmd, "sh", String(root.fps)]
            : ["sh", "-c", "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$1/cava.conf\" && exec cava -p \"$1/cava.conf\"",
               "sh", root.confDir, root.conf]

        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(";").filter(s => s !== "");
                if (parts.length !== root.bars)
                    return;
                root.failures = 0;
                root.levels = parts.map(s => Math.max(0, Math.min(1, Number(s) / 100)));
            }
        }

        onExited: code => {
            if (!root.active)
                return;
            root.failures++;
            if (root.failures >= 3) {
                console.warn("visualizer: cava keeps stopping (exit " + code + "), giving up until the music starts again");
                root.clear();
            } else {
                retry.restart();
            }
        }
    }

    Timer {
        id: retry
        interval: 2000
        onTriggered: if (root.active && !cava.running) cava.running = true
    }
}
