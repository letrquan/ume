import QtQuick

// A floating glass pill. Things inside go in a row and the island sizes
// itself around them, so it grows and shrinks smoothly when something inside
// slides in or out. At start it drops in from just above, `delay` ms after
// the wallpaper has come in (common/Intro.qml).
Item {
    id: root

    default property alias content: row.data
    property int delay: 0
    // While something stands in for the island (a notification, the
    // launcher, the control center growing out of it): its glass goes at
    // once (the stand-in has the very same glass in the very same place,
    // see MorphCard) and only what's inside fades.
    property bool hidden: false
    readonly property bool hovered: hover.hovered

    implicitWidth: row.implicitWidth + Style.islandPadding * 2
    implicitHeight: Style.islandHeight
    opacity: 0
    // Moves only what you see; the island's real place (and its click area)
    // stays put.
    transform: Translate {
        id: drop
        y: -18
    }

    HoverHandler {
        id: hover
    }

    Glass {
        anchors.fill: parent
        visible: !root.hidden
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Style.islandSpacing
        opacity: root.hidden ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: root.hidden ? Motion.contentOut : Motion.contentIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.hidden ? Motion.emphasizedAccel : Motion.emphasizedDecel
            }
        }
    }

    // Waits for the wallpaper (Intro); with the intro off, Intro.started is
    // already true and this runs at once, as it always did.
    Component.onCompleted: if (Intro.started) dropIn.start()
    Connections {
        target: Intro
        function onStartedChanged() {
            if (Intro.started)
                dropIn.start();
        }
    }

    SequentialAnimation {
        id: dropIn
        PauseAnimation { duration: root.delay }
        ParallelAnimation {
            NumberAnimation {
                target: drop; property: "y"; to: 0
                duration: Motion.slow; easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.defaultSpatial
            }
            NumberAnimation {
                target: root; property: "opacity"; to: 1
                duration: Motion.normal; easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.defaultEffects
            }
        }
    }
}
