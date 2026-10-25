pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The power menu: whether it's open, and the five things it can do (plus
// Switch to GNOME and Restart to Windows, see the end).
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
        // Switch to GNOME: a log out that leaves a note for the login screen
        // (scripts/switch-session.sh), so GNOME is already picked there.
        // Only while GNOME is installed.
        ...(root.gnomeListed ? [{ id: "gnome", label: "Switch to GNOME", icon: "swap_horiz", shape: "Clover4Leaf",
                                  confirm: true, command: ["sh", Quickshell.shellDir + "/scripts/switch-session.sh", "gnome"] }] : []),
        { id: "reboot", label: "Restart", icon: "restart_alt", shape: "Cookie12Sided", confirm: true,
          command: ["systemctl", "reboot"] },
        // Restart to Windows (services/WindowsBoot.qml): only while the
        // firmware has a Windows Boot Manager entry. No command of its own:
        // run() hands it to WindowsBoot, which restarts through "reboot".
        ...(root.windowsListed ? [{ id: "windows", label: "Restart to Windows", icon: "window", shape: "Cookie6Sided",
                                    confirm: true, command: [] }] : []),
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
        // Restart to Windows: the menu closes, the password dialog asks, and
        // only once the firmware will start Windows next does WindowsBoot
        // come back here with "reboot".
        if (id === "windows") {
            close();
            WindowsBoot.restart();
            return;
        }
        if (id === "logout" || id === "reboot" || id === "poweroff")
            AppRestore.leave(id);
        else if (id === "gnome")
            AppRestore.leave("logout");
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

    // ---- Restart to Windows (services/WindowsBoot.qml) ---------------------------------
    // The button follows WindowsBoot only while the menu is closed: the
    // buttons and the number keys go by their place in the list. Each
    // opening reads the firmware's entries again (for the next one).
    property bool windowsListed: false
    function syncWindows() {
        if (!open)
            windowsListed = Style.sessionWindows && WindowsBoot.entry !== "";
    }
    Connections {
        target: WindowsBoot
        function onEntryChanged() { root.syncWindows(); }
    }
    Connections {
        target: Style
        function onSessionWindowsChanged() { root.syncWindows(); }
    }
    Connections {
        target: root
        function onOpenChanged() {
            root.syncWindows();
            if (root.open)
                WindowsBoot.check();
        }
    }
    Component.onCompleted: {
        syncWindows();
        syncGnome();
    }

    // ---- Switch to GNOME ----------------------------------------------------------------
    // Like the Windows button: follows the knob and the session file only
    // while the menu is closed.
    property bool gnomeInstalled: false
    property bool gnomeListed: false
    function syncGnome() {
        if (!open)
            gnomeListed = Style.sessionGnome && gnomeInstalled;
    }
    FileView {
        path: "/usr/share/wayland-sessions/gnome.desktop"
        printErrors: false
        onLoaded: {
            root.gnomeInstalled = true;
            root.syncGnome();
        }
    }
    Connections {
        target: Style
        function onSessionGnomeChanged() { root.syncGnome(); }
    }
    Connections {
        target: root
        function onOpenChanged() { root.syncGnome(); }
    }
}
