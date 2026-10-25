import QtQuick
import QtQuick.Effects
import qs.common
import qs.services

// The lyrics at the bottom of the Now Playing card (services/Lyrics.qml).
// Timed lyrics: the line being sung lit up in the cover's color and kept a
// bit above the middle (the list glides there), the others dimmer; click a
// line to go there; scroll to look around (it follows again 2.5 s later).
// Plain lyrics just scroll. While looking, without lyrics, or offline: a
// quiet empty state. Always the same height (Style.lyricsCardHeight), so
// the card never jumps when they arrive; `shown` fades it in and out, and
// the card's own height glide makes the room.
Item {
    id: root

    property bool shown: true
    // The card is open and grown (the empty state's little turn waits).
    property bool active: true
    property color accent: Colors.primary

    signal seekRequested(real seconds)

    implicitHeight: Style.lyricsCardHeight
    visible: shown || opacity > 0.01
    opacity: shown ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: root.shown ? Motion.contentIn : Motion.contentOut
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.shown ? Motion.emphasizedDecel : Motion.emphasizedAccel
        }
    }

    // What it shows: synced | plain | loading | none | instrumental | offline | browser
    readonly property string mode: {
        if (Lyrics.skipped)
            return "browser";
        if (!Lyrics.current || Lyrics.status === "idle" || Lyrics.status === "loading")
            return "loading";
        if (Lyrics.synced)
            return "synced";
        if ((Lyrics.status === "synced" || Lyrics.status === "plain") && Lyrics.plain.length > 0)
            return "plain";
        return Lyrics.status === "synced" ? "none" : Lyrics.status;
    }

    // ---- Timed lines ------------------------------------------------------------------------
    // The lines fade out toward the top and bottom edges.
    Item {
        id: lyricsBox
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: root.mode === "synced" || root.mode === "plain" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle } }

        layer.enabled: visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: edges
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        ListView {
            id: list

            anchors.fill: parent
            visible: root.mode === "synced"
            model: root.shown && root.mode === "synced" ? Lyrics.lines : []
            // Only the lines near the view are made (making all ~60–90 of
            // a song slowed the card's opening by ~100 ms); a jump to one
            // not made yet snaps there instead of gliding.
            cacheBuffer: 200
            boundsBehavior: Flickable.StopAtBounds
            spacing: 2
            // Room so the first and last lines can sit at the reading spot.
            header: Item { width: 1; height: list.height * root.spot }
            footer: Item { width: 1; height: list.height * (1 - root.spot) }

            onCountChanged: root.snapSoon()
            onVisibleChanged: if (visible) root.snapSoon()
            onMovementStarted: {
                if (Lyrics.debug)
                    console.log("lyrics panel: movement started at", contentY.toFixed(1), "glide", glide.running);
                if (!glide.running) {
                    root.following = false;
                    refollow.stop();
                }
            }
            onMovementEnded: if (!root.following) refollow.restart()

            delegate: MouseArea {
                id: row

                required property var modelData
                required property int index
                readonly property bool isCurrent: index === Lyrics.index

                width: list.width
                height: words.implicitHeight + 8
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.seekRequested(Lyrics.timeOf(index))

                // How lit it is: 1 = the line being sung.
                property real lit: isCurrent ? 1 : 0
                Behavior on lit { NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle } }

                StyledText {
                    id: words
                    x: 0
                    y: 4
                    width: parent.width
                    role: "title"
                    // A pause in the singing.
                    text: row.modelData.text !== "" ? row.modelData.text : "♪"
                    wrapMode: Text.Wrap
                    color: Qt.tint(Colors.textOnSurface, Style.alpha(root.accent, row.lit))
                    // Brighter under the mouse: click to go there.
                    opacity: 0.42 + 0.58 * row.lit + (row.containsMouse ? 0.25 : 0)
                    scale: 0.96 + 0.04 * row.lit
                    transformOrigin: Item.Left
                }
            }
        }

        // ---- Plain lyrics (no timing, or a player that won't say where it is) --------------
        Flickable {
            id: flick

            anchors.fill: parent
            visible: root.mode === "plain"
            contentHeight: plainText.implicitHeight + 32
            boundsBehavior: Flickable.StopAtBounds
            clip: false
            onVisibleChanged: contentY = 0

            StyledText {
                id: plainText
                y: 12
                width: flick.width
                role: "body"
                text: root.mode === "plain" ? Lyrics.plain.join("\n") : ""
                wrapMode: Text.Wrap
                lineHeight: 1.25
                color: Colors.textOnSurfaceVariant
            }
        }
    }

    // The fade mask: solid in the middle, fading over the top and bottom
    // 14 % of the height.
    Item {
        id: edges
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.14; color: "white" }
                GradientStop { position: 0.86; color: "white" }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    // ---- Nothing to sing along to ------------------------------------------------------------
    EmptyState {
        anchors.centerIn: parent
        visible: opacity > 0.01
        opacity: root.mode !== "synced" && root.mode !== "plain" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle } }
        active: root.active && root.shown
        shapeSize: Math.min(72, Math.max(40, root.height - 96))
        icon: root.mode === "instrumental" ? "music_note" : root.mode === "offline" ? "cloud_off" : root.mode === "browser" ? "public" : "lyrics"
        title: root.mode === "loading" ? "Looking for lyrics…"
             : root.mode === "browser" ? "No lyrics for browsers"
             : root.mode === "instrumental" ? "Instrumental"
             : root.mode === "offline" ? "Can't reach lrclib.net"
             : "No lyrics for this song"
        hint: root.mode === "instrumental" ? "No words to sing along to"
            : root.mode === "offline" ? "It tries again in a little while"
            : root.mode === "none" ? "lrclib.net doesn't have them"
            : root.mode === "browser" ? "Settings → Lyrics → From browsers"
            : " "       // keeps the line, so nothing shifts when the answer comes
    }

    // ---- Following the song ----------------------------------------------------------------
    // Where the line being sung sits, from the top (0..1).
    readonly property real spot: 0.38
    property bool following: true

    // Scrolled by hand: follow again a moment after letting go.
    Timer {
        id: refollow
        interval: 2500
        onTriggered: {
            root.following = true;
            root.glideTo(Lyrics.index, true);
        }
    }

    Connections {
        target: Lyrics
        function onIndexChanged() {
            if (root.following && root.mode === "synced")
                root.glideTo(Lyrics.index, root.active);
        }
    }
    onModeChanged: if (mode === "synced") snapSoon()

    function snapSoon() {
        Qt.callLater(() => glideTo(Lyrics.index, false));
    }

    // The list's place that puts this line at the reading spot.
    function targetY(item) {
        const y = item.y + item.height / 2 - list.height * spot;
        const top = list.originY;
        const bottom = list.originY + list.contentHeight - list.height;
        return Math.max(top, Math.min(bottom, y));
    }

    // Line i to the reading spot (before the first line: the first one).
    function glideTo(i, animate) {
        if (list.count === 0)
            return;
        glide.stop();
        const k = Math.max(0, i);
        list.forceLayout();
        let item = list.itemAtIndex(k);
        if (!item) {
            // Not made yet (a seek far away): go there at once.
            list.positionViewAtIndex(k, ListView.Center);
            list.forceLayout();
            item = list.itemAtIndex(k);
            animate = false;
        }
        if (!item)
            return;
        const y = targetY(item);
        if (Lyrics.debug)
            console.log("lyrics panel: line", k, animate ? "glide" : "snap", list.contentY.toFixed(1), "->", y.toFixed(1),
                        "origin", list.originY.toFixed(1), "content", list.contentHeight.toFixed(1));
        if (animate && Math.abs(y - list.contentY) > 0.5) {
            glide.from = list.contentY;
            glide.to = y;
            glide.restart();
        } else {
            list.contentY = y;
        }
    }

    NumberAnimation {
        id: glide
        target: list
        property: "contentY"
        duration: 560
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.gentle
    }
}
