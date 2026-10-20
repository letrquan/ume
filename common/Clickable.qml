import QtQuick

// Something clickable inside an island: a row of icons/text with a round
// hover highlight and a little squish when pressed. Never narrower than it
// is tall, so a single icon gets a circle.
MouseArea {
    id: root

    default property alias content: row.data
    property alias spacing: row.spacing
    property real padding: 6
    // Its tip on the bar, after a moment (common/Tooltips.qml): `tip` the
    // first line, `tipDetail` quieter lines under it, `tipShortcut` which
    // keys to show next to it ("mine:session", "func:switch_layout", looked
    // up in mango's binds by bar/TooltipView.qml). No tip: nothing happens.
    property string tip: ""
    property string tipDetail: ""
    property string tipShortcut: ""

    anchors.verticalCenter: parent?.verticalCenter
    implicitWidth: Math.max(row.implicitWidth + padding * 2, implicitHeight)
    implicitHeight: Style.itemHeight
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: {
        if (containsMouse ? Tooltips.hasTip(root) : Tooltips.hovered === root)
            Tooltips.hover(root, containsMouse);
    }
    onPressed: if (Tooltips.hovered === root || Tooltips.source === root) Tooltips.press(root)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Colors.textOnSurface
        opacity: root.pressed ? Style.pressTint : root.containsMouse ? Style.hoverTint : 0

        Behavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastEffects }
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        scale: root.pressed ? Style.pressScale : 1

        Behavior on scale {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
        }
    }
}
