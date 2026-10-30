import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The window of the small bar popups (BarPopupState: the battery, the USB
// drives) on the screen it was opened on. Like the volume popup's: it
// covers the whole screen (see-through) so a click outside closes it, and
// takes the keyboard while open (Esc closes). shell.qml creates it only
// while needed (BarPopupState.mapped).
PanelWindow {
    id: root

    required property ShellScreen modelData
    // Once the new window has settled (Settle), so the opening animation
    // doesn't jump over its slow first frames.
    readonly property bool ready: settle.settled
    Settle { id: settle }

    Component.onCompleted: {
        keys.forceActiveFocus();
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

    WlrLayershell.namespace: "mine-barpopup"
    WlrLayershell.layer: WlrLayer.Overlay
    // (The password dialog, when Open needs one, comes after this closed.)
    WlrLayershell.keyboardFocus: BarPopupState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // While open the whole screen takes clicks (outside = close); while
    // shrinking back, clicks already go to your windows.
    mask: BarPopupState.open ? everything : nothing
    Region { id: everything; item: catcher }
    Region { id: nothing }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: BarPopupState.close()
    }

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: BarPopupState.close()
    }

    BarPopupCard {
        anchors.fill: parent
        from: BarPopupState.from
        open: root.ready && BarPopupState.open
        toWidth: BarPopupState.kind === "battery" ? Style.batteryPopupWidth
            : BarPopupState.kind === "screentime" ? Style.screenTimePopupWidth
            : BarPopupState.kind === "aiusage" ? Style.aiUsagePopupWidth
            : Style.drivesPopupWidth
        body: BarPopupState.kind === "battery" ? battery
            : BarPopupState.kind === "screentime" ? screentime
            : BarPopupState.kind === "aiusage" ? aiusage
            : drives
        // Back in the item: the window can go.
        onSettledChanged: if (settled && root.ready) BarPopupState.settled()
    }

    Component {
        id: battery
        BatteryPopup {}
    }
    Component {
        id: drives
        DrivesPopup {}
    }
    // Screen time and AI usage (services/ScreenTime.qml, services/AiUsage.qml).
    Component {
        id: screentime
        ScreenTimePopup {}
    }
    Component {
        id: aiusage
        AiUsagePopup {}
    }
}
