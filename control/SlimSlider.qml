import QtQuick
import qs.common

// A thin slider like macOS menus have: a slim track, the filled part in the
// accent color, a round knob. Drag, click anywhere, or scroll.
Item {
    id: root

    property real value: 0              // 0-1, from the system
    property bool muted: false

    signal moved(real value)

    // While dragging, show where the finger is, not the system's echo.
    property bool dragging: false
    property real dragValue: 0
    readonly property real shown: Math.max(0, Math.min(1, dragging ? dragValue : value))

    readonly property real knobSize: 16
    implicitHeight: 24

    function valueAt(x) {
        return Math.max(0, Math.min(1, (x - knobSize / 2) / (width - knobSize)));
    }

    // The track and its filled part.
    Rectangle {
        id: track
        x: root.knobSize / 2 - 2
        width: root.width - root.knobSize + 4
        height: 4
        anchors.verticalCenter: parent.verticalCenter
        radius: 2
        color: Style.alpha(Colors.textOnSurface, 0.16)

        Rectangle {
            height: parent.height
            width: 4 + (parent.width - 4) * root.shown
            radius: 2
            color: root.muted ? Style.alpha(Colors.textOnSurface, 0.35) : Colors.primary
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
    }

    // The knob: a white disc with a soft edge (white in light and dark,
    // like macOS), a bit bigger while held.
    Rectangle {
        id: knob
        x: (root.width - root.knobSize) * root.shown
        anchors.verticalCenter: parent.verticalCenter
        width: root.knobSize
        height: root.knobSize
        radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.96)
        border.width: 0.5
        border.color: Style.alpha(Colors.shadow, 0.3)
        scale: root.dragging ? 1.12 : area.containsMouse ? 1.05 : 1

        Behavior on x {
            enabled: !root.dragging
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            root.dragging = true;
            root.dragValue = root.valueAt(mouse.x);
            root.moved(root.dragValue);
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            root.dragValue = root.valueAt(mouse.x);
            root.moved(root.dragValue);
        }
        onReleased: root.dragging = false
        onCanceled: root.dragging = false
        onWheel: wheel => {
            const step = (wheel.angleDelta.y || -wheel.angleDelta.x) / 120 * Style.volumeStep;
            root.moved(Math.max(0, Math.min(1, root.value + step)));
        }
    }
}
