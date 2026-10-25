import QtQuick
import qs.common

// The screenshot overlay: the frozen screen, dimmed except what you pick.
//   Region: drag a rectangle (a click on a window takes the window).
//   Window: hover a window, click it.
//   Screen: click anywhere (or Enter).
// A small glass toolbar at the bottom switches mode and Edit. Esc / right
// click cancel, Tab cycles the mode, Enter / Space takes what's picked.
// With `recording` it picks what a screen recording takes, with `reading`
// where to copy text from: no Edit, and the hint says so.
//
// Tools (`task`, the toolbar's second group; a key toggles one, again goes
// back to a plain screenshot): T copy text · Q scan a QR code · L Google
// Lens · D translate. Not while picking for a recording.
// Translate: once picked, the overlay stays with the pick bright and the
// card (screenshot/TranslateCard.qml) next to it; keys then:
//   Tab the other way · C / Ctrl+C copy · Enter copy and close · Esc close
// (a click outside the card closes too).
//
// Edit on (E): once picked, the overlay stays with the pick bright and you
// draw on it (`marking`, screenshot/MarkupLayer.qml); the toolbar becomes
// the markup bar (screenshot/MarkupBar.qml), at the bottom, or just above
// the pick when the pick reaches down there, or at the top when the pick
// fills the screen. Keys while marking:
//   P pen · A arrow · B box · T text · X blur · 1-4 colors · [ ] size
//   Ctrl+Z undo · Ctrl+Shift+Z / Ctrl+Y redo
//   Enter / Ctrl+S save · Ctrl+C copy only · Esc cancel (with marks: twice)
// `editFile`: the same for a saved picture (the notification's Edit): it
// shows fitted on the dimmed screen, and saving writes it over.
// Plain QtQuick (no Quickshell types), so it can be previewed offscreen
// (QT_QUICK_BACKEND=rhi there, or the blur's shader draws nothing).
Item {
    id: root

    property string frozen: ""          // file path of the frozen screen
    property real outputScale: 1        // output scale, for the size label
    property var windows: []            // [{ x, y, width, height, title, appid }]
    property string mode: "region"
    property bool edit: false
    property bool confirm: false        // region: adjust then Enter (else: on release)
    property bool recording: false      // picking for a screen recording
    property bool reading: false        // picking text to copy (OCR)
    // What a pick is for: shot | text | qr | lens | translate.
    property string task: reading ? "text" : "shot"

    // ---- Translating (after a translate pick) ----
    property bool translating: false    // the card is up
    property var cardGeo: null          // the pick: { x, y, w, h }
    property string cardState: ""       // reading | translating | done | empty | failed
    property string cardText: ""
    property string cardTranslation: ""
    property string cardFrom: ""
    property string cardTo: ""
    property string cardError: ""
    property string cardNote: ""

    // ---- Marking (Edit) ----
    property bool marking: false        // drawing on what was picked
    property var markGeo: null          // its geometry (services/Screenshot.qml beginMarkup)
    property string editFile: ""        // drawing on this saved picture instead
    property int pixelSize: 16          // blur blocks, in real pixels
    property string marksPath: ""       // where the drawn marks go for saving (a temp file)

    signal modeRequested(string mode)
    signal editRequested(bool wanted)
    signal taskRequested(string task)
    // The translate card's buttons.
    signal swapRequested()
    signal copyRequested()
    signal retryRequested()
    signal captureRect(real x, real y, real w, real h)
    signal captureAll()
    signal cancel()
    // Marking done: how ("save" | "copy"), the geometry, the blurred
    // rectangles ("WxH+X+Y" in the kept part's pixels) and whether
    // marksPath holds the lines, arrows, boxes and text.
    signal markupDone(string how, var geo, var blurs, bool marked)
    // The saved picture to edit can't be read.
    signal loadFailed()

    // ---- What's picked -----------------------------------------------------------------------
    property real pointerX: -1
    property real pointerY: -1
    property bool dragging: false
    property real startX: 0
    property real startY: 0
    property var selection: null        // { x, y, width, height } while / after dragging

    readonly property var hovered: {
        if (pointerX < 0 || mode === "screen")
            return null;
        return windows.find(w => pointerX >= w.x && pointerX < w.x + w.width && pointerY >= w.y && pointerY < w.y + w.height) ?? null;
    }
    // While marking: the pick and its picture (MarkupLayer's geo). A saved
    // picture is fitted on the screen, at most one real pixel per pixel,
    // leaving room for the toolbar under it.
    readonly property var fileGeo: {
        const pic = markup.item?.picture ?? null;
        if (editFile === "" || !pic || pic.status !== Image.Ready || width <= 0)
            return null;
        const iw = pic.implicitWidth, ih = pic.implicitHeight;
        const top = 48, bottom = 48 + 28 + 32;
        const s = Math.max(outputScale, iw / (width - 96), ih / (height - top - bottom));
        const w = iw / s, h = ih / s;
        const x = Math.round((width - w) / 2), y = Math.round(top + (height - top - bottom - h) / 2);
        return { x: x, y: y, w: w, h: h, ox: x, oy: y, s: s, px: 0, py: 0, pw: iw, ph: ih };
    }
    readonly property var geo: !marking ? null : editFile !== "" ? fileGeo : markGeo

    // The rectangle shown undimmed (null = nothing yet).
    readonly property var picked: translating ? (cardGeo ? { x: cardGeo.x, y: cardGeo.y, width: cardGeo.w, height: cardGeo.h } : null)
                                : geo ? { x: geo.x, y: geo.y, width: geo.w, height: geo.h }
                                : marking ? null
                                : mode === "screen" ? { x: 0, y: 0, width: width, height: height }
                                : mode === "region" && selection ? selection
                                : hovered

    function takePicked() {
        if (mode === "screen")
            captureAll();
        else if (picked)
            captureRect(picked.x, picked.y, picked.width, picked.height);
    }

    function cycleMode() {
        const order = ["region", "window", "screen"];
        selection = null;
        modeRequested(order[(order.indexOf(mode) + 1) % order.length]);
    }

    onModeChanged: selection = null

    // ---- Marking: finishing --------------------------------------------------------------------
    property bool discardArmed: false   // Esc once with marks: the next Esc discards
    property string pendingHow: ""
    property var pendingBlurs: []
    property string problem: ""         // shown in the tip for a while

    Timer {
        id: discardTimer
        interval: 2500
        onTriggered: root.discardArmed = false
    }
    Timer {
        id: problemTimer
        interval: 3500
        onTriggered: root.problem = ""
    }

    function requestCancel() {
        if (marking && (markup.item?.hasMarks ?? false) && !discardArmed) {
            discardArmed = true;
            discardTimer.restart();
            return;
        }
        cancel();
    }

    // Save or copy. Without lines, arrows, boxes or text there's no marks
    // picture to draw (and with no marks at all, Screenshot takes the plain
    // cut, unchanged).
    function finishMarkup(how) {
        const layer = markup.item;
        if (!layer || !geo || layer.exporting || pendingHow !== "")
            return;
        layer.commitText();
        pendingHow = how;
        pendingBlurs = layer.blurAreas();
        if (!layer.exportTo(marksPath)) {
            pendingHow = "";
            markupDone(how, geo, pendingBlurs, false);
        }
    }

    function markupExported(ok) {
        const how = pendingHow;
        pendingHow = "";
        if (!ok) {
            problem = "Couldn't draw the marks";
            problemTimer.restart();
            return;
        }
        markupDone(how, geo, pendingBlurs, true);
    }

    function markKey(event) {
        const layer = markup.item;
        const k = event.key;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        if (!layer || pendingHow !== "") {
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_Escape)
            requestCancel();
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            // A held Enter (it took the pick) mustn't save at once.
            if (!event.isAutoRepeat)
                finishMarkup("save");
        } else if (ctrl && k === Qt.Key_S)
            finishMarkup("save");
        else if (ctrl && k === Qt.Key_C)
            finishMarkup("copy");
        else if (ctrl && (k === Qt.Key_Y || (k === Qt.Key_Z && shift)))
            layer.redo();
        else if (ctrl && k === Qt.Key_Z)
            layer.undo();
        else if (ctrl || (event.modifiers & Qt.AltModifier))
            return;
        else if (k === Qt.Key_P)
            layer.setTool("pen");
        else if (k === Qt.Key_A)
            layer.setTool("arrow");
        else if (k === Qt.Key_B)
            layer.setTool("box");
        else if (k === Qt.Key_T)
            layer.setTool("text");
        else if (k === Qt.Key_X)
            layer.setTool("blur");
        else if (k >= Qt.Key_1 && k < Qt.Key_1 + layer.colors.length)
            layer.colorIndex = k - Qt.Key_1;
        else if (k === Qt.Key_BracketLeft)
            layer.cycleSize(-1);
        else if (k === Qt.Key_BracketRight)
            layer.cycleSize(1);
        else
            return;
        event.accepted = true;
    }

    // ---- Tools ----
    readonly property var tools: [
        { id: "shot", icon: "photo_camera", label: "Screenshot", key: "" },
        { id: "text", icon: "text_fields", label: "Copy text", key: "T" },
        { id: "qr", icon: "qr_code_scanner", label: "Scan a QR code", key: "Q" },
        { id: "lens", icon: "image_search", label: "Search with Google Lens", key: "L" },
        { id: "translate", icon: "translate", label: "Translate", key: "D" }
    ]
    // A tool's key or button: on, or back to a plain screenshot.
    function toggleTask(t) {
        if (!recording)
            taskRequested(task === t ? "shot" : t);
    }

    function cardKey(event) {
        const k = event.key;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        if (k === Qt.Key_Escape)
            cancel();
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab)
            cardLoader.item?.swap();
        else if (k === Qt.Key_C && (ctrl || !(event.modifiers & Qt.AltModifier)))
            cardLoader.item?.copyNow();
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && !event.isAutoRepeat) {
            if (cardLoader.item?.canCopy) {
                cardLoader.item.copyNow();
                cancel();
            }
        } else
            return;
        event.accepted = true;
    }

    focus: true
    Keys.onPressed: event => {
        if (marking) {
            markKey(event);
            return;
        }
        if (translating) {
            cardKey(event);
            return;
        }
        if (!recording && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))
                && (event.key === Qt.Key_T || event.key === Qt.Key_Q || event.key === Qt.Key_L || event.key === Qt.Key_D)) {
            toggleTask(event.key === Qt.Key_T ? "text" : event.key === Qt.Key_Q ? "qr" : event.key === Qt.Key_L ? "lens" : "translate");
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Escape)
            cancel();
        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            cycleMode();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
            takePicked();
        else if (event.key === Qt.Key_E && task === "shot")
            editRequested(!edit);
        else if (event.key === Qt.Key_R)
            modeRequested("region");
        else if (event.key === Qt.Key_W)
            modeRequested("window");
        else if (event.key === Qt.Key_S)
            modeRequested("screen");
        else
            return;
        event.accepted = true;
    }

    // ---- The frozen screen -----------------------------------------------------------------
    // (Not for a saved picture: the screen behind shows through, dimmed.)
    Image {
        id: frozenImage
        anchors.fill: parent
        visible: root.editFile === ""
        source: root.frozen !== "" ? "file://" + root.frozen : ""
        sourceSize: Qt.size(root.width * root.outputScale, root.height * root.outputScale)
        fillMode: Image.Stretch
        asynchronous: false
        cache: false
        smooth: true
    }

    // Dim everything but the picked rectangle (four strips around it).
    Item {
        id: dim
        anchors.fill: parent
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }

        readonly property var r: root.picked ?? { x: 0, y: 0, width: 0, height: 0 }
        readonly property color shade: Qt.rgba(0, 0, 0, root.editFile !== "" ? Math.max(0.6, Style.screenshotDim)
                                                : root.picked && root.mode === "screen" ? Style.screenshotDim * 0.35 : Style.screenshotDim)

        Rectangle { x: 0; y: 0; width: parent.width; height: dim.r.y; color: dim.shade }
        Rectangle { x: 0; y: dim.r.y + dim.r.height; width: parent.width; height: parent.height - y; color: dim.shade }
        Rectangle { x: 0; y: dim.r.y; width: dim.r.x; height: dim.r.height; color: dim.shade }
        Rectangle { x: dim.r.x + dim.r.width; y: dim.r.y; width: parent.width - x; height: dim.r.height; color: dim.shade }
        // Nothing picked yet: dim it all.
        Rectangle { anchors.fill: parent; color: dim.shade; visible: !root.picked }
    }

    // Accent frame around the picked rectangle; glides between windows.
    Rectangle {
        id: frame
        visible: root.picked !== null && root.mode !== "screen" && !root.marking
        x: root.picked?.x ?? 0
        y: root.picked?.y ?? 0
        width: root.picked?.width ?? 0
        height: root.picked?.height ?? 0
        color: "transparent"
        border.width: 2
        border.color: Colors.primary
        radius: root.mode === "window" || (root.mode === "region" && !root.selection) ? 10 : 2

        // Only glide when moving between windows, not while dragging.
        Behavior on x { enabled: !root.dragging; NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on y { enabled: !root.dragging; NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on width { enabled: !root.dragging; NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on height { enabled: !root.dragging; NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
    }

    // Size in real pixels (what gets saved), and the window's name.
    Rectangle {
        id: sizeChip
        visible: frame.visible && !root.translating
        readonly property bool below: frame.y + frame.height + 34 < root.height - 70
        x: Math.max(8, Math.min(root.width - width - 8, frame.x + frame.width / 2 - width / 2))
        y: below ? frame.y + frame.height + 8 : Math.max(8, frame.y - height - 8)
        width: sizeText.implicitWidth + 20
        height: 26
        radius: 13
        color: Style.alpha(Colors.surfaceContainer, 0.88)
        border.width: 1
        border.color: Style.islandBorder

        StyledText {
            id: sizeText
            anchors.centerIn: parent
            readonly property string name: root.mode !== "region" || !root.selection ? (root.hovered?.title ?? "") : ""
            text: Math.round((root.picked?.width ?? 0) * root.outputScale) + " × " + Math.round((root.picked?.height ?? 0) * root.outputScale)
                  + (name !== "" ? "   " + (name.length > 40 ? name.slice(0, 40) + "…" : name) : "")
            role: "label"
            font.features: ({ "tnum": 1 })
        }
    }

    // While marking: the frame sits just outside the pick, off the picture.
    Rectangle {
        visible: root.geo !== null && (root.geo.w < root.width || root.geo.h < root.height)
        x: (root.geo?.x ?? 0) - 2
        y: (root.geo?.y ?? 0) - 2
        width: (root.geo?.w ?? 0) + 4
        height: (root.geo?.h ?? 0) + 4
        color: "transparent"
        border.width: 2
        border.color: Style.alpha(Colors.primary, 0.85)
        radius: 4
    }

    // ---- Picking with the mouse -------------------------------------------------------------
    MouseArea {
        anchors.fill: parent
        enabled: !root.marking && !root.translating
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.mode === "region" ? Qt.CrossCursor : Qt.PointingHandCursor

        onPositionChanged: mouse => {
            root.pointerX = mouse.x;
            root.pointerY = mouse.y;
            if (!pressed || root.mode !== "region")
                return;
            const dx = mouse.x - root.startX, dy = mouse.y - root.startY;
            if (!root.dragging && Math.abs(dx) + Math.abs(dy) < 6)
                return;
            root.dragging = true;
            root.selection = {
                x: Math.min(root.startX, mouse.x), y: Math.min(root.startY, mouse.y),
                width: Math.abs(dx), height: Math.abs(dy)
            };
        }
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.cancel();
                return;
            }
            // A tap (touch) has no hover before it: the window under it
            // is the one it takes.
            root.pointerX = mouse.x;
            root.pointerY = mouse.y;
            root.startX = mouse.x;
            root.startY = mouse.y;
            root.dragging = false;
            if (root.mode === "region" && !root.confirm)
                root.selection = null;
        }
        onReleased: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return;
            const wasDrag = root.dragging;
            root.dragging = false;
            if (root.mode === "region" && wasDrag) {
                if (!root.confirm)
                    root.takePicked();
                return;
            }
            // A click: the window under it, or the screen.
            if (root.mode === "screen")
                root.captureAll();
            else if (root.hovered)
                root.captureRect(root.hovered.x, root.hovered.y, root.hovered.width, root.hovered.height);
        }
    }

    // ---- Marking: the marks ------------------------------------------------------------------
    Loader {
        id: markup
        anchors.fill: parent
        active: root.marking

        sourceComponent: MarkupLayer {
            geo: root.geo
            source: root.editFile !== "" ? root.editFile : root.frozen
            showPicture: root.editFile !== ""
            block: root.pixelSize
            onDone: root.forceActiveFocus()
            onExported: ok => root.markupExported(ok)
        }
    }
    // A new mark after a first Esc: the next Esc asks again.
    Connections {
        target: markup.item
        function onMarksChanged() {
            root.discardArmed = false;
        }
    }
    Connections {
        target: markup.item?.picture ?? null
        function onStatusChanged() {
            if (markup.item.picture.status === Image.Error)
                root.loadFailed();
        }
    }

    // ---- Translating: the card ------------------------------------------------------------------
    // A click (or right click) outside the card closes.
    MouseArea {
        anchors.fill: parent
        enabled: root.translating
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.cancel()
    }

    // Next to the pick: under it, else above, else right, else left, else
    // over its bottom (a pick that fills the screen). Made when it's needed
    // (so it rises in then; a plain screenshot has none of its frost).
    Loader {
        id: cardLoader
        active: root.translating && root.cardGeo !== null
        sourceComponent: TranslateCard {
            id: card
            objectName: "translateCard"
            backdrop: frozenImage
            stage: root.cardState
            original: root.cardText
            translation: root.cardTranslation
            from: root.cardFrom
            to: root.cardTo
            error: root.cardError
            note: root.cardNote
            maxHeight: Math.max(220, Math.min(520, root.height - 48))
            width: Math.min(440, root.width - 24)
            height: implicitHeight

            readonly property var g: root.cardGeo ?? { x: 0, y: 0, w: 0, h: 0 }
            readonly property real gap: 12
            readonly property string side: g.y + g.h + gap + height <= root.height - gap ? "below"
                                          : g.y - gap - height >= gap ? "above"
                                          : g.x + g.w + gap + width <= root.width - gap ? "right"
                                          : g.x - gap - width >= gap ? "left" : "over"
            function clampX(v) { return Math.max(gap, Math.min(root.width - width - gap, v)); }
            function clampY(v) { return Math.max(gap, Math.min(root.height - height - gap, v)); }
            x: side === "right" ? g.x + g.w + gap
               : side === "left" ? g.x - gap - width
               : clampX(g.w >= width && side !== "over" ? g.x : g.x + g.w / 2 - width / 2)
            y: side === "below" ? g.y + g.h + gap
               : side === "above" ? g.y - gap - height
               : side === "over" ? clampY(g.y + g.h - height - 3 * gap)
               : clampY(g.y)

            onSwap: root.swapRequested()
            onCopy: root.copyRequested()
            onRetry: root.retryRequested()
            onClose: root.cancel()
        }
    }

    // ---- Toolbar ----------------------------------------------------------------------------
    // Where the markup bar goes: at the bottom when the pick ends above it,
    // else just above the pick, else (the pick fills the screen) at the top.
    readonly property real bottomY: height - 48 - 28
    readonly property string markPlace: {
        const g = geo;
        if (!g || g.y + g.h + 14 <= bottomY)
            return "bottom";
        return g.y - 48 - 14 >= 12 ? "above" : "top";
    }

    Item {
        id: toolbar
        x: root.marking && root.markPlace === "above"
           ? Math.max(12, Math.min(root.width - width - 12, root.geo.x + root.geo.w / 2 - width / 2))
           : Math.round((root.width - width) / 2)
        y: !root.marking || root.markPlace === "bottom" ? root.bottomY
           : root.markPlace === "above" ? root.geo.y - height - 14 : 20
        width: (root.marking ? markBar.implicitWidth : bar.implicitWidth) + 12
        height: 48
        // The translate card has its own buttons.
        visible: !root.translating
        opacity: 0
        transform: Translate { id: rise; y: 14 }
        Component.onCompleted: { opacity = 1; rise.y = 0; }
        Behavior on opacity { NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }

        Glass {
            anchors.fill: parent
            radius: height / 2
            color: Style.alpha(Colors.surfaceContainer, 0.9)
        }

        // Keeps clicks on the toolbar from picking.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        // Marking: tools, colors, undo, Copy, Save.
        MarkupBar {
            id: markBar
            anchors.centerIn: parent
            marker: markup.item
            enabled: root.marking
            opacity: root.marking ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
            onSave: root.finishMarkup("save")
            onCopy: root.finishMarkup("copy")
            onClose: root.requestCancel()
        }

        Row {
            id: bar
            anchors.centerIn: parent
            spacing: 4
            enabled: !root.marking
            opacity: root.marking ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Motion.contentOut } }

            // Mode: a pill that slides under the chosen one.
            Item {
                id: modes
                anchors.verticalCenter: parent.verticalCenter
                width: modeRow.implicitWidth
                height: 36

                readonly property var list: [
                    { id: "region", icon: "crop", label: "Region" },
                    { id: "window", icon: "select_window", label: "Window" },
                    { id: "screen", icon: "fullscreen", label: "Screen" }
                ]
                // (count: re-read once the buttons exist.)
                readonly property Item current: {
                    modeRepeater.count;
                    return modeRepeater.itemAt(list.findIndex(m => m.id === root.mode));
                }

                Rectangle {
                    x: modes.current?.x ?? 0
                    width: modes.current?.width ?? 0
                    height: parent.height
                    radius: height / 2
                    color: Colors.primary
                    Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                }

                Row {
                    id: modeRow
                    height: parent.height

                    Repeater {
                        id: modeRepeater
                        model: modes.list

                        MouseArea {
                            id: modeButton
                            required property var modelData
                            readonly property bool chosen: root.mode === modelData.id
                            width: modeLabel.implicitWidth + 50
                            height: modeRow.height
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.modeRequested(modelData.id)

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: Colors.textOnSurface
                                opacity: !modeButton.chosen && modeButton.containsMouse ? Style.hoverTint : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            }

                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: modeButton.modelData.icon
                                    size: 18
                                    color: modeButton.chosen ? Colors.textOnPrimary : Colors.textOnSurface
                                }
                                StyledText {
                                    id: modeLabel
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modeButton.modelData.label
                                    weight: 600
                                    color: modeButton.chosen ? Colors.textOnPrimary : Colors.textOnSurface
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 20
                color: Style.alpha(Colors.textOnSurface, 0.15)
            }

            // Tools: a picture, or what to do with the pick instead (copy
            // the text, scan a code, Google Lens, translate). A pill slides
            // under the chosen one, like the modes'.
            Item {
                id: toolGroup
                visible: !root.recording
                anchors.verticalCenter: parent.verticalCenter
                width: toolRow.implicitWidth
                height: 36

                readonly property Item current: {
                    toolRepeater.count;
                    return toolRepeater.itemAt(root.tools.findIndex(t => t.id === root.task));
                }

                Rectangle {
                    x: toolGroup.current?.x ?? 0
                    width: toolGroup.current?.width ?? 0
                    height: parent.height
                    radius: height / 2
                    color: Colors.primary
                    Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                }

                Row {
                    id: toolRow
                    height: parent.height

                    Repeater {
                        id: toolRepeater
                        model: root.tools

                        MouseArea {
                            id: toolButton
                            required property var modelData
                            readonly property bool chosen: root.task === modelData.id
                            objectName: "tool-" + modelData.id
                            width: 40
                            height: toolRow.height
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.taskRequested(modelData.id)
                            onContainsMouseChanged: root.toolHover(containsMouse, modelData.label, modelData.key)

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: Colors.textOnSurface
                                opacity: !toolButton.chosen && toolButton.containsMouse ? Style.hoverTint : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            }
                            Icon {
                                anchors.centerIn: parent
                                name: toolButton.modelData.icon
                                size: 19
                                fill: toolButton.chosen ? 1 : 0
                                color: toolButton.chosen ? Colors.textOnPrimary : Colors.textOnSurface
                            }
                        }
                    }
                }
            }

            Rectangle {
                visible: !root.recording
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 20
                color: Style.alpha(Colors.textOnSurface, 0.15)
            }

            // Edit: mark it up before saving (or swappy afterwards,
            // Style.screenshotEditor). Not for recordings or the tools.
            MouseArea {
                id: editButton
                visible: !root.recording && root.task === "shot"
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.editRequested(!root.edit)

                Shape {
                    anchors.fill: parent
                    shape: root.edit ? "Cookie9Sided" : "Circle"
                    color: root.edit ? Colors.primary : Style.alpha(Colors.textOnSurface, editButton.containsMouse ? 0.12 : 0.0)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
                Icon {
                    anchors.centerIn: parent
                    name: "edit"
                    size: 18
                    fill: root.edit ? 1 : 0
                    color: root.edit ? Colors.textOnPrimary : Colors.textOnSurface
                }
            }

            // Cancel.
            MouseArea {
                id: closeButton
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cancel()

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Colors.textOnSurface
                    opacity: closeButton.containsMouse ? Style.hoverTint : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }
                Icon {
                    anchors.centerIn: parent
                    name: "close"
                    size: 18
                }
            }
        }
    }

    // Marking: what the button under the pointer does and its key, or
    // "Esc again" after a first Esc with marks; next to the toolbar.
    property bool tipShown: false
    // The tool under the pointer (picking).
    property string toolTip: ""
    property string toolTipKey: ""
    function toolHover(on, label, key) {
        if (on) {
            toolTip = label;
            toolTipKey = key;
        } else if (toolTip === label) {
            toolTip = "";
            toolTipKey = "";
        }
    }
    readonly property string hoverTip: marking ? markBar.tip : toolTip
    readonly property string hoverTipKey: marking ? markBar.tipKey : toolTipKey
    Timer {
        id: tipWait
        interval: 450
        onTriggered: root.tipShown = true
    }
    Timer {
        id: tipCool
        interval: 400
        onTriggered: root.tipShown = false
    }
    Connections {
        target: root
        function onHoverTipChanged() {
            if (root.hoverTip === "") {
                tipWait.stop();
                tipCool.restart();
            } else {
                tipCool.stop();
                if (!root.tipShown)
                    tipWait.restart();
            }
        }
    }

    Rectangle {
        id: tipChip
        readonly property string text: root.problem !== "" ? root.problem
                                     : root.discardArmed ? "Esc or × again to discard your marks"
                                     : root.tipShown ? root.hoverTip : ""
        readonly property string key: root.problem === "" && !root.discardArmed && root.tipShown ? root.hoverTipKey : ""
        visible: opacity > 0
        opacity: !root.translating && text !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        x: Math.max(8, Math.min(root.width - width - 8, toolbar.x + toolbar.width / 2 - width / 2))
        // Above the bar, or under it when there's no room (it says "Esc again").
        y: toolbar.y - height - 8 >= 8 ? toolbar.y - height - 8 : toolbar.y + toolbar.height + 8
        width: tipRow.implicitWidth + 24
        height: 30
        radius: 15
        color: Style.alpha(Colors.surfaceContainer, 0.92)
        border.width: 1
        border.color: Style.islandBorder

        Row {
            id: tipRow
            anchors.centerIn: parent
            spacing: 8
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: tipChip.text
                role: "label"
                color: root.problem !== "" ? Colors.error : Colors.textOnSurface
            }
            // The key, in a small cap.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: tipChip.key !== ""
                width: keyText.implicitWidth + 10
                height: 18
                radius: 5
                color: Style.alpha(Colors.textOnSurface, 0.1)
                border.width: 1
                border.color: Style.alpha(Colors.textOnSurface, 0.18)
                StyledText {
                    id: keyText
                    anchors.centerIn: parent
                    text: tipChip.key
                    role: "micro"
                    color: Colors.textOnSurfaceVariant
                }
            }
        }
    }

    // First hint, until something is picked.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 70
        visible: !root.marking && !root.translating && ((!root.picked && root.mode !== "screen") || root.recording || root.task !== "shot")
        width: hint.implicitWidth + 28
        height: 32
        radius: 16
        color: Style.alpha(Colors.surfaceContainer, 0.88)
        border.width: 1
        border.color: Style.islandBorder

        StyledText {
            id: hint
            anchors.centerIn: parent
            text: (root.recording ? "Record:  "
                   : ({ text: "Copy text:  ", qr: "Scan a QR code:  ", lens: "Google Lens:  ", translate: "Translate:  " })[root.task] ?? "")
                  + (root.mode === "region" ? "Drag to select · click a window · Esc to cancel"
                     : root.mode === "window" ? "Click a window · Esc to cancel"
                     : "Click anywhere or Enter · Esc to cancel")
            role: "caption"
            color: Colors.textOnSurfaceVariant
        }
    }
}
