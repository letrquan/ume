.pragma library
.import "../screenshot/marks.js" as Marks

// Strokes of the ink (ink/InkCanvas.qml: drawing on the screen, a note's
// drawing page). A stroke keeps its points, so the eraser can find it and a
// note can save it; what's drawn comes from screenshot/marks.js (the
// screenshot markup's smoothing and pressure widths):
//   pen  { id, kind: "pen", color, width, points: [x0, y0, ...], levels, paths, box, t }
//   hl   { id, kind: "hl", color, width, points, path, box, t }      (highlighter)
// `levels`: a stylus's pressure level per point (0-4, as the markup's), or
// null; `box`: [left, top, right, bottom] around it, line width included;
// `t`: when it was drawn (ms), for Style.inkFadeSeconds.

// Pressure (0-1) -> width level, the same steps as screenshot/MarkupLayer.qml.
function levelOf(p) {
    return p < 0.18 ? 0 : p < 0.38 ? 1 : p < 0.62 ? 2 : p < 0.84 ? 3 : 4;
}

// [left, top, right, bottom] of points, `pad` wider all round.
function box(pts, pad) {
    let l = Infinity, t = Infinity, r = -Infinity, b = -Infinity;
    for (let i = 0; i < pts.length; i += 2) {
        l = Math.min(l, pts[i]);
        r = Math.max(r, pts[i]);
        t = Math.min(t, pts[i + 1]);
        b = Math.max(b, pts[i + 1]);
    }
    return [l - pad, t - pad, r + pad, b + pad];
}

// The distance from (px, py) to the segment (ax, ay)-(bx, by).
function segmentDistance(px, py, ax, ay, bx, by) {
    const dx = bx - ax, dy = by - ay;
    const len = dx * dx + dy * dy;
    let u = len > 0 ? ((px - ax) * dx + (py - ay) * dy) / len : 0;
    u = Math.max(0, Math.min(1, u));
    return Math.hypot(px - (ax + u * dx), py - (ay + u * dy));
}

// Whether a circle of radius `r` at (x, y) touches the stroke.
function touches(stroke, x, y, r) {
    const b = stroke.box;
    if (b && (x < b[0] - r || x > b[2] + r || y < b[1] - r || y > b[3] + r))
        return false;
    const p = stroke.points ?? [];
    const reach = r + (stroke.width ?? 0) / 2;
    if (p.length === 2)
        return Math.hypot(x - p[0], y - p[1]) <= reach;
    for (let i = 0; i + 3 < p.length; i += 2)
        if (segmentDistance(x, y, p[i], p[i + 1], p[i + 2], p[i + 3]) <= reach)
            return true;
    return false;
}

// A stroke's drawn shape (paths / path) and box, from its points.
function made(stroke) {
    const out = Object.assign({}, stroke);
    if (out.kind === "hl")
        out.path = Marks.smooth(out.points);
    else
        out.paths = Marks.penPaths(out.points, out.levels, 5, 2);
    out.box = box(out.points, out.width * (out.kind === "hl" ? 0.5 : 0.8) + 2);
    return out;
}

// Only what a stroke needs to be drawn again (for saving): points, no
// paths (they're made again when read back).
function bare(stroke) {
    return { id: stroke.id, kind: stroke.kind, color: stroke.color, width: stroke.width,
             points: stroke.points.map(v => Math.round(v * 10) / 10), levels: stroke.levels ?? null, t: stroke.t ?? 0 };
}
