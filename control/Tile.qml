import QtQuick
import qs.common

// A big toggle tile:  [shape+icon]  Wi-Fi          ›
//                                    Home 5G
// Click the tile to switch it, the arrow for its page. When on, it fills
// with the accent color and its shape turns into a cookie. With
// `hasSecondary`, a right click or a long press does `secondary` instead.
Item {
    id: root

    property string icon: ""
    property string label: ""
    property string detail: ""
    property bool active: false
    property bool hasPage: false
    property bool hasSecondary: false

    signal toggled()
    signal openPage()
    signal secondary()

    implicitHeight: Style.ccTileHeight

    Rectangle {
        id: body
        anchors.fill: parent
        radius: Style.inner(Style.ccRadius, Style.ccPadding)
        color: root.active ? Colors.primary : Style.alpha(Colors.textOnSurface, 0.08)
        scale: main.pressed ? 0.96 : 1

        Behavior on color { ColorAnimation { duration: Motion.normal } }
        Behavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }

        // Hover tint.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: root.active ? Colors.textOnPrimary : Colors.textOnSurface
            opacity: main.containsMouse || arrow.containsMouse ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
    }

    MouseArea {
        id: main
        anchors.fill: parent
        anchors.rightMargin: root.hasPage ? arrow.width : 0
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: root.hasSecondary ? Qt.LeftButton | Qt.RightButton : Qt.LeftButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.secondary();
            else
                root.toggled();
        }
        // (No click follows a long press.)
        onPressAndHold: if (root.hasSecondary) root.secondary()
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: root.hasPage ? arrow.width : 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36

            Shape {
                anchors.fill: parent
                shape: root.active ? "Cookie9Sided" : "Circle"
                color: root.active ? Colors.primaryContainer : Style.alpha(Colors.textOnSurface, 0.1)
                rotation: root.active ? 0 : -40
                Behavior on rotation {
                    NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                }
                Behavior on color { ColorAnimation { duration: Motion.normal } }
            }
            Icon {
                anchors.centerIn: parent
                name: root.icon
                size: 19
                fill: root.active ? 1 : 0
                color: root.active ? Colors.textOnPrimaryContainer : Colors.textOnSurface
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 36 - parent.spacing

            StyledText {
                width: parent.width
                text: root.label
                weight: 650
                color: root.active ? Colors.textOnPrimary : Colors.textOnSurface
                elide: Text.ElideRight
            }
            StyledText {
                width: parent.width
                text: root.detail
                visible: text !== ""
                role: "caption"
                color: root.active ? Style.alpha(Colors.textOnPrimary, 0.75) : Colors.textOnSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }

    // The arrow to the tile's page.
    MouseArea {
        id: arrow
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.hasPage ? 34 : 0
        visible: root.hasPage
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openPage()

        Icon {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -4
            name: "chevron_right"
            size: 20
            color: root.active ? Colors.textOnPrimary : Colors.textOnSurfaceVariant
        }
    }
}
