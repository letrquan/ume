import QtQuick
import qs.common

// The Settings window's "Bar items" editor (SettingRow kind "baritems").
// With an island `key` (barLeft / barCenter / barRight): its items, top to
// bottom = left to right on the bar, each with ↑ ↓ (order), ← → (to the
// island next to it) and ✕ (off the bar). Without a key: what isn't on the
// bar, each with Left / Middle / Right to put it there.
Column {
    id: root

    property string key: ""
    readonly property bool island: key !== ""
    readonly property int islandIndex: BarItems.islands.findIndex(i => i.key === key)
    readonly property var names: island ? Style[key] : BarItems.unused.map(i => i.name)

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

    // "Left", "Middle", "Right": add to that island.
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
        text: root.island ? "Nothing here: this island is hidden." : "Everything is on the bar."
        role: "body"
        color: Colors.textOnSurfaceVariant
    }

    Repeater {
        model: root.names

        Item {
            id: line
            required property string modelData
            required property int index
            readonly property var info: BarItems.info(modelData)

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
                name: line.info.icon
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
                    text: line.info.label
                    role: "title"
                    elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    visible: text !== ""
                    text: line.info.desc
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

                // On an island: order, other island, off.
                Small {
                    visible: root.island
                    glyph: "arrow_upward"
                    enabled: line.index > 0
                    onClicked: BarItems.move(root.key, line.index, -1)
                }
                Small {
                    visible: root.island
                    glyph: "arrow_downward"
                    enabled: line.index < root.names.length - 1
                    onClicked: BarItems.move(root.key, line.index, 1)
                }
                Small {
                    visible: root.island
                    glyph: "arrow_back"
                    enabled: root.islandIndex > 0
                    onClicked: BarItems.moveIsland(root.key, line.index, -1)
                }
                Small {
                    visible: root.island
                    glyph: "arrow_forward"
                    enabled: root.islandIndex < BarItems.islands.length - 1
                    onClicked: BarItems.moveIsland(root.key, line.index, 1)
                }
                Small {
                    visible: root.island
                    glyph: "close"
                    onClicked: BarItems.remove(root.key, line.index)
                }

                // Not on the bar: which island to put it in.
                Row {
                    visible: !root.island
                    spacing: 6

                    Repeater {
                        model: root.island ? [] : BarItems.islands

                        Chip {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.title.split(" ")[0]
                            onPicked: BarItems.add(modelData.key, line.modelData)
                        }
                    }
                }
            }
        }
    }
}
