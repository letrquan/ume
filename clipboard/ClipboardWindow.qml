import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The clipboard window on one screen. It covers the whole screen (see-
// through) so a click outside closes it, and takes the keyboard while open
// so you can type right away. shell.qml creates it only while open
// (ClipboardState.mapped).
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

    WlrLayershell.namespace: "mine-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: ClipboardState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open the whole screen takes clicks (outside = close); while
    // shrinking back, clicks already go to your windows.
    mask: ClipboardState.open ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: ClipboardState.close()
    }

    ClipboardView {
        id: view

        anchors.fill: parent
        startWidth: IslandState.centerWidth
        open: root.ready && ClipboardState.open
        onCloseRequested: ClipboardState.close()
        onCoveringChanged: IslandState.clipboardCovering = covering
        // Back in the island: the window can go.
        onSettledChanged: if (settled && root.ready) ClipboardState.settled()
    }

    // If this window goes away early, give the bar its island back.
    Component.onDestruction: IslandState.clipboardCovering = false
}
