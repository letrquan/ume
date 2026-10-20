pragma Singleton
import QtQuick
import Quickshell

// Whether the Settings window is open. Only one window; closing it (its
// close button, the compositor's close key, Esc) unloads it. Never comes
// back open after a reload or restart.
Singleton {
    id: root

    property bool open: false
    // Section to show when it opens (appearance, bar, dock, notifications,
    // launcher, wallpaper, power, about).
    property string section: "appearance"

    // A setting to show and light up when the window opens (a ref from
    // settings/SettingsSearch.qml, "dock/dockBehavior"), or text to put in its
    // search field. The window takes them (and empties them).
    property string target: ""
    property string search: ""

    function show(which) {
        if (which)
            section = which;
        open = true;
    }

    // Open at one setting (the launcher's Settings results), or with a
    // search typed in. Already open (maybe on another workspace): closed and
    // opened again, so it comes up where you are.
    function reveal(which, ref) {
        const was = open;
        open = false;
        if (which)
            section = which;
        target = ref ?? "";
        reopen(was);
    }
    function find(text) {
        const was = open;
        open = false;
        search = text ?? "";
        reopen(was);
    }
    function reopen(was) {
        if (was)
            again.restart();
        else
            open = true;
    }
    Timer {
        id: again
        interval: 80
        onTriggered: root.open = true
    }

    function close() {
        open = false;
    }

    function toggle() {
        open = !open;
    }
}
