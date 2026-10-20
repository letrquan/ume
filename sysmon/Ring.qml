import QtQuick
// (As Q: qs.common has a Shape of its own, the filled Material shapes.)
import QtQuick.Shapes as Q
import qs.common

// A round gauge: a soft track, an arc filled to `value` (0-1) from the top,
// the number in the middle and a small label under it. Red past `warn`.
Item {
    id: root

    property real value: 0
    property string text: ""
    property string label: ""
    property bool warn: false
    property real size: 58
    property real thickness: 5
    readonly property bool hovered: hover.hovered

    readonly property color tint: warn ? Colors.error : Colors.primary
    // Animated, so the arc glides between reads.
    property real shown: Math.max(0, Math.min(1, value))
    Behavior on shown {
        NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
    }

    implicitWidth: size
    implicitHeight: size + 6 + caption.implicitHeight

    HoverHandler {
        id: hover
    }

    Q.Shape {
        id: gauge
        width: root.size
        height: root.size
        anchors.horizontalCenter: parent.horizontalCenter
        preferredRendererType: Q.Shape.CurveRenderer     // smooth edges

        Q.ShapePath {
            fillColor: "transparent"
            strokeColor: Style.alpha(Colors.textOnSurface, 0.1)
            strokeWidth: root.thickness
            capStyle: Q.ShapePath.RoundCap
            PathAngleArc {
                centerX: root.size / 2
                centerY: root.size / 2
                radiusX: (root.size - root.thickness) / 2
                radiusY: radiusX
                startAngle: 0
                sweepAngle: 360
            }
        }
        Q.ShapePath {
            fillColor: "transparent"
            strokeColor: root.tint
            strokeWidth: root.thickness
            capStyle: Q.ShapePath.RoundCap
            PathAngleArc {
                centerX: root.size / 2
                centerY: root.size / 2
                radiusX: (root.size - root.thickness) / 2
                radiusY: radiusX
                startAngle: -90
                // A dot even at 0, so the ring always shows where it starts.
                sweepAngle: Math.max(0.5, root.shown * 360)
            }
        }
    }

    StyledText {
        anchors.centerIn: gauge
        text: root.text
        role: "title"
        font.features: ({ "tnum": 1 })
        color: root.warn ? Colors.error : Colors.textOnSurface
        Behavior on color { ColorAnimation { duration: Motion.normal } }
    }

    StyledText {
        id: caption
        anchors.top: gauge.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.label
        role: "caption"
        color: Colors.textOnSurfaceVariant
    }
}
