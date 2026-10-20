import QtQuick
import Quickshell.Widgets
import qs.common
import qs.services

// One window on the dock's preview card: a picture of it
// (services/WindowShots.qml, taken again about every second while the card
// is out; the app's icon until the first one is in), its title under it, ✕
// on hover. Click: go to it; middle-click: close it.
Item {
    id: root

    required property var modelData      // Toplevel
    property var app: null               // DockState item, for the icon
    // Show its picture (the card asks for them while it's out).
    property bool pictures: false
    // mango's { id, ftid, width, height } for this window.
    readonly property var info: WindowShots.infoFor(modelData)

    signal picked()

    readonly property real pictureHeight: Style.dockPreviewSize
    readonly property bool hasPicture: root.pictures && picture.ready
    // The window's shape (kept within reason).
    readonly property real aspect: info ? Math.max(0.6, Math.min(2.2, info.width / info.height)) : 1.6
    readonly property bool hovered: pointer.containsMouse || closeArea.containsMouse

    width: Math.round(pictureHeight * aspect)
    height: pictureHeight + 26

    Behavior on width {
        NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
    }

    ClippingRectangle {
        id: frame
        width: parent.width
        height: root.pictureHeight
        radius: 12
        color: Style.alpha(Colors.textOnSurface, 0.06)
        scale: pointer.pressed ? 0.97 : 1

        Behavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }

        // Until (or unless) there's a picture: the app's icon.
        AppIcon {
            anchors.centerIn: parent
            width: 44
            height: 44
            visible: !root.hasPicture
            source: DockState.iconFor(root.app)
            name: root.app?.entry?.name ?? root.app?.appId ?? ""
            sourceSize: Qt.size(88, 88)
        }

        // The picture (grim); a new one crossfades in over the last.
        CrossImage {
            id: picture
            anchors.fill: parent
            source: root.pictures ? WindowShots.url(root.info?.ftid ?? "", "dock") : ""
        }

        // Hover tint.
        Rectangle {
            anchors.fill: parent
            color: Colors.textOnSurface
            opacity: root.hovered ? Style.hoverTint : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
    }

    // The focused window gets an accent ring.
    Rectangle {
        anchors.fill: frame
        radius: frame.radius
        color: "transparent"
        border.width: 2
        border.color: Colors.primary
        visible: root.modelData?.activated ?? false
    }

    StyledText {
        anchors.top: frame.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, parent.width)
        text: root.modelData?.title || DockState.title(root.app)
        textFormat: Text.PlainText
        elide: Text.ElideRight
        role: "label"
        weight: root.modelData?.activated ? 650 : 500
    }

    MouseArea {
        id: pointer
        anchors.fill: frame
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                DockState.closeWindow(root.modelData);
            } else {
                DockState.focusWindow(root.modelData);
                root.picked();
            }
        }
    }

    // ✕ in the corner while the pointer is on the window.
    Rectangle {
        anchors.top: frame.top
        anchors.right: frame.right
        anchors.margins: 6
        width: 24
        height: 24
        radius: 12
        color: closeArea.containsMouse ? Colors.error : Style.alpha(Colors.surfaceContainer, 0.9)
        opacity: root.hovered ? 1 : 0
        scale: root.hovered ? 1 : 0.6
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        Behavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Icon {
            anchors.centerIn: parent
            name: "close"
            size: 15
            color: closeArea.containsMouse ? Colors.textOnError : Colors.textOnSurface
        }

        MouseArea {
            id: closeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: DockState.closeWindow(root.modelData)
        }
    }
}
