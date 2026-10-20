import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The screenshot overlay on the frozen output: full screen, above
// everything, takes the keyboard. shell.qml creates it only while a
// screenshot is being picked (Screenshot.active); it goes the moment you
// capture (the frozen picture is cut afterwards, so nothing flickers).
PanelWindow {
    id: root

    // The output the frozen picture belongs to (mango's focused one).
    screen: Quickshell.screens.find(s => s.name === Screenshot.monitor?.name) ?? Quickshell.screens[0]
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "black"

    // The frozen picture is opaque: nothing behind it to blur (mango needs
    // `layer_rule=no_blur:1,layer_name:^mine-screenshot$`).
    WlrLayershell.namespace: "mine-screenshot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    ShotView {
        id: view
        anchors.fill: parent
        frozen: Screenshot.frozen
        outputScale: Screenshot.monitor?.scale ?? 1
        windows: Screenshot.windows
        mode: Screenshot.mode
        edit: Screenshot.edit
        recording: Screenshot.forRecording
        reading: Screenshot.forText
        confirm: Style.screenshotConfirm

        onModeRequested: m => Screenshot.mode = m
        onEditRequested: wanted => Screenshot.edit = wanted
        onCaptureRect: (x, y, w, h) => Screenshot.captureRect(x, y, w, h)
        onCaptureAll: Screenshot.captureAll()
        onCancel: Screenshot.close()

        Component.onCompleted: forceActiveFocus()
    }
}
