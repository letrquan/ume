import QtQuick
import QtQuick.Shapes as Paths
import qs.common

// A round gauge: a track ring, a value arc that sweeps smoothly, a symbol in
// the middle and the value under it.
Item {
    id: root

    property real value: 0          // 0-1
    property string icon: ""
    property string label: ""       // under the ring, e.g. "42%"
    property color accent: Colors.primary
    property real ring: 64

    implicitWidth: ring
    implicitHeight: ring + 24

    property real shown: 0
    Component.onCompleted: shown = Qt.binding(() => Math.max(0, Math.min(1, root.value)))
    Behavior on shown {
        NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
    }

    // QtQuick.Shapes' Shape (qs.common has its own Shape).
    Paths.Shape {
        id: rings
        width: root.ring
        height: root.ring
        anchors.horizontalCenter: parent.horizontalCenter
        preferredRendererType: Paths.Shape.CurveRenderer

        Paths.ShapePath {
            fillColor: "transparent"
            strokeColor: Style.alpha(Colors.textOnSurface, 0.1)
            strokeWidth: 6
            capStyle: Paths.ShapePath.RoundCap
            PathAngleArc {
                centerX: root.ring / 2; centerY: root.ring / 2
                radiusX: root.ring / 2 - 4; radiusY: root.ring / 2 - 4
                startAngle: 135; sweepAngle: 270
            }
        }
        Paths.ShapePath {
            fillColor: "transparent"
            strokeColor: root.accent
            strokeWidth: 6
            capStyle: Paths.ShapePath.RoundCap
            PathAngleArc {
                centerX: root.ring / 2; centerY: root.ring / 2
                radiusX: root.ring / 2 - 4; radiusY: root.ring / 2 - 4
                startAngle: 135; sweepAngle: Math.max(0.5, 270 * root.shown)
            }
        }
    }

    Icon {
        anchors.centerIn: rings
        name: root.icon
        size: 22
        color: root.accent
    }

    StyledText {
        anchors.top: rings.bottom
        anchors.topMargin: 4
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.label
        role: "body"
        weight: 600
        font.features: ({ "tnum": 1 })
    }
}
