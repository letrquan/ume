import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services
import qs.corners
import qs.overview

// One bar per screen. The window is a see-through strip across the top of
// the screen (gap + islands) that windows stay out of; the islands float
// inside it, or sit in one bar (Style.barStyle).
PanelWindow {
    id: root

    required property ShellScreen modelData

    screen: modelData
    anchors {
        top: true
        left: true
        right: true
    }
    // "hug" curves into the screen under the bar: drawn here, but windows
    // may go under the curves.
    implicitHeight: Style.barBottom + (Style.barStyle === "hug" ? Style.cornerRadius : 0)
    exclusiveZone: Style.barBottom
    color: "transparent"

    // mango blurs layers by name; "mine-bar" isn't on its no-blur list, so
    // the islands get frosted glass (only pixels that aren't see-through
    // are blurred). Clicks between the islands go through.
    WlrLayershell.namespace: "mine-bar"
    WlrLayershell.layer: WlrLayer.Top
    mask: Region {
        item: Style.barJoined ? content.backdrop : content.leftIsland

        Region { item: Style.barJoined ? null : content.centerIsland }
        Region { item: Style.barJoined ? null : content.rightIsland }
        Region { item: hotCorner.active ? hotCorner : null }
    }

    // "Keep awake" (control center): holds off dimming, screen off and lock.
    IdleInhibitor {
        window: root
        enabled: Idle.keepAwake
    }

    BarContent {
        id: content
        anchors.fill: parent
        screenName: root.modelData.name
    }

    // The screen's two top rounded corners live here (no windows of their
    // own); outside the mask, so they never take a click.
    CornerShape {
        visible: Style.cornersEnabled
        turn: 0
    }
    CornerShape {
        x: root.width - width
        visible: Style.cornersEnabled
        turn: 90
    }

    // The overview's hot corner, when it's a top one.
    HotCorner {
        id: hotCorner
        edge: "top"
    }

    // The tips under the islands (common/Tooltips.qml), in a window of their
    // own made only while tips are about.
    LazyLoader {
        active: Tooltips.mapped && Tooltips.screenName === root.modelData.name
        TooltipWindow {
            modelData: root.modelData
        }
    }
}
