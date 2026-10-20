import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The list panel on one screen. The window covers the whole screen (see-
// through) so a click anywhere outside the panel closes it; Escape too.
// shell.qml creates it only while open (Notifs.centerMapped), and it never
// comes back open after a reload or restart.
PanelWindow {
    id: root

    required property ShellScreen modelData
    // Once the new window has settled (Settle), so the entry animation
    // doesn't jump over its slow first frames.
    readonly property bool open: settle.settled
    Settle { id: settle }
    readonly property bool shown: open && Notifs.centerOpen


    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "mine-notification-center"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // A click outside the panel closes it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: Notifs.setCenter(false)
    }

    CenterPanel {
        id: panel

        x: parent.width - width - Style.marginEnds
        y: Style.marginEdge + Style.islandHeight + Style.osdGap
        maxHeight: root.height * 0.75
        focus: true
        Keys.onEscapePressed: Notifs.setCenter(false)

        transformOrigin: Item.TopRight
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.94
        transform: Translate {
            y: root.shown ? 0 : -10
            Behavior on y {
                NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
        }
    }
}
