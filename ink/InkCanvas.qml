import QtQuick
import QtQuick.Shapes as Shapes
import qs.common
import "ink.js" as Ink

// Drawing with the pen, the mouse (and touch, when `touchDraws`): the
// screen's ink (ink/InkWindow.qml) and a note's drawing page
// (notes/NoteInk.qml). Tools:
//   pen          freehand, smoothed; a stylus's pressure picks the width
//                (as the screenshot markup does: five levels)
//   highlighter  wide and see-through
//   laser        a red dot and a trail that fades at once; nothing stays
//   eraser       takes away every stroke it touches (the pen's eraser end
//                erases with any tool)
// Undo and redo know each stroke, each erasing and Clear. `strokes` is
// plain data (ink/ink.js), `edited()` says the user changed it.
// press() / move() / release() take a point like PointHandler's
// (position, pressure, device): the tests call them with made-up ones.
Item {
    id: root

    property string tool: "pen"             // pen | highlighter | laser | eraser
    property color color: "#ff453a"
    property real lineWidth: 5
    property bool touchDraws: false
    property bool active: true              // takes the pointer at all
    property real fadeAfter: 0              // s; 0 = strokes stay
    // Where a press must not draw (the toolbar over the ink): a function
    // (x, y) -> true, or null.
    property var blocked: null

    property var strokes: []
    property var history: []                // [{ op: "add" | "erase" | "clear", ... }]
    property var future: []                 // undone ops, for redo
    property var current: null              // the stroke being drawn
    readonly property bool canUndo: history.length > 0
    readonly property bool canRedo: future.length > 0
    readonly property bool hasInk: strokes.length > 0
    readonly property real eraserRadius: Math.max(10, lineWidth * 2.2)

    readonly property alias handler: draw
    signal edited()
    // A press that drew or erased (InkWindow moves the toolbar to its screen).
    signal touched()

    property int counter: 0
    function nextId() {
        counter++;
        return Date.now().toString(36) + "-" + counter;
    }

    // ---- Changes, each one undoable -------------------------------------------------------
    function apply(op, fromUser) {
        if (op.op === "add") {
            strokes = strokes.concat([op.stroke]);
        } else if (op.op === "erase") {
            const gone = new Set(op.removed.map(r => r.stroke.id));
            strokes = strokes.filter(s => !gone.has(s.id));
        } else if (op.op === "clear") {
            strokes = [];
        }
        if (fromUser) {
            history = history.concat([op]).slice(-300);
            future = [];
        }
        edited();
    }
    function revert(op) {
        if (op.op === "add") {
            strokes = strokes.filter(s => s.id !== op.stroke.id);
        } else if (op.op === "erase") {
            // Back where each one was.
            const list = strokes.slice();
            for (const r of op.removed.slice().sort((a, b) => a.index - b.index))
                list.splice(Math.min(r.index, list.length), 0, r.stroke);
            strokes = list;
        } else if (op.op === "clear") {
            strokes = op.before.slice();
        }
        edited();
    }
    function undo() {
        if (history.length === 0)
            return;
        const op = history[history.length - 1];
        history = history.slice(0, -1);
        future = future.concat([op]);
        revert(op);
    }
    function redo() {
        if (future.length === 0)
            return;
        const op = future[future.length - 1];
        future = future.slice(0, -1);
        history = history.concat([op]);
        apply(op, false);
    }
    function clear() {
        current = null;
        if (strokes.length > 0)
            apply({ op: "clear", before: strokes.slice() }, true);
    }
    // New strokes without history (a note opened): plain data in, paths made.
    function load(list) {
        current = null;
        history = [];
        future = [];
        strokes = (list ?? []).filter(s => s && Array.isArray(s.points) && s.points.length >= 2)
            .map(s => Ink.made(Object.assign({}, s, { id: s.id || nextId() })));
    }
    // What to keep (a note's save): points only.
    function saved() {
        return strokes.map(Ink.bare);
    }

    // Strokes older than fadeAfter go (they faded out already). Not undoable:
    // what faded is gone, and so are the steps that would bring it back.
    Timer {
        interval: 500
        repeat: true
        running: root.fadeAfter > 0 && root.strokes.length > 0
        onTriggered: {
            const limit = Date.now() - root.fadeAfter * 1000;
            const left = root.strokes.filter(s => (s.t ?? 0) === 0 || s.t > limit);
            if (left.length === root.strokes.length)
                return;
            root.strokes = left;
            const ids = new Set(left.map(s => s.id));
            const alive = op => op.op === "add" ? ids.has(op.stroke.id) : op.op === "clear" ? false : op.removed.every(r => !ids.has(r.stroke.id));
            root.history = root.history.filter(alive);
            root.future = [];
            root.edited();
        }
    }

    // ---- Drawing ------------------------------------------------------------------------
    property real pressure: 1
    property bool ignoring: false           // this press doesn't draw
    property string using: ""               // the tool of this press (the eraser end: eraser)
    property var erased: []                 // this press's erased strokes [{ stroke, index }]

    function press(pt) {
        const x = pt.position.x, y = pt.position.y;
        ignoring = !active || (blocked !== null && blocked(x, y));
        if (ignoring)
            return;
        const device = pt.device;
        const stylus = device?.type === PointerDevice.Stylus || device?.type === PointerDevice.Airbrush;
        using = device?.pointerType === PointerDevice.Eraser ? "eraser" : tool;
        touched();
        if (using === "laser") {
            laserAt(x, y);
            return;
        }
        if (using === "eraser") {
            erased = [];
            eraserPos = Qt.point(x, y);
            eraseAt(x, y);
            return;
        }
        pressure = pt.pressure > 0 ? pt.pressure : 0.5;
        const levels = using === "pen" && stylus ? [Ink.levelOf(pressure)] : null;
        current = Ink.made({ id: nextId(), kind: using === "highlighter" ? "hl" : "pen", color: color.toString(),
                             width: using === "highlighter" ? lineWidth * 3.2 : lineWidth,
                             points: [x, y], levels: levels, t: 0 });
    }

    function move(pt) {
        if (ignoring)
            return;
        const x = pt.position.x, y = pt.position.y;
        if (using === "laser") {
            laserAt(x, y);
            return;
        }
        if (using === "eraser") {
            // Along the way from the last point, not only where it is now
            // (a quick swipe moves far between two points).
            const from = eraserPos;
            const steps = Math.max(1, Math.ceil(Math.hypot(x - from.x, y - from.y) / (eraserRadius * 0.6)));
            for (let i = 1; i <= steps; i++)
                eraseAt(from.x + (x - from.x) * i / steps, from.y + (y - from.y) * i / steps);
            return;
        }
        const c = current;
        if (!c)
            return;
        const p = c.points;
        if (Math.hypot(x - p[p.length - 2], y - p[p.length - 1]) < 1.2)
            return;
        let levels = c.levels;
        if (levels) {
            // Smoothed, so the width doesn't flicker between levels.
            pressure = pressure * 0.6 + (pt.pressure > 0 ? pt.pressure : pressure) * 0.4;
            levels = levels.concat([Ink.levelOf(pressure)]);
        }
        current = Ink.made(Object.assign({}, c, { points: p.concat([x, y]), levels: levels }));
    }

    function release() {
        if (ignoring) {
            ignoring = false;
            return;
        }
        if (using === "eraser") {
            if (erased.length > 0) {
                history = history.concat([{ op: "erase", removed: erased }]).slice(-300);
                future = [];
            }
            erased = [];
            return;
        }
        const c = current;
        current = null;
        if (c && using !== "laser") {
            const done = Object.assign({}, c, { t: Date.now() });
            apply({ op: "add", stroke: done }, true);
        }
    }

    function eraseAt(x, y) {
        eraserPos = Qt.point(x, y);
        const hit = [];
        strokes.forEach((s, i) => {
            if (Ink.touches(s, x, y, eraserRadius))
                hit.push({ stroke: s, index: i });
        });
        if (hit.length === 0)
            return;
        // Their places among all the strokes there were before this press
        // (undo puts them back there): past the ones this press took already.
        const earlier = erased.map(e => e.index).sort((a, b) => a - b);
        for (const h of hit) {
            let index = h.index;
            for (const e of earlier)
                if (e <= index)
                    index++;
            erased.push({ stroke: h.stroke, index: index });
        }
        const gone = new Set(hit.map(h => h.stroke.id));
        strokes = strokes.filter(s => !gone.has(s.id));
        edited();
    }

    PointHandler {
        id: draw
        enabled: root.active
        acceptedDevices: root.touchDraws
            ? PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus | PointerDevice.Airbrush | PointerDevice.TouchScreen
            : PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus | PointerDevice.Airbrush
        acceptedButtons: Qt.LeftButton
        onActiveChanged: active ? root.press(point) : root.release()
        onPointChanged: if (active) root.move(point)
    }
    HoverHandler {
        id: hover
        enabled: root.active
        cursorShape: root.tool === "laser" || root.tool === "eraser" ? Qt.BlankCursor : Qt.CrossCursor
    }

    InkMarks {
        anchors.fill: parent
        strokes: root.strokes
        current: root.current
        fadeAfter: root.fadeAfter
    }

    // ---- The laser ---------------------------------------------------------------------
    // Points of the last moments [{ x, y, t }]; older than `laserLife` go.
    property var trail: []
    readonly property int laserLife: 650
    function laserAt(x, y) {
        const now = Date.now();
        trail = trail.filter(p => now - p.t < laserLife).concat([{ x: x, y: y, t: now }]);
    }
    FrameAnimation {
        running: root.trail.length > 0
        onTriggered: {
            const now = Date.now();
            const left = root.trail.filter(p => now - p.t < root.laserLife);
            if (left.length !== root.trail.length)
                root.trail = left;
        }
    }
    // The trail in four parts, older ones thinner and fainter.
    readonly property var trailParts: {
        const now = Date.now();
        const parts = ["", "", "", ""];
        for (let i = 1; i < trail.length; i++) {
            const a = trail[i - 1], b = trail[i];
            const k = Math.min(3, Math.floor((now - b.t) / (laserLife / 4)));
            parts[k] += "M " + a.x.toFixed(1) + " " + a.y.toFixed(1) + " L " + b.x.toFixed(1) + " " + b.y.toFixed(1) + " ";
        }
        return parts;
    }
    Shapes.Shape {
        anchors.fill: parent
        visible: root.trail.length > 1
        preferredRendererType: Shapes.Shape.CurveRenderer
        Shapes.ShapePath { strokeColor: Qt.rgba(1, 0.2, 0.15, 0.9); strokeWidth: 6; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; PathSvg { path: root.trailParts[0] } }
        Shapes.ShapePath { strokeColor: Qt.rgba(1, 0.2, 0.15, 0.6); strokeWidth: 5; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; PathSvg { path: root.trailParts[1] } }
        Shapes.ShapePath { strokeColor: Qt.rgba(1, 0.2, 0.15, 0.35); strokeWidth: 4; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; PathSvg { path: root.trailParts[2] } }
        Shapes.ShapePath { strokeColor: Qt.rgba(1, 0.2, 0.15, 0.15); strokeWidth: 3; fillColor: "transparent"; capStyle: Shapes.ShapePath.RoundCap; PathSvg { path: root.trailParts[3] } }
    }
    // The dot: where the pen or the pointer is, while the laser is picked.
    readonly property point laserPoint: draw.active ? draw.point.position : hover.point.position
    Rectangle {
        visible: root.tool === "laser" && (draw.active || hover.hovered) && root.active
        x: root.laserPoint.x - width / 2
        y: root.laserPoint.y - height / 2
        width: 22
        height: 22
        radius: 11
        color: Qt.rgba(1, 0.2, 0.15, 0.28)
        Rectangle {
            anchors.centerIn: parent
            width: 10
            height: 10
            radius: 5
            color: "#ff3b30"
            border.width: 1.5
            border.color: Qt.rgba(1, 1, 1, 0.85)
        }
    }

    // ---- The eraser's ring --------------------------------------------------------------
    property point eraserPos: Qt.point(-100, -100)
    Rectangle {
        readonly property point at: draw.active ? root.eraserPos : hover.point.position
        visible: root.tool === "eraser" && (draw.active || hover.hovered) && root.active
        x: at.x - width / 2
        y: at.y - height / 2
        width: root.eraserRadius * 2
        height: width
        radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.18)
        border.width: 1.5
        border.color: Qt.rgba(0, 0, 0, 0.45)
    }
}
