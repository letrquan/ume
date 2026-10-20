import QtQuick
import qs.common

// One key on the cheat sheet, drawn like a keycap: a soft rounded chip with
// a darker lip at the bottom. `icon` (Material Symbols) goes before the text
// (⌘ for Super, a hand for touchpad gestures, a mouse for mouse binds).
Item {
    id: root

    property string text: ""
    property string icon: ""

    implicitWidth: Math.max(Style.cheatSheetChipHeight, line.implicitWidth + 12)
    implicitHeight: Style.cheatSheetChipHeight + 2

    // The lip under the cap.
    Rectangle {
        width: parent.width
        height: Style.cheatSheetChipHeight
        y: 2
        radius: 7
        color: Style.alpha(Colors.shadow, 0.35)
    }

    Rectangle {
        width: parent.width
        height: Style.cheatSheetChipHeight
        radius: 7
        color: Qt.tint(Colors.surfaceContainerHighest, Style.alpha(Colors.textOnSurface, 0.06))
        border.width: 1
        border.color: Style.alpha(Colors.textOnSurface, 0.10)

        Row {
            id: line
            anchors.centerIn: parent
            spacing: 3

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.icon !== ""
                name: root.icon
                size: 13
                color: Colors.textOnSurfaceVariant
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                role: "label"
                font.features: ({ "tnum": 1 })
            }
        }
    }
}
