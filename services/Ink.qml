pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Drawing on the screen with the pen, to explain or present: a see-through
// window over everything on each screen (ink/InkWindow.qml, only while
// it's on) and a small glass toolbar you can drag: pen (with the stylus's
// pressure), highlighter, laser pointer, eraser, six colors, three sizes,
// undo / redo, clear, pass-through, a screenshot with the ink, exit.
//   pass-through  the ink stays on screen but the mouse, the pen and the
//                 keyboard go to the apps under it; only the toolbar still
//                 takes clicks (click its arrow again to draw on)
//   screenshot    the toolbar hides for a moment, then the screen it's on is
//                 saved with the ink, like Ctrl+Print (services/Screenshot.qml:
//                 copied, the notification with Edit)
// Touch draws too only with Style.inkTouch (a palm on the screen would draw
// while you write); Style.inkFadeSeconds: strokes fade away after that long.
// Esc or the toolbar's × ends it, and the ink goes with it.
// qs -c mine ipc call ink toggle | open | close | clear | undo | passthrough | save
//
// MINE_INK_DRYRUN=1 (tests): the screenshot's command is only printed.
Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("MINE_INK_DRYRUN") === "1"

    property bool open: false
    property bool passThrough: false
    property string tool: "pen"             // pen | highlighter | laser | eraser
    property int colorIndex: 0
    property int sizeIndex: 1
    readonly property var colors: ["#ff453a", "#ffd60a", "#30d158", "#0a84ff", "#ffffff", "#1c1c1e"]
    readonly property var colorNames: ["Red", "Yellow", "Green", "Blue", "White", "Black"]
    readonly property var widths: [3, 5, 9]
    readonly property color color: colors[colorIndex]
    readonly property real lineWidth: widths[sizeIndex]

    // The screen the toolbar is on (the focused one when it opened; then
    // wherever you last drew), and where on it (x < 0: its first place).
    property string toolbarScreen: ""
    property point toolbarPos: Qt.point(-1, -1)
    // The toolbar is hidden for the screenshot.
    property bool capturing: false

    // To the windows: "clear" (all of them), "undo" / "redo" (the toolbar's).
    signal command(string what)

    function show() {
        if (open)
            return;
        passThrough = false;
        tool = "pen";
        toolbarPos = Qt.point(-1, -1);
        toolbarScreen = Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
        focused.running = true;
        open = true;
    }
    function close() {
        open = false;
        passThrough = false;
        capturing = false;
    }
    function toggle() {
        if (open)
            close();
        else
            show();
    }
    function clear() {
        command("clear");
    }
    function undo() {
        command("undo");
    }
    function redo() {
        command("redo");
    }
    function togglePassThrough() {
        if (open)
            passThrough = !passThrough;
    }
    function setTool(t) {
        tool = t;
        // Picking a tool means drawing again.
        passThrough = false;
    }
    function cycleSize(step) {
        sizeIndex = Math.max(0, Math.min(widths.length - 1, sizeIndex + step));
    }

    // Which screen has the focus (mango): the toolbar starts there.
    Process {
        id: focused
        command: ["mmsg", "get", "all-monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text).monitors ?? [];
                    const m = list.find(o => o.active);
                    if (m && Quickshell.screens.some(s => s.name === m.name))
                        root.toolbarScreen = m.name;
                } catch (e) {}
            }
        }
    }

    // ---- The screenshot with the ink ----------------------------------------------------------
    function save() {
        if (!open || capturing || Screenshot.active || Screenshot.busy)
            return;
        capturing = true;
        // A few frames, so the toolbar is really gone from the screen.
        shootSoon.restart();
    }
    Timer {
        id: shootSoon
        interval: 180
        onTriggered: {
            const out = Screenshot.target();
            const cmd = ["grim", "-o", root.toolbarScreen, out];
            if (root.dryRun) {
                console.log("ink (dry run): screenshot", JSON.stringify(cmd));
                root.capturing = false;
                return;
            }
            Screenshot.save(cmd, out);
            backSoon.restart();
        }
    }
    // Back once it's saved (or a moment later in any case: saving failed).
    Connections {
        target: Screenshot
        function onDone(file) {
            root.capturing = false;
        }
    }
    Timer {
        id: backSoon
        interval: 2500
        onTriggered: root.capturing = false
    }
}
