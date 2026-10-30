pragma Singleton
import QtQuick
import Quickshell
import qs.common

// Whether the launcher is open. It never comes back open after a reload or
// restart, and its window only exists while open (plus the shrink-back).
// `grid`: it shows every app as a grid (launcher/AppGrid.qml) until you
// type; it opens that way from `mine launcher grid`, and in tablet mode
// with Style.launcherGridInTablet.
Singleton {
    id: root

    property bool open: false
    property bool mapped: false
    property bool grid: false

    function toggle() {
        if (open)
            close();
        else
            show();
    }

    // `mine launcher grid`: open with the grid (again: close).
    function toggleGrid() {
        if (open && grid)
            close();
        else if (open)
            setGrid(true);
        else
            show(true);
    }

    function setGrid(on) {
        if (on)
            Apps.gridWanted = true;
        grid = on;
    }

    // `withGrid`: true / false, or left out: as the tablet knob says.
    function show(withGrid) {
        ClipboardState.close();         // they share the middle island
        CalendarState.close();
        NowPlayingState.close();
        unmap.stop();
        setGrid(withGrid ?? (Style.launcherGridInTablet && TabletMode.tablet));
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

    // The window goes once the launcher reports it's back in the island
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
