import QtQuick
import qs.common

// A row in a detail page: icon, name, a quiet status, and something on the
// right (a check, a lock...). `current` gives it the accent color. With
// `action` (an icon) and `actionText`, a small button on the right instead
// (actionClicked; the row's own click stays the row's).
MouseArea {
    id: root

    property string icon: ""
    property string label: ""
    property string detail: ""
    property string trailing: ""        // a Material icon name, or ""
    property string action: ""          // a Material icon name: a button on the right
    property string actionText: ""
    signal actionClicked()
    property bool current: false
    property bool busy: false           // connecting: the icon's shape turns
    default property alias below: extra.data

    implicitHeight: 48 + extra.implicitHeight
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        radius: Style.inner(Style.ccRadius, Style.ccPadding)
        color: root.current ? Style.alpha(Colors.primary, 0.16) : Colors.textOnSurface
        opacity: root.current ? 1 : root.pressed ? Style.pressTint : root.containsMouse ? Style.hoverTint : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
    }

    Item {
        id: badge
        x: 8
        y: 8
        width: 32
        height: 32

        Shape {
            anchors.fill: parent
            shape: root.current ? "Cookie9Sided" : "Circle"
            color: root.current ? Colors.primary : Style.alpha(Colors.textOnSurface, 0.1)
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            RotationAnimation on rotation {
                running: root.busy
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 1600
            }
        }
        Icon {
            anchors.centerIn: parent
            name: root.icon
            size: 18
            fill: root.current ? 1 : 0
            color: root.current ? Colors.textOnPrimary : Colors.textOnSurface
        }
    }

    Column {
        anchors.left: badge.right
        anchors.leftMargin: 12
        anchors.right: root.action !== "" ? act.left : trail.left
        anchors.rightMargin: 8
        y: root.detail !== "" ? 7 : 14

        StyledText {
            width: parent.width
            text: root.label
            weight: root.current ? 700 : 550
            color: root.current ? Colors.primary : Colors.textOnSurface
            elide: Text.ElideRight
        }
        StyledText {
            width: parent.width
            text: root.detail
            visible: text !== ""
            role: "caption"
            color: Colors.textOnSurfaceVariant
            elide: Text.ElideRight
        }
    }

    Icon {
        id: trail
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: 14
        name: root.trailing
        size: 18
        color: Colors.textOnSurfaceVariant
        visible: root.trailing !== "" && root.action === ""
        // Glyphs are square: the size, not implicitWidth (which loops
        // through the Text's own layout).
        width: visible ? size : 0
    }

    Clickable {
        id: act
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: undefined
        y: 8
        implicitHeight: 32
        padding: 10
        visible: root.action !== ""
        onClicked: root.actionClicked()

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.action
            size: 18
            color: root.current ? Colors.primary : Colors.textOnSurface
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            text: root.actionText
            role: "label"
            weight: 600
            color: root.current ? Colors.primary : Colors.textOnSurface
        }
    }

    // Extra content under the row (e.g. a password field).
    Column {
        id: extra
        anchors.left: parent.left
        anchors.right: parent.right
        y: 48
    }
}
