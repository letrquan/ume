import QtQuick
import qs.common

// One rounded screen corner: the black bit outside a quarter circle, drawn
// for the top-left corner and turned for the others (`turn`: 0, 90, 180,
// 270 degrees clockwise). Painted once (smooth edge), never again. The bar
// window holds the top two, the dock window the bottom two.
// Plain QtQuick, so it can be previewed.
Item {
    id: root

    property real turn: 0
    readonly property real r: Style.cornerRadius

    width: r
    height: r

    Canvas {
        anchors.fill: parent
        rotation: root.turn

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = Style.cornerColor;
            // The screen's corner, along the top edge, the arc back to the
            // left edge (circle centred at r, r), and home.
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(root.r, 0);
            ctx.arc(root.r, root.r, root.r, -Math.PI / 2, Math.PI, true);
            ctx.closePath();
            ctx.fill();
        }
    }
}
