import QtQuick
import qs.common

// The screenshot markup's toolbar, in the overlay's glass pill
// (screenshot/ShotView.qml) in place of Region / Window / Screen:
//   ✎ pen  ↗ arrow  ▭ box  T text  ▒ blur | four colors, size | ↶ ↷ | Copy  Save  ×
// The chosen tool sits on a pill that slides, like the modes do. What the
// pointer is on (`tip`, `tipKey`) is shown by ShotView above the pill.
Row {
    id: root

    property Item marker: null          // screenshot/MarkupLayer.qml
    property string tip: ""
    property string tipKey: ""

    signal save()
    signal copy()
    signal close()

    spacing: 4
    height: 36

    function hover(on, label, key) {
        if (on) {
            tip = label;
            tipKey = key;
        } else if (tip === label) {
            tip = "";
            tipKey = "";
        }
    }

    // A round icon button with the usual hover tint.
    component IconButton: MouseArea {
        id: button
        property string icon: ""
        property string label: ""
        property string key: ""
        property bool on: true
        width: 36
        height: 36
        hoverEnabled: true
        enabled: on
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: root.hover(containsMouse, label, key)

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Colors.textOnSurface
            opacity: button.containsMouse ? (button.pressed ? Style.pressTint : Style.hoverTint) : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Icon {
            anchors.centerIn: parent
            name: button.icon
            size: 20
            opacity: button.on ? 1 : 0.35
        }
    }

    component Separator: Rectangle {
        anchors.verticalCenter: parent?.verticalCenter
        width: 1
        height: 20
        color: Style.alpha(Colors.textOnSurface, 0.15)
    }

    // ---- Tools ------------------------------------------------------------------------------
    Item {
        id: tools
        width: toolRow.implicitWidth
        height: 36

        readonly property var list: [
            { id: "pen", icon: "draw", label: "Pen", key: "P" },
            { id: "arrow", icon: "arrow_outward", label: "Arrow", key: "A" },
            { id: "box", icon: "check_box_outline_blank", label: "Box", key: "B" },
            { id: "text", icon: "title", label: "Text", key: "T" },
            { id: "blur", icon: "blur_on", label: "Blur", key: "X" }
        ]
        readonly property Item current: {
            toolRepeater.count;
            return toolRepeater.itemAt(list.findIndex(t => t.id === root.marker?.tool));
        }

        Rectangle {
            x: tools.current?.x ?? 0
            width: tools.current?.width ?? 0
            height: parent.height
            radius: height / 2
            color: Colors.primary
            Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        }

        Row {
            id: toolRow
            height: parent.height

            Repeater {
                id: toolRepeater
                model: tools.list

                MouseArea {
                    id: toolButton
                    required property var modelData
                    readonly property bool chosen: root.marker?.tool === modelData.id
                    width: 42
                    height: 36
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.marker.setTool(modelData.id)
                    onContainsMouseChanged: root.hover(containsMouse, modelData.label, modelData.key)

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Colors.textOnSurface
                        opacity: !toolButton.chosen && toolButton.containsMouse ? Style.hoverTint : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: toolButton.modelData.icon
                        size: 20
                        fill: toolButton.chosen ? 1 : 0
                        color: toolButton.chosen ? Colors.textOnPrimary : Colors.textOnSurface
                    }
                }
            }
        }
    }

    Separator {}

    // ---- Colors and size ------------------------------------------------------------------------
    Row {
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
            model: root.marker?.colors.length ?? 0

            MouseArea {
                id: swatch
                required property int index
                readonly property bool chosen: root.marker.colorIndex === index
                width: 28
                height: 36
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.marker.colorIndex = index
                onContainsMouseChanged: root.hover(containsMouse, root.marker.colorNames[index], String(index + 1))

                // A ring around the chosen one.
                Rectangle {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    radius: 13
                    color: "transparent"
                    border.width: 2
                    border.color: Colors.textOnSurface
                    opacity: swatch.chosen ? 1 : swatch.containsMouse ? 0.3 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: swatch.chosen ? 18 : 16
                    height: width
                    radius: width / 2
                    color: root.marker.colors[swatch.index]
                    border.width: 1
                    border.color: Style.alpha(Colors.textOnSurface, 0.3)
                    Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                }
            }
        }
    }

    // Size: a dot as thick as the line; click for the next one.
    MouseArea {
        id: sizeButton
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 36
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.marker.sizeIndex = (root.marker.sizeIndex + 1) % root.marker.widths.length
        onContainsMouseChanged: root.hover(containsMouse, "Size", "[  ]")

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Colors.textOnSurface
            opacity: sizeButton.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Rectangle {
            anchors.centerIn: parent
            width: [6, 10, 15][root.marker?.sizeIndex ?? 1]
            height: width
            radius: width / 2
            color: Colors.textOnSurface
            Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        }
    }

    Separator {}

    IconButton {
        anchors.verticalCenter: parent.verticalCenter
        icon: "undo"
        label: "Undo"
        key: "Ctrl+Z"
        on: root.marker?.canUndo ?? false
        onClicked: root.marker.undo()
    }
    IconButton {
        anchors.verticalCenter: parent.verticalCenter
        icon: "redo"
        label: "Redo"
        key: "Ctrl+Shift+Z"
        on: root.marker?.canRedo ?? false
        onClicked: root.marker.redo()
    }

    Separator {}

    // Copy: the clipboard only, no file.
    MouseArea {
        id: copyButton
        anchors.verticalCenter: parent.verticalCenter
        width: copyRow.implicitWidth + 28
        height: 36
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.copy()
        onContainsMouseChanged: root.hover(containsMouse, "Copy only", "Ctrl+C")

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Colors.textOnSurface
            opacity: copyButton.containsMouse ? (copyButton.pressed ? Style.pressTint : Style.hoverTint) : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Row {
            id: copyRow
            anchors.centerIn: parent
            spacing: 6
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "content_copy"
                size: 18
                fill: 0
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Copy"
                weight: 600
            }
        }
    }

    // Save: the picture in the screenshot folder, copied, the notification.
    MouseArea {
        id: saveButton
        anchors.verticalCenter: parent.verticalCenter
        width: saveRow.implicitWidth + 30
        height: 36
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.save()
        onContainsMouseChanged: root.hover(containsMouse, "Save and copy", "Enter")

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Colors.primary
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Colors.textOnPrimary
            opacity: saveButton.containsMouse ? (saveButton.pressed ? Style.pressTint : Style.hoverTint) : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Row {
            id: saveRow
            anchors.centerIn: parent
            spacing: 6
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "check"
                size: 18
                color: Colors.textOnPrimary
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Save"
                weight: 650
                color: Colors.textOnPrimary
            }
        }
    }

    IconButton {
        anchors.verticalCenter: parent.verticalCenter
        icon: "close"
        label: "Cancel"
        key: "Esc"
        onClicked: root.close()
    }
}
