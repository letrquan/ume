import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The calendar window on one screen. It covers the whole screen (see-
// through) so a click anywhere outside the calendar closes it, and takes the
// keyboard while open (←/→, T, Esc). shell.qml creates it only while the
// calendar is open (CalendarState.mapped).
PanelWindow {
    id: root

    required property ShellScreen modelData
    // Once the new window has settled (Settle), so the opening animation
    // doesn't jump over its slow first frames.
    readonly property bool ready: settle.settled
    Settle { id: settle }

    Component.onCompleted: {
        view.focusKeys();
    }

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "mine-calendar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: CalendarState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open, the whole screen takes clicks (outside the calendar =
    // close); while shrinking back, clicks already go to your windows.
    mask: CalendarState.open ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: CalendarState.close()
    }

    CalendarView {
        id: view

        anchors.fill: parent
        startWidth: IslandState.centerWidth
        open: root.ready && CalendarState.open
        onCloseRequested: CalendarState.close()
        onCoveringChanged: IslandState.calendarCovering = covering
        // Back in the island: the window can go.
        onSettledChanged: if (settled && root.ready) CalendarState.settled()
    }

    // If this window goes away early, give the bar its island back.
    Component.onDestruction: IslandState.calendarCovering = false
}
