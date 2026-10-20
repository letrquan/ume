import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The Now Playing card's window on one screen. It covers the whole screen
// (see-through) so a click anywhere outside the card closes it, and takes
// the keyboard while open (Space, ←/→, ↑/↓, N/P, Esc). shell.qml creates it
// only while the card is open (NowPlayingState.mapped).
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

    WlrLayershell.namespace: "mine-nowplaying"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: NowPlayingState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open, the whole screen takes clicks (outside the card = close);
    // while shrinking back, clicks already go to your windows.
    mask: NowPlayingState.open ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: NowPlayingState.close()
    }

    NowPlayingView {
        id: view

        anchors.fill: parent
        startWidth: IslandState.centerWidth
        open: root.ready && NowPlayingState.open
        onCloseRequested: NowPlayingState.close()
        onCoveringChanged: IslandState.nowPlayingCovering = covering
        // Back in the island: the window can go.
        onSettledChanged: if (settled && root.ready) NowPlayingState.settled()
    }

    // If this window goes away early, give the bar its island back.
    Component.onDestruction: IslandState.nowPlayingCovering = false
}
