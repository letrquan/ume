pragma Singleton
import QtQuick
import Quickshell
import qs.common

// The volume popup: a click on the bar's speaker opens it right under the
// icon (control/VolumePopup.qml), so the slider is where the mouse already
// is. Keys (volume up/down) keep the OSD in the middle instead.
// It never comes back open after a reload or restart.
Singleton {
    id: root

    property bool open: false
    // The window exists only while this is true: while open, plus the time
    // the card takes to shrink back into the icon.
    property bool mapped: false

    // Where it was opened from: the screen's name and the speaker icon's
    // rect in that screen's coordinates (the bar spans the whole width).
    property string screen: ""
    property rect from: Qt.rect(0, 0, 0, 0)

    function toggle(screenName, iconRect) {
        if (open)
            close();
        else
            show(screenName, iconRect);
    }

    function show(screenName, iconRect) {
        unmap.stop();
        screen = screenName;
        from = iconRect;
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

    // The window goes once the card reports it's back in the icon
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
