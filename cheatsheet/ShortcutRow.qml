import QtQuick
import qs.common

// One shortcut: what it does on the left, its keys on the right. Keys that
// do the same thing are separated by a thin "/" (Super ← / H).
Item {
    id: root

    // { combos: [{ chips: [{ text, icon }], note }], desc }
    required property var row

    // A long description wraps onto a second line.
    implicitHeight: Math.max(Style.cheatSheetRowHeight, desc.implicitHeight + 8)

    StyledText {
        id: desc
        anchors.left: parent.left
        anchors.right: keys.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.row.desc
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        lineHeight: 0.95
        textFormat: Text.PlainText
    }

    Row {
        id: keys
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Repeater {
            model: root.row.combos

            Row {
                id: combo
                required property var modelData
                required property int index

                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: combo.index > 0
                    text: "/"
                    rightPadding: 2
                    color: Colors.textOnSurfaceVariant
                    opacity: 0.6
                }
                Repeater {
                    model: combo.modelData.chips

                    KeyChip {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.text
                        icon: modelData.icon
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: combo.modelData.note !== ""
                    text: combo.modelData.note
                    role: "caption"
                    color: Colors.textOnSurfaceVariant
                }
            }
        }
    }
}
