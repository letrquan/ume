import QtQuick
import Quickshell.Widgets
import qs.common
import qs.services

// What's playing, inside the clock island (the island grows to make room).
// Click: the Now Playing card (the island grows into a player); a click on
// the little cover, or a middle click: play/pause; right click: next;
// scroll: next/previous. With Style.nowPlayingEnabled off, a click plays or
// pauses as before. Hovering the island shows previous/next buttons. Little
// bars dance to the music while it plays (MusicBars.qml). With timed lyrics
// (Style.lyricsInBar) the line being sung shows instead of the name.
Reveal {
    id: root

    // Set by the bar: the mouse is over the island this sits in.
    property bool islandHovered: false

    // The player the whole shell shows (common/Players.qml).
    readonly property var player: Players.active
    readonly property bool playing: player?.isPlaying ?? false
    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""

    readonly property string song: artist !== "" ? title + "  ·  " + artist : title

    anchors.verticalCenter: parent?.verticalCenter
    shown: title !== ""

    // ---- Lyrics (services/Lyrics.qml) ---------------------------------------------------
    // With timed lyrics the song's name gives way to the line being sung,
    // in a slot of fixed width (Style.lyricsBarWidth): the island changes
    // size when the slot opens or closes, never per line. The slot stays
    // open into the next song while its lyrics are looked up (showing its
    // name), so a run of songs with lyrics doesn't move the island at all.
    property bool lyricMode: false
    readonly property bool lyricsHere: Style.lyricsEnabled && Style.lyricsInBar && Lyrics.player === player
    readonly property string lineText: lyricMode && lyricsHere && Lyrics.synced && Lyrics.index >= 0
        ? (Lyrics.line !== "" ? Lyrics.line : "♪") : song

    function updateMode() {
        // Under a card (the island is hidden): keep its size until it's back.
        if (IslandState.takenOver)
            return;
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
    Connections {
        target: IslandState
        function onTakenOverChanged() {
            Qt.callLater(root.updateMode);
        }
    }
    Component.onCompleted: {
        Lyrics.barViews++;
        updateMode();
    }
    Component.onDestruction: Lyrics.barViews--

    Row {
        Divider {}

        Clickable {
            id: track

            padding: 4
            spacing: 8
            tip: root.title
            tipDetail: [[root.artist, root.player?.trackAlbum ?? ""].filter(s => s !== "").join(" — "),
                        root.player?.identity ?? "",
                        Style.nowPlayingEnabled ? "Click: the player · the cover: play/pause" : ""]
                .filter(s => s !== "").join("\n")
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    root.player?.next();
                else if (mouse.button === Qt.MiddleButton || !Style.nowPlayingEnabled)
                    root.player?.togglePlaying();
                else
                    NowPlayingState.toggle();
            }
            onWheel: wheel => {
                if (wheel.angleDelta.y > 0)
                    root.player?.previous();
                else if (wheel.angleDelta.y < 0)
                    root.player?.next();
            }

            // Cover art, with play/pause on top while paused or hovered.
            ClippingRectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                radius: 10
                color: Colors.secondaryContainer

                Image {
                    id: art
                    anchors.fill: parent
                    source: Players.art(root.player)
                    sourceSize: Qt.size(40, 40)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: root.playing && !track.containsMouse ? 1 : 0.45

                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                Icon {
                    anchors.centerIn: parent
                    name: root.playing ? "pause" : "play_arrow"
                    size: 14
                    color: art.status === Image.Ready ? "white" : Colors.textOnSecondaryContainer
                    opacity: art.status !== Image.Ready || !root.playing || track.containsMouse ? 1 : 0

                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                // The cover shows ⏯ under the mouse: a click there plays or
                // pauses (right and middle clicks go on to the song).
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -2
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.player?.togglePlaying()
                }
            }

            // The song's name, or (lyricMode) the line being sung in a
            // slot of fixed width.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: root.lyricMode ? Style.lyricsBarWidth : songText.width
                height: songText.implicitHeight

                StyledText {
                    id: songText
                    width: Math.min(implicitWidth, Style.mediaMaxWidth)
                    visible: !root.lyricMode
                    rightPadding: 4
                    text: root.song
                    elide: Text.ElideRight
                    color: root.playing ? Colors.textOnSurface : Colors.textOnSurfaceVariant
                }
                LyricLine {
                    width: Style.lyricsBarWidth - 4
                    height: parent.height
                    visible: root.lyricMode
                    text: root.lineText
                    color: root.playing ? Colors.textOnSurface : Colors.textOnSurfaceVariant
                }
            }

            // Bars dancing to the music (cava), while it plays.
            MusicBars {}
        }

        Reveal {
            anchors.verticalCenter: parent.verticalCenter
            shown: root.islandHovered

            Row {
                Clickable {
                    tip: "Previous"
                    tipShortcut: "mine:key previous"
                    onClicked: root.player?.previous()
                    Icon { name: "skip_previous"; size: 18 }
                }
                Clickable {
                    tip: "Next"
                    tipShortcut: "mine:key next"
                    onClicked: root.player?.next()
                    Icon { name: "skip_next"; size: 18 }
                }
            }
        }
    }
}
