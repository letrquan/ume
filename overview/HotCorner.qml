import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The hot corner: push the pointer into a corner of the screen
// (Style.overviewHotCorner) and the overview opens. The pointer has to rest
// there a moment (Style.overviewHotCornerDelay), so passing by doesn't open
// it. Not while a full-screen window (a game, a video) has the focus.
//
// A 1×1 item in the corner of a window that is there anyway: the bar's for
// the top corners, the dock's for the bottom ones (both span the screen),
// each putting it in its mask. No window of its own (each window costs a
// render thread and a GL context).
Item {
    id: root

    // "top" in the bar, "bottom" in the dock.
    required property string edge
    readonly property string corner: Style.overviewHotCorner
    readonly property bool active: corner.startsWith(edge)

    visible: active
    width: 1
    height: 1
    x: corner.endsWith("right") ? (parent?.width ?? 1) - 1 : 0
    y: edge === "bottom" ? (parent?.height ?? 1) - 1 : 0

    HoverHandler {
        id: pointer
        onHoveredChanged: {
            if (hovered)
                rest.restart();
            else
                rest.stop();
        }
    }

    Timer {
        id: rest
        interval: Style.overviewHotCornerDelay
        onTriggered: {
            if (pointer.hovered && !OverviewState.open && !(ToplevelManager.activeToplevel?.fullscreen ?? false))
                OverviewState.toggle();
        }
    }
}
