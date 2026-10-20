import QtQuick
import Quickshell
import qs.common
import qs.services

// One app's notifications in the list (Style.notifGroupByApp).
//   (icon) Discord  3                      ⌄  ✕
//   ╭ newest card ──────────────────────────────╮
//   ╰───────────────────────────────────────────╯
//     ╰─────────── the others, peeking ───────╯
// Click the header (or the peeking edges) to see them all; ✕ clears the
// app's notifications; right-click: mute the app, or list only (RuleMenu).
// Just one: only its card, as before.
Item {
    id: root

    // [{ id, app, entries }] from Notifs.groups; null once the app's last
    // one is gone (the row then fades out still showing it).
    required property var group
    property var lastEntries: []
    property string lastApp: ""
    onGroupChanged: remember()
    Component.onCompleted: remember()
    function remember() {
        if (!group)
            return;
        lastEntries = group.entries;
        lastApp = group.app;
    }
    readonly property var entries: group?.entries ?? lastEntries
    readonly property bool many: entries.length > 1
    property bool expanded: false
    // The other cards are only made once the group is first unfolded
    // (then kept, so folding can still animate): with a long list, making
    // every folded card up front stalled the panel's opening.
    property bool unfolded: false
    onExpandedChanged: if (expanded) unfolded = true
    onManyChanged: if (!many) {
        expanded = false;
        menuOpen = false;
    }
    // The header's right-click menu is open.
    property bool menuOpen: false

    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: 0

        // ---- Header (only for a group) -------------------------------------------
        MouseArea {
            id: header
            visible: root.many
            width: parent.width
            height: 34
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded

            // Right-click; keeps the click (see NotifCard). On an Item of its
            // own: a handler on the MouseArea itself would make it take every
            // button (a right-click would also fold / unfold).
            Item {
                anchors.fill: parent
                TapHandler {
                    gesturePolicy: TapHandler.WithinBounds
                    acceptedButtons: Qt.RightButton
                    onTapped: root.menuOpen = !root.menuOpen
                }
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20

                    AppIcon {
                        id: appIcon
                        anchors.fill: parent
                        source: root.entries[0]?.icon ?? ""
                        name: root.group?.app ?? root.lastApp
                        visible: source !== ""
                    }
                    Icon {
                        anchors.centerIn: parent
                        visible: !appIcon.visible
                        name: "notifications"
                        size: 18
                        color: Colors.textOnSurfaceVariant
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.group?.app ?? root.lastApp
                    weight: 650
                    role: "body"
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(height, count.implicitWidth + 10)
                    height: 18
                    radius: 9
                    color: Colors.secondaryContainer

                    StyledText {
                        id: count
                        anchors.centerIn: parent
                        text: root.entries.length
                        role: "micro"
                        color: Colors.textOnSecondaryContainer
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Clickable {
                    implicitHeight: 28
                    padding: 4
                    onClicked: root.expanded = !root.expanded

                    Icon {
                        name: "expand_more"
                        size: 20
                        color: Colors.textOnSurfaceVariant
                        rotation: root.expanded ? 180 : 0
                        Behavior on rotation {
                            NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                        }
                    }
                }

                // Clear this app's notifications.
                Clickable {
                    implicitHeight: 28
                    padding: 4
                    onClicked: Notifs.dismissApp(root.group?.app ?? root.lastApp)

                    Icon {
                        name: "close"
                        size: 18
                        color: Colors.textOnSurfaceVariant
                    }
                }
            }
        }

        // ---- The header's right-click menu ----------------------------------------------
        Item {
            width: parent.width
            height: root.menuOpen && root.many ? groupMenu.implicitHeight + 10 : 0
            clip: true
            visible: height > 0

            Behavior on height {
                NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }

            RuleMenu {
                id: groupMenu
                x: 6
                width: parent.width - 12
                app: root.group?.app ?? root.lastApp
                opacity: root.menuOpen ? 1 : 0
                onDone: root.menuOpen = false
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }
        }

        // ---- The newest -----------------------------------------------------------
        Loader {
            width: parent.width
            active: root.entries.length > 0
            sourceComponent: NotifCard {
                entry: root.entries[0]
            }
        }

        // ---- The others, peeking out while folded --------------------------------------
        Item {
            width: parent.width
            height: root.many && !root.expanded ? 6 * Math.min(2, root.entries.length - 1) : 0
            visible: height > 0

            Behavior on height {
                NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }

            Repeater {
                model: Math.max(0, Math.min(2, root.entries.length - 1))

                Rectangle {
                    required property int index
                    x: 12 * (index + 1)
                    y: 6 * index - 2
                    z: -index
                    width: parent.width - 24 * (index + 1)
                    height: 8
                    radius: 4
                    color: Style.alpha(Colors.surfaceContainerHigh, 0.85 - index * 0.25)
                    border.width: 1
                    border.color: Style.islandBorder
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = true
            }
        }

        // ---- The others, unfolded -----------------------------------------------------------
        Item {
            width: parent.width
            height: root.expanded ? rest.implicitHeight : 0
            clip: true
            visible: height > 0

            Behavior on height {
                NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            }

            Column {
                id: rest
                width: parent.width
                topPadding: 8
                spacing: 8
                opacity: root.expanded ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: Motion.normal } }

                Repeater {
                    model: ScriptModel {
                        values: root.many && root.unfolded ? root.entries.slice(1) : []
                    }

                    NotifCard {
                        required property var modelData
                        width: rest.width
                        entry: modelData
                    }
                }
            }
        }
    }
}
