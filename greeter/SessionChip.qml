import QtQuick
import QtQuick.Effects
import qs.common

// The login screen's bottom-left corner: a white see-through pill with the
// session that will start ("mango ⌃"); click it for the others, listed
// above it. With more than one person on the laptop, a second pill picks
// who logs in. Same look as the lock's ⏻ buttons.
Item {
    id: root

    property var sessions: []       // [{ id, name }]
    property var current: null
    property var users: []
    property string user: ""
    property bool open: false
    property string openList: ""    // "sessions" | "users"
    // 0 → 1 as the picture behind gets bright: darker pills (MacView's
    // WallpaperLight).
    property real boost: 0

    signal picked(string id)
    signal userPicked(string name)

    implicitWidth: row.implicitWidth
    implicitHeight: 34
    width: implicitWidth
    height: implicitHeight

    onEnabledChanged: if (!enabled) open = false

    Row {
        id: row
        spacing: 10

        // The shadow only on the pills: a layer on the whole chip would cut
        // off the list that opens above it.
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.3)
            shadowBlur: 0.5
            shadowVerticalOffset: 1
        }

        Pill {
            visible: root.users.length > 1
            icon: "person"
            text: root.user
            onClicked: root.toggle("users")
        }
        Pill {
            icon: "desktop_windows"
            text: root.current?.name ?? "No session found"
            chevron: root.sessions.length > 1
            onClicked: if (root.sessions.length > 1) root.toggle("sessions")
        }
    }

    function toggle(which) {
        if (open && openList === which) {
            open = false;
        } else {
            openList = which;
            open = true;
        }
    }

    // The list, above the pills.
    Rectangle {
        id: list
        readonly property var entries: root.openList === "users"
            ? root.users.map(u => ({ id: u, name: u, on: u === root.user }))
            : root.sessions.map(s => ({ id: s.id, name: s.name, on: s.id === root.current?.id }))
        x: root.openList === "users" ? 0 : (root.users.length > 1 ? row.children[0].width + row.spacing : 0)
        y: -height - 10
        width: 250
        height: column.implicitHeight + 12
        radius: 16
        color: Qt.rgba(0.1, 0.1, 0.12, 0.62)
        border.color: Qt.rgba(1, 1, 1, 0.16)
        border.width: 1
        opacity: root.open ? 1 : 0
        visible: opacity > 0.01
        scale: root.open ? 1 : 0.94
        transformOrigin: Item.BottomLeft
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        Behavior on scale {
            NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }

        Column {
            id: column
            x: 6
            y: 6
            width: list.width - 12

            Repeater {
                model: list.entries

                Rectangle {
                    required property var modelData
                    width: column.width
                    height: 32
                    radius: 10
                    color: Qt.rgba(1, 1, 1, rowHover.hovered ? 0.14 : 0)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Icon {
                        id: check
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        name: "check"
                        size: 16
                        color: "white"
                        opacity: modelData.on ? 1 : 0
                    }
                    StyledText {
                        anchors.left: check.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: "white"
                        weight: modelData.on ? 650 : 500
                        elide: Text.ElideRight
                    }

                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            root.open = false;
                            if (root.openList === "users")
                                root.userPicked(modelData.id);
                            else
                                root.picked(modelData.id);
                        }
                    }
                }
            }
        }
    }

    // Closes by itself after a while, like ⏻.
    Timer {
        running: root.open
        interval: 8000
        onTriggered: root.open = false
    }

    component Pill: Rectangle {
        id: pill
        property string icon: ""
        property string text: ""
        property bool chevron: false
        signal clicked()

        width: content.implicitWidth + 26
        height: 34
        radius: height / 2
        readonly property real a: pillTap.pressed ? 0.34 : pillHover.hovered ? 0.26 : 0.18
        color: Qt.rgba(1 - root.boost, 1 - root.boost, 1 - root.boost, a * (1 - root.boost) + (a + 0.2) * root.boost)
        border.color: Qt.rgba(1, 1, 1, 0.22)
        border.width: 1
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: 7

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: pill.icon
                size: 17
                color: "white"
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                color: "white"
                weight: 600
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: pill.chevron
                name: "expand_less"
                size: 17
                color: "white"
                rotation: root.open && root.openList === "sessions" ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Motion.normal } }
            }
        }

        HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: pillTap; onTapped: pill.clicked() }
    }
}
