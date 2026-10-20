import QtQuick

// What a list shows when there's nothing in it: a big soft shape with an
// icon, a title and one small hint line. Each time it comes into view the
// shape settles in with a short springy turn (once, not a loop); `active`
// says when it's really in view (e.g. once the card it's in has grown), so
// the turn isn't spent while it's still hidden.
//   EmptyState { icon: "content_paste_off"; title: "Nothing copied yet"; hint: "…" }
// Its height (about 150 px) is added up from its parts rather than left to
// a Column's layout, so it's right from the first frame: a card that grows
// to fit it goes straight to its size instead of gliding there late.
Item {
    id: root

    property string icon: "inbox"
    property string title: ""
    property string hint: ""
    property string shape: "Cookie9Sided"
    property real shapeSize: 72
    // Longest a hint line gets before it wraps.
    property real textWidth: 280
    property bool active: true
    readonly property bool showing: visible && active

    readonly property real topPadding: 16
    readonly property real bottomPadding: 18
    readonly property real spacing: 4

    implicitWidth: Math.max(shapeSize, titleText.implicitWidth, hintText.width)
    implicitHeight: topPadding + shapeHolder.height
        + (title !== "" ? spacing + titleText.implicitHeight : 0)
        + (hint !== "" ? spacing + hintText.implicitHeight : 0)
        + bottomPadding

    function settle() {
        settleIn.restart();
    }
    onShowingChanged: if (showing) settle()
    Component.onCompleted: if (showing) settle()

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.topPadding
        spacing: root.spacing

        Item {
            id: shapeHolder
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.shapeSize
            height: root.shapeSize + 8      // a little air under the shape

            Shape {
                id: blob
                width: root.shapeSize
                height: root.shapeSize
                shape: root.shape
                color: Style.alpha(Colors.secondaryContainer, 0.55)
                // Where the turn starts, until it's first in view.
                rotation: -40
                scale: 0.8
            }
            Icon {
                anchors.centerIn: blob
                name: root.icon
                size: Math.round(root.shapeSize * 0.4)
                color: Colors.textOnSecondaryContainer
            }
        }

        StyledText {
            id: titleText
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text !== ""
            text: root.title
            weight: 650
            color: Colors.textOnSurface
        }

        StyledText {
            id: hintText
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, root.textWidth)
            visible: text !== ""
            text: root.hint
            role: "caption"
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: Colors.textOnSurfaceVariant
        }
    }

    // A short turn and grow into place, overshooting a touch.
    ParallelAnimation {
        id: settleIn
        NumberAnimation {
            target: blob; property: "rotation"; from: -40; to: 0
            duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.slowSpatial
        }
        NumberAnimation {
            target: blob; property: "scale"; from: 0.8; to: 1
            duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial
        }
    }
}
