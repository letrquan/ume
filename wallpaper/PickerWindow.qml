import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The wallpaper picker on one screen: it grows out of the middle island and
// shrinks back into it (MorphCard, like the launcher and the clipboard), so
// its glass and mango's blur behind it come and go with the island's
// instead of a blurred box popping in and lingering. The window covers the
// screen (see-through) so a click outside closes it, and takes the keyboard
// while open. shell.qml creates it only while open (Wallpaper.pickerMapped);
// it never comes back open after a restart.
PanelWindow {
    id: root

    required property ShellScreen modelData
    // Once the new window has settled (Settle), so the opening animation
    // doesn't jump over its slow first frames.
    readonly property bool ready: settle.settled
    Settle { id: settle }

    Component.onCompleted: {
        panel.focusGrid();
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

    WlrLayershell.namespace: "mine-wallpaper-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Wallpaper.pickerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open the whole screen takes clicks (outside = close); while
    // shrinking back, clicks already go to your windows.
    mask: Wallpaper.pickerOpen ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: Wallpaper.setPicker(false)
    }

    MorphCard {
        id: morph

        anchors.fill: parent
        fromX: (width - IslandState.centerWidth) / 2
        fromY: Style.marginEdge
        fromWidth: IslandState.centerWidth
        toWidth: panel.implicitWidth
        toHeight: panel.implicitHeight
        radius: Style.launcherRadius
        glassOpacity: Style.launcherOpacity
        open: root.ready && Wallpaper.pickerOpen
        onCoveringChanged: IslandState.pickerCovering = covering
        // Back in the island: the window can go.
        onSettledChanged: if (settled && root.ready) Wallpaper.pickerSettled()

        PickerPanel {
            id: panel
            onCloseRequested: Wallpaper.setPicker(false)
        }
    }

    // If this window goes away early, give the bar its island back.
    Component.onDestruction: IslandState.pickerCovering = false
}
