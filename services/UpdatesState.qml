pragma Singleton
import QtQuick
import Quickshell
import qs.common

// The updates panel (updates/UpdatesPanel.qml): a click on the bar's
// updates item opens it right under the item (Style.updatesClick "panel").
// Like the volume popup: it grows out of the item and shrinks back into
// it, Esc or a click outside closes it. It never comes back open after a
// reload or restart; an install going on keeps going (services/UpdateRun).
Singleton {
    id: root

    property bool open: false
    // The window exists only while this is true: while open, plus the time
    // the card takes to shrink back into the item.
    property bool mapped: false

    // Where it was opened from: the screen's name and the item's rect in
    // that screen's coordinates (empty: the top right corner).
    property string screen: ""
    property rect from: Qt.rect(0, 0, 0, 0)

    // Update was pressed with heads-up packages among the updates: the
    // panel asks again, listing them.
    property bool confirming: false
    // Update was pressed on a list that may be old (pacman -Syu syncs
    // fresh, so a new kernel could slip past the heads-up): checking first.
    property bool freshening: false

    // The panel's Update (its own checks done): a fresh list first (older
    // than 10 minutes, or the last check didn't work), then heads-up
    // packages ask again, else it installs.
    function update() {
        if (Updates.checking || Updates.failed !== "" || Date.now() - Updates.checkedAt > 600000) {
            freshening = true;
            Updates.check("before updating");
            return;
        }
        gate();
    }
    function gate() {
        if (Updates.headsUp.length > 0)
            confirming = true;
        else
            UpdateRun.start();
    }
    Connections {
        target: Updates
        function onCheckingChanged() {
            if (Updates.checking || !root.freshening)
                return;
            root.freshening = false;
            // (Once the check has handed over its lists: it says "done"
            // just before.)
            Qt.callLater(() => {
                if (root.open)
                    root.gate();
            });
        }
    }
    // The install's output (Details), and which package lists are open
    // (repo / aur / flatpak: true or false; unset = open when short).
    property bool showLog: false
    property var expanded: ({})
    // The password dialog is up (shell.qml binds it to PolkitService): the
    // panel lets go of the keyboard and the clicks meanwhile.
    property bool passwordUp: false

    function toggle(screenName, itemRect) {
        if (open)
            close();
        else
            show(screenName, itemRect);
    }

    function show(screenName, itemRect) {
        unmap.stop();
        wanted = false;
        screen = screenName;
        from = itemRect;
        // open first: the window is created the moment `mapped` turns on,
        // and must see the panel open already.
        open = true;
        mapped = true;
        if (!holding) {
            holding = true;
            Updates.use(true);
        }
        ArchNews.refresh();
    }

    function close() {
        if (!open)
            return;
        open = false;
        confirming = false;
        freshening = false;
        // A result you've seen (or a dismissed password) goes once you close.
        if (seen && (UpdateRun.result === "ok" || UpdateRun.result === "cancelled"))
            UpdateRun.dismiss();
        seen = false;
        UpdateRun.refused = "";
        unmap.restart();
    }

    function setExpanded(kind, on) {
        const next = Object.assign({}, expanded);
        next[kind] = on;
        expanded = next;
    }

    // While it's open the checks run even if the item isn't on the bar.
    property bool holding: false
    onMappedChanged: if (!mapped && holding) { holding = false; Updates.use(false); }

    // Seen: open for a moment while there's a result.
    property bool seen: false
    Timer {
        running: root.open && UpdateRun.stage === "done"
        interval: 1200
        onTriggered: root.seen = true
    }

    // From IPC or the "Show" of a notification: the bar's updates item opens
    // it under itself (bar/UpdatesItem.qml); not on the bar, it opens at the
    // top right of the first screen.
    property bool wanted: false
    function request() {
        if (open)
            return;
        wanted = true;
        noItem.restart();
    }
    Timer {
        id: noItem
        interval: 400
        onTriggered: {
            if (root.wanted)
                root.show(Quickshell.screens[0]?.name ?? "", Qt.rect(0, 0, 0, 0));
        }
    }

    // The window goes once the card reports it's back in the item
    // (settled). This is only a safety net in case it never does.
    Timer {
        id: unmap
        interval: Motion.morphOut + 1500
        onTriggered: root.settled()
    }

    function settled() {
        if (open || !mapped)
            return;
        unmap.stop();
        // A moment later, not in the very frame the item fades back in
        // (letting go of a window stalls the shell for ~50 ms).
        release.restart();
    }

    Timer {
        id: release
        interval: Motion.contentIn + 80
        onTriggered: if (!root.open) root.mapped = false
    }
}
