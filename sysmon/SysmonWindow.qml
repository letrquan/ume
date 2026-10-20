import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The System popup's window on one screen. It covers the whole screen
// (see-through) so a click anywhere outside the popup closes it, and takes
// the keyboard while open (Esc, C / M). shell.qml creates it only while the
// popup is open (SysmonState.mapped).
PanelWindow {
    id: root

    required property ShellScreen modelData
    // Once the new window has settled (Settle), so the opening animation
    // doesn't jump over its slow first frames.
    readonly property bool ready: settle.settled
    Settle { id: settle }

    Component.onCompleted: {
        view.focusKeys();
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

    WlrLayershell.namespace: "mine-sysmon"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: SysmonState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open, the whole screen takes clicks (outside the popup =
    // close); while shrinking back, clicks already go to your windows.
    mask: SysmonState.open ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: SysmonState.close()
    }

    SysmonView {
        id: view

        anchors.fill: parent
        island: SysmonState.island
        startWidth: SysmonState.island === "left" ? IslandState.leftWidth
                  : SysmonState.island === "center" ? IslandState.centerWidth
                  : IslandState.rightWidth
        open: root.ready && SysmonState.open
        onCloseRequested: SysmonState.close()
        onCoveringChanged: {
            IslandState.sysmonIsland = SysmonState.island;
            IslandState.sysmonCovering = covering;
        }
        // Back in the island: the window can go.
        onSettledChanged: if (settled && root.ready) SysmonState.settled()
    }

    // If this window goes away early, give the bar its island back.
    Component.onDestruction: IslandState.sysmonCovering = false
}
