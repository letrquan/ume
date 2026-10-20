import QtQuick
import QtQuick.Effects
import qs.common

// The glass of a desktop widget. mango doesn't blur behind the desktop
// layer (its no_blur rule keeps the clock's text shadow clean), so the tint
// is thicker than the bar's (Style.desktopWidgetOpacity) and a soft shadow
// lifts it off a busy wallpaper. Content goes inside, `padding` from the edge.
Item {
    id: root

    default property alias content: inner.data
    property real padding: 14
    property real radius: 22

    RectangularShadow {
        anchors.fill: glass
        radius: glass.radius
        offset.y: 3
        blur: 18
        spread: 0
        color: Qt.rgba(0, 0, 0, 0.32)
    }

    Rectangle {
        id: glass
        anchors.fill: parent
        radius: root.radius
        color: Style.alpha(Colors.surfaceContainer, Style.desktopWidgetOpacity)
        border.color: Style.islandBorder
        border.width: Style.islandBorderWidth

        // Soft light on the top half, like the islands.
        Rectangle {
            anchors.fill: parent
            anchors.margins: glass.border.width
            radius: Math.max(0, glass.radius - glass.border.width)
            visible: Style.islandSheen > 0
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Style.islandSheen) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
    }

    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: root.padding
    }
}
