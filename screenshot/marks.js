.pragma library

// Shapes of the screenshot markup (screenshot/Mark.qml), as SVG path
// strings for QtQuick.Shapes. Coordinates are the picked rectangle's own
// (logical px from its top-left corner), so a mark looks the same on screen
// and in the saved file, whatever its pixel size.

function n(v) {
    return (Math.round(v * 100) / 100).toString();
}

// A freehand line through points [x0, y0, x1, y1, ...], smoothed: a curve
// through the middle of each step, bent by the point between (the usual
// quadratic midpoint smoothing). One point is a dot.
function smooth(pts) {
    const count = pts.length / 2;
    if (count === 0)
        return "";
    if (count === 1)
        return "M " + n(pts[0]) + " " + n(pts[1]) + " L " + n(pts[0] + 0.01) + " " + n(pts[1]);
    let d = "M " + n(pts[0]) + " " + n(pts[1]);
    for (let i = 1; i < count - 1; i++) {
        const x = pts[2 * i], y = pts[2 * i + 1];
        const mx = (x + pts[2 * i + 2]) / 2, my = (y + pts[2 * i + 3]) / 2;
        d += " Q " + n(x) + " " + n(y) + " " + n(mx) + " " + n(my);
    }
    return d + " L " + n(pts[2 * count - 2]) + " " + n(pts[2 * count - 1]);
}

// A pen line drawn with a stylus: points [x, y, ...] and a width level per
// point. Runs of points on the same level become one line of that width
// (each run starts where the one before ended, so they join), gathered per
// level: [path of level 0, path of level 1, ...]. Without levels (mouse,
// touch) everything is one line on `base`.
function penPaths(pts, levels, count, base) {
    const out = [];
    for (let i = 0; i < count; i++)
        out.push("");
    if (!levels || levels.length === 0) {
        out[base] = smooth(pts);
        return out;
    }
    let start = 0;
    const total = pts.length / 2;
    for (let i = 1; i <= total; i++) {
        if (i < total && levels[i] === levels[start])
            continue;
        // Points start..i-1, plus the next one so the runs meet.
        const end = Math.min(i + 1, total);
        const run = pts.slice(2 * start, 2 * end);
        out[levels[start]] += (out[levels[start]] === "" ? "" : " ") + smooth(run);
        start = i;
    }
    return out;
}

// An arrow from (x1, y1) to (x2, y2): the shaft (stroked) and the head (a
// filled point with a notch at the back), sized by the line width.
function arrow(x1, y1, x2, y2, width) {
    const dx = x2 - x1, dy = y2 - y1;
    const len = Math.max(Math.hypot(dx, dy), 0.001);
    const ux = dx / len, uy = dy / len;     // along
    const px = -uy, py = ux;                // across
    const head = Math.min(len * 0.6, width * 3.2 + 9);
    const half = head * 0.58;
    const bx = x2 - ux * head, by = y2 - uy * head;
    const notch = head * 0.28;
    // The shaft ends inside the head, so no seam shows.
    const sx = x2 - ux * (head - notch * 0.5), sy = y2 - uy * (head - notch * 0.5);
    return {
        shaft: "M " + n(x1) + " " + n(y1) + " L " + n(sx) + " " + n(sy),
        head: "M " + n(x2) + " " + n(y2)
            + " L " + n(bx + px * half) + " " + n(by + py * half)
            + " L " + n(bx + ux * notch) + " " + n(by + uy * notch)
            + " L " + n(bx - px * half) + " " + n(by - py * half) + " Z",
        headWidth: Math.max(1, width * 0.55)
    };
}

// A rectangle from two corners, either way round.
function rect(x1, y1, x2, y2) {
    return { x: Math.min(x1, x2), y: Math.min(y1, y2), w: Math.abs(x2 - x1), h: Math.abs(y2 - y1) };
}
