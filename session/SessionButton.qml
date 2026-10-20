import QtQuick
import qs.common

// One power-menu button: a big Material shape with an icon and a label.
// Resting: a soft circle. Selected (keys or hover): it morphs into its own
// shape in the accent color and turns a little. Armed (restart, shut down
// and log out ask twice): a red burst with a ring that runs out.
Item {
    id: root

    required property var action
    required property int index
    property bool selected: false
    property bool armed: false
    property real armLeft: 1          // 1 → 0 while armed
    property bool shown: false        // pop-in, staggered by index

    signal hovered()
    signal pressed()

    implicitWidth: Style.sessionButtonSize + 16
    implicitHeight: Style.sessionButtonSize + 44

    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.6

    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: root.shown ? root.index * 45 : 0 }
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
        }
    }
    Behavior on scale {
        SequentialAnimation {
            PauseAnimation { duration: root.shown ? root.index * 45 : 0 }
            NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }
    }

    Item {
        id: badge
        anchors.horizontalCenter: parent.horizontalCenter
        width: Style.sessionButtonSize
        height: Style.sessionButtonSize
        scale: mouse.pressed ? 0.92 : root.selected ? 1.06 : 1

        Behavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }

        Shape {
            anchors.fill: parent
            shape: root.armed ? "SoftBurst" : root.selected ? root.action.shape : "Circle"
            color: root.armed ? Colors.error
                 : root.selected ? Colors.primary
                 : Style.alpha(Colors.surfaceContainerHighest, 0.9)
            rotation: root.armed ? 30 : root.selected ? 15 : 0

            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on rotation {
                NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }
        }

        // Time left to press again.
        Canvas {
            id: ring
            anchors.fill: parent
            anchors.margins: -7
            visible: root.armed
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.lineWidth = 3;
                ctx.lineCap = "round";
                ctx.strokeStyle = Colors.error;
                const r = width / 2 - 2;
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * root.armLeft);
                ctx.stroke();
            }
            Connections {
                target: root
                function onArmLeftChanged() { ring.requestPaint(); }
            }
        }

        Icon {
            anchors.centerIn: parent
            name: root.action.icon
            size: Style.sessionButtonSize * 0.36
            color: root.armed ? Colors.textOnError
                 : root.selected ? Colors.textOnPrimary
                 : Colors.textOnSurface
        }

        // Its number key.
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 2
            anchors.topMargin: 2
            width: 20
            height: 20
            radius: 10
            color: Style.alpha(Colors.surfaceContainer, 0.85)
            border.width: 1
            border.color: Style.alpha(Colors.textOnSurface, 0.15)
            opacity: root.selected || root.armed ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

            StyledText {
                anchors.centerIn: parent
                text: root.index + 1
                role: "micro"
                color: Colors.textOnSurfaceVariant
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: root.hovered()
            onClicked: root.pressed()
        }
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: badge.bottom
        anchors.topMargin: 12
        text: root.armed ? "Press again" : root.action.label
        role: "body"
        weight: root.selected || root.armed ? 700 : 500
        color: root.armed ? Colors.error : root.selected ? Colors.textOnSurface : Colors.textOnSurfaceVariant
    }
}
