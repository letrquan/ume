import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import qs.services

// The OSD window on one screen: centered under the middle island (or right
// under the bar's speaker after scrolling on it: OsdState.anchored), above
// everything, never takes clicks or keys. shell.qml creates it only while
// the OSD shows (OsdState.mapped), so it costs nothing the rest of the time.
PanelWindow {
    id: root

    required property ShellScreen modelData
    // Room around the pill for its spring overshoot.
    readonly property int pad: 10
    // Once the new window has settled (Settle), so the entry animation
    // doesn't jump over its slow first frames.
    readonly property bool open: settle.settled
    Settle { id: settle }
    readonly property bool shown: open && OsdState.shown

    // Under the speaker icon: its center, kept inside the screen.
    readonly property bool underIcon: OsdState.anchored && OsdState.anchorScreen === modelData.name
    readonly property real iconLeft: Math.max(Style.marginEdge - pad,
        Math.min(modelData.width - implicitWidth - Style.marginEdge + pad, OsdState.anchorX - implicitWidth / 2))

    screen: modelData
    anchors.top: true
    anchors.left: underIcon
    margins.top: Style.barBottom + Style.osdGap - pad
    margins.left: underIcon ? Math.round(iconLeft) : 0
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: view.implicitWidth + pad * 2
    implicitHeight: view.implicitHeight + pad * 2
    color: "transparent"

    WlrLayershell.namespace: "mine-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    OsdView {
        id: view

        x: root.pad
        y: root.pad
        kind: OsdState.kind
        value: OsdState.value
        muted: OsdState.muted
        label: OsdState.label
        isState: OsdState.isState
        active: OsdState.active
        detail: OsdState.detail
        tilingIcon: OsdState.tilingIcon
        // The pill's place on the screen, for its frost: the window is
        // centered at the top (layer shell) or under the speaker icon.
        screenAt: Qt.point((root.underIcon ? Math.round(root.iconLeft) : Math.floor((root.modelData.width - root.implicitWidth) / 2)) + root.pad,
                           root.margins.top + root.pad)
        screenSize: Qt.size(root.modelData.width, root.modelData.height)

        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.9
        transform: Translate {
            y: root.shown ? 0 : -8
            Behavior on y {
                NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultEffects }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.defaultSpatial }
        }
    }
}
