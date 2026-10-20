import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The launcher window on one screen. It covers the whole screen (see-
// through) so a click anywhere outside the launcher closes it, and takes
// the keyboard so you can type right away. shell.qml creates it only while
// the launcher is open (LauncherState.mapped).
PanelWindow {
    id: root

    required property ShellScreen modelData
    // Once the new window has settled (Settle), so the opening animation
    // doesn't jump over its slow first frames.
    readonly property bool ready: settle.settled
    Settle { id: settle }

    Component.onCompleted: {
        view.focusSearch();
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

    WlrLayershell.namespace: "mine-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: LauncherState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open, the whole screen takes clicks (outside the launcher =
    // close); while shrinking back, clicks already go to your windows.
    mask: LauncherState.open ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: LauncherState.close()
    }

    LauncherView {
        id: view

        anchors.fill: parent
        startWidth: IslandState.centerWidth
        open: root.ready && LauncherState.open
        onCloseRequested: LauncherState.close()
        onCoveringChanged: IslandState.launcherCovering = covering
        // Back in the island: the window can go.
        onSettledChanged: if (settled && root.ready) LauncherState.settled()
    }

    // If this window goes away early, give the bar its island back.
    Component.onDestruction: IslandState.launcherCovering = false
}
