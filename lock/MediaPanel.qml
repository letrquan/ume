import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris
import qs.common

// Now playing, as a tall card: the cover in a turning cookie, title,
// artist and ⏮ ⏯ ⏭. A quiet placeholder when nothing plays.
LockCard {
    id: root

    // The first player that plays, else the first one at all.
    readonly property var player: {
        const list = Mpris.players.values;
        return list.find(p => p.isPlaying) ?? list[0] ?? null;
    }
    readonly property bool hasMedia: player !== null && (player.trackTitle ?? "") !== ""
    readonly property bool playing: player?.isPlaying ?? false

    title: "Now playing"
    titleIcon: "music_note"

    Item {
        id: art
        width: Math.max(0, Math.min(parent.width, parent.height - 110))
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: root.hasMedia ? 1 : 0.5

        property real spin: 0
        NumberAnimation on spin {
            running: root.playing
            from: art.spin
            to: art.spin + 360
            duration: 24000
            loops: Animation.Infinite
        }

        Shape {
            anchors.fill: parent
            shape: "Cookie9Sided"
            rotation: art.spin
            color: Colors.secondaryContainer
        }
        Icon {
            anchors.centerIn: parent
            visible: cover.status !== Image.Ready
            name: root.hasMedia ? "music_note" : "music_off"
            size: parent.width * 0.32
            color: Colors.textOnSecondaryContainer
        }
        Image {
            id: cover
            anchors.fill: parent
            source: root.player?.trackArtUrl ?? ""
            sourceSize: Qt.size(256, 256)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        Item {
            id: mask
            anchors.fill: parent
            visible: false
            layer.enabled: true

            Shape {
                anchors.fill: parent
                shape: "Cookie9Sided"
                rotation: art.spin
                color: "white"
            }
        }
        MultiEffect {
            anchors.fill: parent
            visible: cover.status === Image.Ready
            source: cover
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    Column {
        anchors.top: art.bottom
        anchors.topMargin: 10
        width: parent.width
        spacing: 2

        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.hasMedia ? root.player.trackTitle : "Nothing playing"
            role: "title"
            color: root.hasMedia ? Colors.textOnSurface : Colors.textOnSurfaceVariant
            elide: Text.ElideRight
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: root.hasMedia && text !== ""
            text: root.player?.trackArtist ?? ""
            color: Colors.textOnSurfaceVariant
            elide: Text.ElideRight
        }
    }

    component Control: Item {
        id: ctl

        property string icon
        property bool primary: false
        signal clicked()

        width: primary ? 46 : 36
        height: width

        Shape {
            anchors.fill: parent
            shape: ctl.primary && root.playing ? "Cookie6Sided" : "Circle"
            color: ctl.primary ? Colors.primary
                 : hover.hovered ? Style.alpha(Colors.textOnSurface, Style.hoverTint) : "transparent"
            scale: tap.pressed ? Style.pressScale : 1
            Behavior on scale {
                NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial }
            }
        }
        Icon {
            anchors.centerIn: parent
            name: ctl.icon
            size: ctl.primary ? 24 : 22
            color: ctl.primary ? Colors.textOnPrimary : Colors.textOnSurface
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tap; onTapped: ctl.clicked() }
    }

    Row {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10
        enabled: root.hasMedia
        opacity: root.hasMedia ? 1 : 0.4

        Control {
            anchors.verticalCenter: parent.verticalCenter
            icon: "skip_previous"
            onClicked: root.player?.previous()
        }
        Control {
            icon: root.playing ? "pause" : "play_arrow"
            primary: true
            onClicked: root.player?.togglePlaying()
        }
        Control {
            anchors.verticalCenter: parent.verticalCenter
            icon: "skip_next"
            onClicked: root.player?.next()
        }
    }
}
