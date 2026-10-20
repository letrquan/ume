import QtQuick
import qs.common
import qs.services

// A small live area chart: the newest value on the right, the older ones
// sliding off to the left (`values`, oldest first, 0-1; SysStats keeps the
// CPU's last historyLength of them, full from the start). The top is a
// bit above the highest value (at least `floor`), so a quiet CPU still
// shows its ups and downs; the exact number is on the ring above.
Canvas {
    id: root

    property var values: []
    property color color: Colors.primary
    property real floor: 0.1
    readonly property int capacity: SysStats.historyLength
    readonly property real ceiling: Math.min(1, Math.max(floor, Math.max(...values, 0) * 1.3))

    onValuesChanged: requestPaint()
    onCeilingChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function rgba(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const list = values;
        if (list.length < 2)
            return;
        // Through the midpoints between samples: a smooth line.
        const step = width / (capacity - 1);
        const pts = list.map((v, i) => ({
            x: width - (list.length - 1 - i) * step,
            y: height - 2 - Math.max(0, Math.min(1, v / root.ceiling)) * (height - 4)
        }));
        ctx.beginPath();
        ctx.moveTo(pts[0].x, pts[0].y);
        for (let i = 1; i < pts.length; i++) {
            const mx = (pts[i - 1].x + pts[i].x) / 2, my = (pts[i - 1].y + pts[i].y) / 2;
            ctx.quadraticCurveTo(pts[i - 1].x, pts[i - 1].y, mx, my);
        }
        const last = pts[pts.length - 1];
        ctx.lineTo(last.x, last.y);

        ctx.lineWidth = 2;
        ctx.lineJoin = "round";
        ctx.strokeStyle = rgba(color, 0.95);
        ctx.stroke();

        ctx.lineTo(last.x, height);
        ctx.lineTo(pts[0].x, height);
        ctx.closePath();
        const fill = ctx.createLinearGradient(0, 0, 0, height);
        fill.addColorStop(0, rgba(color, 0.35));
        fill.addColorStop(1, rgba(color, 0));
        ctx.fillStyle = fill;
        ctx.fill();
    }
}
