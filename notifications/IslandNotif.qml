import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The notification island window on one screen: over the middle island,
// above everything. Only the card takes clicks. shell.qml creates it only
// while there are notifications to show (Notifs.popupsMapped).
PanelWindow {
    id: root

    required property ShellScreen modelData
    // Once the new window has settled (Settle), so the opening animation
    // doesn't jump over its slow first frames.
    readonly property bool ready: settle.settled
    Settle { id: settle }

    screen: modelData
    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Math.max(Style.notifWidth, 560) + 40
    // (+ room for the reply field)
    implicitHeight: Style.marginEdge + Style.notifMaxHeight + 66
    color: "transparent"

    WlrLayershell.namespace: "mine-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    // The keyboard only while typing a reply in the card.
    WlrLayershell.keyboardFocus: Notifs.replying !== "" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region {
        item: island.cardItem
    }

    IslandCard {
        id: island

        anchors.fill: parent
        entry: Notifs.popups[0] ?? null
        count: Notifs.popups.length
        startWidth: IslandState.centerWidth
        // (A live activity showing in the island leaves first.)
        open: root.ready && Notifs.popups.length > 0 && !Activities.busy
        onCoveringChanged: IslandState.notifCovering = covering
        // Back in the island: the window can go (if nothing new arrived).
        onSettledChanged: if (settled && root.ready) Notifs.islandSettled()
    }

    // If this window goes away early, give the bar its island back (and
    // the keyboard).
    Component.onDestruction: {
        IslandState.notifCovering = false;
        Notifs.replying = "";
    }
}
