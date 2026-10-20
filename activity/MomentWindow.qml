import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// A live activity's moment on one screen: over the middle island, above
// windows. Only the card takes clicks. shell.qml creates it only while a
// moment shows (Activities.mapped).
PanelWindow {
    id: root

    required property ShellScreen modelData
    // Once the new window has settled (Settle), so the growing doesn't jump
    // over its slow first frames.
    readonly property bool ready: settle.settled
    Settle { id: settle }

    screen: modelData
    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Math.max(Style.activityMaxWidth, IslandState.centerWidth) + 40
    implicitHeight: Style.marginEdge + Style.activityHeight + 12
    color: "transparent"

    WlrLayershell.namespace: "mine-activity"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {
        item: card.cardItem
    }

    MomentCard {
        id: card

        anchors.fill: parent
        entry: Activities.moment
        revision: Activities.revision
        startWidth: IslandState.centerWidth
        open: root.ready && Activities.moment !== null
        onCoveringChanged: IslandState.activityCovering = covering
        onSettledChanged: if (settled && root.ready) Activities.settled()
    }

    // If this window goes away early, give the bar its island back.
    Component.onDestruction: IslandState.activityCovering = false
}
