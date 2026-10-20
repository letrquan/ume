import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The volume popup's window on the screen it was opened on. It covers the
// whole screen (see-through) so a click outside closes it (a click on the
// speaker icon too), and takes the keyboard while open: Esc closes, the
// arrows change the volume, M mutes. Scrolling on the speaker icon still
// changes the volume. shell.qml creates it only while needed
// (VolumeState.mapped).
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

    WlrLayershell.namespace: "mine-volume"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: VolumeState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open the whole screen takes clicks (outside = close); while
    // shrinking back, clicks already go to your windows.
    mask: VolumeState.open ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: VolumeState.close()
        // Over the speaker icon (under this window now): still the volume.
        onWheel: wheel => {
            const r = VolumeState.from;
            if (wheel.x >= r.x && wheel.x <= r.x + r.width && wheel.y >= r.y && wheel.y <= r.y + r.height)
                popup.step((wheel.angleDelta.y || -wheel.angleDelta.x) / 120);
        }
    }

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: VolumeState.close()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Right) {
                popup.step(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Left) {
                popup.step(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_M) {
                ControlState.toggleMute(popup.sink);
                event.accepted = true;
            }
        }
    }

    VolumePopup {
        id: popup
        anchors.fill: parent
        from: VolumeState.from
        open: root.ready && VolumeState.open
        // Back in the icon: the window can go.
        onSettledChanged: if (settled && root.ready) VolumeState.settled()
    }
}
