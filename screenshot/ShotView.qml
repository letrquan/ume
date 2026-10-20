import QtQuick
import qs.common

// The screenshot overlay: the frozen screen, dimmed except what you pick.
//   Region: drag a rectangle (a click on a window takes the window).
//   Window: hover a window, click it.
//   Screen: click anywhere (or Enter).
// A small glass toolbar at the bottom switches mode and Edit (open the
// picture in swappy instead of the notification). Esc / right click cancel,
// Tab cycles the mode, Enter / Space takes what's picked.
// With `recording` it picks what a screen recording takes, with `reading`
// where to copy text from: no Edit, and the hint says so.
// Plain QtQuick (no Quickshell types), so it can be previewed offscreen.
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

    signal modeRequested(string mode)
    signal editRequested(bool wanted)
    signal captureRect(real x, real y, real w, real h)
    signal captureAll()
    signal cancel()

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
    // The rectangle shown undimmed (null = nothing yet).
    readonly property var picked: mode === "screen" ? { x: 0, y: 0, width: width, height: height }
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

    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape)
            cancel();
        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            cycleMode();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
            takePicked();
        else if (event.key === Qt.Key_E)
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
    Image {
        anchors.fill: parent
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
        readonly property color shade: Qt.rgba(0, 0, 0, root.picked && root.mode === "screen" ? Style.screenshotDim * 0.35 : Style.screenshotDim)

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
        visible: root.picked !== null && root.mode !== "screen"
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
        visible: frame.visible
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

    // ---- Picking with the mouse -------------------------------------------------------------
    MouseArea {
        anchors.fill: parent
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

    // ---- Toolbar ----------------------------------------------------------------------------
    Item {
        id: toolbar
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - 28
        width: bar.implicitWidth + 12
        height: 48
        opacity: 0
        transform: Translate { id: rise; y: 14 }
        Component.onCompleted: { opacity = 1; rise.y = 0; }
        Behavior on opacity { NumberAnimation { duration: Motion.contentIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }

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

        Row {
            id: bar
            anchors.centerIn: parent
            spacing: 4

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

            // Edit afterwards in swappy (not for recordings or text).
            MouseArea {
                id: editButton
                visible: !root.recording && !root.reading
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

    // First hint, until something is picked.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 70
        visible: (!root.picked && root.mode !== "screen") || root.recording || root.reading
        width: hint.implicitWidth + 28
        height: 32
        radius: 16
        color: Style.alpha(Colors.surfaceContainer, 0.88)
        border.width: 1
        border.color: Style.islandBorder

        StyledText {
            id: hint
            anchors.centerIn: parent
            text: (root.recording ? "Record:  " : root.reading ? "Copy text:  " : "")
                  + (root.mode === "region" ? "Drag to select · click a window · Esc to cancel"
                     : root.mode === "window" ? "Click a window · Esc to cancel"
                     : "Click anywhere or Enter · Esc to cancel")
            role: "caption"
            color: Colors.textOnSurfaceVariant
        }
    }
}
