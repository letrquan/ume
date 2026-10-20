import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.services

// The power menu: the screen dims, a glass card springs up in the middle
// with five big buttons that pop in one after another.
//
//      ╭─────────────────────────────────────────────────────╮
//      │  Power                                              │
//      │  Up 3 h 12 min · user                               │
//      │   (🔒)    (☾)     (⇥)      (↻)      (⏻)              │
//      │   Lock   Sleep  Log out  Restart  Shut down         │
//      │           ← →  Enter  ·  1–5  ·  Esc                │
//      ╰─────────────────────────────────────────────────────╯
//
// Restart, Shut down and Log out ask for a second press (a ring shows the
// time left). Plain QtQuick + SessionState, so it can be previewed.
Item {
    id: root

    property bool open: false
    property int selected: 0
    property int armedIndex: -1
    property real armLeft: 1

    readonly property var actions: SessionState.actions

    signal closeRequested()

    function move(by) {
        selected = (selected + by + actions.length) % actions.length;
    }

    function press(i) {
        const a = actions[i];
        if (!a)
            return;
        selected = i;
        if (a.confirm && armedIndex !== i) {
            armedIndex = i;
            arm.restart();
            return;
        }
        disarm();
        SessionState.run(a.id);
    }

    function disarm() {
        arm.stop();
        armedIndex = -1;
        armLeft = 1;
    }

    // Moving away cancels a pending "press again".
    onSelectedChanged: if (armedIndex !== selected) disarm()
    onOpenChanged: if (!open) disarm()

    NumberAnimation {
        id: arm
        target: root
        property: "armLeft"
        from: 1
        to: 0
        duration: Style.sessionConfirmMs
        onFinished: root.disarm()
    }

    focus: true
    Keys.onPressed: event => {
        const k = event.key;
        if (k === Qt.Key_Escape)
            root.closeRequested();
        else if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_Tab || k === Qt.Key_L || k === Qt.Key_J)
            root.move(1);
        else if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_Backtab || k === Qt.Key_H || k === Qt.Key_K)
            root.move(-1);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)
            root.press(root.selected);
        else if (k >= Qt.Key_1 && k <= Qt.Key_5)
            root.press(k - Qt.Key_1);
        else
            return;
        event.accepted = true;
    }

    // ---- How long the computer has been on (from /proc/uptime) -------------------
    property real uptime: 0
    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: root.uptime = parseFloat(text().split(" ")[0]) || 0
    }
    Timer {
        interval: 60000
        running: root.open
        repeat: true
        onTriggered: uptimeFile.reload()
    }
    readonly property string uptimeText: {
        const m = Math.floor(uptime / 60);
        const d = Math.floor(m / 1440), h = Math.floor(m % 1440 / 60), min = m % 60;
        return "Up " + (d > 0 ? d + " d " : "") + (d > 0 || h > 0 ? h + " h " : "") + min + " min";
    }

    // ---- Dim the screen ---------------------------------------------------------------
    // The blurred wallpaper and the dim, fading together (Backdrop).
    Backdrop {
        anchors.fill: parent
        shown: root.open
        dim: Style.sessionDim
    }

    // ---- The card -----------------------------------------------------------------------
    Item {
        id: card
        anchors.centerIn: parent
        width: buttons.width + 64
        height: column.height + 56
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.9

        Behavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
        }

        // Darkening off: no backdrop, so the card frosts its own piece.
        WallpaperFrost {
            anchors.fill: parent
            at: Qt.point(card.x, card.y)
            radius: Style.radiusDialog
            visible: Style.sessionDim <= 0
        }
        Glass {
            anchors.fill: parent
            radius: Style.radiusDialog
            color: Style.alpha(Colors.surfaceContainer, Style.sessionOpacity)
        }

        // Clicks on the card stay on the card.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: column
            anchors.centerIn: parent
            spacing: 22

            Column {
                spacing: 2
                StyledText {
                    text: "Power"
                    role: "headline"
                }
                StyledText {
                    text: root.uptimeText + "  ·  " + (Quickshell.env("USER") ?? "")
                    role: "caption"
                    color: Colors.textOnSurfaceVariant
                }
            }

            Row {
                id: buttons
                spacing: 14

                Repeater {
                    model: root.actions

                    SessionButton {
                        required property var modelData
                        action: modelData
                        selected: index === root.selected
                        armed: index === root.armedIndex
                        armLeft: root.armLeft
                        shown: root.open
                        onHovered: root.selected = index
                        onPressed: root.press(index)
                    }
                }
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "←  →  choose   ·   Enter   ·   1–5   ·   Esc closes"
                role: "caption"
                color: Colors.textOnSurfaceVariant
                opacity: 0.8
            }
        }
    }
}
