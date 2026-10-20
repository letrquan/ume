import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The on-screen keyboard's window: a strip along the bottom of the built-in
// screen (the touch one). Windows shrink above it (exclusive zone), and it
// never takes the keyboard focus, so what it types goes to the window you
// were in. On the Overlay layer, so it also comes up over a fullscreen app;
// mango stacks it under everything else at the bottom (the dock moves up
// above it). shell.qml creates it only while it shows (OskState.mapped).
PanelWindow {
    id: root

    // False for the first frame, so it slides in.
    property bool entered: false
    readonly property bool shown: entered && OskState.open

    Component.onCompleted: entered = true

    screen: Quickshell.screens.find(s => s.name.startsWith("eDP")) ?? Quickshell.screens[0]
    anchors {
        bottom: true
        left: true
        right: true
    }
    implicitHeight: Style.oskHeight + Style.marginEdge
    // The whole height at once, never the sliding one (windows would
    // resize on every frame); none while it slides away.
    exclusiveZone: OskState.open ? implicitHeight : 0
    color: "transparent"

    WlrLayershell.namespace: "mine-osk"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Only the keyboard takes touches; the gaps beside it don't. Its
    // rectangle as it slides (OskView.slideY), not `item: view.card`.
    mask: Region {
        x: view.card.x
        y: view.card.y + view.slideY
        width: view.card.width
        height: view.card.height
    }

    OskView {
        id: view
        anchors.fill: parent
        shown: root.shown
    }
}
