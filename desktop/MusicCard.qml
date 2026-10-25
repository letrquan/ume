import QtQuick
import Quickshell.Widgets
import qs.common
import qs.services

// What's playing, on the desktop: cover, title, artist, a thin progress
// line and ⏮ ⏯ ⏭, the cover's colors through the glass, and with timed
// lyrics (Style.lyricsOnDesktop) the song's lines under them (CardLyrics).
// Only there while a player has a track (`wanted`). The card takes clicks
// (buttons, lyrics): DesktopWindow lets clicks through everywhere else.
DesktopCard {
    id: root

    // The player the whole shell shows (common/Players.qml).
    readonly property var player: Players.active
    readonly property bool wanted: player !== null && (player.trackTitle ?? "") !== ""
    readonly property bool playing: player?.isPlaying ?? false
    readonly property real length: player?.length ?? 0
    property real position: 0

    implicitWidth: 320
    implicitHeight: 88 + (lyricRoom ? lyrics.implicitHeight + 10 : 0)

    // ---- Lyrics (services/Lyrics.qml) ---------------------------------------------------
    // The card grows when the song has timed lyrics (the desktop window
    // resizes then, never per line) and stays grown into the next song
    // while its lyrics are looked up, like the bar's slot (bar/Media.qml).
    property bool lyricMode: false
    // Room for them until they've faded out.
    readonly property bool lyricRoom: lyricMode || lyrics.visible
    readonly property bool lyricsHere: Style.lyricsEnabled && Style.lyricsOnDesktop && Lyrics.player === player

    function updateMode() {
        if (lyricsHere && Lyrics.synced)
            lyricMode = true;
        else if (!lyricsHere || !Lyrics.pending)
            lyricMode = false;
    }
    // A moment later (Qt.callLater), once Lyrics' bindings agree on the
    // new song (synced and pending change in the same instant).
    onLyricsHereChanged: Qt.callLater(updateMode)
    Connections {
        target: Lyrics
        function onSyncedChanged() {
            Qt.callLater(root.updateMode);
        }
        function onPendingChanged() {
            Qt.callLater(root.updateMode);
        }
    }
    Component.onCompleted: {
        Lyrics.desktopViews++;
        updateMode();
    }
    Component.onDestruction: Lyrics.desktopViews--

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

    // The cover's colors through the glass (Style.desktopMusicTint): the
    // picture shrunk to a few pixels and stretched over the whole card, a
    // soft blend of its colors with no blur pass (drawn once per song),
    // darkened a little so white text stays easy to read.
    Item {
        x: -root.padding
        y: -root.padding
        width: root.width
        height: root.height
        visible: Style.desktopMusicTint > 0 && tintArt.status === Image.Ready
        opacity: Style.desktopMusicTint

        Image {
            id: tintArt
            visible: false
            source: Players.art(root.player)
            sourceSize: Qt.size(6, 6)
            smooth: true
            asynchronous: true
        }
        RoundedTexture {
            anchors.fill: parent
            source: tintArt
            radius: root.radius
        }
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: Style.alpha(Colors.surface, 0.3)
        }
    }

    // Cover, song and buttons.
    Item {
        id: top
        width: parent.width
        height: 60

        ClippingRectangle {
            id: art
            width: 60
            height: 60
            anchors.verticalCenter: parent.verticalCenter
            radius: 14
            color: Colors.secondaryContainer

            Image {
                anchors.fill: parent
                source: Players.art(root.player)
                sourceSize: Qt.size(120, 120)
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

    CardLyrics {
        id: lyrics
        anchors.top: top.bottom
        anchors.topMargin: 10
        width: parent.width
        height: implicitHeight
        shown: root.lyricMode
    }
}
