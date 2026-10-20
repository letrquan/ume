import QtQuick
import qs.common

// A compact slider for one number setting, a small sibling of the control
// center's sliders: a rounded track, the filled part a pill with a dot at
// its end, and the value written next to it. Snaps to `step`. Drag, click
// anywhere on the track, or scroll.
Item {
    id: root

    property real value: 0
    property real from: 0
    property real to: 1
    property real step: 0.01
    property var format: v => String(v)

    signal moved(real value)

    // While dragging, show where the pointer is, not the stored value.
    property bool dragging: false
    property real dragValue: 0
    readonly property real shown: dragging ? dragValue : value
    readonly property real fraction: Math.max(0, Math.min(1, (shown - from) / (to - from)))

    implicitWidth: 280
    implicitHeight: 28

    function snap(v) {
        const snapped = Math.round((v - from) / step) * step + from;
        return Math.max(from, Math.min(to, +snapped.toFixed(6)));
    }
    function valueAt(x) {
        const h = track.height;
        return snap(from + (to - from) * Math.max(0, Math.min(1, (x - h / 2) / (rail.width - h))));
    }
    function send(v) {
        dragValue = v;
        if (v !== value)
            moved(v);
    }

    StyledText {
        id: label
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 70
        horizontalAlignment: Text.AlignRight
        text: root.format(root.shown)
        role: "label"
        font.features: ({ "tnum": 1 })
        color: Colors.textOnSurfaceVariant
    }

    Item {
        id: rail
        anchors.left: parent.left
        anchors.right: label.left
        anchors.rightMargin: 12
        height: parent.height

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 16
            radius: height / 2
            color: Style.alpha(Colors.textOnSurface, mouse.containsMouse || mouse.pressed ? 0.16 : 0.12)
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            Rectangle {
                id: filled
                height: parent.height
                width: parent.height + (parent.width - parent.height) * root.fraction
                radius: height / 2
                color: Colors.primary

                Behavior on width {
                    enabled: !root.dragging
                    NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                }

                // The dot at the end: grows while held.
                Rectangle {
                    property real size: mouse.pressed ? 10 : 6
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width - parent.height / 2 - size / 2
                    width: size
                    height: size
                    radius: size / 2
                    color: Colors.textOnPrimary
                    Behavior on size {
                        NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                    }
                }
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => {
                root.dragging = true;
                root.send(root.valueAt(mouse.x));
            }
            onPositionChanged: mouse => {
                if (pressed)
                    root.send(root.valueAt(mouse.x));
            }
            onReleased: root.dragging = false
            onCanceled: root.dragging = false
            onWheel: wheel => {
                const notches = (wheel.angleDelta.y || -wheel.angleDelta.x) / 120;
                const next = root.snap(root.value + notches * root.step);
                if (next !== root.value)
                    root.moved(next);
            }
        }
    }
}
