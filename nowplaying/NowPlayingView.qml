import QtQuick
import Quickshell
import qs.common
import qs.services

// The Now Playing card. It grows out of the middle island (MorphCard) when
// you click the song, into a player in glass tinted from the cover:
//
//      ╭──────────────────────────────────────────╮
//      │ ┌──────┐  Spotify                        │
//      │ │cover │  Song title                     │
//      │ │      │  Artist · Album                 │
//      │ └──────┘  ▁▃▅▇▅▃                         │
//      │ ━━━━━━━━━━━━●──────────────────────────  │
//      │ 1:12                             -2:36   │
//      │  ⧉ ♪      ⏮     ⏯     ⏭        🔈 ━━━    │
//      │ [Spotify] [Brave]  (several players)     │
//      │   the line before                        │
//      │   The line being sung        (lyrics,    │
//      │   the next line               Lyrics.qml)│
//      ╰──────────────────────────────────────────╯
//
// Keys: Space plays/pauses, ←/→ seek (Style.nowPlayingSeekStep), ↑/↓
// volume (when the player has its own), N/P next/previous, Y lyrics on or
// off, Esc closes.
Item {
    id: root

    // Width of the middle island right now: where we start and end.
    property real startWidth: 200
    property bool open: false

    // While true the bar hides the real middle island.
    readonly property bool covering: morph.covering
    // Fully back in the island: the window can go.
    readonly property bool settled: morph.settled
    readonly property alias cardItem: morph.card

    signal closeRequested()

    readonly property var player: NowPlayingState.player
    readonly property bool playing: player?.isPlaying ?? false
    readonly property string artUrl: Players.art(player)
    readonly property real length: (player?.lengthSupported ?? false) ? (player?.length ?? 0) : 0
    readonly property bool canSeek: (player?.canSeek ?? false) && length > 0

    // The cover's colors (services/ArtColors.qml works them out with
    // matugen, once per cover): the glass is tinted with its primary
    // container, the bar and the play button take its primary.
    property var palette: null
    function readPalette() {
        palette = ArtColors.paletteFor(artUrl);
    }
    onArtUrlChanged: readPalette()
    Component.onCompleted: readPalette()
    Connections {
        target: ArtColors
        function onPaletteReady(key) {
            if (key === ArtColors.keyFor(root.artUrl))
                root.readPalette();
        }
    }
    readonly property color accentWanted: palette?.primary ?? Colors.primary
    readonly property color onAccentWanted: palette?.textOnPrimary ?? Colors.textOnPrimary
    readonly property color tintWanted: palette?.primaryContainer ?? Colors.primaryContainer
    // They glide to a new cover's colors. Started by hand: a Behavior on
    // these crashed Qt 6.12 while the card was being created (in
    // QQmlData::deferData, from the LazyLoader's incubator).
    property color accent: accentWanted
    property color onAccent: onAccentWanted
    property color tint: tintWanted
    onAccentWantedChanged: glide(accentAnim, accentWanted)
    onOnAccentWantedChanged: glide(onAccentAnim, onAccentWanted)
    onTintWantedChanged: glide(tintAnim, tintWanted)
    function glide(anim, to) {
        anim.to = to;
        anim.restart();
    }
    ColorAnimation { id: accentAnim; target: root; property: "accent"; duration: Motion.slow }
    ColorAnimation { id: onAccentAnim; target: root; property: "onAccent"; duration: Motion.slow }
    ColorAnimation { id: tintAnim; target: root; property: "tint"; duration: Motion.slow }

    function focusKeys() {
        keys.forceActiveFocus();
    }

    // ---- Where the song is ----------------------------------------------------------------
    // Mpris doesn't push the position: ask for it once a second while the
    // card is open (the seek bar glides in between).
    Timer {
        running: root.open && root.playing && (root.player?.positionSupported ?? false)
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.player?.positionChanged()
    }
    // A seek shows where it went at once, before the player says so.
    property real wanted: -1
    Timer {
        id: wantedHold
        interval: 1500
        onTriggered: root.wanted = -1
    }
    readonly property real playerPosition: player?.position ?? 0
    onPlayerPositionChanged: if (wanted >= 0 && Math.abs(playerPosition - wanted) < 1.5) wanted = -1
    readonly property real position: wanted >= 0 ? wanted : playerPosition

    function seekTo(seconds) {
        if (!canSeek)
            return;
        const s = Math.max(0, Math.min(length - 0.5, seconds));
        wanted = s;
        wantedHold.restart();
        player.position = s;
    }
    // A key while the card has the keyboard; false = not ours.
    function key(k) {
        const p = player;
        if (k === Qt.Key_Escape)
            closeRequested();
        else if (k === Qt.Key_Space || k === Qt.Key_K || k === Qt.Key_MediaTogglePlayPause)
            p?.togglePlaying();
        else if (k === Qt.Key_Left || k === Qt.Key_J)
            seekTo(position - Style.nowPlayingSeekStep);
        else if (k === Qt.Key_Right || k === Qt.Key_L)
            seekTo(position + Style.nowPlayingSeekStep);
        else if (k === Qt.Key_Up)
            setVolume((p?.volume ?? 0) + Style.volumeStep);
        else if (k === Qt.Key_Down)
            setVolume((p?.volume ?? 0) - Style.volumeStep);
        else if (k === Qt.Key_Y && Style.lyricsEnabled)
            Settings.set("lyricsInCard", !Style.lyricsInCard);
        else if (k === Qt.Key_N || k === Qt.Key_MediaNext)
            p?.next();
        else if (k === Qt.Key_P || k === Qt.Key_MediaPrevious)
            p?.previous();
        else
            return false;
        return true;
    }

    function setVolume(v) {
        if (player?.volumeSupported)
            player.volume = Math.max(0, Math.min(1, v));
    }

    function time(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        const h = Math.floor(s / 3600);
        const m = Math.floor(s / 60) % 60;
        const sec = String(s % 60).padStart(2, "0");
        return h > 0 ? h + ":" + String(m).padStart(2, "0") + ":" + sec : m + ":" + sec;
    }

    readonly property real pad: 16
    // Never narrower than the island it grows out of (a long song makes a
    // wide island); fixed when it opens, so a new song can't move it.
    property real cardWidth: Style.nowPlayingWidth
    onOpenChanged: if (open) cardWidth = Math.max(Style.nowPlayingWidth, Math.ceil(startWidth))

    MorphCard {
        id: morph

        anchors.fill: parent
        fromX: (width - root.startWidth) / 2
        fromY: Style.islandTop
        fromWidth: root.startWidth
        toWidth: root.cardWidth
        toHeight: content.implicitHeight + root.pad * 2
        radius: Style.nowPlayingRadius
        glassOpacity: Style.nowPlayingOpacity
        tint: root.tint
        tintStrength: Style.nowPlayingTint
        open: root.open

        // Clicks on the card stay on the card; scrolling changes the volume.
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => {
                const step = wheel.angleDelta.y || -wheel.angleDelta.x;
                if (step !== 0)
                    root.setVolume((root.player?.volume ?? 0) + (step > 0 ? Style.volumeStep : -Style.volumeStep));
            }
        }

        Item {
            id: keys
            focus: true
            Keys.onPressed: event => event.accepted = root.key(event.key)
        }

        Column {
            id: content
            x: root.pad
            y: root.pad
            width: root.cardWidth - root.pad * 2
            spacing: 14

            // ---- Cover, title, artist, the bars ----------------------------------------------
            Item {
                width: parent.width
                height: Style.nowPlayingArtSize

                Rectangle {
                    id: coverBack
                    width: Style.nowPlayingArtSize
                    height: width
                    // Its corner follows the card's (it sits pad px inside).
                    radius: Style.inner(Style.nowPlayingRadius, root.pad)
                    color: Style.alpha(Colors.textOnSurface, 0.08)

                    Icon {
                        anchors.centerIn: parent
                        visible: !cover.ready
                        name: "music_note"
                        size: parent.width * 0.4
                        color: Colors.textOnSurfaceVariant
                    }

                    CrossImage {
                        id: cover
                        anchors.fill: parent
                        source: root.artUrl
                        sourceSize: Qt.size(Style.nowPlayingArtSize * 2, Style.nowPlayingArtSize * 2)
                        radius: coverBack.radius
                        fade: Motion.normal
                    }
                }

                Column {
                    anchors.left: coverBack.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    StyledText {
                        width: parent.width
                        role: "label"
                        text: root.player?.identity ?? ""
                        color: Colors.textOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: parent.width
                        role: "headline"
                        text: root.player?.trackTitle || "Nothing playing"
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: parent.width
                        role: "body"
                        text: [root.player?.trackArtist ?? "", root.player?.trackAlbum ?? ""].filter(s => s !== "").join("  ·  ")
                        visible: text !== ""
                        color: Colors.textOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                    Item {
                        width: 1
                        height: 6
                    }
                    Bars {
                        visible: Style.showVisualizer
                        running: root.open && morph.revealed && root.playing
                        color: root.accent
                    }
                }
            }

            // ---- Where the song is -----------------------------------------------------------
            Column {
                width: parent.width
                visible: root.length > 0
                spacing: 2

                Track {
                    id: seek
                    width: parent.width
                    value: root.length > 0 ? root.position / root.length : 0
                    accent: root.accent
                    step: root.length > 0 ? Style.nowPlayingSeekStep / root.length : 0.05
                    glide: root.playing ? 1000 : 0
                    glideLimit: root.length > 0 ? 2.5 / root.length : 0.02
                    enabled: root.canSeek
                    onCommitted: v => root.seekTo(v * root.length)
                }
                Item {
                    width: parent.width
                    height: elapsed.implicitHeight

                    StyledText {
                        id: elapsed
                        role: "caption"
                        text: root.time(seek.dragging ? seek.dragValue * root.length : root.position)
                        color: Colors.textOnSurfaceVariant
                        font.features: ({ "tnum": 1 })
                    }
                    StyledText {
                        anchors.right: parent.right
                        role: "caption"
                        text: "-" + root.time(root.length - (seek.dragging ? seek.dragValue * root.length : root.position))
                        color: Colors.textOnSurfaceVariant
                        font.features: ({ "tnum": 1 })
                    }
                }
            }

            // ---- Buttons ------------------------------------------------------------------------
            Item {
                width: parent.width
                height: 52

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    // The player's window.
                    Clickable {
                        implicitHeight: 36
                        onClicked: {
                            NowPlayingState.raise(root.player);
                            root.closeRequested();
                        }
                        Icon { name: "open_in_new"; size: 20; color: Colors.textOnSurfaceVariant }
                    }
                    // Lyrics on or off (remembered).
                    Clickable {
                        implicitHeight: 36
                        visible: Style.lyricsEnabled
                        onClicked: Settings.set("lyricsInCard", !Style.lyricsInCard)
                        Icon {
                            name: "lyrics"
                            size: 20
                            fill: Style.lyricsInCard ? 1 : 0
                            color: Style.lyricsInCard ? root.accent : Colors.textOnSurfaceVariant
                        }
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 14

                    Clickable {
                        implicitHeight: 44
                        enabled: root.player?.canGoPrevious ?? false
                        opacity: enabled ? 1 : 0.4
                        onClicked: root.player?.previous()
                        Icon { name: "skip_previous"; size: 28 }
                    }
                    MouseArea {
                        id: playButton
                        anchors.verticalCenter: parent.verticalCenter
                        width: 52
                        height: 52
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.player?.togglePlaying()

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: root.accent
                            scale: playButton.pressed ? Style.pressScale : playButton.containsMouse ? 1.05 : 1
                            Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.fastSpatial } }

                            Icon {
                                anchors.centerIn: parent
                                name: root.playing ? "pause" : "play_arrow"
                                size: 30
                                color: root.onAccent
                            }
                        }
                    }
                    Clickable {
                        implicitHeight: 44
                        enabled: root.player?.canGoNext ?? false
                        opacity: enabled ? 1 : 0.4
                        onClicked: root.player?.next()
                        Icon { name: "skip_next"; size: 28 }
                    }
                }

                // The player's own volume (only some players have one).
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.player?.volumeSupported ?? false
                    spacing: 6

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property real v: root.player?.volume ?? 0
                        name: v <= 0 ? "volume_off" : v < 0.5 ? "volume_down" : "volume_up"
                        size: 18
                        color: Colors.textOnSurfaceVariant
                    }
                    Track {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 72
                        value: root.player?.volume ?? 0
                        accent: root.accent
                        step: Style.volumeStep
                        onMoved: v => root.setVolume(v)
                        onCommitted: v => root.setVolume(v)
                    }
                }
            }

            // ---- Other players ------------------------------------------------------------------
            Flow {
                width: parent.width
                visible: NowPlayingState.players.length > 1
                spacing: 6

                Repeater {
                    model: NowPlayingState.players

                    MouseArea {
                        id: chip
                        required property var modelData
                        readonly property bool current: modelData === root.player

                        width: chipRow.implicitWidth + 20
                        height: 30
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NowPlayingState.choose(modelData)

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: chip.current ? Style.alpha(root.accent, 0.22)
                                 : Style.alpha(Colors.textOnSurface, chip.containsMouse ? 0.1 : 0.05)
                            border.width: chip.current ? 1 : 0
                            border.color: Style.alpha(root.accent, 0.6)
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6

                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 18
                                source: MangoClients.iconFor(chip.modelData.desktopEntry || chip.modelData.identity || "")
                                name: chip.modelData.identity ?? ""
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "label"
                                text: chip.modelData.identity || chip.modelData.dbusName
                            }
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: chip.modelData.isPlaying
                                name: "graphic_eq"
                                size: 14
                                color: root.accent
                            }
                        }
                    }
                }
            }

            // ---- Lyrics ---------------------------------------------------------------------
            LyricsPanel {
                width: parent.width
                shown: Style.lyricsEnabled && Style.lyricsInCard
                active: root.open && morph.revealed
                accent: root.accent
                onSeekRequested: seconds => root.seekTo(seconds)
            }
        }
    }
}
