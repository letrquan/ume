import QtQuick
import Quickshell
import qs.common
import qs.services

// Package updates waiting (services/Updates.qml): a box with an arrow and
// how many. On the bar while there are some, and while the updates panel
// installs or has something to tell (services/UpdateRun.qml). Accent while
// there's something to look at first (Style.updatesHeadsUp: the kernel,
// Quickshell, …), faded while the update runs in its terminal, pulsing with
// the % while the panel installs; a ✓ (or a ⚠) once it's done, until seen.
// Click: the updates panel right under it (Style.updatesClick "terminal":
// the update command in a terminal, as before); right-click: check now.
Reveal {
    id: root

    // (`wanted`: the bar's slot reads it, see BarContent.)
    readonly property bool wanted: shown || implicitWidth > 0.5

    anchors.verticalCenter: parent?.verticalCenter
    // Stays during an install even when the count drops (the panel must
    // stay reachable), and after it until its result is seen.
    shown: Updates.count > 0 || UpdateRun.showing

    readonly property bool installing: UpdateRun.busy
    readonly property bool told: UpdateRun.stage === "done" && UpdateRun.result !== "cancelled"
    readonly property bool bad: told && UpdateRun.result !== "ok"
    readonly property color tint: bad ? Colors.error
        : told || Updates.headsUp.length > 0 ? Colors.primary : Colors.textOnSurface

    // Checks only while it's on the bar.
    Component.onCompleted: Updates.use(true)
    Component.onDestruction: Updates.use(false)

    // "Checked 12 min ago" stays true while the tip is up.
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        enabled: button.containsMouse
    }

    // This item on its screen: x from the bar window, which spans the screen.
    function itemRect() {
        const win = button.QsWindow.window;
        return win ? win.itemRect(button) : Qt.rect(0, 0, width, height);
    }
    function screenName() {
        return button.QsWindow.window?.screen?.name ?? "";
    }

    function route(mouseButton) {
        if (mouseButton === Qt.RightButton) {
            Updates.check("asked");
            return;
        }
        if (mouseButton !== Qt.LeftButton)
            return;
        // The panel; also in "terminal" mode while it installs or has a result.
        if (Style.updatesClick !== "terminal" || UpdateRun.showing)
            UpdatesState.toggle(screenName(), itemRect());
        else if (!Updates.updating)
            Updates.run();
    }

    // Asked to open (IPC, a notification's Show): under this item.
    Connections {
        target: UpdatesState
        function onWantedChanged() {
            if (UpdatesState.wanted && root.visible)
                UpdatesState.show(root.screenName(), root.itemRect());
        }
    }

    Clickable {
        id: button
        spacing: 3
        opacity: Updates.updating ? 0.5 : 1
        tip: root.installing ? "Installing updates"
            : root.told ? UpdateRun.summary
            : Updates.updating ? "Updating…" : Updates.count === 1 ? "1 update" : Updates.count + " updates"
        tipDetail: {
            clock.date;
            if (root.installing)
                return UpdateRun.progressText + "\nClick: show progress";
            if (root.told)
                return (UpdateRun.restartFor.length > 0 ? "Restart to finish\n" : "") + "Click: see what it did";
            const lines = [Updates.summary];
            if (Updates.headsUp.length > 0)
                lines.push("Heads-up: " + Updates.headsUp.slice(0, 6).join(", ")
                    + (Updates.headsUp.length > 6 ? " +" + (Updates.headsUp.length - 6) : ""));
            lines.push(Updates.checking ? "Checking…"
                : Updates.failed !== "" ? Updates.failed
                : "Checked " + Updates.ago(Updates.checkedAt));
            lines.push(Updates.updating ? "In the terminal"
                : Style.updatesClick === "terminal" ? "Click: update in a terminal · right-click: check now"
                : "Click: the list and Update · right-click: check now");
            return lines.join("\n");
        }
        onClicked: mouse => root.route(mouse.button)

        Behavior on opacity {
            NumberAnimation { duration: Motion.normal }
        }

        Icon {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            name: root.told ? (root.bad ? "error" : "task_alt") : "deployed_code_update"
            size: 16
            fill: root.installing || root.told || Updates.headsUp.length > 0 ? 1 : 0
            color: root.tint

            // Breathes while the panel installs.
            SequentialAnimation on opacity {
                running: root.installing
                loops: Animation.Infinite
                onRunningChanged: if (!running) glyph.opacity = 1
                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            text: root.installing ? UpdateRun.percentText
                : root.told && Updates.count === 0 ? ""
                : Updates.count > 99 ? "99+" : String(Updates.count)
            role: "body"
            font.features: ({ "tnum": 1 })
            color: root.tint
        }
    }
}
