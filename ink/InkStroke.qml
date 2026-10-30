import QtQuick
import QtQuick.Shapes as Shapes
import qs.common
import qs.screenshot

// One stroke of the ink (ink/ink.js): a pen line is the screenshot
// markup's own (screenshot/Mark.qml: its pressure widths and the faint dark
// edge that keeps white and yellow readable on a white page); a highlighter
// line is wide and see-through, without an edge, the same strength where
// it crosses itself (one path).
// `fadeAfter` (s, 0 = never): it fades out over its last half second.
Item {
    id: root

    property var stroke: null
    property real fadeAfter: 0
    readonly property string kind: stroke?.kind ?? ""

    Mark {
        visible: root.kind === "pen"
        mark: root.kind === "pen" ? root.stroke : null
    }

    Loader {
        active: root.kind === "hl"
        sourceComponent: Shapes.Shape {
            preferredRendererType: Shapes.Shape.CurveRenderer
            Shapes.ShapePath {
                strokeColor: Style.alpha(root.stroke.color, 0.38)
                strokeWidth: root.stroke.width
                fillColor: "transparent"
                capStyle: Shapes.ShapePath.RoundCap
                joinStyle: Shapes.ShapePath.RoundJoin
                PathSvg { path: root.stroke.path ?? "" }
            }
        }
    }

    // Fading: from what's left of its time, so a stroke made again (an
    // undo, a reload) fades when it would have.
    SequentialAnimation {
        running: root.fadeAfter > 0 && root.stroke !== null && (root.stroke.t ?? 0) > 0
        PauseAnimation { duration: Math.max(0, root.fadeAfter * 1000 - 500 - (Date.now() - (root.stroke?.t ?? 0))) }
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 500; easing.type: Easing.InQuad }
    }
}
