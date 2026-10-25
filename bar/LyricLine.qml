import QtQuick
import qs.common

// A line of text that crossfades to the next one: the old line drifts up a
// little as it fades, the new one comes up from below. It never changes
// its own size (the bar's lyrics slot is fixed, so the island stays put);
// a line longer than the slot is cut with a soft edge (FadeEdge), not "…".
Item {
    id: root

    property string text: ""
    property color color: Colors.textOnSurface
    property string role: "body"

    implicitHeight: a.implicitHeight

    // Which of the two lines shows: a (0) or b (1).
    property int showing: 0
    onTextChanged: {
        const out = showing === 0 ? a : b;
        const into = showing === 0 ? b : a;
        if (out.text === text && out.opacity > 0.5)
            return;
        into.text = text;
        showing = 1 - showing;
        out.leave();
        into.come();
    }
    Component.onCompleted: {
        a.text = text;
        a.opacity = 1;
    }

    component Line: Item {
        id: line

        property alias text: words.text
        // 0 = in place; 1 = below (coming), -1 = above (gone).
        property real lift: 1

        width: root.width
        height: root.height
        implicitHeight: words.implicitHeight
        opacity: 0
        visible: opacity > 0.01
        transform: Translate { y: line.lift * 5 }

        function come() {
            leaving.stop();
            coming.restart();
        }
        function leave() {
            coming.stop();
            leaving.restart();
        }

        // The old line is mostly gone before the new one shows, so the
        // two never sit on top of each other for long.
        SequentialAnimation {
            id: coming
            PropertyAction { target: line; property: "lift"; value: 1 }
            PauseAnimation { duration: 100 }
            ParallelAnimation {
                NumberAnimation { target: line; property: "opacity"; to: 1; duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                NumberAnimation { target: line; property: "lift"; to: 0; duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            }
        }
        ParallelAnimation {
            id: leaving
            NumberAnimation { target: line; property: "opacity"; to: 0; duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
            NumberAnimation { target: line; property: "lift"; to: -1; duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
        }

        FadeEdge {
            width: words.implicitWidth
            height: parent.height
            visibleWidth: line.width

            StyledText {
                id: words
                anchors.verticalCenter: parent.verticalCenter
                role: root.role
                color: root.color
            }
        }
    }

    Line { id: a; lift: 0 }
    Line { id: b }
}
