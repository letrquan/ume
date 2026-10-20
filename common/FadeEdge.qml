import QtQuick
import QtQuick.Effects

// Its content, cut at `visibleWidth` with the last bit before the cut
// fading out, instead of a hard cut through a letter (or a "…" that swaps
// in and out while the width moves). The fade is as long as what's cut
// off, up to 16 px, so it grows in smoothly as the cut starts. Nothing
// extra is drawn while nothing is cut. Used by Reveal and the bar's window
// title.
//   FadeEdge { width: row.implicitWidth; visibleWidth: parent.width; Row { … } }
Item {
    id: root

    property real visibleWidth: width
    default property alias content: inner.data
    readonly property alias items: inner.children
    readonly property bool cut: visibleWidth < width - 0.5
    readonly property real fade: Math.min(16, Math.max(0, width - visibleWidth))

    Item {
        id: inner
        anchors.fill: parent
        layer.enabled: root.cut
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: edge
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    Item {
        id: edge
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            width: Math.max(0, root.visibleWidth)
            height: parent.height
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "white" }
                GradientStop { position: Math.max(0, 1 - root.fade / Math.max(1, root.visibleWidth)); color: "white" }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }
}
