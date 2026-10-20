import QtQuick

// A rounded box drawn by one small shader: fill, border, soft shadow, and
// optionally cut to a second rounded box (clipRect/clipRadius, in the box's
// own coordinates: a workspace's corners in the overview). Unlike
// ClippingRectangle or a layer it makes no offscreen copy, so it costs
// nothing extra to move, scale or resize every frame.
//
// The item is the box grown by `pad` on every side (room for the shadow):
// place it with `anchors.fill: <box>; anchors.margins: -pad`.
ShaderEffect {
    id: root

    property real radius: 0
    property color color: "transparent"
    property real borderWidth: 0
    property color borderColor: "transparent"
    property color shadowColor: "transparent"
    property real shadowBlur: 0
    property point shadowOffset: Qt.point(0, 0)
    property rect clipRect: Qt.rect(-1e6, -1e6, 2e6, 2e6)
    property real clipRadius: 0

    readonly property real pad: shadowColor.a > 0
        ? Math.ceil(shadowBlur + Math.max(Math.abs(shadowOffset.x), Math.abs(shadowOffset.y))) : 0

    function premultiplied(c) {
        return Qt.vector4d(c.r * c.a, c.g * c.a, c.b * c.a, c.a);
    }

    // What the shader reads.
    readonly property vector2d itemSize: Qt.vector2d(width, height)
    readonly property rect box: Qt.rect(pad, pad, width - 2 * pad, height - 2 * pad)
    readonly property vector4d fillPm: premultiplied(color)
    readonly property vector4d borderPm: premultiplied(borderColor)
    readonly property vector4d shadowPm: premultiplied(shadowColor)
    readonly property rect clipBox: Qt.rect(clipRect.x + pad, clipRect.y + pad, clipRect.width, clipRect.height)

    fragmentShader: Qt.resolvedUrl("shaders/roundbox.frag.qsb")
}
