import QtQuick
import qs.common

// A chip under the empty search field: the sign that starts a mode, and
// its name ( [:] Emoji ). A click types the sign for you.
Rectangle {
    id: root

    property string sign: ""
    property string label: ""
    property string icon: ""
    property bool clickable: true

    signal picked()

    width: line.implicitWidth + 16
    height: 28
    radius: 14
    color: Style.alpha(Colors.textOnSurface, area.containsMouse && clickable ? 0.12 : 0.06)
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    Row {
        id: line
        anchors.centerIn: parent
        spacing: 6

        // The sign, like a key.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(18, signText.implicitWidth + 8)
            height: 18
            radius: 5
            color: "transparent"
            border.width: 1
            border.color: Style.alpha(Colors.textOnSurface, 0.22)

            StyledText {
                id: signText
                anchors.centerIn: parent
                text: root.sign
                role: "micro"
                color: Colors.primary
            }
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            size: 15
            color: Colors.textOnSurfaceVariant
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            role: "label"
            color: Colors.textOnSurfaceVariant
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.clickable
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
    }
}
