import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.common

// The mac style's now playing: a small frosted card under the time with
// the cover, the song, the artist and ⏯. It shows once something plays
// and then stays for the rest of the lock (so a paused song can go on).
Item {
    id: root

    required property Item source      // the lock's background, for the frost
    property rect area: Qt.rect(x, y, width, height)
    // 0 → 1 as the picture behind gets bright: a darker card.
    property real boost: 0

    // The first player that plays, else the first one at all.
    readonly property var player: {
        const list = Mpris.players.values;
        return list.find(p => p.isPlaying) ?? list[0] ?? null;
    }
    readonly property bool hasMedia: player !== null && (player.trackTitle ?? "") !== ""
    readonly property bool playing: player?.isPlaying ?? false
    property bool seen: false
    onPlayingChanged: if (playing) seen = true
    Component.onCompleted: if (playing) seen = true
    readonly property bool wanted: hasMedia && seen

    implicitWidth: 320
    implicitHeight: 64

    Frosted {
        anchors.fill: parent
        source: root.source
        area: root.area
        radius: 20
        tint: Qt.rgba(1 - root.boost, 1 - root.boost, 1 - root.boost, 0.16 * (1 - root.boost) + 0.38 * root.boost)
        saturation: -0.5
    }

    ClippingRectangle {
        id: cover
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 44
        height: 44
        radius: 10
        color: Qt.rgba(1, 1, 1, 0.18)

        Icon {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            name: "music_note"
            size: 22
            color: "white"
        }
        Image {
            id: art
            anchors.fill: parent
            source: root.player?.trackArtUrl ?? ""
            sourceSize: Qt.size(96, 96)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    Column {
        anchors.left: cover.right
        anchors.leftMargin: 12
        anchors.right: playButton.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        StyledText {
            width: parent.width
            text: root.player?.trackTitle ?? ""
            color: "white"
            weight: 650
            elide: Text.ElideRight
        }
        StyledText {
            width: parent.width
            visible: text !== ""
            text: root.player?.trackArtist ?? ""
            color: Qt.rgba(1, 1, 1, 0.72)
            elide: Text.ElideRight
        }
    }

    Item {
        id: playButton
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 34
        height: 34

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(1, 1, 1, tap.pressed ? 0.3 : hover.hovered ? 0.2 : 0)
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
        Icon {
            anchors.centerIn: parent
            name: root.playing ? "pause" : "play_arrow"
            size: 24
            color: "white"
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: tap
            onTapped: if (root.player?.canTogglePlaying) root.player.togglePlaying()
        }
    }
}
