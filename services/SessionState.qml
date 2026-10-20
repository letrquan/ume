pragma Singleton
import QtQuick
import Quickshell
import qs.common

// The power menu: whether it's open, and the five things it can do.
// It never comes back open after a reload or restart, and its window only
// exists while open (plus its exit animation).
Singleton {
    id: root

    property bool open: false
    property bool mapped: false

    // MINE_SESSION_DRYRUN=1 is for testing: actions are only printed.
    readonly property bool dryRun: Quickshell.env("MINE_SESSION_DRYRUN") === "1"

    // In menu order. `confirm`: asks for a second press first.
    readonly property var actions: [
        { id: "lock", label: "Lock", icon: "lock", shape: "Cookie9Sided", confirm: false,
          command: [Quickshell.env("HOME") + "/.local/bin/qs-lock"] },
        { id: "suspend", label: "Sleep", icon: "bedtime", shape: "Clover8Leaf", confirm: false,
          command: ["systemctl", "suspend"] },
        { id: "logout", label: "Log out", icon: "logout", shape: "Pentagon", confirm: true,
          command: ["mmsg", "dispatch", "quit"] },
        { id: "reboot", label: "Restart", icon: "restart_alt", shape: "Cookie12Sided", confirm: true,
          command: ["systemctl", "reboot"] },
        { id: "poweroff", label: "Shut down", icon: "power_settings_new", shape: "Cookie4Sided", confirm: true,
          command: ["systemctl", "poweroff"] }
    ]

    function toggle() {
        if (open)
            close();
        else
            show();
    }

    function show() {
        unmap.stop();
        mapped = true;
        open = true;
    }

    function close() {
        if (!open)
            return;
        open = false;
        unmap.restart();
    }

    // Close the menu first, then act, so the lock screen (or the shutdown)
    // doesn't capture a half-closed menu. Leaving: the list of open apps
    // for the next login is written now, before the windows start closing
    // (services/AppRestore.qml).
    function run(id) {
        const action = actions.find(a => a.id === id);
        if (!action)
            return;
        if (id === "logout" || id === "reboot" || id === "poweroff")
            AppRestore.leave(id);
        pending = action.command;
        close();
        runLater.restart();
    }

    property var pending: null
    Timer {
        id: runLater
        interval: Motion.fast
        onTriggered: {
            if (root.dryRun)
                console.log("session (dry run):", JSON.stringify(root.pending));
            else
                Quickshell.execDetached(root.pending);
            root.pending = null;
        }
    }

    Timer {
        id: unmap
        interval: Motion.normal + 200
        onTriggered: root.mapped = false
    }
}
