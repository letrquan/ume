import QtQuick
import qs.common
import qs.services

// Top of a detail page:  ‹  Wi-Fi                     [switch]
Item {
    id: root

    property string title: ""
    property bool hasSwitch: false
    property bool checked: false
    default property alias extra: tools.data

    signal flipped()

    implicitHeight: 40

    Clickable {
        id: back
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        onClicked: ControlState.page = "main"
        Icon { name: "chevron_left"; size: 22 }
    }

    StyledText {
        anchors.left: back.right
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        role: "title"
    }

    Row {
        id: tools
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Toggle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasSwitch
            checked: root.checked
            onFlipped: root.flipped()
        }
    }
}
