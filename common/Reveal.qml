import QtQuick

// Shows or hides one child by smoothly growing or shrinking its width, so
// the widgets next to it slide over instead of jumping. What's inside fades
// in once there's some room for it and out before the room is gone, and
// while it's cut its edge is soft (FadeEdge): no text appearing or
// disappearing letter by letter.
// Reveal { shown: something; Row { ... } }
Item {
    id: root

    property bool shown: true
    default property alias content: holder.content
    readonly property Item child: holder.items.length > 0 ? holder.items[0] : null

    // 0 hidden → 1 shown, in step with the width when it comes or goes (not
    // when the child changes size while shown).
    property real reveal: shown ? 1 : 0
    Behavior on reveal {
        NumberAnimation { duration: Motion.reveal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle }
    }

    implicitWidth: shown && child ? child.implicitWidth : 0
    implicitHeight: child ? child.implicitHeight : 0
    visible: width > 0.5
    clip: true

    Behavior on implicitWidth {
        NumberAnimation { duration: Motion.reveal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.gentle }
    }

    FadeEdge {
        id: holder
        width: root.child ? root.child.implicitWidth : 0
        height: root.height
        visibleWidth: root.width
        opacity: Math.max(0, Math.min(1, (root.reveal - 0.25) / 0.6))
    }
}
