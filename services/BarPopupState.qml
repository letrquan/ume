pragma Singleton
import QtQuick
import Quickshell
import qs.common

// Small popups that grow out of a bar item and sit right under it, like
// the volume popup (control/BarPopupWindow.qml): `kind` "battery" (the
// charge over the last hours and the battery's health, a click on the bar's
// battery) or "drives" (the USB drives, a click on the bar's USB item).
// One at a time. It never comes back open after a reload or restart, and
// its window only exists while open (plus the shrink back into the item).
Singleton {
    id: root

    property bool open: false
    property bool mapped: false
    property string kind: ""

    // Where it was opened from: the screen's name and the item's rect in
    // that screen's coordinates (the bar spans the whole width). An empty
    // rect (IPC): it grows from the right end of the bar.
    property string screen: ""
    property rect from: Qt.rect(0, 0, 0, 0)

    function toggle(which, screenName, itemRect) {
        if (open && kind === which)
            close();
        else
            show(which, screenName, itemRect);
    }

    function show(which, screenName, itemRect) {
        const where = screenName || (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
        // Still shrinking back from another item: start over from this one.
        if (mapped && (kind !== which || screen !== where))
            mapped = false;
        unmap.stop();
        release.stop();
        kind = which;
        screen = where;
        from = itemRect ?? Qt.rect(0, 0, 0, 0);
        // open first: the window is created the moment `mapped` turns on,
        // and must see the popup open already.
        open = true;
        mapped = true;
    }

    function close() {
        if (!open)
            return;
        open = false;
        unmap.restart();
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
        // A moment later, not in the very frame the item shows again
        // (letting go of a window stalls the shell for a few frames).
        release.restart();
    }

    Timer {
        id: release
        interval: Motion.contentIn + 80
        onTriggered: if (!root.open) root.mapped = false
    }
}
