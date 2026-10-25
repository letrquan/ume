import QtQuick
import qs.common

// The battery's charge over the last `hours`, along the clock (UPower's
// history, services/BatteryHealth.qml): the left edge is `hours` ago, the
// right edge now. A line with a soft area under it, in the accent color
// while on battery and in the second color while plugged in; faint lines at
// 0, 50 and 100 % with their numbers on the right, the clock under it every
// few hours. UPower writes a point each time the charge changes, so the
// points are uneven; before the first one the graph is empty.
Item {
    id: root

    // [{ t: seconds, v: 0-100, plugged }], oldest first.
    property var points: []
    property real hours: 24
    property real now: Date.now() / 1000
    // Where it is right now (the line runs on to the right edge).
    property real nowValue: -1
    property bool nowPlugged: false
    property bool use24h: true

    property color battery: Colors.primary
    property color plugged: Colors.tertiary

    readonly property real span: Math.max(1, hours) * 3600
    readonly property real start: now - span
    // The plot, inside the room for the numbers (right) and the clock (below).
    readonly property real plotW: width - 34
    readonly property real plotH: height - 18
    readonly property real topRoom: 4

    readonly property var series: {
        const list = (points ?? []).filter(p => p.t >= start - 1 && p.t <= now);
        if (nowValue >= 0 && list.length > 0)
            list.push({ t: now, v: nowValue, plugged: nowPlugged });
        return list;
    }
    readonly property bool empty: series.length < 2

    function xOf(t) {
        return (t - start) / span * plotW;
    }
    function yOf(v) {
        return topRoom + (1 - Math.max(0, Math.min(100, v)) / 100) * (plotH - topRoom);
    }

    // The clock under the graph: every 6 hours (3 for 12 h or less) on the hour.
    readonly property var ticks: {
        const step = (hours <= 12 ? 3 : 6) * 3600;
        const out = [];
        const d = new Date(start * 1000);
        d.setMinutes(0, 0, 0);
        let t = d.getTime() / 1000;
        while (t < now) {
            const hour = new Date(t * 1000).getHours();
            if (t > start + 1800 && t < now - 1800 && hour % (step / 3600) === 0)
                out.push(t);
            t += 3600;
        }
        return out;
    }
    function clockText(t) {
        const d = new Date(t * 1000);
        if (use24h)
            return Qt.formatTime(d, "HH:mm");
        const h = d.getHours();
        return (h % 12 === 0 ? 12 : h % 12) + (h < 12 ? " AM" : " PM");
    }

    onSeriesChanged: plot.requestPaint()
    onWidthChanged: plot.requestPaint()
    onHeightChanged: plot.requestPaint()
    onBatteryChanged: plot.requestPaint()
    onPluggedChanged: plot.requestPaint()

    Canvas {
        id: plot
        width: root.plotW
        height: root.plotH

        function rgba(c, a) {
            return Qt.rgba(c.r, c.g, c.b, a);
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            // 0 / 50 / 100 %.
            ctx.lineWidth = 1;
            for (const v of [0, 50, 100]) {
                const y = Math.round(root.yOf(v)) + 0.5;
                ctx.strokeStyle = rgba(Colors.textOnSurface, v === 0 ? 0.18 : 0.08);
                ctx.beginPath();
                ctx.moveTo(0, y);
                ctx.lineTo(width, y);
                ctx.stroke();
            }
            const pts = root.series;
            if (pts.length < 2)
                return;
            const base = root.yOf(0);
            // Each stretch takes the state of its end: the point UPower wrote
            // when that change had happened.
            for (let i = 1; i < pts.length; i++) {
                const a = pts[i - 1], b = pts[i];
                const c = b.plugged ? root.plugged : root.battery;
                const x0 = root.xOf(a.t), x1 = root.xOf(b.t);
                const y0 = root.yOf(a.v), y1 = root.yOf(b.v);
                const fill = ctx.createLinearGradient(0, root.topRoom, 0, base);
                fill.addColorStop(0, rgba(c, 0.38));
                fill.addColorStop(1, rgba(c, 0.04));
                ctx.fillStyle = fill;
                ctx.beginPath();
                ctx.moveTo(x0, base);
                ctx.lineTo(x0, y0);
                ctx.lineTo(x1, y1);
                ctx.lineTo(x1, base);
                ctx.closePath();
                ctx.fill();
            }
            ctx.lineWidth = 2;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            for (let i = 1; i < pts.length; i++) {
                const a = pts[i - 1], b = pts[i];
                ctx.strokeStyle = rgba(b.plugged ? root.plugged : root.battery, 0.95);
                ctx.beginPath();
                ctx.moveTo(root.xOf(a.t), root.yOf(a.v));
                ctx.lineTo(root.xOf(b.t), root.yOf(b.v));
                ctx.stroke();
            }
            // Now: a dot at the end.
            const last = pts[pts.length - 1];
            ctx.fillStyle = rgba(last.plugged ? root.plugged : root.battery, 1);
            ctx.beginPath();
            ctx.arc(root.xOf(last.t), root.yOf(last.v), 3, 0, Math.PI * 2);
            ctx.fill();
        }
    }

    // 100 % / 50 % / 0 % on the right.
    Repeater {
        model: [100, 50, 0]

        StyledText {
            required property int modelData
            x: root.plotW + 6
            y: root.yOf(modelData) - height / 2
            text: modelData + "%"
            role: "micro"
            font.features: ({ "tnum": 1 })
            color: Colors.textOnSurfaceVariant
        }
    }

    // The clock below.
    Repeater {
        model: root.ticks

        StyledText {
            required property real modelData
            x: Math.max(0, Math.min(root.plotW - width, root.xOf(modelData) - width / 2))
            y: root.plotH + 3
            text: root.clockText(modelData)
            role: "micro"
            font.features: ({ "tnum": 1 })
            color: Colors.textOnSurfaceVariant
        }
    }

    StyledText {
        anchors.centerIn: plot
        visible: root.empty
        text: "No history yet"
        role: "caption"
        color: Colors.textOnSurfaceVariant
    }
}
