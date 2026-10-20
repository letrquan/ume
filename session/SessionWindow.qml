import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The power menu window. One window (on the screen mango picks, the focused
// one), covering it so a click outside the card closes the menu, and taking
// the keyboard only while open. shell.qml creates it only while the menu is
// open (SessionState.mapped).
PanelWindow {
    id: root

    // Once the new window has settled (Settle), so the opening animation
    // doesn't jump over its slow first frames.
    readonly property bool ready: settle.settled
    Settle { id: settle }

    Component.onCompleted: {
        view.forceActiveFocus();
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
    WlrLayershell.namespace: "mine-session"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: SessionState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open the whole screen takes clicks (outside the card = close);
    // while it fades out, clicks already reach your windows.
    mask: SessionState.open ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: SessionState.close()
    }

    SessionView {
        id: view
        anchors.fill: parent
        open: root.ready && SessionState.open
        onCloseRequested: SessionState.close()
    }
}
