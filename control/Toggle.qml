import QtQuick
import qs.common

// A Material 3 switch: the thumb grows and shows a check when on.
MouseArea {
    id: root

    property bool checked: false

    signal flipped()

    implicitWidth: 52
    implicitHeight: 32
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.flipped()

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Colors.primary : Style.alpha(Colors.textOnSurface, 0.12)
        border.width: root.checked ? 0 : 2
        border.color: Style.alpha(Colors.textOnSurface, 0.35)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    Rectangle {
        property real size: root.pressed ? 28 : root.checked ? 24 : 16
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? root.width - size - 4 : 8 - (size - 16) / 2
        width: size
        height: size
        radius: size / 2
        color: root.checked ? Colors.textOnPrimary : Style.alpha(Colors.textOnSurface, 0.6)

        Behavior on x {
            NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }
        Behavior on size {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Icon {
            anchors.centerIn: parent
            name: "check"
            size: 15
            color: Colors.primary
            opacity: root.checked ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
    }
}
