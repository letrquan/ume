import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The notes panel's window (services/Notes.qml), on the screen it was opened
// on: see-through over the whole screen so a click outside closes it, and
// it takes the keyboard while open (the shell's on-screen keyboard types
// into it too). The on-screen keyboard's strip stays outside it (input and
// card), so its keys can be tapped. shell.qml creates it only while needed
// (Notes.mapped).
PanelWindow {
    id: root

    readonly property ShellScreen target: Quickshell.screens.find(s => s.name === Notes.screen) ?? Quickshell.screens[0]
    // The on-screen keyboard is up on this screen (osk/OskWindow.qml: the
    // built-in one): the card stays above it.
    readonly property var oskScreen: Quickshell.screens.find(s => s.name.startsWith("eDP")) ?? Quickshell.screens[0]
    readonly property bool oskHere: OskState.open && oskScreen === target
    readonly property real oskRoom: oskHere ? Style.oskHeight + Style.marginEdge : 0
    readonly property bool ready: settle.settled
    readonly property alias viewItem: view
    Settle { id: settle }

    screen: target
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "mine-notes"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Notes.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Open: everything but the keyboard's strip; closing: nothing.
    mask: Notes.open ? opened : nothing
    Region {
        id: opened
        item: catcher
        Region {
            intersection: Intersection.Subtract
            x: 0
            y: root.height - root.oskRoom
            width: root.width
            height: root.oskRoom
        }
    }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: Notes.close()
    }

    NotesView {
        id: view
        readonly property real topGap: Style.barBottom + Style.marginEdge + 8
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: topGap
        width: Style.notesWidth
        height: Math.min(Style.notesHeight, root.height - topGap - root.oskRoom - 12)
        shown: root.ready && Notes.open
    }
}
