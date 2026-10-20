import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The cheat sheet window (Super+/). One window, on the screen mango picks
// (the focused one), covering it so a click outside the card closes it, and
// taking the keyboard only while open, so you can type to search right
// away. shell.qml creates it only while open (CheatSheetState.mapped).
PanelWindow {
    id: root

    // Once the new window has settled (Settle), so the opening animation
    // doesn't jump over its slow first frames.
    readonly property bool ready: settle.settled
    Settle { id: settle }

    Component.onCompleted: {
        view.focusSearch();
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // On mango's no_blur list (~/.config/mango/shell.conf): the blurred,
    // dimmed screen behind the card is the shell's own (common/Backdrop.qml),
    // so it fades in and out instead of popping.
    WlrLayershell.namespace: "mine-cheatsheet"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: CheatSheetState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open the whole screen takes clicks (outside the card = close);
    // while it fades out, clicks already reach your windows.
    mask: CheatSheetState.open ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: CheatSheetState.close()
    }

    CheatSheetView {
        id: view
        anchors.fill: parent
        open: root.ready && CheatSheetState.open
        onCloseRequested: CheatSheetState.close()
    }
}
