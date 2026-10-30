import QtQuick
import qs.common

// The glass card of a small bar popup (the battery, the USB drives): it
// grows out of the bar item it was opened from, sits right under it (kept
// inside the screen) and shrinks back into the item when it closes, like
// the volume popup. What's inside is `body` (a Component; its implicitHeight
// sets the card's height, which eases when it changes).
Item {
    id: root

    // The item it grows out of, in this item's (the screen's) coordinates;
    // empty: the right end of the bar.
    property rect from: Qt.rect(0, 0, 0, 0)
    property bool open: false
    property real toWidth: 320
    property Component body: null
    readonly property Item content: loader.item

    // Back in the item and hidden: the window can go now.
    readonly property bool settled: !open && t === 0

    readonly property rect origin: from.width > 0 ? from
        : Qt.rect(width - Style.islandSide - 48, Style.islandTop, 40, Style.islandHeight)

    // ---- Where the card goes ----------------------------------------------------------------
    readonly property real toX: Math.max(Style.marginEdge,
        Math.min(width - toWidth - Style.marginEdge, origin.x + origin.width / 2 - toWidth / 2))
    readonly property real toY: Style.barBottom + Style.osdGap
    property real toHeight: (loader.item?.implicitHeight ?? 0) + 2 * pad
    Behavior on toHeight {
        NumberAnimation { duration: Motion.resize; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
    }
    readonly property int pad: 12

    // 0 = the item, 1 = the card.
    property real t: 0
    onOpenChanged: {
        morph.stop();
        morph.to = open ? 1 : 0;
        morph.duration = open ? Motion.morphIn : Motion.morphOut;
        morph.start();
    }
    NumberAnimation {
        id: morph
        target: root
        property: "t"
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.emphasized
    }

    function lerp(a, b) {
        return a + (b - a) * t;
    }

    // A click on the card itself must not reach the window's "outside" catcher.
    MouseArea {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        acceptedButtons: Qt.AllButtons
    }

    Item {
        id: card

        x: root.lerp(root.origin.x, root.toX)
        y: root.lerp(root.origin.y, root.toY)
        width: root.lerp(root.origin.width, root.toWidth)
        height: root.lerp(root.origin.height, root.toHeight)
        // Fades in over the first bit, so it doesn't start as a solid pill
        // over the item.
        opacity: Math.min(1, root.t * 5)
        visible: root.t > 0

        Glass {
            anchors.fill: parent
            radius: root.lerp(root.origin.height / 2, Style.radiusPopup)
            color: Style.alpha(Colors.surfaceContainer, root.lerp(Style.islandOpacity, Style.ccOpacity))
        }

        // The content: clipped to the card, slides in near the end of the
        // opening and leaves first when closing (like MorphCard).
        Item {
            anchors.fill: parent
            clip: true
            readonly property bool revealed: root.open && root.t > 0.6
            opacity: revealed ? 1 : 0
            transform: Translate {
                y: parent.revealed ? 0 : 6
                Behavior on y {
                    NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: parent.revealed ? Motion.contentIn : Motion.contentOut
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: parent.revealed ? Motion.emphasizedDecel : Motion.emphasizedAccel
                }
            }

            Loader {
                id: loader
                x: root.pad
                y: root.pad
                width: root.toWidth - 2 * root.pad
                sourceComponent: root.body
            }
        }
    }
}
