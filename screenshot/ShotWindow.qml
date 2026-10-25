import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The screenshot overlay on the frozen output: full screen, above
// everything, takes the keyboard. shell.qml creates it only while a
// screenshot is being picked or marked up (Screenshot.active); it goes the
// moment you capture or save (the picture is cut afterwards, so nothing
// flickers). For a saved picture being marked up it is see-through: the
// screen behind shows, dimmed.
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
    color: Screenshot.editFile !== "" ? "transparent" : "black"

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
        task: Screenshot.task
        translating: Screenshot.translating
        cardGeo: Screenshot.cardGeo
        cardState: Screenshot.cardState
        cardText: Screenshot.cardText
        cardTranslation: Screenshot.cardTranslation
        cardFrom: Screenshot.cardFrom
        cardTo: Screenshot.cardTo
        cardError: Screenshot.cardError
        cardNote: Screenshot.cardNote
        confirm: Style.screenshotConfirm
        marking: Screenshot.marking
        markGeo: Screenshot.markGeo
        editFile: Screenshot.editFile
        pixelSize: Math.max(2, Math.round(Style.screenshotPixelSize))
        marksPath: Screenshot.marksPath

        onModeRequested: m => Screenshot.mode = m
        onEditRequested: wanted => Screenshot.edit = wanted
        onTaskRequested: t => Screenshot.setTask(t)
        onSwapRequested: Screenshot.swapDirection()
        onCopyRequested: Screenshot.copyTranslation()
        onRetryRequested: Screenshot.retryTranslation()
        onCaptureRect: (x, y, w, h) => Screenshot.captureRect(x, y, w, h)
        onCaptureAll: Screenshot.captureAll()
        onCancel: Screenshot.close()
        onMarkupDone: (how, geo, blurs, marked) => Screenshot.markupDone(how, geo, blurs, marked)
        onLoadFailed: Screenshot.editFailed()

        Component.onCompleted: forceActiveFocus()
    }
}
