import QtQuick
import Quickshell.Widgets
import qs.common

// What's playing: cover, title, artist, ⏮ ⏯ ⏭ and a seek bar.
// Hidden when nothing plays.
Item {
    id: root

    // The player the whole shell shows (common/Players.qml).
    readonly property var player: Players.active
    readonly property bool playing: player?.isPlaying ?? false
    readonly property real length: player?.length ?? 0
    readonly property real position: player?.position ?? 0

    visible: player !== null && (player.trackTitle ?? "") !== ""
    implicitHeight: visible ? 104 : 0

    function time(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    // Mpris doesn't push the position: ask for it while we're on screen.
    Timer {
        running: root.visible && root.playing
        interval: 1000
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    Rectangle {
        anchors.fill: parent
        radius: Style.inner(Style.ccRadius, Style.ccPadding)
        color: Style.alpha(Colors.textOnSurface, 0.06)
    }

    ClippingRectangle {
        id: art
        x: 12
        y: 12
        width: 56
        height: 56
        radius: Style.inner(Style.inner(Style.ccRadius, Style.ccPadding), x)
        color: Colors.secondaryContainer

        Image {
            anchors.fill: parent
            source: Players.art(root.player)
            sourceSize: Qt.size(112, 112)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Icon {
            anchors.centerIn: parent
            visible: Players.art(root.player) === ""
            name: "music_note"
            color: Colors.textOnSecondaryContainer
        }
    }

    Column {
        anchors.left: art.right
        anchors.leftMargin: 12
        anchors.right: controls.left
        anchors.rightMargin: 8
        anchors.verticalCenter: art.verticalCenter
        spacing: 2

        StyledText {
            width: parent.width
            text: root.player?.trackTitle ?? ""
            weight: 650
            elide: Text.ElideRight
        }
        StyledText {
            width: parent.width
            text: root.player?.trackArtist ?? ""
            role: "caption"
            color: Colors.textOnSurfaceVariant
            elide: Text.ElideRight
        }
    }

    Row {
        id: controls
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: art.verticalCenter
        spacing: 2

        Clickable {
            enabled: root.player?.canGoPrevious ?? false
            opacity: enabled ? 1 : 0.4
            onClicked: root.player.previous()
            Icon { name: "skip_previous"; size: 20 }
        }

        // Play / pause on a shape that softens while playing.
        MouseArea {
            width: 40
            height: 40
            anchors.verticalCenter: parent.verticalCenter
            cursorShape: Qt.PointingHandCursor
            onClicked: root.player?.togglePlaying()

            Shape {
                anchors.fill: parent
                shape: root.playing ? "Cookie9Sided" : "Circle"
                color: Colors.primary
                scale: parent.pressed ? 0.9 : 1
                Behavior on scale {
                    NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
                }
            }
            Icon {
                anchors.centerIn: parent
                name: root.playing ? "pause" : "play_arrow"
                size: 22
                color: Colors.textOnPrimary
            }
        }

        Clickable {
            enabled: root.player?.canGoNext ?? false
            opacity: enabled ? 1 : 0.4
            onClicked: root.player.next()
            Icon { name: "skip_next"; size: 20 }
        }
    }

    // Seek bar with times.
    Item {
        x: 12
        y: 78
        width: parent.width - 24
        height: 16
        visible: root.length > 0

        StyledText {
            id: now
            anchors.verticalCenter: parent.verticalCenter
            text: root.time(root.position)
            role: "caption"
            font.features: ({ "tnum": 1 })
            color: Colors.textOnSurfaceVariant
        }
        StyledText {
            id: total
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.time(root.length)
            role: "caption"
            font.features: ({ "tnum": 1 })
            color: Colors.textOnSurfaceVariant
        }

        Rectangle {
            id: bar
            anchors.left: now.right
            anchors.leftMargin: 8
            anchors.right: total.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 4
            radius: 2
            color: Style.alpha(Colors.textOnSurface, 0.14)

            Rectangle {
                width: parent.width * Math.min(1, root.position / Math.max(1, root.length))
                height: parent.height
                radius: 2
                color: Colors.primary
                Behavior on width { NumberAnimation { duration: 900 } }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                enabled: root.player?.canSeek ?? false
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    const target = Math.max(0, Math.min(1, (mouse.x - 6) / bar.width)) * root.length;
                    root.player.position = target;
                }
            }
        }
    }
}
