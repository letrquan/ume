import QtQuick
import QtQuick.Shapes as Paths
import qs.common
import qs.services

// The focus timer on the bar (services/FocusTimer.qml). Stopped: a timer
// symbol (hover: how long). Running: a ring that fills up and the time
// left; dimmed while paused. Click: start / pause / go on. Right click:
// stop. Scroll before starting: 5 minutes more or less.
Clickable {
    id: root

    readonly property color accent: FocusTimer.phase === "focus" ? Colors.primary : Colors.tertiary

    spacing: 5
    tip: FocusTimer.active ? FocusTimer.phaseLabel + (FocusTimer.paused ? " · paused" : "") + " · " + FocusTimer.timeText + " left"
                           : "Focus timer · " + FocusTimer.plannedMinutes + " min"
    tipDetail: FocusTimer.active ? "Click: " + (FocusTimer.paused ? "go on" : "pause") + " · right-click: stop"
                                 : "Click: start · scroll: 5 min more or less"
    onClicked: mouse => mouse.button === Qt.RightButton ? FocusTimer.reset() : FocusTimer.toggle()

    // Touchpads scroll in small steps: add them up to one notch first.
    property real wheelSum: 0
    onWheel: wheel => {
        wheelSum += wheel.angleDelta.y || -wheel.angleDelta.x;
        if (Math.abs(wheelSum) >= 120) {
            FocusTimer.adjust(wheelSum > 0 ? 5 : -5);
            wheelSum = 0;
        }
    }

    Item {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.iconSize
        height: Style.iconSize

        Icon {
            anchors.centerIn: parent
            visible: !FocusTimer.active
            name: "timer"
            size: Style.iconSize - 2
            color: Colors.textOnSurfaceVariant
        }

        // QtQuick.Shapes' Shape (qs.common has its own Shape).
        Paths.Shape {
            id: ring
            anchors.fill: parent
            visible: FocusTimer.active
            opacity: FocusTimer.paused ? 0.5 : 1
            preferredRendererType: Paths.Shape.CurveRenderer

            property real shown: FocusTimer.progress
            Behavior on shown {
                NumberAnimation { duration: 900; easing.type: Easing.Linear }
            }
            Behavior on opacity { NumberAnimation { duration: Motion.normal } }

            Paths.ShapePath {
                fillColor: "transparent"
                strokeColor: Style.alpha(Colors.textOnSurface, 0.16)
                strokeWidth: 2.5
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: ring.width / 2 - 2; radiusY: ring.height / 2 - 2
                    startAngle: 0; sweepAngle: 360
                }
            }
            Paths.ShapePath {
                fillColor: "transparent"
                strokeColor: root.accent
                strokeWidth: 2.5
                capStyle: Paths.ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: ring.width / 2 - 2; radiusY: ring.height / 2 - 2
                    startAngle: -90; sweepAngle: Math.max(1, 360 * ring.shown)
                }
            }
        }

        // A dot in the middle: work (filled) or break (hollow).
        Rectangle {
            anchors.centerIn: parent
            visible: FocusTimer.active
            width: 6
            height: 6
            radius: 3
            color: FocusTimer.phase === "focus" ? root.accent : "transparent"
            border.width: FocusTimer.phase === "focus" ? 0 : 1.5
            border.color: root.accent
        }
    }

    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        visible: FocusTimer.active
        text: FocusTimer.timeText
        font.features: ({ "tnum": 1 })
        weight: 650
        opacity: FocusTimer.paused ? 0.55 : 1

        Behavior on opacity { NumberAnimation { duration: Motion.normal } }
    }

    // Stopped: how long the next round of work is (it changes as you scroll).
    Reveal {
        anchors.verticalCenter: parent.verticalCenter
        shown: !FocusTimer.active && root.containsMouse

        StyledText {
            text: FocusTimer.plannedMinutes + " min"
            font.features: ({ "tnum": 1 })
            color: Colors.textOnSurfaceVariant
        }
    }
}
