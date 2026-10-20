import QtQuick
import qs.common

// One emoji in the launcher's grid: big, with a soft square behind the
// selected one.
Item {
    id: root

    required property var modelData
    required property int index
    property bool selected: false

    signal hoveredCell(int index)
    signal chosen(int index)

    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 14
        color: Style.alpha(Colors.primary, 0.18)
        opacity: root.selected ? 1 : 0
        scale: root.selected ? 1 : 0.85
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        Behavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }
    }

    Text {
        anchors.centerIn: parent
        text: root.modelData.title
        font.family: "Noto Color Emoji"
        font.pixelSize: 28
        scale: root.selected ? 1.12 : 1
        Behavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Only a real mouse move selects (see ResultRow).
        onPositionChanged: root.hoveredCell(root.index)
        onClicked: root.chosen(root.index)
    }
}
