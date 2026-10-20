import QtQuick

// A short faint line between groups inside an island.
Item {
    anchors.verticalCenter: parent?.verticalCenter
    implicitWidth: 11
    implicitHeight: 16

    Rectangle {
        anchors.centerIn: parent
        width: 1
        height: parent.height
        radius: 0.5
        color: Style.alpha(Colors.textOnSurface, 0.14)
    }
}
