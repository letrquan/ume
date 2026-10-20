import QtQuick

// Frosted glass: a see-through tint, a thin light edge and soft light on the
// top half, like light on curved glass. mango blurs what is behind it.
// Used by the islands, the OSD and every panel, so they always match.
//
// "liquid" glass (Style.glassStyle) adds the light on the edge itself
// (shaders/glassrim.frag): a rim that is bright where the edge faces the
// light and glints on the far side, a glow just inside the lit edge and a
// little shade inside the bottom one. It stays inside the pane: a shadow
// outside would get blurred by mango into a smudge around it.
Rectangle {
    id: glass

    radius: Style.islandRadius
    color: Style.alpha(Colors.surfaceContainer, Style.islandOpacity)
    // The edge light (Style.glassStyle "liquid"); a test can set it per pane.
    property bool liquid: Style.glassStyle === "liquid"

    border.color: liquid ? Style.glassBorder : Style.islandBorder
    border.width: Style.islandBorderWidth

    Rectangle {
        anchors.fill: parent
        anchors.margins: glass.border.width
        radius: Math.max(0, glass.radius - glass.border.width)
        visible: Style.islandSheen > 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Style.islandSheen) }
            GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0) }
        }
    }

    ShaderEffect {
        anchors.fill: parent
        visible: glass.liquid && width > 0 && height > 0

        readonly property vector2d itemSize: Qt.vector2d(width, height)
        readonly property real radius: glass.radius
        readonly property vector2d light: Qt.vector2d(-Math.sin(Style.glassLightAngle * Math.PI / 180), -Math.cos(Style.glassLightAngle * Math.PI / 180))
        readonly property real rimWidth: Style.glassRimWidth
        readonly property real rim: Style.glassRim
        readonly property real rimBack: Style.glassRimBack
        readonly property real glow: Style.glassGlow
        readonly property real glowDepth: Style.glassGlowDepth
        readonly property real shade: Style.glassShade
        readonly property real shadeDepth: Style.glassShadeDepth
        readonly property real edge: Style.glassEdge
        readonly property real edgeDepth: Style.glassEdgeDepth

        fragmentShader: Qt.resolvedUrl("shaders/glassrim.frag.qsb")
    }
}
