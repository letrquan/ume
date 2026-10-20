import QtQuick
import qs.common

// An island on the lock screen, the same pill as the bar's (Style.island*),
// in frosted glass (see Frosted). It drops in from above `delay` ms after
// `presence` turns 1 and goes back up when it turns 0 (unlocking).
Item {
    id: root

    required property Item source      // the lock screen's background
    property real presence: 0
    property int delay: 0
    default property alias content: row.data

    implicitWidth: row.implicitWidth + Style.islandPadding * 2
    implicitHeight: Style.islandHeight

    property real p: 0
    opacity: p
    // Moves only what you see; the glass samples the island's real place.
    transform: Translate { y: -(1 - root.p) * (Style.islandHeight + Style.marginEdge) }

    onPresenceChanged: animate()
    Component.onCompleted: animate()
    function animate() {
        drop.stop();
        pause.duration = presence > 0 ? delay : 0;
        num.to = presence > 0 ? 1 : 0;
        num.duration = presence > 0 ? Motion.slow : Motion.fast;
        num.easing.bezierCurve = presence > 0 ? Motion.defaultSpatial : Motion.emphasizedAccel;
        drop.start();
    }
    SequentialAnimation {
        id: drop
        PauseAnimation { id: pause }
        NumberAnimation { id: num; target: root; property: "p"; easing.type: Easing.BezierSpline }
    }

    Frosted {
        anchors.fill: parent
        source: root.source
        area: Qt.rect(root.x, root.y, root.width, root.height)
        radius: Style.islandRadius
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Style.islandSpacing
    }
}
