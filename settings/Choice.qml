import QtQuick
import qs.common

// A segmented choice: one rounded group, the chosen part filled with the
// accent color (the fill slides to the new choice).
// Choice { choices: [{ value: "a", label: "A" }, ...]; value: ...; onPicked: v => ... }
Item {
    id: root

    property var choices: []
    property var value
    readonly property int current: choices.findIndex(c => c.value === value)

    signal picked(var value)

    implicitWidth: parts.implicitWidth + 6
    implicitHeight: 32

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Style.alpha(Colors.textOnSurface, 0.08)
    }

    // The chosen part.
    Rectangle {
        // itemAt alone isn't re-read when the parts are made; count is.
        readonly property Item target: rep.count > 0 && root.current >= 0 ? rep.itemAt(root.current) : null
        visible: target !== null
        x: 3 + (target?.x ?? 0)
        y: 3
        width: target?.width ?? 0
        height: parent.height - 6
        radius: height / 2
        color: Colors.primary

        Behavior on x {
            NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }
        Behavior on width {
            NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }
    }

    Row {
        id: parts
        x: 3
        y: 3
        height: parent.height - 6

        Repeater {
            id: rep
            model: root.choices

            MouseArea {
                id: part
                required property var modelData
                required property int index

                width: text.implicitWidth + 28
                height: parts.height
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (index !== root.current) root.picked(modelData.value)

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Colors.textOnSurface
                    opacity: part.index === root.current ? 0 : part.containsMouse ? Style.hoverTint : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                StyledText {
                    id: text
                    anchors.centerIn: parent
                    text: part.modelData.label
                    role: "label"
                    color: part.index === root.current ? Colors.textOnPrimary : Colors.textOnSurface
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }
        }
    }
}
