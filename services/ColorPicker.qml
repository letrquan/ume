pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Pick a color anywhere on the screen (hyprpicker: the screen freezes, a
// zoom lens follows the pointer, click takes the color, Esc cancels).
// The hex (#a1b2c3) is copied to the clipboard and a notification shows it
// with a swatch (scripts/color-notify.sh; "Copy as rgb()" copies it that
// way instead).
//
// MINE_PICKER_DRYRUN=1 (tests): nothing is copied or notified, only printed.
// MINE_PICKER_CMD (tests): a shell command whose output stands in for
// hyprpicker's.
Singleton {
    id: root

    property bool picking: false
    property string last: ""            // the last color picked, "#a1b2c3"

    readonly property bool dryRun: Quickshell.env("MINE_PICKER_DRYRUN") === "1"
    readonly property string fakeCommand: Quickshell.env("MINE_PICKER_CMD") ?? ""

    function pick() {
        if (picking)
            return;
        picking = true;
        proc.running = true;
    }

    // "#A1B2C3\n" (maybe with color codes around it) -> "#a1b2c3"; "" when
    // nothing was picked (Esc).
    function parse(text) {
        const m = (text ?? "").match(/#([0-9a-fA-F]{6})\b/);
        return m ? "#" + m[1].toLowerCase() : "";
    }

    function rgbOf(hex) {
        const n = parseInt(hex.slice(1), 16);
        return "rgb(" + ((n >> 16) & 255) + ", " + ((n >> 8) & 255) + ", " + (n & 255) + ")";
    }

    function got(text) {
        const hex = parse(text);
        if (hex === "") {
            console.log("color picker: nothing picked");
            return;
        }
        last = hex;
        const rgb = rgbOf(hex);
        // The live activity shows the swatch; then the notification (with
        // "Copy as rgb()") only goes to the list.
        const said = Activities.color(hex, rgb);
        if (dryRun)
            console.log("color picker (dry run): copy", hex, "· notify", rgb, said ? "(quiet)" : "");
        else {
            Quickshell.execDetached(["wl-copy", "--", hex]);
            Quickshell.execDetached(["sh", Quickshell.shellDir + "/scripts/color-notify.sh", hex, rgb, said ? "quiet" : ""]);
        }
        picked(hex);
    }

    signal picked(string hex)

    Process {
        id: proc
        command: root.fakeCommand !== "" ? ["sh", "-c", root.fakeCommand]
                                         : ["hyprpicker", "--format=hex", "--no-fancy", "--quiet"]
        stdout: StdioCollector {
            onStreamFinished: root.got(text)
        }
        onExited: root.picking = false
    }
}
