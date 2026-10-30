import QtQuick
import qs.common

// One app in the launcher's grid (AppGrid): its icon, big enough for a
// finger, and its name under it (two lines at most). A tap opens it; a long
// press or a right click opens its menu (AppMenu). Flicking the grid from
// a tile doesn't open anything.
Item {
    id: root

    required property var modelData     // Apps.gridApps: { title, icon, entry }
    required property int index
    property bool selected: false
    property real iconSize: 60
    // Taps wait while an app's menu is open over the grid.
    property bool frozen: false

    signal hoveredTile(int index)
    signal chosen(int index)
    signal menuRequested(int index)

    width: GridView.view?.cellWidth ?? 0
    height: GridView.view?.cellHeight ?? 0

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: 20
        color: Style.alpha(Colors.primary, 0.16)
        opacity: root.selected ? 1 : 0
        scale: root.selected ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        Behavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }
    }

    AppIcon {
        id: icon
        anchors.horizontalCenter: parent.horizontalCenter
        y: 10
        width: root.iconSize
        height: root.iconSize
        source: root.modelData.icon
        name: root.modelData.title
        scale: tap.pressed ? 0.88 : 1
        Behavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }
    }

    StyledText {
        anchors.top: icon.bottom
        anchors.topMargin: 6
        x: 6
        width: parent.width - 12
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignTop
        text: root.modelData.title
        role: "label"
        weight: 550
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        color: root.selected ? Colors.primary : Colors.textOnSurface
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    // Only a real mouse move selects (see ResultRow); taps are the handlers'.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: root.hoveredTile(root.index)
    }
    TapHandler {
        id: tap
        enabled: !root.frozen
        longPressThreshold: 0.45
        onTapped: root.chosen(root.index)
        onLongPressed: root.menuRequested(root.index)
    }
    TapHandler {
        enabled: !root.frozen
        acceptedButtons: Qt.RightButton
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onTapped: root.menuRequested(root.index)
    }
}
