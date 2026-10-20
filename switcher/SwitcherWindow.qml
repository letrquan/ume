import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The Alt+Tab window: the whole screen (see-through), above everything,
// with the keyboard while open. Letting go of Alt switches; Tab / arrows
// move, Q or W closes the picked window, Enter switches, Esc or a click
// outside cancels. shell.qml creates it only while needed
// (SwitcherState.mapped), on the screen mango has focused.
PanelWindow {
    id: root

    // Once the new window has settled (Settle), so the opening animation
    // doesn't jump over its slow first frames.
    readonly property bool ready: settle.settled
    Settle { id: settle }

    Component.onCompleted: {
        keys.forceActiveFocus();
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "mine-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: SwitcherState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open the whole screen takes clicks (outside = cancel); while
    // fading out, clicks already go to your windows.
    mask: SwitcherState.open ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: SwitcherState.cancel()
    }

    SwitcherView {
        anchors.fill: parent
        windows: SwitcherState.windows
        selected: SwitcherState.selected
        shown: root.ready && SwitcherState.open
        tagOf: t => SwitcherState.tagOf(t)
        onHoveredIndex: i => {
            SwitcherState.selected = i;
        }
        onPicked: i => SwitcherState.pick(i)
    }

    Item {
        id: keys
        focus: true

        Keys.onReleased: event => {
            // Alt let go: switch.
            if (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr || event.key === Qt.Key_Meta) {
                SwitcherState.commit("Alt let go");
                event.accepted = true;
            }
        }

        Keys.onPressed: event => {
            const shift = event.modifiers & Qt.ShiftModifier;
            switch (event.key) {
            case Qt.Key_Tab:
                SwitcherState.move(shift ? -1 : 1);
                break;
            case Qt.Key_Backtab:
            case Qt.Key_Left:
            case Qt.Key_Up:
                SwitcherState.move(-1);
                break;
            case Qt.Key_Right:
            case Qt.Key_Down:
                SwitcherState.move(1);
                break;
            case Qt.Key_Q:
            case Qt.Key_W:
                SwitcherState.closeSelected();
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                SwitcherState.commit("Enter");
                break;
            case Qt.Key_Escape:
                SwitcherState.cancel();
                break;
            default:
                return;
            }
            event.accepted = true;
        }
    }
}
