import QtQuick
import qs.common
import qs.services

// The toolbar of the screen's ink (services/Ink.qml), a glass pill you drag
// by its grip:
//   ⠿ | ✎ pen  ▬ highlighter  ● laser  ⌫ eraser | six colors, size |
//   ↶ ↷ clear | ↖ pass-through  📷 screenshot  ×
// The chosen tool sits on a pill that slides, like the screenshot markup's
// (screenshot/MarkupBar.qml). What the pointer is on shows under it.
// The ink's window has no blur behind it (mango's no_blur rule: the strokes
// would get a frosted halo), so the glass is thicker, like the desktop cards.
Item {
    id: root

    property Item canvas: null              // ink/InkCanvas.qml of this screen
    property string tip: ""
    property string tipKey: ""

    implicitWidth: pill.width
    implicitHeight: pill.height + 30

    function hover(on, label, key) {
        if (on) {
            tip = label;
            tipKey = key;
        } else if (tip === label) {
            tip = "";
            tipKey = "";
        }
    }

    component IconButton: MouseArea {
        id: button
        property string icon: ""
        property string label: ""
        property string key: ""
        property bool on: true
        property bool lit: false            // shown as switched on
        width: 40
        height: 40
        hoverEnabled: true
        enabled: on
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: root.hover(containsMouse, label, key)

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: button.lit ? Colors.primary : Colors.textOnSurface
            opacity: button.lit ? 1 : button.containsMouse ? (button.pressed ? Style.pressTint : Style.hoverTint) : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Icon {
            anchors.centerIn: parent
            name: button.icon
            size: 21
            fill: button.lit ? 1 : 0
            color: button.lit ? Colors.textOnPrimary : Colors.textOnSurface
            opacity: button.on ? 1 : 0.35
        }
    }

    component Separator: Rectangle {
        anchors.verticalCenter: parent?.verticalCenter
        width: 1
        height: 22
        color: Style.alpha(Colors.textOnSurface, 0.15)
    }

    Rectangle {
        id: pill
        width: row.implicitWidth + 16
        height: 52
        radius: height / 2
        color: Style.alpha(Colors.surfaceContainer, Style.inkToolbarOpacity)
        border.color: Style.islandBorder
        border.width: Style.islandBorderWidth

        // Soft light on the top half, like the islands.
        Rectangle {
            anchors.fill: parent
            anchors.margins: parent.border.width
            radius: height / 2
            visible: Style.islandSheen > 0
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Style.islandSheen) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0) }
            }
        }

        Row {
            id: row
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            // The grip: drag the toolbar anywhere on its screen.
            MouseArea {
                id: grip
                width: 26
                height: 40
                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                hoverEnabled: true
                onContainsMouseChanged: root.hover(containsMouse, "Drag to move", "")
                drag.target: root
                drag.minimumX: 0
                drag.minimumY: 0
                drag.maximumX: (root.parent?.width ?? 0) - root.width
                drag.maximumY: (root.parent?.height ?? 0) - pill.height
                drag.threshold: 2
                onReleased: Ink.toolbarPos = Qt.point(root.x, root.y)

                Icon {
                    anchors.centerIn: parent
                    name: "drag_indicator"
                    size: 20
                    color: Colors.textOnSurfaceVariant
                }
            }

            Separator {}

            // ---- Tools ----
            Item {
                id: tools
                anchors.verticalCenter: parent.verticalCenter
                width: toolRow.implicitWidth
                height: 40

                readonly property var list: [
                    { id: "pen", icon: "stylus", label: "Pen", key: "P" },
                    { id: "highlighter", icon: "ink_highlighter", label: "Highlighter", key: "H" },
                    { id: "laser", icon: "radio_button_checked", label: "Laser pointer", key: "L" },
                    { id: "eraser", icon: "ink_eraser", label: "Eraser (or the pen's other end)", key: "E" }
                ]
                readonly property Item current: {
                    toolRepeater.count;
                    return Ink.passThrough ? null : toolRepeater.itemAt(list.findIndex(t => t.id === Ink.tool));
                }

                Rectangle {
                    x: tools.current?.x ?? 0
                    width: tools.current?.width ?? 0
                    height: parent.height
                    radius: height / 2
                    color: Colors.primary
                    visible: tools.current !== null
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
                            readonly property bool chosen: !Ink.passThrough && Ink.tool === modelData.id
                            width: 42
                            height: 40
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Ink.setTool(modelData.id)
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
                                size: 21
                                fill: toolButton.chosen ? 1 : 0
                                color: toolButton.chosen ? Colors.textOnPrimary : Colors.textOnSurface
                            }
                        }
                    }
                }
            }

            Separator {}

            // ---- Colors and size ----
            Row {
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: Ink.colors.length
                    MouseArea {
                        id: swatch
                        required property int index
                        readonly property bool chosen: Ink.colorIndex === index
                        width: 30
                        height: 40
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Ink.colorIndex = index;
                            if (Ink.tool === "eraser" || Ink.tool === "laser")
                                Ink.setTool("pen");
                        }
                        onContainsMouseChanged: root.hover(containsMouse, Ink.colorNames[index], String(index + 1))

                        Rectangle {
                            anchors.centerIn: parent
                            width: 27
                            height: 27
                            radius: 13.5
                            color: "transparent"
                            border.width: 2
                            border.color: Colors.textOnSurface
                            opacity: swatch.chosen ? 1 : swatch.containsMouse ? 0.3 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: swatch.chosen ? 19 : 17
                            height: width
                            radius: width / 2
                            color: Ink.colors[swatch.index]
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
                width: 40
                height: 40
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Ink.sizeIndex = (Ink.sizeIndex + 1) % Ink.widths.length
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
                    width: [6, 10, 16][Ink.sizeIndex]
                    height: width
                    radius: width / 2
                    color: Ink.color
                    border.width: 1
                    border.color: Style.alpha(Colors.textOnSurface, 0.35)
                    Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                }
            }

            Separator {}

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "undo"
                label: "Undo"
                key: "Ctrl+Z"
                on: root.canvas?.canUndo ?? false
                onClicked: root.canvas.undo()
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "redo"
                label: "Redo"
                key: "Ctrl+Shift+Z"
                on: root.canvas?.canRedo ?? false
                onClicked: root.canvas.redo()
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "delete_sweep"
                label: "Clear (every screen)"
                key: "Del"
                onClicked: Ink.clear()
            }

            Separator {}

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "arrow_selector_tool"
                label: Ink.passThrough ? "Draw again" : "Pass-through: use the apps, the ink stays"
                key: "T"
                lit: Ink.passThrough
                onClicked: Ink.togglePassThrough()
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "photo_camera"
                label: "Screenshot with the ink"
                key: "S"
                onClicked: Ink.save()
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "close"
                label: "Done (the ink goes)"
                key: "Esc"
                onClicked: Ink.close()
            }
        }
    }

    // What the pointer is on, under the pill.
    Rectangle {
        anchors.horizontalCenter: pill.horizontalCenter
        anchors.top: pill.bottom
        anchors.topMargin: 6
        width: tipRow.implicitWidth + 20
        height: 24
        radius: 12
        color: Style.alpha(Colors.surfaceContainer, Style.inkToolbarOpacity)
        opacity: root.tip !== "" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        Row {
            id: tipRow
            anchors.centerIn: parent
            spacing: 8
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.tip
                role: "label"
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.tipKey !== ""
                text: root.tipKey
                role: "label"
                color: Colors.textOnSurfaceVariant
            }
        }
    }
}
