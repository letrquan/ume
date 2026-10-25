import QtQuick
import qs.common
import qs.services

// The lyrics in the desktop's music card (services/Lyrics.qml, timed
// lyrics only), the way Apple Music shows them: the song's lines in a list
// that glides up as they're sung (soft start, long settle), the line
// being sung bright and full size, the others dimmer and a little smaller,
// lines already sung dimmer still. The list fades out over the top and
// bottom edges, softly blurred there (shaders/lyricedge.frag, one pass over
// the whole list). Long instrumental gaps, and the intro before the first
// line, show three dots that fill up as the gap passes. Click a line to go
// there; scroll to look around (it follows the song again 2.5 s later).
// Always the same height (Style.lyricsDesktopHeight), so the card never
// resizes per line; `shown` fades it in and out, the card makes the room.
Item {
    id: root

    property bool shown: true

    implicitHeight: Style.lyricsDesktopHeight
    visible: shown || opacity > 0.01
    opacity: shown ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: root.shown ? Motion.contentIn : Motion.contentOut
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.shown ? Motion.emphasizedDecel : Motion.emphasizedAccel
        }
    }

    // A gap this long (s) between lines gets the dots; shorter pauses are
    // just a breath and take no room.
    readonly property real dotsGap: 4

    // The rows: the song's lines, plus a row of dots before the first one
    // when the intro is long.
    readonly property bool hasIntro: Lyrics.synced && Lyrics.lines.length > 0 && Lyrics.lines[0].t >= dotsGap
    readonly property var rows: !Lyrics.synced ? [] : hasIntro ? [{ t: 0, text: "" }].concat(Lyrics.lines) : Lyrics.lines
    // The row being sung (the intro's dots before the first line).
    readonly property int current: Lyrics.synced ? Lyrics.index + (hasIntro ? 1 : 0) : -1

    // Where a row ends: when the next one starts.
    function endOf(i) {
        return rows[i + 1]?.t ?? (rows[i]?.t ?? 0) + 6;
    }

    Item {
        id: lyricsBox
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: list.count > 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle } }

        layer.enabled: visible
        layer.effect: ShaderEffect {
            readonly property vector2d itemSize: Qt.vector2d(width, height)
            readonly property real fadeTop: height * 0.24
            readonly property real fadeBottom: height * 0.3
            readonly property real blurRadius: Style.lyricsDesktopBlur
            fragmentShader: Qt.resolvedUrl("../common/shaders/lyricedge.frag.qsb")
        }

        ListView {
            id: list

            anchors.fill: parent
            model: root.shown ? root.rows : []
            // Only the rows near the view are made.
            cacheBuffer: 120
            boundsBehavior: Flickable.StopAtBounds
            spacing: 0
            // Room so the first and last rows can sit at the reading spot.
            header: Item { width: 1; height: list.height * root.spot }
            footer: Item { width: 1; height: list.height * (1 - root.spot) }

            onCountChanged: root.snapSoon()
            onVisibleChanged: if (visible) root.snapSoon()
            onMovementStarted: {
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
                readonly property bool isCurrent: index === root.current
                readonly property bool sung: index < root.current
                readonly property bool pause: modelData.text === ""
                // A pause long enough for the dots; a short one takes no room.
                readonly property bool dots: pause && root.endOf(index) - modelData.t >= root.dotsGap
                // The song's own line number (the intro's dots aren't one).
                readonly property int line: index - (root.hasIntro ? 1 : 0)

                width: list.width
                height: dots ? 30 : pause ? 0 : words.implicitHeight + 10
                visible: !pause || dots
                hoverEnabled: !pause
                cursorShape: pause ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: {
                    const p = Lyrics.player;
                    if (!pause && line >= 0 && p?.canSeek)
                        p.position = Lyrics.timeOf(line);
                }

                // How lit it is: 1 = the row being sung.
                property real lit: isCurrent ? 1 : 0
                Behavior on lit { NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle } }

                StyledText {
                    id: words
                    y: 5
                    width: parent.width
                    visible: !row.pause
                    role: "headline"
                    weight: 750
                    text: row.modelData.text
                    wrapMode: Text.Wrap
                    // Sung lines dimmer than the ones to come; brighter under the
                    // mouse (click to go there).
                    opacity: (row.sung ? 0.26 : 0.42) + (row.sung ? 0.74 : 0.58) * row.lit + (row.containsMouse ? 0.2 : 0)
                    scale: 0.93 + 0.07 * row.lit
                    transformOrigin: Item.Left
                }

                // The gap's dots: they fill one by one as it passes, with a
                // little swell each time; dim again once the next line comes.
                property int filled: 0
                function updateDots() {
                    if (!dots || !isCurrent) {
                        filled = 0;
                        step.stop();
                        return;
                    }
                    const start = modelData.t;
                    const length = Math.max(0.5, root.endOf(index) - start);
                    const done = Math.max(0, Math.min(1, (Lyrics.clock() - start) / length));
                    const n = Math.min(3, Math.floor(done * 3 + 0.001) + 1);
                    if (n !== filled) {
                        filled = n;
                        swell.restart();
                    }
                    if (Lyrics.playing && n < 3) {
                        const rate = (Lyrics.player?.rate ?? 1) > 0 ? Lyrics.player.rate : 1;
                        step.interval = Math.max(50, Math.ceil(((start + length * n / 3) - Lyrics.clock()) / rate * 1000) + 10);
                        step.restart();
                    } else {
                        step.stop();
                    }
                }
                onIsCurrentChanged: updateDots()
                Component.onCompleted: updateDots()
                Timer {
                    id: step
                    onTriggered: row.updateDots()
                }
                Connections {
                    target: Lyrics
                    enabled: row.dots
                    function onPlayingChanged() {
                        row.updateDots();
                    }
                    function onCorrectionChanged() {
                        row.updateDots();
                    }
                }

                Row {
                    id: dotRow
                    visible: row.dots
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7
                    transformOrigin: Item.Left
                    opacity: 0.4 + 0.6 * row.lit

                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            width: 9
                            height: 9
                            radius: 4.5
                            color: Colors.textOnSurface
                            opacity: row.filled > index ? 1 : 0.3
                            Behavior on opacity { NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle } }
                        }
                    }

                    SequentialAnimation {
                        id: swell
                        NumberAnimation { target: dotRow; property: "scale"; to: 1.18; duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                        NumberAnimation { target: dotRow; property: "scale"; to: 1; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
                    }
                }
            }
        }
    }

    // Waiting for the next song's lyrics: three quiet dots.
    Row {
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7
        visible: opacity > 0.01
        opacity: list.count === 0 ? 0.35 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle } }

        Repeater {
            model: 3
            Rectangle {
                width: 9
                height: 9
                radius: 4.5
                color: Colors.textOnSurface
            }
        }
    }

    // ---- Following the song ----------------------------------------------------------------
    // Where the row being sung sits, from the top (0..1).
    readonly property real spot: 0.3
    property bool following: true

    // Scrolled by hand: follow again a moment after letting go.
    Timer {
        id: refollow
        interval: 2500
        onTriggered: {
            root.following = true;
            root.glideTo(root.current, true);
        }
    }

    onCurrentChanged: if (following) glideTo(current, visible)

    function snapSoon() {
        Qt.callLater(() => glideTo(current, false));
    }

    // The list's place that puts this row at the reading spot.
    function targetY(item) {
        const y = item.y - list.height * spot;
        const top = list.originY;
        const bottom = list.originY + list.contentHeight - list.height;
        return Math.max(top, Math.min(bottom, y));
    }

    // Row i to the reading spot (before the first line: the first one).
    function glideTo(i, animate) {
        if (list.count === 0)
            return;
        glide.stop();
        const k = Math.max(0, Math.min(list.count - 1, i));
        list.forceLayout();
        let item = list.itemAtIndex(k);
        if (!item) {
            // Not made yet (a seek far away): go there at once.
            list.positionViewAtIndex(k, ListView.Beginning);
            list.forceLayout();
            item = list.itemAtIndex(k);
            animate = false;
        }
        if (!item)
            return;
        const y = targetY(item);
        if (animate && Math.abs(y - list.contentY) > 0.5) {
            glide.from = list.contentY;
            glide.to = y;
            glide.restart();
        } else {
            list.contentY = y;
        }
    }

    // A glide that starts softly and settles slowly (a sudden start reads
    // as a jump at this size).
    NumberAnimation {
        id: glide
        target: list
        property: "contentY"
        duration: 650
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.emphasized
    }
}
