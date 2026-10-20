import QtQuick
import Quickshell
import qs.common
import qs.services

// The list of all notifications (opened by the bell): a header with
// do-not-disturb and clear-all, then the cards, newest first, one card per
// app (NotifGroup: click it for the rest).
Item {
    id: root

    property real maxHeight: 700

    implicitWidth: Style.notifWidth + 24
    implicitHeight: Math.min(maxHeight, header.height + 12 + body.height + 12)

    // mango doesn't blur this window (it can't fade its blur): the frost
    // is the shell's own, so it comes and goes with the panel.
    WallpaperFrost {
        anchors.fill: parent
        at: Qt.point(root.x, root.y)
        radius: Style.notifRadius + 4
    }
    Glass {
        anchors.fill: parent
        radius: Style.notifRadius + 4
    }

    // Clicks on the panel stay on the panel (right-clicks too: they open a
    // card's menu, and must not reach the click-outside-closes behind).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Item {
        id: header
        x: 12
        y: 12
        width: parent.width - 24
        height: 32

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                role: "title"
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: Notifs.list.length > 0
                width: Math.max(height, count.implicitWidth + 12)
                height: 20
                radius: 10
                color: Colors.secondaryContainer

                StyledText {
                    id: count
                    anchors.centerIn: parent
                    text: Notifs.list.length
                    role: "micro"
                    color: Colors.textOnSecondaryContainer
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            // Do not disturb: no popups or sound, they still land in the list.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: dndButton.width
                height: dndButton.height

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Colors.primary
                    opacity: Notifs.dnd ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                Clickable {
                    id: dndButton
                    implicitHeight: 32
                    padding: 10
                    onClicked: Notifs.toggleDnd()

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "do_not_disturb_on"
                        size: 18
                        fill: Notifs.dnd ? 1 : 0
                        color: Notifs.dnd ? Colors.textOnPrimary : Colors.textOnSurface
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Silent"
                        role: "label"
                        color: Notifs.dnd ? Colors.textOnPrimary : Colors.textOnSurface
                    }
                }
            }

            Clickable {
                implicitHeight: 32
                enabled: Notifs.list.length > 0
                opacity: enabled ? 1 : 0.4
                onClicked: Notifs.clearAll()

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "clear_all"
                    size: 20
                }
            }
        }
    }

    Item {
        id: body
        x: 12
        y: header.y + header.height + 8
        width: parent.width - 24
        height: Notifs.list.length > 0 ? Math.min(list.contentHeight, root.maxHeight - header.height - 32) : empty.height

        ListView {
            id: list
            anchors.fill: parent
            visible: Notifs.list.length > 0
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds

            // One row per app (or per notification, Style.notifGroupByApp
            // off), by id, so a row stays put (and open) as its app's
            // notifications come and go.
            model: ScriptModel {
                values: Notifs.groups.map(g => g.id)
            }

            delegate: NotifGroup {
                required property string modelData
                width: list.width
                group: Notifs.groups.find(g => g.id === modelData) ?? null
            }

            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: Motion.fast }
            }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                NumberAnimation { property: "opacity"; to: 1; duration: Motion.fast }
            }
        }

        // Nothing here.
        EmptyState {
            id: empty
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Notifs.list.length === 0
            // The panel fades in once its window has settled (NotifCenter).
            active: root.opacity > 0.3
            shape: "Cookie12Sided"
            icon: Notifs.dnd ? "notifications_paused" : "done_all"
            title: "You're all caught up"
            hint: Notifs.dnd ? "Silent is on: new ones land here without a popup or sound"
                             : "New notifications show up here"
        }
    }
}
