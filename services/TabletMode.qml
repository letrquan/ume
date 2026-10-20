pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Whether the screen is folded back into a tablet, for the on-screen
// keyboard (OskState) and turning the screen (AutoRotate). Also what the
// laptop's own keyboard does in tablet mode (Style.tabletKeepKeyboard).
//
// mango runs `mine osk fold` / `mine osk unfold` when a switch turns on /
// off (switchbind). `mine` drops a fold with the lid shut, writes the answer
// to $XDG_RUNTIME_DIR/mine-tablet ("1" or "0") and calls OskState.fold() /
// unfold(), which set it here. That file is read 3 s after start (a shell
// that starts, or restarts, folded) and for `mine osk tablet`; no file is a
// laptop. hp-wmi's /sys/devices/platform/hp-wmi/tablet isn't used: it stays
// 0 on this laptop even folded.
//
// MINE_TABLET_STATE_FILE (tests): another file instead of mine-tablet.
// MINE_LIBINPUT_QUIRKS: another file instead of libinput's local quirks.
Singleton {
    id: root

    // 1 tablet, 0 laptop.
    property int state: 0
    readonly property bool tablet: state === 1
    // Read the file, or had a fold / unfold, since start.
    property bool known: false

    // After reading the file (asked: for `mine osk tablet`, not at start).
    signal fileRead(int state, bool asked)

    readonly property string path: Quickshell.env("MINE_TABLET_STATE_FILE")
        || (Quickshell.env("XDG_RUNTIME_DIR") ?? "/tmp") + "/mine-tablet"

    function fold() {
        state = 1;
        known = true;
    }
    function unfold() {
        state = 0;
        known = true;
    }

    property bool asked: false
    function reread() {
        asked = true;
        read();
    }
    function read() {
        if (file.path === "")
            file.path = path;    // the first read
        else
            file.reload();
    }
    function took(text) {
        const v = text.trim() === "1" ? 1 : 0;
        state = v;
        known = true;
        const a = asked;
        asked = false;
        fileRead(v, a);
    }

    FileView {
        id: file
        printErrors: false
        onLoaded: root.took(text())
        // No file yet: no fold since login.
        onLoadFailed: root.took("0")
    }

    Timer {
        running: true
        interval: 3000
        onTriggered: root.read()
    }

    // ---- The laptop's own keyboard in tablet mode -------------------------------

    // libinput turns the keyboard and touchpad off while a tablet-mode switch
    // is on, unless a quirk says not to: scripts/tablet-keyboard.sh puts one
    // for this laptop in /etc/libinput/local-overrides.quirks (with sudo; the
    // shell can't). That file is the truth here, not the knob: read when
    // Settings opens and after Copy (every 3 s for a minute, until it says
    // what the knob wants).
    readonly property string quirksPath: Quickshell.env("MINE_LIBINPUT_QUIRKS") || "/etc/libinput/local-overrides.quirks"
    readonly property string keyboardScript: Quickshell.shellDir + "/scripts/tablet-keyboard.sh"
    // "on", "off", or "" (not read yet).
    property string keyboardQuirk: ""
    // The marker line the script writes (keep in step with it).
    readonly property string quirkMarker: "# >>> mine shell: tablet keyboard (scripts/tablet-keyboard.sh) >>>"

    readonly property string keyboardCommand: "sudo sh " + keyboardScript + (Style.tabletKeepKeyboard ? " on" : " off")
    readonly property bool keyboardSetUp: keyboardQuirk === (Style.tabletKeepKeyboard ? "on" : "off")

    function readKeyboard() {
        if (quirks.path === "")
            quirks.path = quirksPath;
        else
            quirks.reload();
    }

    function copyKeyboardCommand() {
        Quickshell.execDetached(["wl-copy", "--", keyboardCommand]);
        recheck.left = 20;
        recheck.restart();
    }

    FileView {
        id: quirks
        printErrors: false
        onLoaded: root.keyboardQuirk = text().split("\n").includes(root.quirkMarker) ? "on" : "off"
        onLoadFailed: root.keyboardQuirk = "off"
    }

    Timer {
        id: recheck
        property int left: 0
        interval: 3000
        onTriggered: {
            root.readKeyboard();
            left--;
            if (left > 0 && !root.keyboardSetUp)
                restart();
        }
    }

    Connections {
        target: SettingsState
        function onOpenChanged() {
            if (SettingsState.open)
                root.readKeyboard();
        }
    }
}
