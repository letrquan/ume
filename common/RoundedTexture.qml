import QtQuick

// An Image's picture with rounded corners, drawn straight from its texture
// (no offscreen copy like ClippingRectangle makes), filling the item like
// Image.PreserveAspectCrop. Optionally also cut to a second rounded box
// (clipRect/clipRadius, in this item's coordinates). The Image itself is
// kept hidden: `visible: false`.
ShaderEffect {
    id: root

    property Image source
    property real radius: 0
    property rect clipRect: Qt.rect(-1e6, -1e6, 2e6, 2e6)
    property real clipRadius: 0

    // What the shader reads.
    readonly property vector2d itemSize: Qt.vector2d(width, height)
    readonly property rect clipBox: clipRect
    // The middle part of the picture that fits.
    readonly property vector4d uvRect: {
        const iw = source?.implicitWidth ?? 0;
        const ih = source?.implicitHeight ?? 0;
        if (iw <= 0 || ih <= 0 || width <= 0 || height <= 0)
            return Qt.vector4d(0, 0, 1, 1);
        const pic = iw / ih;
        const box = width / height;
        if (pic > box)
            return Qt.vector4d((1 - box / pic) / 2, 0, box / pic, 1);
        return Qt.vector4d(0, (1 - pic / box) / 2, 1, pic / box);
    }

    fragmentShader: Qt.resolvedUrl("shaders/roundtexture.frag.qsb")
}
