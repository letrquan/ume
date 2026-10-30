import QtQuick
import qs.common

// The one bar behind the three islands (Style.barStyle other than
// "islands"): the glass they sit in as groups. "float" is a rounded bar
// inside the screen gaps, its corners Style.barPad rounder than the
// islands' so the two curves run side by side; "hug" and "plain" fill the
// strip from the top edge, and "hug" curves into the screen under both ends
// (as big as the screen's own corners, Style.cornerRadius). Drops in first
// at start, the islands after it.
Item {
    id: root

    readonly property bool floating: Style.barStyle === "float"
    readonly property bool hugging: Style.barStyle === "hug"
    // The glass part: the bar's click area (the curves under "hug" aren't).
    readonly property alias slab: slab

    visible: Style.barJoined
    opacity: 0
    // Moves only what you see, like an island's drop-in.
    transform: Translate {
        id: drop
        y: -18
    }

    Glass {
        id: slab

        x: root.floating ? Style.marginEnds : 0
        y: root.floating ? Style.marginEdge : 0
        width: root.width - 2 * x
        height: Style.barBottom - y
        radius: root.floating ? Style.islandRadius + Style.barPad : 0
        color: Style.alpha(Colors.surfaceContainer, Style.barOpacity)
        // Against the screen's edge there is no rim to catch the light.
        liquid: root.floating && Style.glassStyle === "liquid"
        border.width: root.floating ? Style.islandBorderWidth : 0

        // Against the edge: a hairline along the bottom instead, so the
        // bar ends crisply over what's under it.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Style.islandBorderWidth
            visible: !root.floating
            color: Style.glassStyle === "liquid" ? Style.glassBorder : Style.islandBorder
        }
    }

    // "hug": the glass under each end, outside a quarter circle, so the bar
    // runs into the screen's side in a curve.
    Repeater {
        model: root.hugging ? 2 : 0

        Canvas {
            id: curve

            required property int index
            readonly property real r: Style.cornerRadius
            readonly property color fill: slab.color

            x: index === 0 ? 0 : root.width - r
            y: Style.barBottom
            width: r
            height: r
            onFillChanged: requestPaint()
            onRChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = curve.fill;
                ctx.beginPath();
                if (curve.index === 0) {
                    // Along the bar's bottom, then the arc back to the
                    // screen's left edge (circle centred at r, r).
                    ctx.moveTo(0, 0);
                    ctx.lineTo(curve.r, 0);
                    ctx.arc(curve.r, curve.r, curve.r, -Math.PI / 2, Math.PI, true);
                } else {
                    // The same, mirrored (circle centred at 0, r).
                    ctx.moveTo(curve.r, 0);
                    ctx.lineTo(0, 0);
                    ctx.arc(0, curve.r, curve.r, -Math.PI / 2, 0, false);
                }
                ctx.closePath();
                ctx.fill();
            }
        }
    }

    // Waits for the wallpaper (Intro), like the islands.
    Component.onCompleted: if (Intro.started) dropIn.start()
    Connections {
        target: Intro
        function onStartedChanged() {
            if (Intro.started)
                dropIn.start();
        }
    }

    ParallelAnimation {
        id: dropIn
        NumberAnimation {
            target: drop; property: "y"; to: 0
            duration: Motion.slow; easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.defaultSpatial
        }
        NumberAnimation {
            target: root; property: "opacity"; to: 1
            duration: Motion.normal; easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.defaultEffects
        }
    }
}
