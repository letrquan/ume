import QtQuick
import Quickshell.Services.Notifications
import qs.common
import qs.services

// Notifications button: a bell, with a small dot while something is unread
// (red while an urgent one is) or the number (Style.notifBadge).
// Click: the list. Right click: do not disturb (the bell gets crossed out).
Clickable {
    id: root

    readonly property bool badge: Notifs.unread > 0 && !Notifs.dnd
    readonly property bool urgent: Notifs.list.some(e => !e.read && e.urgency === NotificationUrgency.Critical)
    readonly property bool asCount: Style.notifBadge === "count"

    tip: "Notifications"
    tipDetail: (Notifs.unread > 0 ? Notifs.unread + " unread" : "Nothing new")
        + (Notifs.dnd ? " · Silent" : "") + "\nRight-click: Silent " + (Notifs.dnd ? "off" : "on")

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            Notifs.toggleDnd();
        else
            Notifs.setCenter(!Notifs.centerOpen);
    }

    Item {
        width: Style.iconSize
        height: Style.iconSize

        Icon {
            anchors.centerIn: parent
            name: Notifs.dnd ? "notifications_off" : "notifications"
            fill: Notifs.centerOpen ? 1 : 0
        }

        // Unread: a dot on the bell's shoulder, or a small number pill. A
        // thin ring in the island's color keeps it apart from the bell.
        Rectangle {
            readonly property real size: root.asCount ? 13 : 8

            x: root.asCount ? parent.width - width / 2 - 2 : parent.width - width + 1
            y: root.asCount ? -4 : -1
            width: root.asCount ? Math.max(size, count.implicitWidth + 6) : size
            height: size
            radius: height / 2
            color: root.urgent ? Colors.error : Colors.primary
            border.width: 1.5
            border.color: Colors.surfaceContainer
            visible: scale > 0.01
            scale: root.badge ? 1 : 0

            Behavior on scale {
                NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
            }
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            StyledText {
                id: count
                anchors.centerIn: parent
                visible: root.asCount
                text: Notifs.unread > 9 ? "9+" : Notifs.unread
                role: "micro"
                font.features: ({ "tnum": 1 })
                color: root.urgent ? Colors.textOnError : Colors.textOnPrimary
            }
        }
    }
}
