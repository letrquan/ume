import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The ink on one screen (services/Ink.qml): a see-through window over
// everything, the strokes drawn on it, and the toolbar on the screen it's
// on (Ink.toolbarScreen: the focused one at first, then wherever you last
// drew). shell.qml creates it only while the ink is on.
// Drawing: the whole window takes the pointer, and the toolbar's screen the
// keyboard (Esc, the tools' keys). Pass-through: only the toolbar takes
// clicks (an input region of just its pill; none on the other screens) and
// nothing takes the keyboard, so the apps under it work as usual.
// mango must not blur behind it (the strokes would get a frosted halo):
// `layer_rule=no_blur:1,layer_name:^mine-ink$`.
PanelWindow {
    id: root

    required property ShellScreen modelData
    readonly property bool hasBar: Ink.toolbarScreen === modelData.name
    readonly property bool drawing: !Ink.passThrough
    // For the tests (and anything that wants to look in).
    readonly property alias canvasItem: canvas
    readonly property alias barItem: bar

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "mine-ink"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: drawing && hasBar ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Drawing: all of it (no mask). Pass-through: the toolbar's pill only.
    mask: drawing ? null : barOnly
    Region {
        id: barOnly
        x: root.hasBar ? bar.x : 0
        y: root.hasBar ? bar.y : 0
        width: root.hasBar ? bar.width : 0
        height: root.hasBar ? bar.height - 30 : 0
    }

    InkCanvas {
        id: canvas
        anchors.fill: parent
        active: root.drawing
        tool: Ink.tool
        color: Ink.color
        lineWidth: Ink.lineWidth
        touchDraws: Style.inkTouch
        fadeAfter: Style.inkFadeSeconds
        visible: true
        // Not under the toolbar.
        blocked: (x, y) => root.hasBar && bar.visible && x >= bar.x && x <= bar.x + bar.width && y >= bar.y && y <= bar.y + bar.height - 30
        onTouched: Ink.toolbarScreen = root.modelData.name
    }

    Connections {
        target: Ink
        function onCommand(what) {
            if (what === "clear")
                canvas.clear();
            else if (what === "undo" && root.hasBar)
                canvas.undo();
            else if (what === "redo" && root.hasBar)
                canvas.redo();
        }
    }

    InkBar {
        id: bar
        canvas: canvas
        visible: root.hasBar
        // Hidden at once for the screenshot (no fade: it would be caught).
        opacity: Ink.capturing ? 0 : 1
        x: Ink.toolbarPos.x >= 0 ? Math.min(Ink.toolbarPos.x, root.width - width) : (root.width - width) / 2
        y: Ink.toolbarPos.y >= 0 ? Math.min(Ink.toolbarPos.y, root.height - height) : Style.barBottom + 24
    }

    // ---- Keys (drawing, on the toolbar's screen) ----
    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            const ctrl = event.modifiers & Qt.ControlModifier;
            const shift = event.modifiers & Qt.ShiftModifier;
            let used = true;
            if (event.key === Qt.Key_Escape)
                Ink.close();
            else if (ctrl && (event.key === Qt.Key_Y || (shift && event.key === Qt.Key_Z)))
                canvas.redo();
            else if (ctrl && event.key === Qt.Key_Z)
                canvas.undo();
            else if (ctrl)
                used = false;
            else if (event.key === Qt.Key_P)
                Ink.setTool("pen");
            else if (event.key === Qt.Key_H)
                Ink.setTool("highlighter");
            else if (event.key === Qt.Key_L)
                Ink.setTool("laser");
            else if (event.key === Qt.Key_E)
                Ink.setTool("eraser");
            else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + Ink.colors.length)
                Ink.colorIndex = event.key - Qt.Key_1;
            else if (event.key === Qt.Key_BracketLeft)
                Ink.cycleSize(-1);
            else if (event.key === Qt.Key_BracketRight)
                Ink.cycleSize(1);
            else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)
                Ink.clear();
            else if (event.key === Qt.Key_T)
                Ink.togglePassThrough();
            else if (event.key === Qt.Key_S)
                Ink.save();
            else
                used = false;
            event.accepted = used;
        }
    }
    onDrawingChanged: if (drawing) keys.forceActiveFocus()
    Component.onCompleted: keys.forceActiveFocus()
}
