import QtQuick
import qs.common
import "marks.js" as M

// Drawing on a screenshot before it is saved (screenshot/ShotView.qml shows
// this once something is picked with Edit on, or for the notification's
// Edit). The marks stay inside the picked rectangle:
//   pen     freehand, smoothed; a stylus's pressure picks the width
//   arrow   drag from the tail to the head
//   box     a rounded outline
//   text    click, type, Enter (or click elsewhere); Esc drops it
//   blur    drag a rectangle: the picture under it turns to blocks
// Mouse, touch and stylus all draw. Undo / redo, four colors, three sizes.
//
// Saving (services/Screenshot.qml, scripts/shot-mark.sh): blurred
// rectangles are made blocks by ImageMagick in the saved picture itself
// (snapped to whole blocks, the same blocks this shows), and everything
// else is drawn here once more at the picture's real pixel size (exportTo:
// lines, arrows, boxes and text on a transparent picture) and laid on top.
// So whatever has no mark stays exactly the plain cut.
// Plain QtQuick, so it can be previewed offscreen.
Item {
    id: root

    // The pick and its picture:
    //   x, y, w, h       the picked rectangle on this item (logical px)
    //   ox, oy, s        where the picture's top-left corner is (logical) and
    //                    its pixels per logical px
    //   px, py, pw, ph   the part of the picture that is kept (its pixels)
    property var geo: null
    property string source: ""          // the picture's file
    property bool showPicture: false    // draw it here (a saved file); else the frozen screen behind shows it
    property int block: 16              // blur blocks, in the picture's pixels

    // ---- Tools ---------------------------------------------------------------------------
    property string tool: "pen"         // pen | arrow | box | text | blur
    property int colorIndex: 0
    property int sizeIndex: 1
    readonly property var colors: ["#ff453a", "#ffd60a", Colors.primary, "#ffffff"]
    readonly property var colorNames: ["Red", "Yellow", "Accent", "White"]
    readonly property color color: colors[colorIndex]
    readonly property var widths: [3, 5, 8]             // lines (logical px)
    readonly property var textSizes: [18, 24, 34]       // text (logical px)
    readonly property real lineWidth: widths[sizeIndex]
    readonly property int textSize: textSizes[sizeIndex]

    // ---- Marks ---------------------------------------------------------------------------
    property var marks: []
    property var undone: []
    property var current: null
    readonly property bool canUndo: marks.length > 0 || editingText
    readonly property bool canRedo: undone.length > 0
    readonly property bool hasMarks: marks.length > 0 || current !== null || (editingText && editor.displayText.trim() !== "")
    readonly property bool exporting: exporter.active

    // The keyboard can go back to the overlay (a text was finished).
    signal done()
    // exportTo() finished: the marks picture is at `path` (ok) or not.
    signal exported(bool ok, string path)

    function add(m) {
        marks = marks.concat([m]);
        undone = [];
    }
    function undo() {
        if (editingText) {
            cancelText();
            return;
        }
        if (marks.length === 0)
            return;
        undone = undone.concat([marks[marks.length - 1]]);
        marks = marks.slice(0, -1);
    }
    function redo() {
        commitText();
        if (undone.length === 0)
            return;
        marks = marks.concat([undone[undone.length - 1]]);
        undone = undone.slice(0, -1);
    }
    function setTool(t) {
        commitText();
        tool = t;
    }
    function cycleSize(step) {
        sizeIndex = Math.max(0, Math.min(widths.length - 1, sizeIndex + step));
    }

    // The blurred rectangles in the kept part's pixels, ready for magick:
    // "WxH+X+Y" each.
    function blurAreas() {
        return marks.filter(m => m.kind === "blur").map(m => m.area[2] + "x" + m.area[3] + "+" + m.area[0] + "+" + m.area[1]);
    }
    function lineMarks() {
        return marks.filter(m => m.kind !== "blur");
    }

    // A blur rectangle (pick coordinates) as whole blocks of the kept part:
    // [x, y, w, h] in its pixels, and the same back on screen.
    function snapBlur(x1, y1, x2, y2) {
        const g = geo;
        const r = M.rect(Math.max(0, Math.min(x1, g.w)), Math.max(0, Math.min(y1, g.h)),
                         Math.max(0, Math.min(x2, g.w)), Math.max(0, Math.min(y2, g.h)));
        // Pick → the kept part's pixels.
        const kx = v => (g.x - g.ox + v) * g.s - g.px;
        const ky = v => (g.y - g.oy + v) * g.s - g.py;
        let x = Math.max(0, Math.floor(kx(r.x)));
        let y = Math.max(0, Math.floor(ky(r.y)));
        const xe = Math.min(g.pw, Math.ceil(kx(r.x + r.w)));
        const ye = Math.min(g.ph, Math.ceil(ky(r.y + r.h)));
        if (xe - x < 2 || ye - y < 2)
            return null;
        // Whole blocks: wider to the right (or to the left at the edge).
        let w = Math.min(g.pw, Math.ceil((xe - x) / block) * block);
        let h = Math.min(g.ph, Math.ceil((ye - y) / block) * block);
        x = Math.max(0, Math.min(x, g.pw - w));
        y = Math.max(0, Math.min(y, g.ph - h));
        // Back on screen (pick coordinates).
        const sx = v => (v + g.px) / g.s - (g.x - g.ox);
        const sy = v => (v + g.py) / g.s - (g.y - g.oy);
        return { area: [x, y, w, h], x1: sx(x), y1: sy(y), x2: sx(x + w), y2: sy(y + h) };
    }

    // ---- The picture ---------------------------------------------------------------------------
    // At its own size: shown for a saved file, read by the blur in any case.
    Image {
        id: pictureImage
        x: root.geo?.x ?? 0
        y: root.geo?.y ?? 0
        width: root.geo?.w ?? 0
        height: root.geo?.h ?? 0
        visible: root.showPicture && root.geo !== null
        source: root.source === "" ? "" : "file://" + root.source.split("/").map(encodeURIComponent).join("/")
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
    }
    readonly property alias picture: pictureImage

    // ---- Drawing ---------------------------------------------------------------------------
    property real pressure: 1
    property bool ignoring: false       // this press doesn't draw (it finished a text, or began outside)

    function levelOf(p) {
        return p < 0.18 ? 0 : p < 0.38 ? 1 : p < 0.62 ? 2 : p < 0.84 ? 3 : 4;
    }

    function press(pt) {
        if (!geo)
            return;
        const x = pt.position.x - geo.x, y = pt.position.y - geo.y;
        ignoring = editingText || x < 0 || y < 0 || x > geo.w || y > geo.h;
        if (editingText) {
            commitText();
            return;
        }
        if (ignoring)
            return;
        if (tool === "text") {
            startText(x, y);
            ignoring = true;
            return;
        }
        if (tool === "pen") {
            const type = pt.device?.type;
            const stylus = type === PointerDevice.Stylus || type === PointerDevice.Airbrush;
            pressure = pt.pressure > 0 ? pt.pressure : 0.5;
            const levels = stylus ? [levelOf(pressure)] : null;
            current = { kind: "pen", color: color.toString(), width: lineWidth, points: [x, y], levels: levels,
                        paths: M.penPaths([x, y], levels, 5, 2) };
        } else if (tool === "blur") {
            current = { kind: "blur", ax: x, ay: y, x1: x, y1: y, x2: x, y2: y, area: null };
        } else {
            current = { kind: tool, color: color.toString(), width: lineWidth, x1: x, y1: y, x2: x, y2: y };
        }
    }

    function move(pt) {
        if (!current || ignoring)
            return;
        const x = pt.position.x - geo.x, y = pt.position.y - geo.y;
        const c = current;
        if (c.kind === "pen") {
            const p = c.points;
            if (Math.hypot(x - p[p.length - 2], y - p[p.length - 1]) < 1.2)
                return;
            const points = p.concat([x, y]);
            let levels = c.levels;
            if (levels) {
                // Smoothed, so the width doesn't flicker between levels.
                pressure = pressure * 0.6 + (pt.pressure > 0 ? pt.pressure : pressure) * 0.4;
                levels = levels.concat([levelOf(pressure)]);
            }
            current = Object.assign({}, c, { points: points, levels: levels, paths: M.penPaths(points, levels, 5, 2) });
        } else if (c.kind === "blur") {
            // Shown as it will be saved: whole blocks.
            const snapped = snapBlur(c.ax, c.ay, x, y) ?? { x1: c.ax, y1: c.ay, x2: c.ax, y2: c.ay, area: null };
            current = Object.assign({ kind: "blur", ax: c.ax, ay: c.ay }, snapped);
        } else {
            current = Object.assign({}, c, { x2: x, y2: y });
        }
    }

    function release() {
        const c = current;
        current = null;
        if (!c || ignoring)
            return;
        if (c.kind === "pen")
            add({ kind: "pen", color: c.color, width: c.width, paths: c.paths });
        else if (c.kind === "arrow" && Math.hypot(c.x2 - c.x1, c.y2 - c.y1) >= 8)
            add(c);
        else if (c.kind === "box" && Math.abs(c.x2 - c.x1) >= 4 && Math.abs(c.y2 - c.y1) >= 4)
            add(c);
        else if (c.kind === "blur" && c.area)
            add({ kind: "blur", x1: c.x1, y1: c.y1, x2: c.x2, y2: c.y2, area: c.area });
    }

    PointHandler {
        id: draw
        enabled: root.geo !== null && !root.exporting
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.TouchScreen
                         | PointerDevice.Stylus | PointerDevice.Airbrush
        acceptedButtons: Qt.LeftButton
        onActiveChanged: active ? root.press(point) : root.release()
        onPointChanged: if (active) root.move(point)
    }

    // ---- The picked rectangle: the marks, cut to it --------------------------------------------
    Item {
        id: area
        x: root.geo?.x ?? 0
        y: root.geo?.y ?? 0
        width: root.geo?.w ?? 0
        height: root.geo?.h ?? 0
        clip: true

        HoverHandler {
            cursorShape: root.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
        }

        Marks {
            anchors.fill: parent
            marks: root.marks
            current: root.current
            geo: root.geo
            picture: pictureImage.status === Image.Ready ? pictureImage : null
            block: root.block
        }

        // ---- Text being typed ----
        // The typing happens in an invisible TextInput; what shows is the
        // same Text the mark becomes (with its outline), so nothing moves
        // on Enter. displayText: an input method's unfinished word counts.
        TextInput {
            id: editor
            x: root.textX
            y: root.textY
            visible: root.editingText
            enabled: root.editingText
            color: "transparent"
            selectedTextColor: "transparent"
            selectionColor: Style.alpha(Colors.primary, 0.4)
            font.family: Style.font
            font.pixelSize: root.textSize
            font.variableAxes: ({ "wght": 700, "ROND": 100 })
            renderType: Text.CurveRendering
            cursorDelegate: Rectangle {
                width: 2
                color: root.color
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: root.editingText
                    PauseAnimation { duration: 500 }
                    NumberAnimation { to: 0; duration: 80 }
                    PauseAnimation { duration: 420 }
                    NumberAnimation { to: 1; duration: 80 }
                }
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.cancelText();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.commitText();
                    event.accepted = true;
                }
            }
        }
        Rectangle {
            visible: root.editingText
            x: editor.x - 6
            y: editor.y - 3
            width: Math.max(editor.contentWidth, root.textSize * 0.6) + 12
            height: editor.contentHeight + 6
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.16)
            border.width: 1.5
            border.color: Style.alpha(root.color, 0.9)
        }
        Mark {
            visible: root.editingText
            mark: root.editingText ? { kind: "text", x: editor.x, y: editor.y, text: editor.displayText, color: root.color, size: root.textSize } : null
        }
    }

    property bool editingText: false
    property real textX: 0
    property real textY: 0

    function startText(x, y) {
        editor.text = "";
        textX = x;
        // The click is the middle of the first line.
        textY = Math.max(0, y - editor.implicitHeight / 2);
        editingText = true;
        editor.forceActiveFocus();
    }
    function commitText() {
        if (!editingText)
            return;
        Qt.inputMethod.commit();
        const t = editor.text;
        editingText = false;
        editor.text = "";
        if (t.trim() !== "")
            add({ kind: "text", x: textX, y: textY, text: t, color: color.toString(), size: textSize });
        done();
    }
    function cancelText() {
        if (!editingText)
            return;
        Qt.inputMethod.reset();
        editingText = false;
        editor.text = "";
        done();
    }

    // ---- Saving ---------------------------------------------------------------------------
    // Lines, arrows, boxes and text, alone on a transparent picture the size
    // of the kept part (pw × ph item units = its pixels; the marks scaled by
    // s). Off to the side of the window, never seen. grabToImage makes it
    // `devicePixelRatio` times bigger than asked; shot-mark.sh scales it back.
    Loader {
        id: exporter
        active: false
        x: -(root.geo?.pw ?? 0) - 64
        sourceComponent: Item {
            width: root.geo.pw
            height: root.geo.ph

            Item {
                x: (root.geo.x - root.geo.ox) * root.geo.s - root.geo.px
                y: (root.geo.y - root.geo.oy) * root.geo.s - root.geo.py

                Marks {
                    width: root.geo.w
                    height: root.geo.h
                    scale: root.geo.s
                    transformOrigin: Item.TopLeft
                    marks: root.lineMarks()
                    geo: root.geo
                    block: root.block
                }
            }
        }
    }

    // Draws the lines, arrows, boxes and text into `path` (PNG); false when
    // there are none (only blurs, or nothing): then there's no picture.
    function exportTo(path) {
        commitText();
        current = null;
        if (lineMarks().length === 0)
            return false;
        exporter.active = true;
        const started = exporter.item.grabToImage(result => {
            const ok = result.saveToFile(path);
            exporter.active = false;
            root.exported(ok, path);
        }, Qt.size(geo.pw, geo.ph));
        if (!started) {
            exporter.active = false;
            exported(false, path);
        }
        return true;
    }
}
