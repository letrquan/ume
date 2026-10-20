import QtQuick
import qs.common

// The lock screen's left island: a lock and since when it's locked.
LockIsland {
    id: root

    property date lockedAt: new Date()
    readonly property string since: Style.clock24h ? Qt.formatTime(lockedAt, "HH:mm") : Qt.formatTime(lockedAt, "h:mm AP")

    Item {
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: line.implicitWidth + 16
        implicitHeight: Style.itemHeight

        Row {
            id: line
            anchors.centerIn: parent
            spacing: 6

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "lock"
                color: Colors.primary
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Locked"
                weight: 650
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "since " + root.since
                color: Colors.textOnSurfaceVariant
            }
        }
    }
}
