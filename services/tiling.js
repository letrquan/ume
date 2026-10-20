.pragma library

// Where mango will put the windows of a workspace you're not on, once
// windows were moved into or out of it (the overview's drag).
//
// mango tiles a workspace only while it's shown. Until you go there it
// keeps reporting the old places: a window moved in sits where it was on
// its old workspace (on top of the ones there, or hidden under them) and
// the one it left keeps a hole. Its dwindle layout (src/layout/dwindle.c)
// is a tree of halves that it only changes when it tiles:
// - a window gone: the other half of its split takes its place;
// - a window new: the window it splits (mango: the focused one; here the
//   biggest) gives it its second half, side by side if wider than tall,
//   else one over the other (dwindle_hsplit/vsplit 1, ratio 0.5).
// So: start from the places mango last tiled (`base`), take out the
// windows that left, split for the ones that came. A guess when focus or
// resized splits matter; mango puts them right when you go there (the
// overview's windows glide there).
//
// Rects are { x, y, width, height } in mango's (logical) pixels.

const TOL = 3;

function box(r) {
    return { x: r.x, y: r.y, width: r.width, height: r.height };
}
function bounds(list) {
    const x = Math.min(...list.map(r => r.x));
    const y = Math.min(...list.map(r => r.y));
    return { x: x, y: y,
             width: Math.max(...list.map(r => r.x + r.width)) - x,
             height: Math.max(...list.map(r => r.y + r.height)) - y };
}

// mango's split of `r` (dwindle_assign): [first, second].
function split(r, gap, ratio) {
    const half = Math.floor(gap / 2);
    if (r.width >= r.height) {
        const w1 = Math.max(1, Math.floor(r.width * ratio) - half);
        return [{ x: r.x, y: r.y, width: w1, height: r.height },
                { x: r.x + w1 + gap, y: r.y, width: Math.max(1, r.width - w1 - gap), height: r.height }];
    }
    const h1 = Math.max(1, Math.floor(r.height * ratio) - half);
    return [{ x: r.x, y: r.y, width: r.width, height: h1 },
            { x: r.x, y: r.y + h1 + gap, width: r.width, height: Math.max(1, r.height - h1 - gap) }];
}

// The other half of the split `gone` was in: the windows right next to it
// along one whole side (the smallest such group: the closest split).
function siblings(gone, others, gap) {
    const g = gone;
    const sides = [
        o => o.x >= g.x + g.width - TOL && o.y >= g.y - TOL && o.y + o.height <= g.y + g.height + TOL,     // right
        o => o.x + o.width <= g.x + TOL && o.y >= g.y - TOL && o.y + o.height <= g.y + g.height + TOL,     // left
        o => o.y >= g.y + g.height - TOL && o.x >= g.x - TOL && o.x + o.width <= g.x + g.width + TOL,     // below
        o => o.y + o.height <= g.y + TOL && o.x >= g.x - TOL && o.x + o.width <= g.x + g.width + TOL       // above
    ];
    let best = null;
    for (let i = 0; i < 4; i++) {
        let group = others.filter(sides[i]);
        if (group.length === 0)
            continue;
        // Only the ones touching the hole's side, and what's stacked with
        // them up to where the split ends.
        const b = bounds(group);
        const across = i < 2 ? Math.abs(b.y - g.y) <= TOL && Math.abs(b.height - g.height) <= TOL
                             : Math.abs(b.x - g.x) <= TOL && Math.abs(b.width - g.width) <= TOL;
        const near = i === 0 ? b.x - (g.x + g.width) : i === 1 ? g.x - (b.x + b.width)
                   : i === 2 ? b.y - (g.y + g.height) : g.y - (b.y + b.height);
        if (!across || near < -TOL || near > gap + TOL)
            continue;
        const parent = bounds([g, b]);
        if (!best || parent.width * parent.height < best.parent.width * best.parent.height)
            best = { group: group, inner: b, parent: parent };
    }
    return best;
}

// Take window `id` out: its split's other half grows into its place.
function remove(list, id, gap) {
    const gone = list.find(r => r.id === id);
    const others = list.filter(r => r.id !== id);
    if (!gone || others.length === 0)
        return others;
    const s = siblings(gone, others, gap);
    if (!s)
        return others;
    const P = s.parent, B = s.inner;
    let placed;
    if (s.group.length === 1) {
        placed = [Object.assign({}, s.group[0], box(P))];
    } else if (s.group.length === 2) {
        // A split of two: mango decides its direction again for the bigger
        // box (wider than tall: side by side), same share for the first.
        const [a, b] = s.group.slice().sort((p, q) => (p.x - q.x) || (p.y - q.y));
        const sideBySide = Math.abs(a.y - b.y) <= TOL;
        const ratio = sideBySide ? (a.width + Math.floor(gap / 2)) / B.width
                                 : (a.height + Math.floor(gap / 2)) / B.height;
        const [r1, r2] = split(P, gap, Math.min(0.95, Math.max(0.05, ratio)));
        placed = [Object.assign({}, a, r1), Object.assign({}, b, r2)];
    } else {
        // More: stretched into the bigger box.
        const kx = P.width / Math.max(1, B.width), ky = P.height / Math.max(1, B.height);
        placed = s.group.map(o => Object.assign({}, o, {
            x: Math.round(P.x + (o.x - B.x) * kx), y: Math.round(P.y + (o.y - B.y) * ky),
            width: Math.round(o.width * kx), height: Math.round(o.height * ky) }));
    }
    const moved = {};
    for (const p of placed)
        moved[p.id] = p;
    return others.map(o => moved[o.id] ?? o);
}

// Put window `id` in: the biggest one there splits for it (nothing there:
// the whole work area, if known).
function insert(list, id, area, gap, splitId) {
    if (list.length === 0)
        return area ? [Object.assign({ id: id }, box(area))] : null;
    let target = list.find(r => r.id === splitId);
    if (!target) {
        // (As big: the top left one, like mango's first.)
        target = list[0];
        for (const r of list) {
            const d = r.width * r.height - target.width * target.height;
            if (d > 4 || (d >= -4 && (r.y < target.y - TOL || (Math.abs(r.y - target.y) <= TOL && r.x < target.x))))
                target = r;
        }
    }
    const [r1, r2] = split(target, gap, 0.5);
    return list.map(r => r === target ? Object.assign({}, r, r1) : r).concat([Object.assign({ id: id }, r2)]);
}

// base: [{ id, x, y, width, height }] the tiled windows as mango last
// tiled them; now: the ids of the tiled windows there now (in order).
// Returns { id: rect } for the ones it could place.
function dwindle(base, now, area, gap) {
    let list = base.map(r => Object.assign({ id: r.id }, box(r)));
    for (const r of base)
        if (!now.includes(r.id))
            list = remove(list, r.id, gap);
    for (const id of now) {
        if (list.some(r => r.id === id))
            continue;
        const next = insert(list, id, area, gap);
        if (next)
            list = next;
    }
    const out = {};
    for (const r of list)
        out[r.id] = box(r);
    return out;
}

// The gap between tiled windows, from ones side by side or one over the
// other on the same workspace (else `fallback`).
function innerGap(windows, fallback) {
    let best = -1;
    for (const a of windows)
        for (const b of windows) {
            if (a === b || a.tag !== b.tag)
                continue;
            let d = -1;
            if (Math.abs(a.y - b.y) <= TOL && Math.abs(a.height - b.height) <= TOL)
                d = b.x - (a.x + a.width);
            else if (Math.abs(a.x - b.x) <= TOL && Math.abs(a.width - b.width) <= TOL)
                d = b.y - (a.y + a.height);
            if (d >= 0 && d <= 40 && (best < 0 || d < best))
                best = d;
        }
    return best >= 0 ? best : fallback;
}
