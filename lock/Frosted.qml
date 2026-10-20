import QtQuick
import QtQuick.Effects
import qs.common

// The shell's glass for the lock screen. On the desktop mango blurs what's
// behind the islands; the lock screen draws its own background, so here the
// blur is ours: the piece of `source` under this item, blurred and cut to
// the rounded shape, with the same Glass (tint, edge, shine) on top.
Item {
    id: root

    // The background item (it fills the screen, so `area` is in screen
    // coordinates) and where this glass sits on it.
    property Item source
    property rect area: Qt.rect(0, 0, width, height)
    property real radius: Style.islandRadius
    property color tint: Style.alpha(Colors.surfaceContainer, Style.lockOpacity)
    // Colour of what shows through: a bit richer (the panel), or greyer
    // like a Mac's (the mac style's field and music card).
    property real saturation: 0.2

    ShaderEffectSource {
        id: piece
        anchors.fill: parent
        sourceItem: root.source
        sourceRect: root.area
        // A quarter of the size is plenty under a strong blur.
        textureSize: Qt.size(Math.max(1, Math.round(root.area.width / 4)), Math.max(1, Math.round(root.area.height / 4)))
        live: true
        visible: false
    }

    Item {
        id: shape
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: root.radius
        }
    }

    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: shape
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        MultiEffect {
            anchors.fill: parent
            source: piece
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blur: 1.0
            saturation: root.saturation
        }
    }

    Glass {
        anchors.fill: parent
        radius: root.radius
        color: root.tint
    }
}
