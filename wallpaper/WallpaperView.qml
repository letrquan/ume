import QtQuick
import Quickshell.Widgets
import qs.common

// The wallpaper. A new one spreads out from `origin` in a growing circle
// (like a drop of the new picture), with a thin light rim in the new
// accent color, and then simply stays. Only two pictures are ever loaded,
// and only during the change; each one is decoded at screen size.
// Plain QtQuick, so it can be previewed outside the shell.
Item {
    id: root

    property string source: ""                  // picture path
    property point origin: Qt.point(0.5, 0)     // fraction of the size
    property size decodeSize: Qt.size(width, height)

    // What is fully shown right now.
    property string shown: ""
    // The first picture (at start, and after every shell reload) is read
    // right away instead of in the background, so there is never an empty
    // black frame; later ones load in the background during the reveal.
    property bool settled: false
    // The first picture fades in (Intro: the way in after login); later
    // ones use the circle.
    property real entry: Intro.enabled ? 0 : 1
    property bool entered: false
    function enter() {
        if (entered || entry >= 1)
            return;
        entered = true;
        entryFade.start();
        Intro.wallpaperShown();
    }
    // The first picture is read right away (not in the background), so it
    // can be ready before this is even finished.
    Component.onCompleted: if (base.status === Image.Ready) enter()
    NumberAnimation {
        id: entryFade
        target: root; property: "entry"; to: 1
        duration: Intro.wallpaperFade
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
    }

    // Circle radius during a change, and the size that covers everything.
    property real radius: 0
    readonly property real ox: origin.x * width
    readonly property real oy: origin.y * height
    readonly property real cover: Math.hypot(Math.max(ox, width - ox), Math.max(oy, height - oy)) + 4

    onSourceChanged: {
        if (source === "" || source === shown)
            return;
        if (shown === "") {
            shown = source;          // first picture: just show it
            return;
        }
        reveal.stop();
        incoming.source = "file://" + source;
        if (incoming.status === Image.Ready)
            reveal.restart();
    }

    Image {
        id: base
        anchors.fill: parent
        source: root.shown !== "" ? "file://" + root.shown : ""
        sourceSize: root.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: root.settled
        cache: false
        smooth: true
        opacity: root.entry

        onStatusChanged: {
            if (status === Image.Ready)
                root.enter();
            if (status === Image.Ready)
                root.settled = true;
            // The new picture became the base: the circle can go.
            if (status === Image.Ready && lens.visible && source === incoming.source)
                root.finish();
        }
    }

    // The new picture, seen through the growing circle.
    ClippingRectangle {
        id: lens
        visible: false
        x: root.ox - root.radius
        y: root.oy - root.radius
        width: root.radius * 2
        height: root.radius * 2
        radius: root.radius
        color: "transparent"

        Image {
            id: incoming
            x: -lens.x
            y: -lens.y
            width: root.width
            height: root.height
            sourceSize: root.decodeSize
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true

            onStatusChanged: if (status === Image.Ready && root.radius === 0 && source !== "") reveal.restart()
        }
    }

    // Rim of light at the circle's edge, fading out as it reaches the corners.
    Rectangle {
        visible: lens.visible
        x: lens.x
        y: lens.y
        width: lens.width
        height: lens.height
        radius: root.radius
        color: "transparent"
        border.width: 2
        border.color: Colors.primary
        opacity: 0.8 * (1 - root.radius / root.cover)
    }

    SequentialAnimation {
        id: reveal
        ScriptAction {
            script: {
                root.radius = 0;
                lens.visible = true;
            }
        }
        NumberAnimation {
            target: root
            property: "radius"
            from: 0
            to: root.cover
            duration: Style.wallpaperReveal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.emphasizedDecel
        }
        // Make the new picture the base. The circle (now covering everything)
        // stays until the base has loaded it, so nothing flashes.
        ScriptAction {
            script: {
                root.shown = root.source;
                if (base.status === Image.Ready && base.source === incoming.source)
                    root.finish();
            }
        }
    }

    function finish() {
        lens.visible = false;
        radius = 0;
        incoming.source = "";
    }
}
