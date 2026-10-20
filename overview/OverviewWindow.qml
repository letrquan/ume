import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The overview window (Super+O, the hot corner): the whole screen mango
// has focused, above everything, with the keyboard while open (type to
// find a window). shell.qml creates it only while needed
// (OverviewState.mapped), so no pictures are taken once it's gone.
PanelWindow {
    id: root

    // Opening, in steps, so nothing jumps:
    // 1. the window is made and drawn once, see-through (the first frame of
    //    a new window is slow: it would eat the start of the zoom);
    // 2. once mango's window list and screens are in and the pictures are
    //    loaded (or after 250 ms anyway), the workspace you're on shows,
    //    as the whole screen, just like your desktop;
    // 3. as soon as that frame is on the screen, the zoom out starts.
    property bool drawn: false
    property bool revealed: false
    property bool ready: false
    readonly property bool canReveal: drawn && OverviewState.fresh && view.picturesReady
    onCanRevealChanged: if (canReveal) revealed = true
    onRevealedChanged: if (revealed) go.start()

    Connections {
        target: view.Window.window
        enabled: !root.drawn || (root.revealed && !root.ready)
        function onFrameSwapped() {
            if (!root.drawn)
                root.drawn = true;
            else
                root.ready = true;
        }
    }
    Timer {
        interval: 250
        running: !root.revealed
        onTriggered: root.revealed = true
    }
    // (In case no frame comes.)
    Timer {
        id: go
        interval: 100
        onTriggered: root.ready = true
    }

    // Closed again before it got going: gone at once.
    Connections {
        target: OverviewState
        function onOpenChanged() {
            if (!OverviewState.open && !root.ready)
                OverviewState.closed();
        }
    }

    Component.onCompleted: view.focusInput()

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // Not on mango's no-blur list: the dimmed screen behind gets blurred.
    WlrLayershell.namespace: "mine-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: OverviewState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open the whole screen takes clicks; while the windows fly back,
    // clicks already reach your windows.
    mask: OverviewState.open ? everything : nothing
    Region { id: everything; item: view }
    Region { id: nothing }

    OverviewView {
        id: view
        anchors.fill: parent
        monitor: root.screen?.name ?? ""
        revealed: root.revealed
        shown: root.ready && OverviewState.open
        onCloseRequested: OverviewState.close()
        onFlownBack: OverviewState.closed()
    }
}
