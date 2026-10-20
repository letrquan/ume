import QtQuick

// One clock digit. When it changes, the old digit slides up and fades out
// while the new one rises in from below (same as the lock screen clock).
Item {
    id: root

    property string digit: "0"
    property font font
    property color color: Colors.textOnSurface

    property string _shown: digit

    implicitWidth: probe.advanceWidth
    implicitHeight: probe.height
    clip: true

    TextMetrics {
        id: probe
        font: root.font
        text: "0"
    }

    Text {
        id: current
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: root._shown
        font: root.font
        color: root.color
        renderType: Text.NativeRendering
    }

    Text {
        id: incoming
        width: root.width
        y: root.height
        opacity: 0
        horizontalAlignment: Text.AlignHCenter
        font: root.font
        color: root.color
        renderType: Text.NativeRendering
    }

    onDigitChanged: {
        if (digit === _shown)
            return;
        incoming.text = digit;
        roll.restart();
    }

    SequentialAnimation {
        id: roll
        ParallelAnimation {
            NumberAnimation {
                target: current; property: "y"; to: -root.height * 0.6
                duration: Motion.slow; easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.defaultSpatial
            }
            NumberAnimation {
                target: current; property: "opacity"; to: 0
                duration: Motion.fast; easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.defaultEffects
            }
            NumberAnimation {
                target: incoming; property: "y"; from: root.height * 0.6; to: 0
                duration: Motion.slow; easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.defaultSpatial
            }
            NumberAnimation {
                target: incoming; property: "opacity"; from: 0; to: 1
                duration: Motion.normal; easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.defaultEffects
            }
        }
        ScriptAction {
            script: {
                root._shown = root.digit;
                current.y = 0;
                current.opacity = 1;
                incoming.opacity = 0;
                incoming.y = root.height;
            }
        }
    }
}
