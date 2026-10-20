import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.common
import qs.services

// What's playing, inside the clock island (the island grows to make room).
// Click: the Now Playing card (the island grows into a player); a click on
// the little cover, or a middle click: play/pause; right click: next;
// scroll: next/previous. With Style.nowPlayingEnabled off, a click plays or
// pauses as before. Hovering the island shows previous/next buttons. Little
// bars dance to the music while it plays (MusicBars.qml).
Reveal {
    id: root

    // Set by the bar: the mouse is over the island this sits in.
    property bool islandHovered: false

    // The first player that's playing, else the first one at all.
    readonly property var player: {
        const list = Mpris.players.values;
        return list.find(p => p.isPlaying) ?? list[0] ?? null;
    }
    readonly property bool playing: player?.isPlaying ?? false
    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""

    anchors.verticalCenter: parent?.verticalCenter
    shown: title !== ""

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
                    source: root.player?.trackArtUrl ?? ""
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

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Style.mediaMaxWidth)
                rightPadding: 4
                text: root.artist !== "" ? root.title + "  ·  " + root.artist : root.title
                elide: Text.ElideRight
                color: root.playing ? Colors.textOnSurface : Colors.textOnSurfaceVariant
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
