import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "../services/netqr.js" as NetQr

// A QR code of `text`, black on white with a quiet border (phones need
// both, also in dark mode). qrencode gets the text on its stdin (never on
// its command line, where other programs could read it) and only hands back
// which squares are dark; they're drawn here, so nothing is written to disk.
// Clearing `text` (or closing what holds this) drops the code.
// MINE_QRENCODE: the qrencode to run (tests).
Item {
    id: root

    property string text: ""
    property var modules: []            // rows of booleans
    readonly property int count: modules.length
    readonly property bool ready: count > 0
    property bool failed: false

    implicitWidth: 220
    implicitHeight: 220

    onTextChanged: make()
    Component.onCompleted: make()
    Component.onDestruction: modules = []

    function make() {
        modules = [];
        failed = false;
        encoder.pending = text;
        if (text === "")
            return;
        if (encoder.running) {
            encoder.again = true;
            return;
        }
        encoder.stdinEnabled = true;
        encoder.running = true;
    }

    Process {
        id: encoder

        property string pending: ""
        property bool again: false

        // (Through sh: a missing qrencode is an exit code, so "failed" shows.)
        command: ["sh", "-c", 'exec "$@"', "sh", Quickshell.env("MINE_QRENCODE") || "qrencode", "-t", "ASCII", "-m", "0", "-l", "M"]
        onStarted: {
            // Exactly the text: a line break would end up in the code.
            write(pending);
            pending = "";
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (encoder.again)
                    return;
                const m = root.text !== "" ? NetQr.parseAscii(text) : [];
                root.modules = m;
                root.failed = root.text !== "" && m.length === 0;
            }
        }
        onExited: {
            if (again) {
                again = false;
                Qt.callLater(root.make);
            }
        }
    }

    // White card with at least four squares of white around the code.
    Rectangle {
        anchors.fill: parent
        radius: Math.min(16, width / 12)
        color: "white"
    }

    Item {
        id: code
        readonly property int cell: root.count > 0 ? Math.max(1, Math.floor(Math.min(root.width, root.height) / (root.count + 8))) : 1
        anchors.centerIn: parent
        width: cell * root.count
        height: width
        visible: root.ready

        Repeater {
            model: root.ready ? NetQr.runs(root.modules) : []

            Rectangle {
                required property var modelData
                x: modelData.x * code.cell
                y: modelData.y * code.cell
                width: modelData.w * code.cell
                height: code.cell
                color: "black"
                antialiasing: false
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        width: parent.width - 32
        visible: !root.ready
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.failed ? "Couldn't make the code (is qrencode installed?)" : root.text === "" ? "" : "…"
        role: "caption"
        color: "#555555"
    }
}
