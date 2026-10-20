import QtQuick

// A picture that changes without blinking: the new one loads behind the
// old one and fades in over it once it's ready (window pictures in the
// overview and the dock's card are taken again every second or so).
// `ready`: some picture is showing.
Item {
    id: root

    property url source: ""
    property int fillMode: Image.PreserveAspectCrop
    property int fade: 180
    // Decode at this size (0 × 0 = the picture's own).
    property size sourceSize: Qt.size(0, 0)
    readonly property bool ready: front.status === Image.Ready || back.status === Image.Ready

    // Rounded corners (radius ≥ 0): drawn straight from the pictures by a
    // shader (RoundedTexture), so no ClippingRectangle (offscreen copies)
    // is needed around it. Also cut to clipRect/clipRadius (its own
    // coordinates). Only PreserveAspectCrop then.
    property real radius: -1
    property rect clipRect: Qt.rect(-1e6, -1e6, 2e6, 2e6)
    property real clipRadius: 0
    readonly property bool rounded: radius >= 0

    // Which of the two is on top (the newest).
    property bool aOnTop: true
    readonly property Image front: aOnTop ? a : b
    readonly property Image back: aOnTop ? b : a

    onSourceChanged: {
        if (source == "") {
            a.source = "";
            b.source = "";
            return;
        }
        // Load into the one underneath; it comes on top when ready.
        back.source = source;
    }
    Component.onCompleted: if (source != "" && a.source == "" && b.source == "") a.source = source

    function arrived(img) {
        if (img !== back || img.status !== Image.Ready)
            return;
        // The first picture just shows; later ones fade in over the last.
        if (front.status !== Image.Ready) {
            img.opacity = 1;
            aOnTop = !aOnTop;
            return;
        }
        img.opacity = 0;
        aOnTop = !aOnTop;
        fadedFrom = back.source;
        fadeIn.target = img;
        fadeIn.restart();
    }

    // The picture that was faded away from: once it's fully covered, let it
    // go (its texture), unless a newer one is already loading in its place.
    property url fadedFrom: ""
    NumberAnimation {
        id: fadeIn
        property: "opacity"
        from: 0
        to: 1
        duration: root.fade
        easing.type: Easing.OutQuad
        onFinished: {
            if (root.fadedFrom != "" && root.back.source == root.fadedFrom)
                root.back.source = "";
            root.fadedFrom = "";
        }
    }

    Image {
        id: a
        anchors.fill: parent
        z: root.aOnTop ? 1 : 0
        fillMode: root.fillMode
        asynchronous: true
        cache: false
        sourceSize: root.sourceSize.width > 0 ? root.sourceSize : undefined
        smooth: true
        mipmap: true
        visible: !root.rounded
        onStatusChanged: root.arrived(a)
    }
    RoundedTexture {
        anchors.fill: parent
        z: a.z
        visible: root.rounded && a.status === Image.Ready && a.opacity > 0
        opacity: a.opacity
        source: a
        radius: Math.max(0, root.radius)
        clipRect: root.clipRect
        clipRadius: root.clipRadius
    }
    Image {
        id: b
        anchors.fill: parent
        z: root.aOnTop ? 0 : 1
        fillMode: root.fillMode
        asynchronous: true
        cache: false
        sourceSize: root.sourceSize.width > 0 ? root.sourceSize : undefined
        smooth: true
        mipmap: true
        visible: !root.rounded
        onStatusChanged: root.arrived(b)
    }
    RoundedTexture {
        anchors.fill: parent
        z: b.z
        visible: root.rounded && b.status === Image.Ready && b.opacity > 0
        opacity: b.opacity
        source: b
        radius: Math.max(0, root.radius)
        clipRect: root.clipRect
        clipRadius: root.clipRadius
    }
}
