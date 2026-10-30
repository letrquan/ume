import QtQuick

// A glass card that grows out of an island and shrinks back into it. Used
// by the notification island and the launcher (middle island), the
// control center (right island) and the System popup (any island), so they
// all move the same way.
//
//   open:  the card appears exactly on the island (same size, same glass),
//          the island hides a frame later, then one progress value (t)
//          carries size, corners and position together to the card; the
//          content slides in near the end.
//   close: the content leaves, t carries the card back to the island's
//          size, and only when that has finished the island shows again
//          and the card hides a couple of frames later. `settled` then
//          says the window can go.
//
// Big shapes use M3's emphasized curve (smooth, no bounce), so the card
// never shrinks past the island on its way back.
Item {
    id: root

    // The island it grows out of, in this item's coordinates.
    property real fromX: 0
    property real fromY: 0
    property real fromWidth: 200
    property real fromHeight: Style.islandHeight
    // Which edge stays put while growing: "center", "left" or "right".
    property string grow: "center"

    property real toWidth: 400
    property real toHeight: 200
    property real radius: 28
    property real glassOpacity: 0.84
    property color borderColor: Style.islandBorder
    property bool open: false
    // Extra vertical offset of the whole card (drag to dismiss).
    property real pullY: 0
    // The morph's curve and times. Big cards keep M3's emphasized curve; a
    // small change of size (a live activity barely wider than the island)
    // takes Motion.gentle, like the bar's own reveals.
    property var curve: Motion.emphasized
    property int durationIn: Motion.morphIn
    property int durationOut: Motion.morphOut
    // A color mixed into the glass (the Now Playing card: its cover's), as
    // much as tintStrength (0 = none), growing with the card so the island
    // size is still plain glass. Only the color changes, never how
    // see-through the glass is.
    property color tint: "transparent"
    property real tintStrength: 0

    default property alias content: inner.data
    readonly property alias card: card

    // While true the bar hides the real island.
    readonly property bool covering: islandHidden
    // Content shown: from late in the opening until closing starts.
    readonly property bool revealed: open && t > 0.6
    // Fully back in the island and hidden: the window can go now.
    readonly property bool settled: !open && !cardShown

    // ---- Internals -------------------------------------------------------------------------
    property real t: 0                  // 0 = the island, 1 = the card
    property bool cardShown: false
    property bool islandHidden: false
    // The card's height eases on its own, so content changes glide too.
    property real targetHeight: toHeight
    Behavior on targetHeight {
        NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
    }

    onOpenChanged: {
        morph.stop();
        if (open) {
            showCard.stop();
            cardShown = true;
            hideIsland.restart();       // a frame after the card is on screen
            morph.to = 1;
            morph.duration = root.durationIn;
        } else {
            morph.to = 0;
            morph.duration = root.durationOut;
        }
        morph.start();
    }

    NumberAnimation {
        id: morph
        target: root
        property: "t"
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.curve
        onFinished: {
            if (root.open)
                return;
            // Back at the island's exact size: hand over. The island comes
            // back first, the card goes a couple of frames later, so the
            // two surfaces never leave a gap between them.
            hideIsland.stop();
            root.islandHidden = false;
            showCard.restart();
        }
    }

    Timer {
        id: hideIsland
        interval: 16
        onTriggered: root.islandHidden = true
    }
    Timer {
        id: showCard
        interval: 34
        onTriggered: root.cardShown = false
    }

    // In one bar (Style.barJoined) a side island is a group with no glass
    // of its own; the middle one keeps its glass (Style.barCenterIsland).
    readonly property bool fromGroup: Style.barJoined && !(grow === "center" && Style.barCenterIsland)
    // ...and that one may be near-black instead of glass (Style.barIslandDark).
    readonly property bool fromDark: Style.barJoined && grow === "center" && Style.barCenterIsland && Style.barIslandDark
    // Out of a group or the dark island: no glass edge to start with.
    readonly property bool plainStart: fromGroup || fromDark
    // ...and out of the dark island it stays dark, edge and all.
    readonly property bool darkCard: fromDark && Style.barIslandCards

    readonly property real currentWidth: fromWidth + (toWidth - fromWidth) * t
    readonly property real currentHeight: fromHeight + (targetHeight - fromHeight) * t

    Item {
        id: card

        x: root.grow === "right" ? root.fromX + root.fromWidth - width
         : root.grow === "left" ? root.fromX
         : root.fromX + root.fromWidth / 2 - width / 2
        y: root.fromY + root.pullY
        width: root.currentWidth
        height: root.currentHeight
        visible: root.cardShown

        Glass {
            anchors.fill: parent
            radius: Style.islandRadius + (root.radius - Style.islandRadius) * root.t
            // It starts as exactly what it grows out of and gets its own
            // glass on the way; out of a group (fromGroup) that has no
            // glass edge, so the edge light comes in with it too.
            color: {
                const base = Colors.surfaceContainer;
                const s = root.tint.a > 0 ? Math.max(0, Math.min(1, root.tintStrength)) : 0;
                // Out of the dark island it stays dark (Style.barIslandCards).
                const ground = root.darkCard ? Colors.surfaceContainerLowest : base;
                const to = Qt.rgba(ground.r + (root.tint.r - ground.r) * s, ground.g + (root.tint.g - ground.g) * s,
                                   ground.b + (root.tint.b - ground.b) * s,
                                   root.darkCard ? Style.barIslandCardOpacity : root.glassOpacity);
                // What it stands in for: the island's glass, or (one bar)
                // that or the group's pill (if any) over the bar's glass.
                const o = Style.islandOpacity;
                const k = root.fromDark ? Style.barIslandOpacity
                        : root.fromGroup ? (Style.barGroups ? Style.barGroupTint : 0) : o;
                const top = root.fromDark ? Colors.surfaceContainerLowest : root.fromGroup ? Colors.textOnSurface : base;
                const under = Style.barJoined ? Style.barOpacity : 0;
                const fa = Math.max(0.001, k + under * (1 - k));
                const from = Qt.rgba((k * top.r + under * (1 - k) * base.r) / fa, (k * top.g + under * (1 - k) * base.g) / fa,
                                     (k * top.b + under * (1 - k) * base.b) / fa, fa);
                const t = root.t;
                return Qt.rgba(from.r + (to.r - from.r) * t, from.g + (to.g - from.g) * t,
                               from.b + (to.b - from.b) * t, from.a + (to.a - from.a) * t);
            }
            rimScale: root.darkCard ? 0 : root.plainStart ? root.t : 1
            border.color: root.darkCard ? Style.alpha(root.borderColor, Math.min(root.borderColor.a, 0.06) * root.t)
                : root.plainStart ? Style.alpha(root.borderColor, root.borderColor.a * root.t) : root.borderColor
            Behavior on border.color {
                enabled: !root.plainStart
                ColorAnimation { duration: Motion.normal }
            }
        }

        // The content: clipped to the card, slides in near the end of the
        // opening and leaves first when closing.
        Item {
            id: inner
            anchors.fill: parent
            clip: true
            opacity: root.revealed ? 1 : 0
            transform: Translate {
                y: root.revealed ? 0 : 6
                Behavior on y {
                    NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: root.revealed ? Motion.contentIn : Motion.contentOut
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.revealed ? Motion.emphasizedDecel : Motion.emphasizedAccel
                }
            }
        }
    }
}
