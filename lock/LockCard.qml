import QtQuick
import qs.common

// A card inside the lock panel, like the control center's: a soft tint on
// the glass, with an optional title (symbol + words) at the top.
Item {
    id: root

    property string title: ""
    property string titleIcon: ""
    default property alias content: body.data

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: Style.alpha(Colors.textOnSurface, 0.06)
    }

    Row {
        id: header
        visible: root.title !== ""
        x: 18
        y: 14
        spacing: 6

        Icon {
            visible: root.titleIcon !== ""
            name: root.titleIcon
            size: 18
            color: Colors.primary
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            role: "label"
            color: Colors.textOnSurfaceVariant
        }
    }

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: 16
        anchors.topMargin: header.visible ? 44 : 16
    }
}
