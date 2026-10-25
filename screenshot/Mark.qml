import QtQuick
import QtQuick.Shapes as Shapes
import qs.common
import "marks.js" as M

// One mark of the screenshot markup, drawn in the picked rectangle's own
// coordinates (logical px from its top-left corner):
//   pen    { paths: [5 paths, one per width level], color, width }
//   arrow  { x1, y1, x2, y2, color, width }
//   box    { x1, y1, x2, y2, color, width }
//   text   { x, y, text, color, size }
//   blur   { x1, y1, x2, y2, area }: the picture under it in blocks (pixelated)
// Lines, arrows and boxes have a faint dark edge (a wider line under them)
// and text a dark outline, so white and yellow read on a white page too.
// The same item draws on screen and, scaled to real pixels, in the saved
// file (screenshot/MarkupLayer.qml), so both look alike.
Item {
    id: root

    property var mark: null
    // The pick and its picture (screenshot/MarkupLayer.qml's geo).
    property var geo: null
    // The picture at its own size (the blur reads it), and its block size.
    property Item picture: null
    property int block: 14

    readonly property string kind: mark?.kind ?? ""
    readonly property color edge: Qt.rgba(0, 0, 0, 0.32)
    // Pen widths for a stylus's pressure levels (level 2 = the chosen width).
    readonly property var levels: [0.55, 0.78, 1, 1.25, 1.5]

    Loader {
        active: root.kind !== ""
        sourceComponent: root.kind === "pen" ? pen
                       : root.kind === "arrow" ? arrow
                       : root.kind === "box" ? box
                       : root.kind === "text" ? label
                       : root.kind === "blur" ? blur : null
    }

    Component {
        id: pen
        Shapes.Shape {
            id: penShape
            preferredRendererType: Shapes.Shape.CurveRenderer
            readonly property var paths: root.mark.paths ?? []
            readonly property real w: root.mark.width

            // Edges first (all of them), then the lines on top.
            Shapes.ShapePath { strokeColor: root.edge; strokeWidth: penShape.w * root.levels[0] + 2.5; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; joinStyle: Shapes.ShapePath.RoundJoin; PathSvg { path: penShape.paths[0] ?? "" } }
            Shapes.ShapePath { strokeColor: root.edge; strokeWidth: penShape.w * root.levels[1] + 2.5; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; joinStyle: Shapes.ShapePath.RoundJoin; PathSvg { path: penShape.paths[1] ?? "" } }
            Shapes.ShapePath { strokeColor: root.edge; strokeWidth: penShape.w * root.levels[2] + 2.5; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; joinStyle: Shapes.ShapePath.RoundJoin; PathSvg { path: penShape.paths[2] ?? "" } }
            Shapes.ShapePath { strokeColor: root.edge; strokeWidth: penShape.w * root.levels[3] + 2.5; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; joinStyle: Shapes.ShapePath.RoundJoin; PathSvg { path: penShape.paths[3] ?? "" } }
            Shapes.ShapePath { strokeColor: root.edge; strokeWidth: penShape.w * root.levels[4] + 2.5; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; joinStyle: Shapes.ShapePath.RoundJoin; PathSvg { path: penShape.paths[4] ?? "" } }
            Shapes.ShapePath { strokeColor: root.mark.color; strokeWidth: penShape.w * root.levels[0]; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; joinStyle: Shapes.ShapePath.RoundJoin; PathSvg { path: penShape.paths[0] ?? "" } }
            Shapes.ShapePath { strokeColor: root.mark.color; strokeWidth: penShape.w * root.levels[1]; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; joinStyle: Shapes.ShapePath.RoundJoin; PathSvg { path: penShape.paths[1] ?? "" } }
            Shapes.ShapePath { strokeColor: root.mark.color; strokeWidth: penShape.w * root.levels[2]; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; joinStyle: Shapes.ShapePath.RoundJoin; PathSvg { path: penShape.paths[2] ?? "" } }
            Shapes.ShapePath { strokeColor: root.mark.color; strokeWidth: penShape.w * root.levels[3]; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; joinStyle: Shapes.ShapePath.RoundJoin; PathSvg { path: penShape.paths[3] ?? "" } }
            Shapes.ShapePath { strokeColor: root.mark.color; strokeWidth: penShape.w * root.levels[4]; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; joinStyle: Shapes.ShapePath.RoundJoin; PathSvg { path: penShape.paths[4] ?? "" } }
        }
    }

    Component {
        id: arrow
        Shapes.Shape {
            id: arrowShape
            preferredRendererType: Shapes.Shape.CurveRenderer
            readonly property var a: M.arrow(root.mark.x1, root.mark.y1, root.mark.x2, root.mark.y2, root.mark.width)

            Shapes.ShapePath { strokeColor: root.edge; strokeWidth: root.mark.width + 2.5; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; PathSvg { path: arrowShape.a.shaft } }
            Shapes.ShapePath { strokeColor: root.edge; strokeWidth: arrowShape.a.headWidth + 2.5; fillColor: root.edge; joinStyle: Shapes.ShapePath.RoundJoin; PathSvg { path: arrowShape.a.head } }
            Shapes.ShapePath { strokeColor: root.mark.color; strokeWidth: root.mark.width; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; PathSvg { path: arrowShape.a.shaft } }
            Shapes.ShapePath { strokeColor: root.mark.color; strokeWidth: arrowShape.a.headWidth; fillColor: root.mark.color; joinStyle: Shapes.ShapePath.RoundJoin; PathSvg { path: arrowShape.a.head } }
        }
    }

    Component {
        id: box
        Shapes.Shape {
            id: boxShape
            preferredRendererType: Shapes.Shape.CurveRenderer
            readonly property var r: M.rect(root.mark.x1, root.mark.y1, root.mark.x2, root.mark.y2)
            readonly property real radius: Math.min(root.mark.width * 1.5 + 4, Math.min(r.w, r.h) / 2)

            Shapes.ShapePath {
                strokeColor: root.edge; strokeWidth: root.mark.width + 2.5; fillColor: "transparent"; joinStyle: Shapes.ShapePath.RoundJoin
                PathRectangle { x: boxShape.r.x; y: boxShape.r.y; width: boxShape.r.w; height: boxShape.r.h; radius: boxShape.radius }
            }
            Shapes.ShapePath {
                strokeColor: root.mark.color; strokeWidth: root.mark.width; fillColor: "transparent"; joinStyle: Shapes.ShapePath.RoundJoin
                PathRectangle { x: boxShape.r.x; y: boxShape.r.y; width: boxShape.r.w; height: boxShape.r.h; radius: boxShape.radius }
            }
        }
    }

    // Typed text: the font of the shell, bold, the size chosen with the
    // width (the user's text, so a pixel size, not a text role).
    Component {
        id: label
        Text {
            x: root.mark.x
            y: root.mark.y
            text: root.mark.text
            textFormat: Text.PlainText
            color: root.mark.color
            font.family: Style.font
            font.pixelSize: root.mark.size
            font.variableAxes: ({ "wght": 700, "ROND": 100 })
            style: Text.Outline
            styleColor: root.edge
            renderType: Text.CurveRendering
        }
    }

    // The picture under the rectangle, in blocks (common/shaders/pixelate.frag):
    // `area` is the rectangle in the kept part's pixels, snapped to whole
    // blocks (MarkupLayer.snapBlur), the same blocks shot-mark.sh makes.
    Component {
        id: blur
        ShaderEffect {
            readonly property var r: M.rect(root.mark.x1, root.mark.y1, root.mark.x2, root.mark.y2)
            readonly property var a: root.mark.area ?? [0, 0, 0, 0]
            x: r.x
            y: r.y
            width: r.w
            height: r.h
            visible: root.picture !== null && root.mark.area !== null && width > 0 && height > 0

            property Item source: root.picture
            property vector4d area: Qt.vector4d(a[0] + root.geo.px, a[1] + root.geo.py, a[2], a[3])
            property vector2d texSize: Qt.vector2d(root.picture?.implicitWidth ?? 1, root.picture?.implicitHeight ?? 1)
            property real block: root.block

            fragmentShader: Qt.resolvedUrl("../common/shaders/pixelate.frag.qsb")
        }
    }
}
