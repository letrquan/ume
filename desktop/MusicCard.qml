import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.common

// What's playing, on the desktop: cover, title, artist, a thin progress
// line and ⏮ ⏯ ⏭. Only there while a player has a track (`wanted`). The
// buttons take clicks: DesktopWindow lets clicks through everywhere else.
DesktopCard {
    id: root

    readonly property var player: {
        const list = Mpris.players.values;
        return list.find(p => p.isPlaying) ?? list[0] ?? null;
    }
    readonly property bool wanted: player !== null && (player.trackTitle ?? "") !== ""
    readonly property bool playing: player?.isPlaying ?? false
    readonly property real length: player?.length ?? 0
    property real position: 0

    implicitWidth: 320
    implicitHeight: 88

    // Mpris doesn't push the position: read it once a second while playing
    // (no smooth animation in between, so nothing redraws otherwise).
    Timer {
        running: root.visible && root.playing && root.length > 0
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.position = root.player?.position ?? 0
    }
    onPlayerChanged: position = player?.position ?? 0

    ClippingRectangle {
        id: art
        width: 60
        height: 60
        anchors.verticalCenter: parent.verticalCenter
        radius: 14
        color: Colors.secondaryContainer

        Image {
            anchors.fill: parent
            source: root.player?.trackArtUrl ?? ""
            sourceSize: Qt.size(120, 120)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Icon {
            anchors.centerIn: parent
            visible: (root.player?.trackArtUrl ?? "") === ""
            name: "music_note"
            color: Colors.textOnSecondaryContainer
        }
    }

    Column {
        anchors.left: art.right
        anchors.leftMargin: 12
        anchors.right: controls.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
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

        // How far along: a thin line.
        Item {
            width: parent.width
            height: 10
            visible: root.length > 0

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 3
                radius: 1.5
                color: Style.alpha(Colors.textOnSurface, 0.14)

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.position / Math.max(1, root.length)))
                    height: parent.height
                    radius: parent.radius
                    color: Colors.primary
                }
            }
        }
    }

    Row {
        id: controls
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Clickable {
            enabled: root.player?.canGoPrevious ?? false
            opacity: enabled ? 1 : 0.4
            onClicked: root.player.previous()
            Icon { name: "skip_previous"; size: 20 }
        }

        // Play / pause on a shape that softens while playing.
        MouseArea {
            width: 38
            height: 38
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
}
