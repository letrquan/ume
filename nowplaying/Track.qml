import QtQuick
import qs.common

// A slim bar for the Now Playing card: how far into the song (or how loud).
// Drag or click to set it; scroll steps it. While playing, the seek bar
// glides between the player's once-a-second positions (`glide`); a jump (a
// seek, a new song) moves at once.
Item {
    id: root

    property real value: 0              // 0-1, from the player
    property color accent: Colors.primary
    property real step: 0.05            // per scroll step
    // Glide to a new value over this many ms when it's a small step forward
    // (0 = never glide).
    property int glide: 0
    property real glideLimit: 0.02      // bigger steps than this jump

    // While dragging: as you go (the volume follows at once).
    signal moved(real value)
    // On release, a click or a scroll step (the seek bar seeks here only).
    signal committed(real value)

    property bool dragging: false
    property real dragValue: 0
    readonly property real shown: Math.max(0, Math.min(1, dragging ? dragValue : animated))
    readonly property bool lit: dragging || area.containsMouse

    implicitHeight: 20

    // What shows when not dragging: the value, gliding between small steps.
    property real animated: value
    onValueChanged: {
        if (glide > 0 && value >= animated && value - animated < glideLimit) {
            ease.to = value;
            ease.restart();
        } else {
            ease.stop();
            animated = value;
        }
    }
    NumberAnimation {
        id: ease
        target: root
        property: "animated"
        duration: root.glide
    }

    function valueAt(x) {
        return Math.max(0, Math.min(1, x / width));
    }

    Rectangle {
        id: track
        width: parent.width
        height: root.lit ? 6 : 4
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        color: Style.alpha(Colors.textOnSurface, 0.16)

        Behavior on height { NumberAnimation { duration: Motion.fast } }

        Rectangle {
            height: parent.height
            width: Math.max(parent.height, parent.width * root.shown)
            radius: height / 2
            color: root.accent
            Behavior on color { ColorAnimation { duration: Motion.normal } }
        }
    }

    // The knob: only while the mouse is on it or dragging.
    Rectangle {
        x: (root.width - width) * root.shown
        anchors.verticalCenter: parent.verticalCenter
        width: 12
        height: 12
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.96)
        border.width: 0.5
        border.color: Style.alpha(Colors.shadow, 0.3)
        opacity: root.lit ? 1 : 0
        scale: root.dragging ? 1.15 : 1

        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        Behavior on scale { NumberAnimation { duration: Motion.fast } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: mouse => {
            // The value first: `shown` switches to it with `dragging`.
            root.dragValue = root.valueAt(mouse.x);
            root.dragging = true;
            root.moved(root.dragValue);
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            root.dragValue = root.valueAt(mouse.x);
            root.moved(root.dragValue);
        }
        onReleased: {
            root.committed(root.dragValue);
            root.dragging = false;
        }
        onCanceled: root.dragging = false
        onWheel: wheel => {
            const by = (wheel.angleDelta.y || -wheel.angleDelta.x) > 0 ? root.step : -root.step;
            root.committed(Math.max(0, Math.min(1, root.value + by)));
        }
    }
}
