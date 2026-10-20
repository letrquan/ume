import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The control center window on one screen. It covers the whole screen
// (see-through) so a click outside closes it, and takes the keyboard while
// open (Esc: back, then close; the Wi-Fi password field). shell.qml creates
// it only while open (ControlState.mapped).
PanelWindow {
    id: root

    required property ShellScreen modelData
    // Once the new window has settled (Settle), so the opening animation
    // doesn't jump over its slow first frames.
    readonly property bool ready: settle.settled
    Settle { id: settle }

    Component.onCompleted: {
        keys.forceActiveFocus();
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

    WlrLayershell.namespace: "mine-control-center"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: ControlState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open the whole screen takes clicks (outside = close); while
    // shrinking back, clicks already go to your windows.
    mask: ControlState.open ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: ControlState.close()
    }

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: {
            if (ControlState.page !== "main")
                ControlState.page = "main";
            else
                ControlState.close();
        }
    }

    ControlView {
        anchors.fill: parent
        startWidth: IslandState.rightWidth
        open: root.ready && ControlState.open
        onCoveringChanged: IslandState.controlCovering = covering
        // Back in the island: the window can go.
        onSettledChanged: if (settled && root.ready) ControlState.settled()
    }

    // If this window goes away early, give the bar its island back.
    Component.onDestruction: IslandState.controlCovering = false
}
