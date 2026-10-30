import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// "Take a break" (services/Breaks.qml): the screen goes to the blurred,
// dimmed wallpaper with a countdown in the middle, so there's nothing to
// keep working on. Skip (or Esc) ends it early (the reminder comes back
// after Style.breakSnooze min). It's done when you come back after the
// countdown, or when the countdown ends while you're still there.
// shell.qml creates it on every screen, only while a break is on.
PanelWindow {
    id: root

    required property ShellScreen modelData
    readonly property bool ready: settle.settled
    Settle { id: settle }

    readonly property bool shown: ready && Breaks.showing
    // The keyboard goes to the first screen's window only (one Esc).
    readonly property bool first: Quickshell.screens.length === 0 || Quickshell.screens[0] === modelData

    Component.onCompleted: keys.forceActiveFocus()

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // Proposed for mango's no_blur list next to mine-session (the blur here
    // is the shell's own Backdrop, so it can fade).
    WlrLayershell.namespace: "mine-break"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Breaks.showing && root.first ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Clicks outside the card do nothing (it's a break).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: Breaks.skipBreak()
    }

    Backdrop {
        anchors.fill: parent
        shown: root.shown
        dim: Style.breakDim
    }

    BreakView {
        anchors.centerIn: parent
        open: root.shown
    }
}
