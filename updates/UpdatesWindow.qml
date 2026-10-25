import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The updates panel's window on the screen it was opened on. It covers the
// whole screen (see-through) so a click outside closes it (a click on the
// item too), and takes the keyboard while open: Esc closes. While the
// password dialog is up (pkexec, from Update) it lets go of the keyboard
// and the clicks, so the dialog gets them. shell.qml creates it only while
// needed (UpdatesState.mapped).
PanelWindow {
    id: root

    required property ShellScreen modelData
    // Once the new window has settled (Settle), so the opening animation
    // doesn't jump over its slow first frames.
    readonly property bool ready: settle.settled
    Settle { id: settle }

    readonly property bool taking: UpdatesState.open && !UpdatesState.passwordUp

    Component.onCompleted: {
        panel.focusKeys();
    }

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "mine-updates"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.taking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open the whole screen takes clicks (outside = close); while
    // shrinking back, or while the password dialog is up, clicks go past.
    mask: root.taking ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: UpdatesState.close()
    }

    UpdatesPanel {
        id: panel
        anchors.fill: parent
        from: UpdatesState.from
        open: root.ready && UpdatesState.open
        onCloseRequested: UpdatesState.close()
        // Back in the item: the window can go.
        onSettledChanged: if (settled && root.ready) UpdatesState.settled()
    }
}
