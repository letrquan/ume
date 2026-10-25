import QtQuick
import qs.common
import qs.control

// The Settings window's control center tiles editor (SettingRow kind
// "cctiles"), like the bar items one. `shown` true: the tiles in the
// control center, top to bottom = left to right, row by row, each with ↑ ↓
// (order) and ✕ (off). `shown` false: the ones not there, each with Add (at
// the end). Same as Edit in the control center itself (drag, −, the tray).
Column {
    id: root

    property bool shown: true
    readonly property var names: shown ? ControlTiles.chosen : ControlTiles.hidden

    // A small round icon button, faded out when it can't be used.
    component Small: Clickable {
        id: small
        property string glyph: ""
        implicitHeight: 30
        padding: 0
        opacity: enabled ? 1 : 0.25

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: small.glyph
            size: 18
            color: Colors.textOnSurfaceVariant
        }
    }

    // "Add": at the end of the control center's tiles.
    component Chip: MouseArea {
        id: chip
        property string text: ""
        signal picked()

        width: label.implicitWidth + 22
        height: 28
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: picked()

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Colors.secondaryContainer

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Colors.textOnSurface
                opacity: chip.pressed ? Style.pressTint : chip.containsMouse ? Style.hoverTint : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }
        }
        StyledText {
            id: label
            anchors.centerIn: parent
            text: chip.text
            role: "label"
            color: Colors.textOnSecondaryContainer
        }
    }

    StyledText {
        x: 18
        height: 52
        visible: root.names.length === 0
        text: root.shown ? "No tiles: the control center starts with the sliders." : "Every tile is in the control center."
        role: "body"
        color: Colors.textOnSurfaceVariant
    }

    Repeater {
        model: root.names

        Item {
            id: line
            required property string modelData
            required property int index
            readonly property var info: ControlTiles.spec(modelData)

            width: root.width
            height: 52

            Rectangle {
                x: 18
                width: parent.width - 36
                height: 1
                visible: line.index > 0
                color: Style.alpha(Colors.textOnSurface, 0.08)
            }

            Icon {
                id: glyph
                x: 18
                anchors.verticalCenter: parent.verticalCenter
                name: line.info?.icon ?? "help"
                size: 20
                color: Colors.primary
            }

            Column {
                anchors.left: glyph.right
                anchors.leftMargin: 14
                anchors.right: buttons.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                StyledText {
                    width: parent.width
                    text: line.info?.label ?? line.modelData
                    role: "title"
                    elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    visible: text !== ""
                    text: line.info?.desc ?? ""
                    role: "caption"
                    color: Colors.textOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            Row {
                id: buttons
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Small {
                    visible: root.shown
                    glyph: "arrow_upward"
                    enabled: line.index > 0
                    onClicked: ControlTiles.move(line.index, -1)
                }
                Small {
                    visible: root.shown
                    glyph: "arrow_downward"
                    enabled: line.index < root.names.length - 1
                    onClicked: ControlTiles.move(line.index, 1)
                }
                Small {
                    visible: root.shown
                    glyph: "close"
                    onClicked: ControlTiles.remove(line.modelData)
                }
                Chip {
                    visible: !root.shown
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add"
                    onPicked: ControlTiles.add(line.modelData)
                }
            }
        }
    }
}
