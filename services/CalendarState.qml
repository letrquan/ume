pragma Singleton
import QtQuick
import Quickshell
import qs.common

// Whether the calendar is open (click the clock). It shares the middle
// island with the launcher and the clipboard, so opening one closes the
// others. It never comes back open after a reload or restart; its window
// only exists while open (plus the shrink-back).
Singleton {
    id: root

    property bool open: false
    property bool mapped: false

    function toggle() {
        if (open)
            close();
        else
            show();
    }

    function show() {
        LauncherState.close();          // they share the middle island
        ClipboardState.close();
        NowPlayingState.close();
        unmap.stop();
        // open first: the window is created the moment `mapped` turns on,
        // and must see the panel open already.
        open = true;
        mapped = true;
    }

    function close() {
        if (!open)
            return;
        open = false;
        unmap.restart();
    }

    // The window goes once the calendar reports it's back in the island
    // (settled). This is only a safety net in case it never does.
    Timer {
        id: unmap
        interval: Motion.morphOut + 1500
        onTriggered: root.mapped = false
    }

    function settled() {
        if (open || !mapped)
            return;
        unmap.stop();
        // The window goes a moment later, not in the very frame the island
        // starts fading back in: letting go of a window stalls the shell
        // for ~50 ms, which made that fade stutter.
        release.restart();
    }

    Timer {
        id: release
        interval: Motion.contentIn + 80
        onTriggered: if (!root.open) root.mapped = false
    }
}
