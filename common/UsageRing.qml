import QtQuick
// (As Q: qs.common has a Shape of its own, the filled Material shapes.)
import QtQuick.Shapes as Q

// A ring filled to `value` (0-1) from the top, on a soft track, with an
// optional second ring inside it (`inner`, -1 = none): the AI usage rings
// (Claude's 5-hour outside, its weekly inside) and the break countdown.
// The arcs glide to a new value. Plain drawing, no services: usable
// anywhere.
Item {
    id: root

    property real value: 0
    property color color: Colors.primary
    property real inner: -1
    property color innerColor: Colors.primary
    property real size: 18
    property real thickness: 2.5
    property real gap: 1.5
    property color track: Style.alpha(Colors.textOnSurface, 0.14)

    implicitWidth: size
    implicitHeight: size

    property real shown: Math.max(0, Math.min(1, value))
    Behavior on shown {
        NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
    }
    property real shownInner: Math.max(0, Math.min(1, inner))
    Behavior on shownInner {
        NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
    }

    readonly property real outerR: (size - thickness) / 2
    readonly property real innerR: outerR - thickness - gap

    Q.Shape {
        anchors.fill: parent
        preferredRendererType: Q.Shape.CurveRenderer     // smooth edges

        Q.ShapePath {
            fillColor: "transparent"
            strokeColor: root.track
            strokeWidth: root.thickness
            PathAngleArc {
                centerX: root.size / 2; centerY: root.size / 2
                radiusX: root.outerR; radiusY: root.outerR
                startAngle: 0; sweepAngle: 360
            }
        }
        Q.ShapePath {
            fillColor: "transparent"
            strokeColor: root.color
            strokeWidth: root.thickness
            capStyle: Q.ShapePath.RoundCap
            PathAngleArc {
                centerX: root.size / 2; centerY: root.size / 2
                radiusX: root.outerR; radiusY: root.outerR
                startAngle: -90
                // A dot even at 0, so the ring always shows where it starts.
                sweepAngle: Math.max(0.5, root.shown * 360)
            }
        }
        Q.ShapePath {
            fillColor: "transparent"
            strokeColor: root.inner >= 0 ? root.track : "transparent"
            strokeWidth: root.thickness
            PathAngleArc {
                centerX: root.size / 2; centerY: root.size / 2
                radiusX: Math.max(0.5, root.innerR); radiusY: Math.max(0.5, root.innerR)
                startAngle: 0; sweepAngle: 360
            }
        }
        Q.ShapePath {
            fillColor: "transparent"
            strokeColor: root.inner >= 0 ? root.innerColor : "transparent"
            strokeWidth: root.thickness
            capStyle: Q.ShapePath.RoundCap
            PathAngleArc {
                centerX: root.size / 2; centerY: root.size / 2
                radiusX: Math.max(0.5, root.innerR); radiusY: Math.max(0.5, root.innerR)
                startAngle: -90
                sweepAngle: Math.max(0.5, root.shownInner * 360)
            }
        }
    }
}
