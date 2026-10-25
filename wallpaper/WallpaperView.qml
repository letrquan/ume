import QtQuick
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
    // black frame (unless the intro fades it in: then in the background
    // too); later ones load in the background during the reveal.
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
        // Only once mango has sized the window: before that it's 100 x 100,
        // then 0 x 0 (this view stays 0 x 0 meanwhile), and a picture asked
        // for then is decoded at the wrong size (at 0 x 0: the full 3840 x
        // 2880, ~200 ms on the main thread) and thrown away.
        readonly property bool sized: root.width > 0 && root.height > 0
            && root.decodeSize.width > 0 && root.decodeSize.height > 0
        source: root.shown !== "" && sized ? "file://" + root.shown : ""
        sourceSize: root.decodeSize
        fillMode: Image.PreserveAspectCrop
        // The intro fades the first one in from the window's color anyway,
        // so it can load in the background like the later ones.
        asynchronous: root.settled || Intro.enabled
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

    // The new picture, seen through the growing circle: drawn straight
    // from its texture, cut to the circle in a shader (RoundedTexture). A
    // ClippingRectangle here made two offscreen copies of the circle and
    // made them again at the new size on every frame, up to twice the
    // screen's size across (~100 MB of GPU memory near the end).
    Image {
        id: incoming
        anchors.fill: parent
        sourceSize: root.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        visible: false

        onStatusChanged: if (status === Image.Ready && root.radius === 0 && source !== "") reveal.restart()
    }
    RoundedTexture {
        id: lens
        anchors.fill: parent
        visible: false
        source: incoming
        clipRect: Qt.rect(root.ox - root.radius, root.oy - root.radius, root.radius * 2, root.radius * 2)
        clipRadius: root.radius
    }

    // Rim of light at the circle's edge, fading out as it reaches the corners.
    Rectangle {
        visible: lens.visible
        x: root.ox - root.radius
        y: root.oy - root.radius
        width: root.radius * 2
        height: root.radius * 2
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
